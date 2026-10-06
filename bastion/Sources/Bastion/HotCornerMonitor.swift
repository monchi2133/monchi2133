import AppKit

enum HotCorner: String, CaseIterable, Identifiable {
    case none, topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "なし"
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomRight: return "右下"
        }
    }
}

/// マウスカーソルを画面の角に置くとロックする（Bastion 独自のホットコーナー）。
/// macOS 標準のホットコーナーには他社アプリを割り当てられないため自前で監視する。
final class HotCornerMonitor {
    static let shared = HotCornerMonitor()

    private var timer: Timer?
    private var enteredAt: Date?
    /// ロック解除直後に角にカーソルがあっても再ロックしないよう、一度角から離れるまで無効
    private var armed = true

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let prefs = Preferences.shared
        let lock = LockController.shared
        guard prefs.hotCorner != .none else {
            enteredAt = nil
            return
        }
        if lock.isLocked || lock.isPreview {
            enteredAt = nil
            armed = false
            return
        }

        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
        guard isInCorner(point, of: screen.frame, corner: prefs.hotCorner) else {
            enteredAt = nil
            armed = true
            return
        }
        guard armed else { return }

        let start = enteredAt ?? Date()
        enteredAt = start
        if Date().timeIntervalSince(start) >= prefs.hotCornerDelay {
            armed = false
            enteredAt = nil
            lock.lock()
        }
    }

    private func isInCorner(_ p: NSPoint, of f: NSRect, corner: HotCorner) -> Bool {
        let margin: CGFloat = 4
        let left = p.x <= f.minX + margin
        let right = p.x >= f.maxX - margin - 1
        let bottom = p.y <= f.minY + margin
        let top = p.y >= f.maxY - margin - 1
        switch corner {
        case .none: return false
        case .topLeft: return top && left
        case .topRight: return top && right
        case .bottomLeft: return bottom && left
        case .bottomRight: return bottom && right
        }
    }
}
