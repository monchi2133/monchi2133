import Foundation

enum OverlayStyle: String, CaseIterable, Identifiable {
    case clear, dim, frosted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clear: return "クリア"
        case .dim: return "暗く"
        case .frosted: return "すりガラス"
        }
    }
}

enum CardPosition: String, CaseIterable, Identifiable {
    case bottom, center
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottom: return "下部"
        case .center: return "中央"
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var lockShortcut: Shortcut { didSet { store(lockShortcut, "lockShortcut") } }
    @Published var unlockShortcut: Shortcut { didSet { store(unlockShortcut, "unlockShortcut") } }

    @Published var preventSleep: Bool { didSet { defaults.set(preventSleep, forKey: "preventSleep") } }
    @Published var keepDisplayOn: Bool { didSet { defaults.set(keepDisplayOn, forKey: "keepDisplayOn") } }
    @Published var awakeWhileAgentsRun: Bool { didSet { defaults.set(awakeWhileAgentsRun, forKey: "awakeWhileAgentsRun") } }

    @Published var closedLidEnabled: Bool { didSet { defaults.set(closedLidEnabled, forKey: "closedLidEnabled") } }
    @Published var clamshellThermalGuard: Bool { didSet { defaults.set(clamshellThermalGuard, forKey: "clamshellThermalGuard") } }
    @Published var clamshellMinBattery: Int { didSet { defaults.set(clamshellMinBattery, forKey: "clamshellMinBattery") } }

    @Published var requireAuth: Bool { didSet { defaults.set(requireAuth, forKey: "requireAuth") } }
    @Published var autoUnlockMinutes: Int { didSet { defaults.set(autoUnlockMinutes, forKey: "autoUnlockMinutes") } }

    @Published var overlayStyle: OverlayStyle { didSet { defaults.set(overlayStyle.rawValue, forKey: "overlayStyle") } }
    @Published var cardPosition: CardPosition { didSet { defaults.set(cardPosition.rawValue, forKey: "cardPosition") } }
    @Published var message: String { didSet { defaults.set(message, forKey: "message") } }
    @Published var showTimer: Bool { didSet { defaults.set(showTimer, forKey: "showTimer") } }
    @Published var showAgents: Bool { didSet { defaults.set(showAgents, forKey: "showAgents") } }
    @Published var cardOnAllDisplays: Bool { didSet { defaults.set(cardOnAllDisplays, forKey: "cardOnAllDisplays") } }

    private init() {
        defaults.register(defaults: [
            "preventSleep": true,
            "keepDisplayOn": true,
            "awakeWhileAgentsRun": false,
            "closedLidEnabled": false,
            "clamshellThermalGuard": true,
            "clamshellMinBattery": 20,
            "requireAuth": true,
            "autoUnlockMinutes": 0,
            "overlayStyle": OverlayStyle.clear.rawValue,
            "cardPosition": CardPosition.bottom.rawValue,
            "message": "",
            "showTimer": true,
            "showAgents": true,
            "cardOnAllDisplays": false,
        ])
        lockShortcut = Self.load("lockShortcut", from: defaults) ?? .defaultLock
        unlockShortcut = Self.load("unlockShortcut", from: defaults) ?? .defaultUnlock
        preventSleep = defaults.bool(forKey: "preventSleep")
        keepDisplayOn = defaults.bool(forKey: "keepDisplayOn")
        awakeWhileAgentsRun = defaults.bool(forKey: "awakeWhileAgentsRun")
        closedLidEnabled = defaults.bool(forKey: "closedLidEnabled")
        clamshellThermalGuard = defaults.bool(forKey: "clamshellThermalGuard")
        clamshellMinBattery = defaults.integer(forKey: "clamshellMinBattery")
        requireAuth = defaults.bool(forKey: "requireAuth")
        autoUnlockMinutes = defaults.integer(forKey: "autoUnlockMinutes")
        overlayStyle = OverlayStyle(rawValue: defaults.string(forKey: "overlayStyle") ?? "") ?? .clear
        cardPosition = CardPosition(rawValue: defaults.string(forKey: "cardPosition") ?? "") ?? .bottom
        message = defaults.string(forKey: "message") ?? ""
        showTimer = defaults.bool(forKey: "showTimer")
        showAgents = defaults.bool(forKey: "showAgents")
        cardOnAllDisplays = defaults.bool(forKey: "cardOnAllDisplays")
    }

    func resetShortcuts() {
        lockShortcut = .defaultLock
        unlockShortcut = .defaultUnlock
    }

    private func store(_ shortcut: Shortcut, _ key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
