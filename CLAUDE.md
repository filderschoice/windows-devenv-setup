# CLAUDE.md

このファイルは、このリポジトリでコードを扱う際に Claude Code (claude.ai/code) へガイダンスを提供するものです。

## このリポジトリについて

Windowsの開発マシンを初期構築するためのブートストラップツール一式。決められたwingetパッケージ群と
Claude Code CLI(npm経由)をインストールする。どちらも冪等であり、すでに導入済みのパッケージ/ツールは
スキップされるため、スクリプトは何度実行しても安全。

## スクリプト

- `Install-DevEnvironment.ps1` — 標準版。winget パッケージをマシン全体スコープでインストールする。
  一部のパッケージは管理者権限を必要とする。
- `Install-DevEnvironment-User.ps1` — ユーザースコープ版(管理者権限不要)。winget に
  `--scope user` を渡す。管理者権限で実行された場合は警告を出しつつ処理は続行する。ユーザースコープの
  インストールに対応していないパッケージもあり、その場合は管理者版へのフォールバックを促すヒント付きで
  失敗する。

両スクリプトとも同じ `packages.json` を読み込み、Claude Code CLI のインストール方法も共通
(`npm install -g @anthropic-ai/claude-code`)。ただしこのステップは `packages.json` 由来のデータ駆動
ではなく、各スクリプトに直接ハードコードされている。

実行方法:
```powershell
.\Install-DevEnvironment.ps1
# または
.\Install-DevEnvironment-User.ps1
```
実行ポリシーによりスクリプト実行がブロックされる場合:
```powershell
powershell -ExecutionPolicy Bypass -File .\Install-DevEnvironment.ps1
```

このリポジトリにビルド・lint・テストの仕組みは存在しない — 素のPowerShellを直接実行するだけ。

## パッケージの追加・削除

`packages.json` を編集する(対象はwingetパッケージのみ — Claude Code CLI のインストールは
データ駆動ではなく別のスクリプトロジック)。各エントリの形式:
```json
{ "Id": "<wingetのPackageIdentifier>", "Name": "<表示名>" }
```
`Id` は `winget search <キーワード>` で調べられる。両スクリプトとも同じファイルを参照するため、
編集はどちらのインストール経路にも反映される。

## スクリプトを編集する際に維持すべき規約

- 冪等性: インストール前に `Test-WingetPackageInstalled`(内部で `winget list --id <id> -e` を使用)
  で確認し、Claude Code CLI のインストール前には `Get-Command claude` で確認する。導入済みの場合も
  スキップするだけでなく、winget パッケージは `winget upgrade --id <id> -e`、Claude Code CLI は
  `npm install -g @anthropic-ai/claude-code` を実行して最新版への更新を試みる(winget upgrade が
  「利用可能なアップグレードなし」(exit code `-1978335189` / `0x8A15002B`)を返した場合は最新版として
  スキップ扱いにする)。
- 実行結果は `[PSCustomObject]`(`Name`, `Status`)の配列 `$results` に蓄積し、最後にサマリ表
  (`Format-Table -AutoSize`)として出力する — 新しいステップを追加する場合もこの報告パターンに揃える。
- インストール後、`Update-SessionPath` が Machine + User の `Path` を現在のセッションにマージし、
  新しく導入されたツール(例: winget でインストールした Node.js)をシェルを再起動せずに使えるようにする。
- コンソール出力・コメントは日本語で書かれている。この2つのスクリプトを編集する際はそれに合わせる。
