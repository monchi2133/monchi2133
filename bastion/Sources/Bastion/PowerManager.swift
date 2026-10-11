import Foundation
import IOKit.pwr_mgt

/// IOPMAssertion（caffeinate 相当）でスリープを防ぐ
final class PowerManager: ObservableObject {
    static let shared = PowerManager()

    enum Mode: Equatable {
        case display  // ディスプレイもシステムも起こしたまま
        case system   // システムのみ（画面は消えても処理は継続）
    }

    @Published private(set) var mode: Mode?
    private var assertionID: IOPMAssertionID = 0
    private var sawAgentsThisLock = false

    var isPreventingSleep: Bool { mode != nil }

    func update() {
        let prefs = Preferences.shared
        let locked = LockController.shared.state != .unlocked
        let agentsRunning = !AgentMonitor.shared.agents.isEmpty

        if locked && agentsRunning { sawAgentsThisLock = true }
        if !locked { sawAgentsThisLock = false }

        var wanted: Mode?
        if locked && prefs.preventSleep {
            // AI が終わったら（このロック中に動いていて今は止まっている）スリープ防止を解除して電池を守る
            let doneAndIdle = prefs.releaseSleepWhenDone && sawAgentsThisLock && !agentsRunning
            if !doneAndIdle {
                wanted = prefs.keepDisplayOn ? .display : .system
            }
        } else if prefs.awakeWhileAgentsRun && agentsRunning {
            wanted = .system
        }
        apply(wanted)
        ClamshellManager.shared.update(wantAwake: wanted != nil)
    }

    func releaseAll() {
        apply(nil)
        ClamshellManager.shared.disengageNow()
    }

    private func apply(_ wanted: Mode?) {
        guard wanted != mode else { return }
        if mode != nil {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        mode = nil
        guard let wanted else { return }
        let type = wanted == .display
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AIロックキーパー: AIエージェント・長時間処理を継続中" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            mode = wanted
        }
    }
}
