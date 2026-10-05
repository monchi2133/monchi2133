import AppKit
import SwiftUI

/// 各ディスプレイを覆う透明なボーダーレスウィンドウ。画面の内容はそのまま見える。
final class OverlayWindow: NSWindow {
    let isPrimary: Bool

    init(screen: NSScreen, isPrimary: Bool) {
        self.isPrimary = isPrimary
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = OverlayView(isPrimary: isPrimary)
            .environmentObject(LockController.shared)
            .environmentObject(Preferences.shared)
            .environmentObject(AgentMonitor.shared)
            .environmentObject(PowerManager.shared)
        contentView = NSHostingView(rootView: root)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
