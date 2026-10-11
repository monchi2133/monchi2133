import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared
        let lock = LockController.shared

        installMainMenu()
        menuBar = MenuBarController(openSettings: { [weak self] in self?.openSettings() })

        HotKeyManager.shared.onPressed = { LockController.shared.lock() }
        prefs.$lockShortcut
            .sink { HotKeyManager.shared.register($0) }
            .store(in: &cancellables)

        AgentMonitor.shared.start()
        AgentMonitor.shared.onAllFinished = { detail in Notifier.shared.agentFinished(detail) }
        AgentStatus.shared.start()
        HotCornerMonitor.shared.start()
        ClamshellManager.shared.recoverOnLaunch()
        IntruderCapture.shared.purgeOld()

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

    /// メニューバー常駐アプリは既定でメインメニューを持たず、設定画面の入力欄で
    /// ⌘C / ⌘V / ⌘A が効かない。標準の「編集」メニューを用意してショートカットを有効にする。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "AIロックキーパーを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
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
