import SwiftUI

struct OverlayView: View {
    let isPrimary: Bool

    @EnvironmentObject private var lock: LockController
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var agents: AgentMonitor
    @EnvironmentObject private var power: PowerManager

    @State private var glow = false
    @State private var nudge = false

    var body: some View {
        ZStack {
            background
            frame
            if isPrimary || prefs.cardOnAllDisplays {
                VStack {
                    Spacer()
                    card
                        .offset(x: nudge ? 8 : 0)
                    if prefs.cardPosition == .bottom {
                        Spacer().frame(height: 64)
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
        }
        .onChange(of: lock.activityPulse) { _ in shake() }
        .onChange(of: lock.authFailed) { failed in if failed { shake() } }
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        switch prefs.overlayStyle {
        case .clear:
            // 完全な透明だとクリックが背後に抜けるため、ごくわずかに色を付ける
            Color.black.opacity(0.02)
        case .dim:
            Color.black.opacity(0.38)
        case .frosted:
            VisualEffectBlur(material: .hudWindow, blending: .behindWindow)
        }
    }

    private var frame: some View {
        Rectangle()
            .strokeBorder(frameColor, lineWidth: 5)
            .opacity(glow ? 0.95 : 0.45)
            .shadow(color: frameColor.opacity(0.8), radius: glow ? 18 : 6)
            .allowsHitTesting(false)
    }

    private var frameColor: Color {
        lock.authFailed ? Theme.warning : Theme.accent
    }

    // MARK: Card

    private var card: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(lock.authFailed ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(Theme.accentGradient))
                    .frame(width: 52, height: 52)
                    .shadow(color: frameColor.opacity(0.6), radius: glow ? 14 : 6)
                Image(systemName: lock.state == .authenticating ? "person.badge.key.fill" : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                chips
            }

            Divider()
                .frame(height: 52)
                .overlay(Color.white.opacity(0.15))

            VStack(spacing: 6) {
                Image(systemName: lock.biometryAvailable ? "touchid" : "key.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(frameColor)
                Text(prefs.unlockShortcut.displayString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .foregroundColor(.white)
            }
            .frame(minWidth: 72)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        .frame(maxWidth: 640)
        .animation(.spring(response: 0.25, dampingFraction: 0.35), value: nudge)
    }

    private var title: String {
        if lock.isPreview { return prefs.message.isEmpty ? "このMacはロックされています" : prefs.message }
        switch lock.state {
        case .authenticating: return "Touch ID またはパスワードで認証してください"
        default:
            if lock.authFailed { return "認証できませんでした" }
            return prefs.message.isEmpty ? "このMacはロックされています" : prefs.message
        }
    }

    private var subtitle: String {
        if lock.state == .authenticating { return "キャンセルするとロック状態に戻ります" }
        let how = lock.biometryAvailable ? "Touch ID・パスワード" : "パスワード"
        return "入力はブロック中。作業はそのまま続いています — \(prefs.unlockShortcut.displayString) を押して\(how)で解除"
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if prefs.showTimer, let since = lock.lockedAt {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Chip(icon: "clock", text: Self.elapsed(from: since, to: context.date))
                }
            }
            if power.isPreventingSleep || (lock.isPreview && prefs.preventSleep) {
                Chip(icon: "bolt.fill", text: "スリープ防止")
            }
            if prefs.showAgents && !agents.agents.isEmpty {
                Chip(icon: "sparkles", text: agents.agents.joined(separator: "・") + " 実行中", highlighted: true)
            }
            if let at = lock.autoUnlockAt {
                Chip(icon: "timer", text: "自動解除 " + Self.timeFormatter.string(from: at))
            }
        }
    }

    private func shake() {
        nudge = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { nudge = false }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    static func elapsed(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

private struct Chip: View {
    let icon: String
    let text: String
    var highlighted = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(highlighted ? Theme.accent.opacity(0.22) : Color.white.opacity(0.10)))
        .foregroundColor(highlighted ? Theme.accent : .white.opacity(0.85))
    }
}
