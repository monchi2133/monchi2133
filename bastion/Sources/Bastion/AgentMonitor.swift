import Darwin
import Foundation

/// 実行中の AI コーディングエージェント（Claude Code / Codex など）を検出する
final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()

    @Published private(set) var agents: [String] = []

    private var timer: Timer?
    private let queue = DispatchQueue(label: "bastion.agent-monitor", qos: .utility)

    /// 実行ファイル名 → 表示名
    private static let executables: [String: String] = [
        "claude": "Claude Code",
        "codex": "Codex",
        "cursor-agent": "Cursor Agent",
        "aider": "Aider",
        "gemini": "Gemini CLI",
        "opencode": "OpenCode",
        "goose": "Goose",
        "amp": "Amp",
        "copilot": "Copilot CLI",
        "qwen": "Qwen Code",
        "crush": "Crush",
        "droid": "Factory Droid",
    ]

    /// 実行ファイルのパスに含まれる文字列 → 表示名（ネイティブ版 Claude Code はバージョン名のバイナリ）
    private static let pathHints: [String: String] = [
        "/claude/versions/": "Claude Code",
        "/.claude/local/": "Claude Code",
        "/codex/": "Codex",
    ]

    /// node / bun / python などで動くエージェントの引数ヒント
    private static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]
    private static let argumentHints: [String: String] = [
        "@anthropic-ai/claude-code": "Claude Code",
        "@openai/codex": "Codex",
        "@google/gemini-cli": "Gemini CLI",
        "@github/copilot": "Copilot CLI",
        "opencode-ai": "OpenCode",
        "@qwen-code/qwen-code": "Qwen Code",
        "/bin/aider": "Aider",
    ]

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func scan() {
        queue.async {
            let found = Self.detect()
            DispatchQueue.main.async {
                if found != self.agents { self.agents = found }
            }
        }
    }

    private static func detect() -> [String] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }

        let ownPID = getpid()
        var found = Set<String>()
        var nameBuffer = [CChar](repeating: 0, count: 256)
        var pathBuffer = [CChar](repeating: 0, count: 4096)

        for pid in pids.prefix(Int(count)) where pid > 0 && pid != ownPID {
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            guard nameLength > 0 else { continue }
            let name = String(cString: nameBuffer).lowercased()

            if let display = executables[name] {
                found.insert(display)
                continue
            }
            if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
                let path = String(cString: pathBuffer).lowercased()
                if let hit = pathHints.first(where: { path.contains($0.key) }) {
                    found.insert(hit.value)
                    continue
                }
            }
            if interpreters.contains(name), let args = arguments(of: pid) {
                for (hint, display) in argumentHints where args.contains(hint) {
                    found.insert(display)
                }
            }
        }
        return found.sorted()
    }

    private static func arguments(of pid: pid_t) -> String? {
        var argMax: Int32 = 0
        var argMaxSize = MemoryLayout<Int32>.size
        var argMaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMaxMib, 2, &argMax, &argMaxSize, nil, 0) == 0, argMax > 0 else { return nil }

        var size = Int(argMax)
        var buffer = [UInt8](repeating: 0, count: size)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return nil }

        let bytes = buffer[4..<size].map { $0 == 0 ? UInt8(ascii: " ") : $0 }
        return String(decoding: bytes, as: UTF8.self).lowercased()
    }
}
