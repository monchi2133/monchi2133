import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        Publishers.Merge3(
            LockController.shared.objectWillChange.map { _ in () },
            AgentMonitor.shared.objectWillChange.map { _ in () },
            PowerManager.shared.objectWillChange.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.updateIcon() }
        .store(in: &cancellables)
    }

    private func updateIcon() {
        let locked = LockController.shared.isLocked
        let agentsRunning = !AgentMonitor.shared.agents.isEmpty
        let name = locked ? "lock.shield.fill" : (agentsRunning ? "shield.lefthalf.filled" : "lock.shield")
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Bastion")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = locked ? "Bastion — ロック中" : "Bastion"
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = Preferences.shared
        let agents = AgentMonitor.shared.agents

        let header = NSMenuItem(title: "Bastion", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let status = NSMenuItem(
            title: agents.isEmpty ? "AIエージェント: 検出なし" : "実行中: " + agents.joined(separator: "、"),
            action: nil, keyEquivalent: ""
        )
        status.isEnabled = false
        status.image = NSImage(systemSymbolName: agents.isEmpty ? "circle" : "sparkles", accessibilityDescription: nil)
        menu.addItem(status)

        if PowerManager.shared.isPreventingSleep {
            let awake = NSMenuItem(title: "スリープ防止中", action: nil, keyEquivalent: "")
            awake.isEnabled = false
            awake.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
            menu.addItem(awake)
        }

        menu.addItem(.separator())

        let lockItem = NSMenuItem(title: "このMacをロック", action: #selector(lockNow), keyEquivalent: "")
        lockItem.target = self
        lockItem.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        applyShortcut(prefs.lockShortcut, to: lockItem)
        menu.addItem(lockItem)

        menu.addItem(.separator())

        menu.addItem(toggle("ロック中はスリープを防止", on: prefs.preventSleep, action: #selector(togglePreventSleep)))
        menu.addItem(toggle("AIエージェント実行中はスリープを防止", on: prefs.awakeWhileAgentsRun, action: #selector(toggleAgentAwake)))

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "Bastion について", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func toggle(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func applyShortcut(_ shortcut: Shortcut, to item: NSMenuItem) {
        // 表示用。実際の発火は HotKeyManager が担う
        if shortcut.key.count == 1 {
            item.keyEquivalent = shortcut.key.lowercased()
            item.keyEquivalentModifierMask = shortcut.flags
        }
    }

    // MARK: Actions

    @objc private func lockNow() {
        // メニューが閉じてからロックする
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { LockController.shared.lock() }
    }

    @objc private func togglePreventSleep() { Preferences.shared.preventSleep.toggle() }
    @objc private func toggleAgentAwake() { Preferences.shared.awakeWhileAgentsRun.toggle() }
    @objc private func showSettings() { openSettings() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
