# 変更履歴

このファイルは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) の形式に沿って、
利用者から見た変更点を記録する。

このリポジトリはバージョンタグを打っていないため、リリース単位ではなく変更が入った日付と
コミットで区切っている。

## [Unreleased]

### 変更

- Python Install Manager のインストール元を winget コミュニティリポジトリ版
  (`Python.PythonInstallManager`、python.org の MSIX 直取得)から Microsoft Store 版
  (`9NQ7512CXL7T`)に変更。Store のライブラリに表示され、Store 経由で更新される。
  ユーザー権限版では Store 版が `--scope user` を受け付けず失敗する可能性があり、その場合は管理者版を使う。
  すでに winget 版が入っているマシンでは、Store 版が別途インストールされて二重になりうる。

## 2026-10-07 — `770b5ac`

### 追加

- インストール対象に Claude Desktop(`Anthropic.Claude`)を追加。

## 2026-09-11 — `5e141ed`

### 追加

- `CHANGELOG.md` を追加し、以降の変更をここに記録する運用を開始。

## 2026-09-11 — `8c7f125`

### 修正

- **ユーザー権限版が Windows PowerShell 5.1 で起動できなかった問題。** `Install-DevEnvironment-User.ps1`
  が UTF-8 BOM無しで保存されていたため、README が案内する `powershell -ExecutionPolicy Bypass -File ...`
  （＝Windows PowerShell 5.1）では日本語が文字化けして構文エラーになっていた。両スクリプトを BOM付き
  UTF-8 に統一。
- **ユーザーPATHへの追記が環境変数参照を破壊していた問題。** `%NVM_HOME%` `%NVM_SYMLINK%` `%USERPROFILE%`
  などが実パスに展開されたうえで書き戻されていた。レジストリを `REG_EXPAND_SZ` のまま読み書きするよう変更し、
  あわせて `WM_SETTINGCHANGE` の通知を送るようにした。
- `Update-SessionPath` が現在のセッションにだけ追加されていた PATH エントリ（`nvm use` 等）を消していた問題。
  Machine + User + 既存の `$env:Path` をマージし、重複と空要素を取り除くようにした。
- `Resolve-AppPath` が引用符付きで登録された App Paths の既定値を解決できなかった問題。
- `packages.json` の `Name` に日本語を書くと Windows PowerShell 5.1 で文字化けする問題（`-Encoding UTF8` を指定）。
- `claude --version` が複数行を返す場合に更新判定が壊れる問題（単一文字列へ正規化する `Get-ClaudeVersion` を追加）。
- winget 未検出時に `exit 1` へ到達していなかった問題（`$ErrorActionPreference = 'Stop'` 下で `Write-Error` が
  終端エラーになっていたため）。
- インストール／更新に失敗したパッケージに対しても PATH 確認が走り、無関係な警告が出ていた問題。

### 追加

- `packages.json` の任意項目 `ExeName` と `Sync-PackagePath`。インストール後にコマンドが解決できない場合、
  レジストリの App Paths から実体を探してユーザーPATHへ追記する（winget/MSI インストーラが PATH を
  更新しないケースへの対策）。
- 標準版 `Install-DevEnvironment.ps1` の権限チェック。管理者権限で実行されていない場合に警告する。
- 失敗が1件でもあれば `exit 1` を返す終了コード。
- `packages.json` が見つからない場合の明示的なエラーメッセージ。
- パッケージ追加: Clibor、.NET SDK 8。PowerShell 7 に `ExeName` を設定。
- README にアンインストール手順を追記。

## 2026-07-26 — `149a05c`

### 変更

- 導入済みパッケージをスキップするだけでなく、`winget upgrade` で最新版への更新を試みるようにした。
  「利用可能なアップグレードなし」（exit code `-1978335189`）は最新版として扱う。
- Claude Code CLI も導入済みの場合に更新を試み、実行前後のバージョン比較で `Updated` / `Skip (最新版)` を
  判定するようにした。

### 追加

- パッケージ追加: NVM for Windows、Google Chrome、Vivaldi、PeaZip、Slack、Logi Options+。

### 削除

- パッケージ削除: Node.js LTS（NVM for Windows で管理するため）。

## 2026-07-25 — `34e5327`

### 追加

- `Install-DevEnvironment-User.ps1`。管理者権限を持たない環境向けに、winget を `--scope user` で
  実行するユーザースコープ版。
- `CLAUDE.md`。
- パッケージ追加: .NET Desktop Runtime 10、Microsoft Loop、Microsoft Edit。

## 2026-07-20 — `6780365`

### 追加

- 初期リリース。`Install-DevEnvironment.ps1`、`packages.json`、`README.md`。
  `packages.json` に列挙した winget パッケージ12種と Claude Code CLI（npm）を冪等にインストールする。
