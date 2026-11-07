# TypingOverlay

YouTube などの動画を見ながらタッチタイピングを練習できる、**半透明・最前面表示**のデスクトップアプリ。
**Windows / macOS** 対応（[Tauri](https://tauri.app/) 製）。

- 画面の下に半透明の帯が出て、動画の上に重ねたまま打てる
- **Ctrl+Alt+T** でタイピング ⇄ ブラウザのフォーカスをすぐ切り替え（動画は再生されたまま）
- 日本語（ローマ字）/ English / カスタム文、文章・単語ドリル・ミックス
- キーボードガイド、タイプ音、統計・分析ウィンドウ

## ダウンロード

[Releases](../../releases) から入手（まだ無い場合は [Actions](../../actions) の最新の成功したビルドの Artifacts から）。

| OS | ファイル |
| --- | --- |
| Windows 10 / 11 | `TypingOverlay_x.x.x_x64-setup.exe` または `.msi` |
| macOS 11 以降 | `TypingOverlay_x.x.x_aarch64.dmg` |

> コード署名をしていないため、初回起動時に警告が出ます。
> - **Windows**: 「Windows によって PC が保護されました」→「詳細情報」→「実行」
> - **macOS**: アプリを右クリック →「開く」（または `xattr -dr com.apple.quarantine /Applications/TypingOverlay.app`）

## 使い方

- 起動すると画面下に帯が出る。クリックするか **Ctrl+Alt+T** で入力開始。もう一度 Ctrl+Alt+T でブラウザに戻る
- 背景をドラッグで移動、左右の端でサイズ変更（高さは内容に合わせて自動）
- **右クリック**でメニュー（モード・出題・タイプ音・コンパクト表示など）
- マウスを乗せると右上にモード切替・統計・設定ボタン
- 帯の ✕ ボタン（または Ctrl(⌘)+Q）で終了。タスクトレイ（macOS はメニューバー）のアイコンからも表示・設定・統計・終了ができます
- タイピングしていない間は帯が薄くなって動画が見やすくなる
- 日本語入力（IME）がオンのままでも、物理キーから文字を判定するので練習できる

| キー | 動作 |
| --- | --- |
| Ctrl+Alt+T | タイピング ⇄ ブラウザのフォーカス切替（どのアプリからでも） |
| Esc / Tab | 行の最初から / スキップ |
| Ctrl(⌘)+1 / 2 / 3 | 日本語 / English / カスタム |
| Ctrl(⌘)+, | 設定 |
| Ctrl(⌘)+S | 統計・分析 |
| Ctrl(⌘)+K | コンパクト表示 |
| Ctrl(⌘)+V / O | クリップボード / テキストファイルの文章で練習 |
| Ctrl(⌘)+W / Q | 隠す / 終了 |

### カスタム文

1行に1問。漢字を含む文は `|` の後に読みを書く。

```text
今日は晴れ|きょうははれ
the quick brown fox
ひらがなだけの文はそのままでOK
```

## 機能

- **ローマ字入力**: shi/si、chi/ti、kya/kixya、っ（子音重ね / xtu）、ん（n 1回でも可）など複数の打ち方に対応
- **問題**: 日本語の文章150・単語183、英語の文章101・単語285。文章 / 単語 / ミックス を切り替え
- **キーボードガイド**: 次に押すキーと指を色で表示。JIS / US 配列を自動判別
- **タイプ音**: コトコト（木）/ カチカチ / スコスコ / タイプライター / ポップ（音源ファイルなしで合成）。左手のキーは左から、右手のキーは右から聞こえる
- **統計・分析**: 期間ごとの平均 KPM・正確率・練習時間と前の期間との比較、連続練習日数、KPM の推移、日別グラフ、キーボードのヒートマップ（ミス率 / 打鍵間隔）、指ごとのミス率、苦手なキー・遅いキー・よくある打ち間違い・苦手なかな、最近の行、CSV 書き出し
- KPM は打鍵中の時間だけで計算するので、動画に見入って手が止まっても下がらない
- フォント（モダン / まるっと / 教科書 / システム）、透明度、文字サイズ、カーソルの見た目

## ソースからビルド

必要なもの: [Rust](https://rustup.rs/)、[Node.js](https://nodejs.org/) 20 以上。Windows は WebView2（Windows 10/11 は標準搭載）と Visual Studio Build Tools（C++）。

```bash
npm install
npm run dev      # 開発用に起動
npm run build    # インストーラーを作成（src-tauri/target/release/bundle/）
npm test         # ローマ字判定のテスト
```

`v1.0.0` のようなタグを push すると、GitHub Actions が Windows / macOS 版をビルドして Releases に公開する。

## 構成

```text
src/                 画面（HTML / CSS / JavaScript、ビルド不要）
  index.html         帯
  settings.html      設定ウィンドウ
  analytics.html     統計・分析ウィンドウ
  js/romaji.js       ローマ字入力エンジン
  js/model.js        タイピングの判定と出題
  js/analytics.js    記録の保存と集計
  js/sound.js        タイプ音の合成
  js/keyboard.js     キー配列（JIS / US）と指の割り当て
  js/vocab.js        問題データ
src-tauri/           ウィンドウ制御・トレイ・ホットキー（Rust）
tests/               テスト
macos-swift/         最初に作った macOS ネイティブ（Swift / AppKit）版
```

設定と記録はアプリ内（WebView の localStorage）に保存される。
