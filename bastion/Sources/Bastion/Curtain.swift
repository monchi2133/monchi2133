import CoreGraphics

/// 目の前のディスプレイだけを真っ暗にする（カーテンモード）。
/// ガンマ（ディスプレイへ出力する直前の明るさ補正）を 0 にするので、画面の中身そのものは変わらず、
/// 画面共有・Chrome リモートデスクトップが取り込む映像はそのまま見える。
/// ガンマはアプリが終了すると macOS が自動で元に戻すため、強制終了しても真っ暗のままにはならない。
enum Curtain {
    private(set) static var isDrawn = false

    static func draw() {
        for display in activeDisplays() {
            CGSetDisplayTransferByFormula(display, 0, 0, 1, 0, 0, 1, 0, 0, 1)
        }
        isDrawn = true
    }

    static func open() {
        guard isDrawn else { return }
        CGDisplayRestoreColorSyncSettings()
        isDrawn = false
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}
