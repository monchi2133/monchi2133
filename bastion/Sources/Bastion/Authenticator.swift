import Foundation
import LocalAuthentication

/// Touch ID（Apple Watch）または macOS のログインパスワードで本人確認する
final class Authenticator {
    private var context: LAContext?

    var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "キャンセル"
        context = ctx
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 認証手段が無い環境では閉じ込めを避けるため解除を許可する
            completion(true)
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}
