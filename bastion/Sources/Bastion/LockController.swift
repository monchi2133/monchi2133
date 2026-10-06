import AppKit
import Combine

final class LockController: ObservableObject {
    static let shared = LockController()

    enum State {
        case unlocked
        case locked
        case authenticating
    }

    @Published private(set) var state: State = .unlocked
    @Published private(set) var lockedAt: Date?
    @Published private(set) var isPreview = false
    @Published private(set) var activityPulse = 0
    @Published private(set) var authFailed = false
    @Published private(set) var autoUnlockAt: Date?

    var onNeedsPermission: (() -> Void)?

    private let blocker = InputBlocker()
    private let authenticator = Authenticator()
    private var overlays: [OverlayWindow] = []
    private var autoUnlockTimer: Timer?
    private var authTimeout: DispatchWorkItem?
    private var previewTimer: Timer?
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var systemLockObservers: [NSObjectProtocol] = []
    private var activationObserver: NSObjectProtocol?

    /// 認証中は Dock・メニューバー・アプリ切替・強制終了を無効化（キオスクモード）
    private static let authPresentation: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching,
        .disableForceQuit, .disableSessionTermination, .disableHideApplication,
    ]

    var isLocked: Bool { state != .unlocked }
    var biometryAvailable: Bool { authenticator.biometryAvailable }

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.overlays.isEmpty else { return }
            self.showOverlays()
        }

        // 蓋を閉じて画面がスリープすると macOS 自体のロック画面が出ることがある。
        // その間は macOS が保護しているので入力ブロックを止め、ログインパスワードを入力できるようにする。
        let center = DistributedNotificationCenter.default()
        systemLockObservers = [
            center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.systemDidLock()
            },
            center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.systemDidUnlock()
            },
        ]
    }

    private func systemDidLock() {
        guard state != .unlocked else { return }
        if state == .authenticating {
            // relock() が走らないよう先に状態を戻してから認証を取り消す
            state = .locked
            authTimeout?.cancel()
            authTimeout = nil
            endAuthPresentation()
            authenticator.cancel()
        }
        blocker.passThrough = true
        overlays.forEach { $0.orderOut(nil) }
    }

    private func systemDidUnlock() {
        guard state != .unlocked else { return }
        // macOS のログインパスワードで本人確認済みなので Bastion も解除する
        unlock()
    }

    // MARK: - Lock

    func lock() {
        guard state == .unlocked else { return }
        endPreview()

        guard Permissions.isAccessibilityTrusted else {
            Permissions.requestAccessibility()
            onNeedsPermission?()
            return
        }

        let prefs = Preferences.shared
        blocker.unlockShortcut = prefs.unlockShortcut
        blocker.onUnlockShortcut = { [weak self] in self?.beginUnlock() }
        blocker.onActivity = { [weak self] in self?.activityPulse += 1 }

        guard blocker.start() else {
            let alert = NSAlert()
            alert.messageText = "入力をロックできませんでした"
            alert.informativeText = "システム設定 › プライバシーとセキュリティ › アクセシビリティ で Bastion を許可してください。"
            alert.addButton(withTitle: "システム設定を開く")
            alert.addButton(withTitle: "閉じる")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                Permissions.openAccessibilitySettings()
            }
            return
        }

        authFailed = false
        lockedAt = Date()
        state = .locked
        showOverlays()

        if prefs.autoUnlockMinutes > 0 {
            let interval = TimeInterval(prefs.autoUnlockMinutes * 60)
            autoUnlockAt = Date().addingTimeInterval(interval)
            autoUnlockTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.unlock()
            }
        }
    }

    // MARK: - Unlock

    func beginUnlock() {
        guard state == .locked else { return }
        guard Preferences.shared.requireAuth else {
            unlock()
            return
        }

        state = .authenticating
        authFailed = false
        // 認証ダイアログを操作できるよう一時的に入力を通す。
        // オーバーレイは画面を覆ったまま残し、背後のアプリへのクリックは届かない。
        blocker.passThrough = true
        overlays.forEach { $0.level = .floating }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = Self.authPresentation
        (overlays.first(where: { $0.isPrimary }) ?? overlays.first)?.makeKeyAndOrderFront(nil)
        watchActivations()

        let timeout = DispatchWorkItem { [weak self] in self?.authenticator.cancel() }
        authTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)

        authenticator.authenticate(reason: "入力ロックを解除") { [weak self] success in
            guard let self, self.state == .authenticating else { return }
            if success {
                self.unlock()
            } else {
                self.relock()
            }
        }
    }

    /// 認証中に Bastion・認証UI 以外のアプリが前面に来たら、すぐにロックへ戻す
    private func watchActivations() {
        stopWatchingActivations()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.state == .authenticating,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app == NSRunningApplication.current { return }
            let id = (app.bundleIdentifier ?? "").lowercased()
            let authUI = ["coreauth", "localauthentication", "securityagent", "loginwindow"]
            if authUI.contains(where: { id.contains($0) }) { return }
            self.state = .locked // 補完ハンドラの relock より先に状態を確定
            self.authenticator.cancel()
            self.relock()
        }
    }

    private func stopWatchingActivations() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func endAuthPresentation() {
        stopWatchingActivations()
        NSApp.presentationOptions = []
    }

    private func relock() {
        endAuthPresentation()
        authTimeout?.cancel()
        authTimeout = nil
        blocker.passThrough = false
        authFailed = true
        state = .locked
        overlays.forEach {
            $0.level = .screenSaver
            $0.orderFrontRegardless()
        }
    }

    func unlock() {
        guard state != .unlocked else { return }
        endAuthPresentation()
        authTimeout?.cancel()
        authTimeout = nil
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        autoUnlockAt = nil
        blocker.stop()
        authenticator.cancel()
        hideOverlays()
        state = .unlocked
        lockedAt = nil
        authFailed = false
        if let app = previousApp, app != NSRunningApplication.current {
            app.activate(options: [])
        }
        previousApp = nil
    }

    // MARK: - Preview

    func preview(seconds: TimeInterval = 5) {
        guard state == .unlocked else { return }
        isPreview = true
        lockedAt = Date()
        showOverlays()
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.endPreview()
        }
    }

    private func endPreview() {
        guard isPreview else { return }
        previewTimer?.invalidate()
        previewTimer = nil
        isPreview = false
        lockedAt = nil
        hideOverlays()
    }

    // MARK: - Overlays

    private func showOverlays() {
        hideOverlays()
        let primary = NSScreen.main ?? NSScreen.screens.first
        overlays = NSScreen.screens.map { screen in
            OverlayWindow(screen: screen, isPrimary: screen == primary)
        }
        overlays.forEach {
            if isPreview { $0.ignoresMouseEvents = true }
            $0.orderFrontRegardless()
        }
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }
}
