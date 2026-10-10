import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared
        let lock = LockController.shared

        menuBar = MenuBarController(openSettings: { [weak self] in self?.openSettings() })

        HotKeyManager.shared.onPressed = { LockController.shared.lock() }
        prefs.$lockShortcut
            .sink { HotKeyManager.shared.register($0) }
            .store(in: &cancellables)

        AgentMonitor.shared.start()
        HotCornerMonitor.shared.start()
        ClamshellManager.shared.recoverOnLaunch()

        // 設定・ロック状態・エージェント検出が変わったらスリープ防止を再評価
        Publishers.Merge3(
            prefs.objectWillChange.map { _ in () },
            lock.objectWillChange.map { _ in () },
            AgentMonitor.shared.objectWillChange.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { PowerManager.shared.update() }
        .store(in: &cancellables)

        lock.onNeedsPermission = { [weak self] in self?.openSettings() }

        if !Permissions.isAccessibilityTrusted {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LockController.shared.unlock()
        Curtain.open()
        PowerManager.shared.releaseAll()
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
}
