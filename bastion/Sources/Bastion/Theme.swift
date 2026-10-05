import SwiftUI

enum Theme {
    static let accent = Color(red: 0.20, green: 0.83, blue: 0.60)       // エメラルド
    static let accentDeep = Color(red: 0.05, green: 0.55, blue: 0.48)
    static let warning = Color(red: 1.00, green: 0.42, blue: 0.42)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
