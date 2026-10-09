import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let root = SettingsView()
            .environmentObject(Preferences.shared)
            .environmentObject(AgentMonitor.shared)
            .environmentObject(LockController.shared)
            .environmentObject(ClamshellManager.shared)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.title = "Bastion 設定"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("一般", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("ロック画面", systemImage: "rectangle.on.rectangle") }
            ShortcutSettings().tabItem { Label("ショートカット", systemImage: "keyboard") }
            PermissionSettings().tabItem { Label("権限", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 600)
    }
}

// MARK: - 一般

private struct GeneralSettings: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var agents: AgentMonitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = Permissions.isAccessibilityTrusted

    var body: some View {
        Form {
            if !trusted {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("入力をロックするにはアクセシビリティの許可が必要です。")
                        Spacer()
                        Button("許可する") { Permissions.requestAccessibility(); Permissions.openAccessibilitySettings() }
                    }
                }
            }

            Section {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.accentGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("このMacをロック").font(.headline)
                        Text("画面は見えたまま、キーボード・マウス・トラックパッドの入力だけを止めます。AIエージェントやビルドは動き続けます。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("ロック") { LockController.shared.lock() }
                        .keyboardShortcut(.defaultAction)
                }
            }

            Section("スリープ") {
                Toggle("ロック中はスリープを防止", isOn: $prefs.preventSleep)
                Toggle("ディスプレイも点灯したままにする", isOn: $prefs.keepDisplayOn)
                    .disabled(!prefs.preventSleep)
                Toggle("AIエージェント実行中は常にスリープを防止", isOn: $prefs.awakeWhileAgentsRun)
            }

            ClosedLidSection()

            RemoteControlSection()

            Section("ロック解除") {
                Toggle("解除に Touch ID / パスワードを要求", isOn: $prefs.requireAuth)
                Picker("自動解除", selection: $prefs.autoUnlockMinutes) {
                    Text("オフ").tag(0)
                    Text("15分後").tag(15)
                    Text("30分後").tag(30)
                    Text("1時間後").tag(60)
                    Text("2時間後").tag(120)
                    Text("4時間後").tag(240)
                    Text("8時間後").tag(480)
                }
            }

            Section("検出中のAIエージェント") {
                if agents.agents.isEmpty {
                    Text("なし（Claude Code / Codex / Cursor Agent / Gemini CLI / Aider などを自動検出）")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(agents.agents, id: \.self) { name in
                        Label(name, systemImage: "sparkles").foregroundColor(Theme.accent)
                    }
                }
            }

            Section("起動") {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = Permissions.isAccessibilityTrusted
        }
    }
}

// MARK: - リモート操作

private struct RemoteControlSection: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var lock: LockController

    var body: some View {
        Section {
            Toggle("ロック中もリモートデスクトップからの操作を許可", isOn: $prefs.allowRemoteControl)
            Toggle("リモート操作中はロック表示を小さくする", isOn: $prefs.remoteCompact)
                .disabled(!prefs.allowRemoteControl)
            if prefs.allowRemoteControl, let source = lock.lastBlockedSource {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最後にブロックした入力の送り元").font(.caption).foregroundColor(.secondary)
                    Text(source).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
        } header: {
            Text("リモート操作")
        } footer: {
            Text("macOS の画面共有と Chrome リモートデスクトップに対応しています。目の前の Mac のキーボード・マウスはロックしたまま、リモートからは画面を見て操作できます。リモート操作が効かない場合は、ロック中にリモートから操作したあと、上の「送り元」の表示を開発者に伝えてください。設定の変更は次のロックから反映されます。")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - 蓋を閉じても動かす

private struct ClosedLidSection: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var clamshell: ClamshellManager
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundColor(clamshell.isHelperInstalled ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clamshell.isHelperInstalled ? "セットアップ済み" : "セットアップが必要です").font(.headline)
                    Text("初回のみ管理者パスワードを入力します。許可されるのは pmset のスリープ無効化/有効化の2コマンドだけです。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if working {
                    ProgressView().controlSize(.small)
                } else if clamshell.isHelperInstalled {
                    Button("削除") { run { clamshell.uninstallHelper(completion: $0) } }
                } else {
                    Button("セットアップ") { run { clamshell.installHelper(completion: $0) } }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(Theme.warning)
            }

            Toggle("スリープ防止中は蓋を閉じてもスリープしない", isOn: $prefs.closedLidEnabled)
                .disabled(!clamshell.isHelperInstalled)
            Toggle("本体が高温になったら自動で停止", isOn: $prefs.clamshellThermalGuard)
                .disabled(!prefs.closedLidEnabled)
            Picker("バッテリー残量がこれ以下で停止", selection: $prefs.clamshellMinBattery) {
                Text("10%").tag(10)
                Text("20%").tag(20)
                Text("30%").tag(30)
                Text("50%").tag(50)
            }
            .disabled(!prefs.closedLidEnabled)

            if clamshell.isEngaged {
                Label("いま蓋を閉じても動作を継続します", systemImage: "checkmark.circle.fill")
                    .foregroundColor(Theme.accent)
            } else if prefs.closedLidEnabled, let reason = clamshell.safetyStopReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        } header: {
            Text("蓋を閉じても動かす")
        } footer: {
            Text("外部ディスプレイなしで蓋を閉じても、ロック中（またはAIエージェント実行中）は Mac を起こしたままにします。解除・終了時、高温時、バッテリー低下時は自動で通常のスリープに戻ります。閉じた Mac も発熱するため、バッグには入れないでください。")
                .font(.caption).foregroundColor(.secondary)
        }
        .onAppear { clamshell.refreshHelperStatus() }
    }

    private func run(_ action: (@escaping (String?) -> Void) -> Void) {
        working = true
        errorMessage = nil
        action { message in
            working = false
            errorMessage = message
        }
    }
}

