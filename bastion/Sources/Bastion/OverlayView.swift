import AppKit
import SwiftUI

struct OverlayView: View {
    let isPrimary: Bool
    /// このオーバーレイが覆うスクリーンの frame（Cocoa 座標）
    let screenFrame: CGRect

    @EnvironmentObject private var lock: LockController
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var agents: AgentMonitor
    @EnvironmentObject private var power: PowerManager
    @EnvironmentObject private var clamshell: ClamshellManager

    @State private var glow = false
    @State private var nudge = false
    @State private var hoveringUnlock = false

    var body: some View {
        ZStack {
            background
            frame
            if prefs.showClock && (isPrimary || prefs.cardOnAllDisplays) {
                VStack {
                    ClockView(accent: frameColor)
                        .padding(.top, 72)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
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

            unlockButton
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

    // MARK: Unlock button

    /// 指紋ボタン。ロック中のクリックはイベントタップが位置で判定して認証を開始する
    /// （SwiftUI の Button には届かない）。認証中・プレビュー時は通常のボタンとして動く。
    private var unlockButton: some View {
        Button(action: { LockController.shared.beginUnlock() }) {
            VStack(spacing: 6) {
                Image(systemName: lock.biometryAvailable ? "touchid" : "key.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(hoveringUnlock ? .white : frameColor)
                    .shadow(color: frameColor.opacity(glow ? 0.9 : 0.3), radius: glow ? 10 : 3)
                Text(lock.state == .authenticating ? "認証中…" : "クリックで解除")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 104, height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hoveringUnlock ? frameColor.opacity(0.35) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(frameColor.opacity(hoveringUnlock ? 0.95 : 0.45), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveringUnlock = $0 }
        .animation(.easeOut(duration: 0.15), value: hoveringUnlock)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { reportHotspot(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global)) { reportHotspot($0) }
            }
        )
    }

    /// SwiftUI のウィンドウ内座標 → CGEvent のグローバル座標（メインディスプレイ左上が原点）
    private func reportHotspot(_ rect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let global = CGRect(
            x: screenFrame.minX + rect.minX,
            y: primaryHeight - screenFrame.maxY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        // カードが揺れても押せるよう少し広めに取る
        lock.setUnlockHotspot(global.insetBy(dx: -10, dy: -10), for: "\(screenFrame)")
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
        let how = lock.biometryAvailable ? "指紋" : "鍵"
        return "入力はブロック中。作業はそのまま続いています — \(how)ボタンをクリックして解除（\(prefs.unlockShortcut.displayString) でも可）"
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
            if clamshell.isEngaged {
                Chip(icon: "laptopcomputer", text: "蓋を閉じてもOK")
            } else if prefs.closedLidEnabled, let reason = clamshell.safetyStopReason {
                Chip(icon: "exclamationmark.triangle.fill", text: reason)
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

// MARK: - Clock

/// ロック画面の大きな時計
private struct ClockView: View {
    let accent: Color

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    private static let secondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ss"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(Self.dateFormatter.string(from: context.date))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(2)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.timeFormatter.string(from: context.date))
                        .font(.system(size: 132, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.92), accent.opacity(0.9)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    Text(Self.secondsFormatter.string(from: context.date))
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(accent)
                }
                .shadow(color: accent.opacity(0.55), radius: 24)

                SecondsBar(date: context.date, accent: accent)
                    .frame(width: 260, height: 3)
                    .padding(.top, 6)
            }
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        }
    }
}

/// 1分で一周する細いプログレスバー
private struct SecondsBar: View {
    let date: Date
    let accent: Color

    var body: some View {
        let seconds = Calendar.current.component(.second, from: date)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.4), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(seconds + 1) / 60)
                    .shadow(color: accent, radius: 6)
                    .animation(.linear(duration: 0.9), value: seconds)
            }
        }
    }
}
