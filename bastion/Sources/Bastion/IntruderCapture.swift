import AVFoundation
import Foundation

/// ロック中の操作や解除失敗のときに、カメラで静止画を 1 枚だけ撮って記録する。
/// 保存先: ~/Pictures/Rusuban/ 。30 日より古いものは起動時に自動削除。
/// 画像は端末内に保存するだけで、通知をオンにしている場合のみ Pushover に添付して送る。
final class IntruderCapture: NSObject {
    static let shared = IntruderCapture()

    private let queue = DispatchQueue(label: "rusuban.intruder")
    private var session: AVCaptureSession?
    private var output: AVCapturePhotoOutput?
    private var pending: ((URL?) -> Void)?
    private var capturing = false

    static var folder: URL {
        let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pics.appendingPathComponent("Rusuban")
    }

    /// 権限を確認し、許可されていれば 1 枚撮って保存する。完了で保存先 URL（失敗時 nil）を返す。
    func capture(completion: @escaping (URL?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            begin(completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.begin(completion) } else { DispatchQueue.main.async { completion(nil) } }
            }
        default:
            completion(nil)
        }
    }

    func purgeOld(days: Int = 30) {
        queue.async {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            for url in items {
                if let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate, date < cutoff {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - 内部

    private func begin(_ completion: @escaping (URL?) -> Void) {
        queue.async { [weak self] in
            guard let self, !self.capturing else { DispatchQueue.main.async { completion(nil) }; return }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            let session = AVCaptureSession()
            session.sessionPreset = .photo
            guard session.canAddInput(input) else { DispatchQueue.main.async { completion(nil) }; return }
            session.addInput(input)
            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else { DispatchQueue.main.async { completion(nil) }; return }
            session.addOutput(output)
            self.session = session
            self.output = output
            self.pending = completion
            self.capturing = true
            session.startRunning()
            // 露出が安定するまで少し待ってから撮る
            self.queue.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, self.capturing else { return }
                self.output?.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func finish(_ url: URL?) {
        session?.stopRunning()
        session = nil
        output = nil
        capturing = false
        let cb = pending
        pending = nil
        DispatchQueue.main.async { cb?(url) }
    }
}

extension IntruderCapture: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { finish(nil); return }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = Self.folder.appendingPathComponent("intruder_\(f.string(from: Date())).jpg")
        do { try data.write(to: url); finish(url) } catch { finish(nil) }
    }
}
