import Combine
import Foundation

/// Claude Code などのフックが書き込む状態ファイルを読み、ロック画面に進捗を出す。
/// ファイル: ~/.ailockkeeper/status.json
///   {"tool":"Claude Code","state":"running|waiting|done","message":"テスト実行中","progress":"3/5"}
/// フックが無くても AgentMonitor のプロセス検出だけで「実行中／完了」は分かる。
final class AgentStatus: ObservableObject {
    static let shared = AgentStatus()

    struct Info: Equatable {
        var tool: String
        var state: String      // running / waiting / done
        var message: String
        var progress: String
    }

    /// ロック画面などに出す 1 行（例: "Claude Code：テスト実行中 (3/5)"）。無ければ nil。
    @Published private(set) var line: String?
    @Published private(set) var isWaiting = false

    private var timer: Timer?
    private var lastModified: Date?
    private var lastState: String?
    private let fileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ailockkeeper/status.json")
    }()

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let modified = attrs[.modificationDate] as? Date else {
            if line != nil { line = nil; isWaiting = false; lastState = nil }
            return
        }
        // 古い情報（5 分以上更新なし）は無視する
        if Date().timeIntervalSince(modified) > 300 {
            if line != nil { line = nil; isWaiting = false; lastState = nil }
            return
        }
        if modified == lastModified { return }
        lastModified = modified

        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let info = Info(
            tool: (obj["tool"] as? String) ?? "AI",
            state: (obj["state"] as? String)?.lowercased() ?? "running",
            message: (obj["message"] as? String) ?? "",
            progress: (obj["progress"] as? String) ?? ""
        )
        apply(info)
    }

    private func apply(_ info: Info) {
        var text = info.tool
        if !info.message.isEmpty { text += "：\(info.message)" }
        else {
            switch info.state {
            case "waiting": text += "：入力待ち"
            case "done": text += "：完了"
            default: text += "：実行中"
            }
        }
        if !info.progress.isEmpty { text += " (\(info.progress))" }
        line = text
        isWaiting = info.state == "waiting"

        // 状態が変わったときだけ通知
        if info.state != lastState {
            switch info.state {
            case "waiting": Notifier.shared.agentWaiting(info.message.isEmpty ? nil : "\(info.tool)：\(info.message)")
            case "done": Notifier.shared.agentFinished(info.tool)
            default: break
            }
            lastState = info.state
        }
    }
}
