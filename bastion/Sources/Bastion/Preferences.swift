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

    @Published var hotCorner: HotCorner { didSet { defaults.set(hotCorner.rawValue, forKey: "hotCorner") } }
    @Published var hotCornerDelay: Double { didSet { defaults.set(hotCornerDelay, forKey: "hotCornerDelay") } }

    @Published var preventSleep: Bool { didSet { defaults.set(preventSleep, forKey: "preventSleep") } }
    @Published var keepDisplayOn: Bool { didSet { defaults.set(keepDisplayOn, forKey: "keepDisplayOn") } }
    @Published var awakeWhileAgentsRun: Bool { didSet { defaults.set(awakeWhileAgentsRun, forKey: "awakeWhileAgentsRun") } }

    @Published var closedLidEnabled: Bool { didSet { defaults.set(closedLidEnabled, forKey: "closedLidEnabled") } }
    @Published var clamshellThermalGuard: Bool { didSet { defaults.set(clamshellThermalGuard, forKey: "clamshellThermalGuard") } }
    @Published var clamshellMinBattery: Int { didSet { defaults.set(clamshellMinBattery, forKey: "clamshellMinBattery") } }

    @Published var allowRemoteControl: Bool { didSet { defaults.set(allowRemoteControl, forKey: "allowRemoteControl") } }
    @Published var remoteCurtain: Bool { didSet { defaults.set(remoteCurtain, forKey: "remoteCurtain") } }
    @Published var remoteCompact: Bool { didSet { defaults.set(remoteCompact, forKey: "remoteCompact") } }

    @Published var requireAuth: Bool { didSet { defaults.set(requireAuth, forKey: "requireAuth") } }
    @Published var autoUnlockMinutes: Int { didSet { defaults.set(autoUnlockMinutes, forKey: "autoUnlockMinutes") } }

    @Published var overlayStyle: OverlayStyle { didSet { defaults.set(overlayStyle.rawValue, forKey: "overlayStyle") } }
    @Published var cardPosition: CardPosition { didSet { defaults.set(cardPosition.rawValue, forKey: "cardPosition") } }
    @Published var message: String { didSet { defaults.set(message, forKey: "message") } }
    @Published var showClock: Bool { didSet { defaults.set(showClock, forKey: "showClock") } }
    @Published var showTimer: Bool { didSet { defaults.set(showTimer, forKey: "showTimer") } }
    @Published var showAgents: Bool { didSet { defaults.set(showAgents, forKey: "showAgents") } }
    @Published var cardOnAllDisplays: Bool { didSet { defaults.set(cardOnAllDisplays, forKey: "cardOnAllDisplays") } }

    private init() {
        defaults.register(defaults: [
            "hotCorner": HotCorner.none.rawValue,
            "hotCornerDelay": 0.5,
            "preventSleep": true,
            "keepDisplayOn": true,
            "awakeWhileAgentsRun": false,
            "closedLidEnabled": false,
            "clamshellThermalGuard": true,
            "clamshellMinBattery": 20,
            "allowRemoteControl": false,
            "remoteCompact": true,
            "remoteCurtain": true,
            "requireAuth": true,
            "autoUnlockMinutes": 0,
            "overlayStyle": OverlayStyle.clear.rawValue,
            "cardPosition": CardPosition.bottom.rawValue,
            "message": "",
            "showClock": true,
            "showTimer": true,
            "showAgents": true,
            "cardOnAllDisplays": false,
        ])
        lockShortcut = Self.load("lockShortcut", from: defaults) ?? .defaultLock
        unlockShortcut = Self.load("unlockShortcut", from: defaults) ?? .defaultUnlock
        hotCorner = HotCorner(rawValue: defaults.string(forKey: "hotCorner") ?? "") ?? .none
        hotCornerDelay = defaults.double(forKey: "hotCornerDelay")
        preventSleep = defaults.bool(forKey: "preventSleep")
        keepDisplayOn = defaults.bool(forKey: "keepDisplayOn")
        awakeWhileAgentsRun = defaults.bool(forKey: "awakeWhileAgentsRun")
        closedLidEnabled = defaults.bool(forKey: "closedLidEnabled")
        clamshellThermalGuard = defaults.bool(forKey: "clamshellThermalGuard")
        clamshellMinBattery = defaults.integer(forKey: "clamshellMinBattery")
        allowRemoteControl = defaults.bool(forKey: "allowRemoteControl")
        remoteCurtain = defaults.bool(forKey: "remoteCurtain")
        remoteCompact = defaults.bool(forKey: "remoteCompact")
        requireAuth = defaults.bool(forKey: "requireAuth")
        autoUnlockMinutes = defaults.integer(forKey: "autoUnlockMinutes")
        overlayStyle = OverlayStyle(rawValue: defaults.string(forKey: "overlayStyle") ?? "") ?? .clear
        cardPosition = CardPosition(rawValue: defaults.string(forKey: "cardPosition") ?? "") ?? .bottom
        message = defaults.string(forKey: "message") ?? ""
        showClock = defaults.bool(forKey: "showClock")
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
