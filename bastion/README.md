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
| Touch ID 解除 | ロック画面の指紋ボタンをクリック（または `⌃⌥⌘U`）→ Touch ID / Apple Watch / ログインパスワード |
| ホットコーナー | カーソルを画面の角（左上/右上/左下/右下）に置くとロック。設定 › ショートカット で選択 |
| 時計 | ロック画面に大きな時計・日付・秒バーを表示 |
| ショートカット | ロック（既定 `⌘⇧L`）と解除を自由に変更可能 |
| スリープ防止 | ロック中は IOPMAssertion でスリープを防止（ディスプレイ点灯の有無も選択） |
| AI エージェント検出 | Claude Code / Codex / Cursor Agent / Gemini CLI / Aider / OpenCode などを自動検出し、ロック画面に「実行中」と表示 |
| エージェント実行中のスリープ防止 | ロックしていなくても、エージェントが動いている間だけ Mac を起こしておくオプション |
| 蓋を閉じても動く | 外部ディスプレイなしで蓋を閉じてもスリープしない（`pmset disablesleep`）。高温・バッテリー低下で自動停止 |
| 自動解除タイマー | 15分〜8時間後に自動で解除（任意） |
| カスタムメッセージ | 「エージェント実行中・触らないでください」などをロック画面に表示 |
| マルチディスプレイ | 接続中のすべてのディスプレイを保護。構成変更にも追従 |
| ログイン時に起動 | SMAppService で登録 |
| プライバシー | 入力内容の記録・送信なし、ネットワーク通信なし |

## 使い方

1. メニューバーの 🛡 アイコン →「このMacをロック」、または `⌘⇧L`
2. 画面にロック中のカード（経過時間・スリープ防止・実行中のエージェント）が表示され、入力はすべてブロックされます
3. 戻ったらロック画面の指紋ボタンをクリック（または `⌃⌥⌘U`）→ Touch ID / パスワードで解除。ロック中はカーソル移動と指紋ボタンのクリックだけが有効です。キャンセル・失敗時はロック状態に戻ります

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

## 蓋を閉じても動かす（外部ディスプレイ不要）

macOS は通常、外部ディスプレイなしで蓋を閉じると必ずスリープします（`caffeinate` などでは防げません）。
Bastion は Amphetamine や Agent Mode と同じく `pmset -a disablesleep 1` を使ってこれを防ぎます。

1. 設定 › 一般 ›「蓋を閉じても動かす」で **セットアップ** を押し、管理者パスワードを入力（初回のみ）
   - `/etc/sudoers.d/bastion` に次の1行だけを登録します（visudo で構文チェック後、`root:wheel 0440` で配置）
     ```
     <ユーザー名> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
     ```
2. 「スリープ防止中は蓋を閉じてもスリープしない」をオン
3. ロック中（または「AIエージェント実行中はスリープを防止」が有効でエージェント実行中）だけ蓋閉じスリープが無効になります

自動で通常のスリープ設定（`disablesleep 0`）に戻るタイミング:

- ロック解除時 / エージェント終了時 / Bastion の終了時
- 本体が高温（thermal state が serious 以上）になったとき
- バッテリー駆動で残量が設定値（既定 20%）以下になったとき
- Bastion が強制終了した場合も、見張り用の子プロセスが元に戻します（次回起動時にも念のため戻します）

削除は設定画面の **削除** ボタン、または `sudo rm /etc/sudoers.d/bastion && sudo pmset -a disablesleep 0`。
状態確認は `pmset -g | grep SleepDisabled`。閉じた Mac も発熱するため、バッグには入れないでください。

## 注意

- 入力だけをロックする仕組みで、macOS のログイン画面ロックではありません（画面の内容は見えます）。
- 蓋を閉じた状態で macOS 自体のロック画面が出た場合、Bastion は入力ブロックを止めます。macOS のパスワードでログインし直すと Bastion のロックも解除されます。
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