// MARK: - ロック画面

private struct AppearanceSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section("オーバーレイ") {
                Picker("スタイル", selection: $prefs.overlayStyle) {
                    ForEach(OverlayStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("カードの位置", selection: $prefs.cardPosition) {
                    ForEach(CardPosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("すべてのディスプレイにカードを表示", isOn: $prefs.cardOnAllDisplays)
            }

            Section("表示内容") {
                TextField("メッセージ", text: $prefs.message, prompt: Text("このMacはロックされています"))
                Toggle("大きな時計を表示", isOn: $prefs.showClock)
                Toggle("経過時間を表示", isOn: $prefs.showTimer)
                Toggle("実行中のAIエージェントを表示", isOn: $prefs.showAgents)
            }

            Section {
                HStack {
                    Text("入力はブロックされず、5秒間だけ表示します。")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("プレビュー") { LockController.shared.preview() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ショートカット

private struct ShortcutSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section {
                LabeledContent("ロック") { ShortcutRecorder(shortcut: $prefs.lockShortcut) }
                LabeledContent("ロック解除") { ShortcutRecorder(shortcut: $prefs.unlockShortcut) }
            } footer: {
                Text("ロック中は解除ショートカット以外のすべての入力（キーボード・マウス・トラックパッド・ジェスチャー）がブロックされます。ロック画面の指紋ボタンをクリックするか、解除ショートカットを押すと Touch ID / パスワードの認証が表示されます。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                Button("デフォルトに戻す") { prefs.resetShortcuts() }
            }

            Section {
                Picker("ホットコーナーでロック", selection: $prefs.hotCorner) {
                    ForEach(HotCorner.allCases) { Text($0.label).tag($0) }
                }
                Picker("角に置いてからロックまで", selection: $prefs.hotCornerDelay) {
                    Text("すぐ").tag(0.2)
                    Text("0.5秒").tag(0.5)
                    Text("1秒").tag(1.0)
                    Text("2秒").tag(2.0)
                }
                .disabled(prefs.hotCorner == .none)
            } header: {
                Text("ホットコーナー")
            } footer: {
                Text("マウスカーソルを選んだ画面の角に置くとロックします。macOS のホットコーナー（システム設定 › デスクトップとDock › ホットコーナー）で同じ角を使っている場合は、そちらを「−」にしてください。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { recording ? stop() : start() }) {
            Text(recording ? "キーを入力…（esc で取消）" : shortcut.displayString)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 150)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
                return nil
            }
            let mods = event.modifierFlags.intersection(Shortcut.relevantFlags)
            guard !mods.subtracting(.shift).isEmpty else {
                NSSound.beep()
                return nil
            }
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue, key: Shortcut.keyName(for: event))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyManager.shared.register(Preferences.shared.lockShortcut)
        }
    }
}

// MARK: - 権限

private struct PermissionSettings: View {
    @State private var trusted = Permissions.isAccessibilityTrusted

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: trusted ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.title2)
                        .foregroundColor(trusted ? Theme.accent : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("アクセシビリティ").font(.headline)
                        Text(trusted ? "許可されています" : "入力をブロックするために必要です")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if !trusted {
                        Button("システム設定を開く") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            } footer: {
                Text("Bastion は macOS のイベントタップで入力を破棄します。入力内容を記録・送信することはなく、ネットワーク通信も行いません。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = Permissions.isAccessibilityTrusted
        }
    }
}
