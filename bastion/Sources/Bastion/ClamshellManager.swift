import AppKit
import Foundation
import IOKit.ps

/// 外部ディスプレイなしで蓋を閉じてもスリープさせない（`pmset -a disablesleep 1`）。
/// root 権限が必要なため、初回セットアップで pmset のこの2コマンドだけを
/// パスワードなしで実行できる sudoers ルールを /etc/sudoers.d/bastion に登録する。
final class ClamshellManager: ObservableObject {
    static let shared = ClamshellManager()

    @Published private(set) var isHelperInstalled = false
    /// disablesleep 1 を適用中
    @Published private(set) var isEngaged = false
    /// 安全装置で停止している理由（高温・バッテリー残量）
    @Published private(set) var safetyStopReason: String?

    static let sudoersPath = "/etc/sudoers.d/bastion"
    private let engagedKey = "clamshellEngaged"
    private let queue = DispatchQueue(label: "bastion.clamshell")
    private var watchdog: Process?
    private var safetyTimer: Timer?
    private var wantAwake = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reevaluate() }
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reevaluate()
        }
    }

    // MARK: - 起動時・終了時

    /// 前回の強制終了などで disablesleep 1 が残っていたら戻す
    func recoverOnLaunch() {
        if UserDefaults.standard.bool(forKey: engagedKey) {
            Self.runPmset(disable: false)
            UserDefaults.standard.set(false, forKey: engagedKey)
        }
        refreshHelperStatus()
    }

    /// 終了時は同期的に元へ戻す
    func disengageNow() {
        guard isEngaged else { return }
        Self.runPmset(disable: false)
        stopWatchdog()
        isEngaged = false
        UserDefaults.standard.set(false, forKey: engagedKey)
    }

    // MARK: - 状態更新

    /// PowerManager から「スリープ防止したいか」を受け取る
    func update(wantAwake: Bool) {
        self.wantAwake = wantAwake
        reevaluate()
    }

    private func reevaluate() {
        let reason = currentSafetyStopReason()
        if safetyStopReason != reason { safetyStopReason = reason }

        let want = Preferences.shared.closedLidEnabled && isHelperInstalled && wantAwake && reason == nil
        guard want != isEngaged else { return }
        setEngaged(want)
    }

    private func setEngaged(_ on: Bool) {
        isEngaged = on
        UserDefaults.standard.set(on, forKey: engagedKey)
        if on { startWatchdog() }
        queue.async {
            let ok = Self.runPmset(disable: on)
            DispatchQueue.main.async {
                if !on { self.stopWatchdog() }
                if on && !ok {
                    // ルールが削除された等。状態を戻して再確認
                    self.isEngaged = false
                    UserDefaults.standard.set(false, forKey: self.engagedKey)
                    self.stopWatchdog()
                    self.refreshHelperStatus()
                }
            }
        }
    }

    // MARK: - 安全装置

    private func currentSafetyStopReason() -> String? {
        let prefs = Preferences.shared
        if prefs.clamshellThermalGuard {
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical: return "本体が高温のため停止中"
            default: break
            }
        }
        if let battery = Self.batteryStatus(), battery.onBattery, battery.percent <= prefs.clamshellMinBattery {
            return "バッテリー残量 \(battery.percent)% のため停止中"
        }
        return nil
    }

    static func batteryStatus() -> (percent: Int, onBattery: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onBattery = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            return (current * 100 / max, onBattery)
        }
        return nil
    }

    // MARK: - ウォッチドッグ

    /// Bastion が強制終了しても disablesleep を必ず 0 に戻すための子プロセス。
    /// 親（Bastion）が消えたら pmset を戻して終了する。
    private func startWatchdog() {
        stopWatchdog()
        let script = """
        while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 3; done
        /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        watchdog = process
    }

    private func stopWatchdog() {
        if let watchdog, watchdog.isRunning { watchdog.terminate() }
        watchdog = nil
    }

    // MARK: - セットアップ（sudoers ルール）

    func refreshHelperStatus() {
        queue.async {
            // -n: パスワードを聞かずに、許可されていれば 0 を返す
            let installed = Self.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"])
            DispatchQueue.main.async {
                if self.isHelperInstalled != installed { self.isHelperInstalled = installed }
                self.reevaluate()
            }
        }
    }

    /// 管理者パスワードを1回だけ求め、pmset の2コマンドに限定した sudoers ルールを登録する
    func installHelper(completion: @escaping (String?) -> Void) {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            completion("ユーザー名に使用できない文字が含まれています")
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        // visudo で構文検査してから 0440 root:wheel で配置（壊れたルールで sudo を壊さない）
        let shell = """
        tmp=$(/usr/bin/mktemp) && \
        /usr/bin/printf '%s\\n' '\(rule)' > "$tmp" && \
        /usr/sbin/visudo -cf "$tmp" && \
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(Self.sudoersPath); \
        status=$?; /bin/rm -f "$tmp"; exit $status
        """
        runAsAdmin(shell, completion: completion)
    }

    /// ルールを削除し、disablesleep も 0 に戻す
    func uninstallHelper(completion: @escaping (String?) -> Void) {
        disengageNow()
        runAsAdmin("/usr/bin/pmset -a disablesleep 0; /bin/rm -f \(Self.sudoersPath)", completion: completion)
    }

    private func runAsAdmin(_ shell: String, completion: @escaping (String?) -> Void) {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        do shell script "\(escaped)" with prompt "Bastion が「蓋を閉じてもスリープしない」機能を設定します。" with administrator privileges
        """
        // NSAppleScript はメインスレッドで実行する
        DispatchQueue.main.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let message = error.map { ($0[NSAppleScript.errorMessage] as? String) ?? "セットアップに失敗しました" }
            self.refreshHelperStatus()
            completion(message)
        }
    }

    // MARK: - 実行

    @discardableResult
    private static func runPmset(disable: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disable ? "1" : "0"])
    }

    private static func run(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
