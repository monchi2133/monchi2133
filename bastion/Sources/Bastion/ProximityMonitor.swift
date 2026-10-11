import Foundation

/// 近接オート解除は、iPhone / Apple Watch の BLE を第三者アプリから確実に検出できないため廃止した。
/// 将来 iPhone ショートカット連携などで作り直す余地を残して、空の実装だけ置いておく。
final class ProximityMonitor {
    static let shared = ProximityMonitor()
    func start() {}
}
