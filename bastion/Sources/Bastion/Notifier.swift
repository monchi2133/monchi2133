import Foundation

/// スマホ通知。Pushover / Slack / 汎用Webhook に送る。
/// AI が終わった・入力待ちになった・ロック中に誰かが触った、を離れた場所へ知らせる。
final class Notifier {
    static let shared = Notifier()

    private let session = URLSession(configuration: .ephemeral)
    private var lastKey = ""
    private var lastSent = Date.distantPast

    // MARK: - 高レベル

    func agentFinished(_ detail: String?) {
        let body = detail.map { "AI の作業が完了しました（\($0)）" } ?? "AI の作業が完了しました"
        guard Preferences.shared.notifyOnFinish else { return }
        send(title: "るすばん：作業完了", body: body)
    }

    func agentWaiting(_ message: String?) {
        guard Preferences.shared.notifyOnWaiting else { return }
        let body = (message?.isEmpty == false) ? message! : "AI が入力待ちになりました"
        send(title: "るすばん：入力待ち", body: body)
    }

    func intruder(at date: Date, imageURL: URL?) {
        guard Preferences.shared.notifyOnIntruder else { return }
        let f = DateFormatter(); f.dateFormat = "H:mm:ss"
        send(title: "るすばん：ロック中に操作を検知", body: "\(f.string(from: date)) に操作がありました", imageURL: imageURL)
    }

    /// 設定画面のテスト送信
    func sendTest(completion: @escaping (String?) -> Void) {
        deliver(title: "るすばん：テスト通知", body: "通知の設定は正しく動いています。", imageURL: nil, completion: completion)
    }

    // MARK: - 送信

    func send(title: String, body: String, imageURL: URL? = nil) {
        guard Preferences.shared.notifyEnabled else { return }
        // 同じ通知の連発を抑える
        let key = title + "|" + body
        if key == lastKey && Date().timeIntervalSince(lastSent) < 8 { return }
        lastKey = key
        lastSent = Date()
        deliver(title: title, body: body, imageURL: imageURL, completion: { _ in })
    }

    private func deliver(title: String, body: String, imageURL: URL?, completion: @escaping (String?) -> Void) {
        let prefs = Preferences.shared
        switch prefs.notifyProvider {
        case .pushover: sendPushover(title: title, body: body, imageURL: imageURL, completion: completion)
        case .slack:    sendSlack(title: title, body: body, completion: completion)
        case .webhook:  sendWebhook(title: title, body: body, completion: completion)
        }
    }

    // MARK: - Pushover

    private func sendPushover(title: String, body: String, imageURL: URL?, completion: @escaping (String?) -> Void) {
        let prefs = Preferences.shared
        guard !prefs.pushoverToken.isEmpty, !prefs.pushoverUser.isEmpty else {
            completion("Pushover のトークンとユーザーキーを入力してください"); return
        }
        guard let url = URL(string: "https://api.pushover.net/1/messages.json") else { completion("URL エラー"); return }
        var fields: [String: String] = [
            "token": prefs.pushoverToken, "user": prefs.pushoverUser,
            "title": title, "message": body,
        ]
        let imageData = imageURL.flatMap { try? Data(contentsOf: $0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var data = Data()
        func append(_ s: String) { data.append(s.data(using: .utf8)!) }
        for (k, v) in fields {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        if let imageData {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"attachment\"; filename=\"intruder.jpg\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            data.append(imageData)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        _ = fields // silence unused in some paths
        run(request, body: data, completion: completion)
    }

    // MARK: - Slack

    private func sendSlack(title: String, body: String, completion: @escaping (String?) -> Void) {
        let hook = Preferences.shared.slackWebhook
        guard let url = URL(string: hook), !hook.isEmpty else { completion("Slack の Webhook URL を入力してください"); return }
        let payload: [String: Any] = ["text": "*\(title)*\n\(body)"]
        postJSON(url, payload, completion)
    }

    // MARK: - 汎用Webhook

    private func sendWebhook(title: String, body: String, completion: @escaping (String?) -> Void) {
        let hook = Preferences.shared.webhookURL
        guard let url = URL(string: hook), !hook.isEmpty else { completion("Webhook URL を入力してください"); return }
        let payload: [String: Any] = ["title": title, "body": body, "timestamp": Date().timeIntervalSince1970]
        postJSON(url, payload, completion)
    }

    private func postJSON(_ url: URL, _ payload: [String: Any], _ completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        run(request, body: data, completion: completion)
    }

    private func run(_ request: URLRequest, body: Data, completion: @escaping (String?) -> Void) {
        var req = request
        req.httpBody = body
        req.timeoutInterval = 15
        session.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                if let error { completion("送信に失敗しました：\(error.localizedDescription)"); return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    completion("送信に失敗しました（HTTP \(http.statusCode)）"); return
                }
                completion(nil)
            }
        }.resume()
    }
}
