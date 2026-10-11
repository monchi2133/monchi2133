import Foundation
import IOBluetooth

/// 【実験的】身につけた iPhone / Apple Watch が近づいたら自動で解除する。
/// ペアリング済み Bluetooth 機器の接続状態を見て、選んだ機器が「接続中」になったら解除する。
/// 機器や環境によっては接続状態が安定しないため、確実な解除手段としては使わないこと。
final class ProximityMonitor {
    static let shared = ProximityMonitor()

    private var timer: Timer?
    private var wasPresent = false

    struct Device: Identifiable, Hashable {
        var address: String
        var name: String
        var id: String { address }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// ペアリング済み機器の一覧（設定の選択用）
    static func pairedDevices() -> [Device] {
        guard let list = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return list.map { Device(address: $0.addressString ?? "", name: $0.name ?? ($0.addressString ?? "不明な機器")) }
            .filter { !$0.address.isEmpty }
    }

    private func tick() {
        let prefs = Preferences.shared
        guard prefs.proximityEnabled, !prefs.proximityDevice.isEmpty else { wasPresent = false; return }
        guard LockController.shared.state == .locked else { return }

        let present = isPresent(address: prefs.proximityDevice)
        // 「居なかった → 居る」に変わった瞬間だけ解除する（ロック直後の誤爆を防ぐ）
        if present && !wasPresent {
            LockController.shared.unlock()
        }
        wasPresent = present
    }

    private func isPresent(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        return device.isConnected()
    }
}
