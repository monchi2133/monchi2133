# Bastion — 画面は見えたまま、入力だけロック

[Warden](https://www.getwarden.org/) を参考にした macOS メニューバーアプリです。
キーボード・マウス・トラックパッド・ジェスチャーの入力をブロックしつつ、画面は表示したまま、
Claude Code / Codex / Cursor などの AI エージェントやビルド・レンダリングを動かし続けます。
戻ってきたら Touch ID（またはパスワード）で解除します。

## 機能

| 機能 | 内容 |
| --- | --- |
| 入力ロック | macOS のイベントタップ（HID レベル）で入力を破棄。ターミナル・IDE・エージェントには一切届きません |
| 画面は見えたまま | 全ディスプレイに透明なオーバーレイ＋発光フレーム。スタイルは「クリア / 暗く / すりガラス」 |
| Touch ID 解除 | 解除ショートカット（既定 `⌃⌥⌘U`）→ Touch ID / Apple Watch / ログインパスワード |
| ショートカット | ロック（既定 `⌃⌥⌘L`）と解除を自由に変更可能 |
| スリープ防止 | ロック中は IOPMAssertion でスリープを防止（ディスプレイ点灯の有無も選択） |
| AI エージェント検出 | Claude Code / Codex / Cursor Agent / Gemini CLI / Aider / OpenCode などを自動検出し、ロック画面に「実行中」と表示 |
| エージェント実行中のスリープ防止 | ロックしていなくても、エージェントが動いている間だけ Mac を起こしておくオプション |
| 自動解除タイマー | 15分〜8時間後に自動で解除（任意） |
| カスタムメッセージ | 「エージェント実行中・触らないでください」などをロック画面に表示 |
| マルチディスプレイ | 接続中のすべてのディスプレイを保護。構成変更にも追従 |
| ログイン時に起動 | SMAppService で登録 |
| プライバシー | 入力内容の記録・送信なし、ネットワーク通信なし |

## 使い方

1. メニューバーの 🛡 アイコン →「このMacをロック」、または `⌃⌥⌘L`
2. 画面にロック中のカード（経過時間・スリープ防止・実行中のエージェント）が表示され、入力はすべてブロックされます
3. 戻ったら `⌃⌥⌘U` → Touch ID / パスワードで解除。キャンセル・失敗時はロック状態に戻ります

初回起動時に **システム設定 › プライバシーとセキュリティ › アクセシビリティ** で Bastion を許可してください（入力ブロックに必要）。

## ビルド

macOS 13 以降 + Xcode（Command Line Tools）が必要です。

```bash
cd bastion
./scripts/build-app.sh            # build/Bastion.app を生成
UNIVERSAL=1 ./scripts/build-app.sh  # Apple Silicon + Intel
open build/Bastion.app
```

GitHub Actions（`.github/workflows/bastion.yml`）でもビルドされ、`Bastion.app` がアーティファクトとしてダウンロードできます。
アドホック署名のため、初回は Finder で右クリック →「開く」で起動してください。
再ビルドすると署名が変わるので、アクセシビリティの許可を一度外して付け直してください。

## 注意

- 入力だけをロックする仕組みで、macOS のログイン画面ロックではありません（画面の内容は見えます）。
- ノートの蓋を閉じると（外部ディスプレイ未接続時）macOS の仕様でスリープします。蓋は開けたままにしてください。
- 電源ボタン長押しなどハードウェアレベルの操作は止められません。

## 構成

```
Sources/Bastion/
  main.swift / AppDelegate.swift   起動・配線
  LockController.swift             ロック状態・認証フロー・オーバーレイ管理
  InputBlocker.swift               CGEventTap による入力破棄
  OverlayWindow.swift / OverlayView.swift  ロック画面 UI
  Authenticator.swift              Touch ID / パスワード（LocalAuthentication）
  PowerManager.swift               スリープ防止（IOPMAssertion）
  AgentMonitor.swift               AI エージェントのプロセス検出
  HotKeyManager.swift / Shortcut.swift  グローバルショートカット
  MenuBarController.swift          メニューバー
  SettingsWindow.swift             設定画面
```
