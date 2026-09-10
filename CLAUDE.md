# CLAUDE.md

このファイルは、このリポジトリでコードを扱う際に Claude Code (claude.ai/code) へガイダンスを提供するものです。

## このリポジトリについて

Windowsの開発マシンを初期構築するためのブートストラップツール一式。決められたwingetパッケージ群と
Claude Code CLI(npm経由)をインストールする。どちらも冪等であり、すでに導入済みのパッケージ/ツールは
スキップ(または最新版へ更新)されるため、スクリプトは何度実行しても安全。

ビルド・lint・テストの仕組みは存在しない — 素のPowerShellスクリプト2本と、それが読む `packages.json`
だけで構成される。

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

## 2本のスクリプトはほぼ同一 — 編集は必ず両方に反映する

`Install-DevEnvironment-User.ps1` は `Install-DevEnvironment.ps1` のコピーであり、意図的な差分は
以下だけ。片方だけを直すと両者が静かに乖離するため、共通ロジック(関数・ループ・サマリ出力など)への
変更は必ず2本ともに同じ形で適用し、編集後に差分を取って想定外の乖離が無いことを確認する。

意図的な差分:
1. 冒頭のコメントブロックの説明文
2. 起動時の権限チェックの向き(`Test-IsElevated` 自体は両方にある。標準版は「管理者権限**でない**とき」に
   マシンスコープ失敗の可能性を警告し、ユーザー版は「管理者権限**である**とき」に警告する)
3. `winget install` / `winget upgrade` への `--scope user` の有無
4. 失敗時のメッセージ(ユーザー版は「ユーザースコープ非対応の可能性 → 管理者版を使う」ヒントを付ける)
5. ユーザー版の失敗時 `Status` に「管理者権限が必要な可能性あり」が付く

差分確認の例:
```powershell
git diff --no-index .\Install-DevEnvironment.ps1 .\Install-DevEnvironment-User.ps1
```

## パッケージの追加・削除

`packages.json` を編集する(対象はwingetパッケージのみ — Claude Code CLI のインストールは
データ駆動ではなく別のスクリプトロジック)。各エントリの形式:
```json
{ "Id": "<wingetのPackageIdentifier>", "Name": "<表示名>" }
```
`Id` は `winget search <キーワード>` で調べられる。両スクリプトとも同じファイルを参照するため、
編集はどちらのインストール経路にも反映される。`Name` は表示用なので日本語でも構わない
(スクリプト側は `Get-Content -Encoding UTF8` で読むため、BOM無しUTF-8のままでも文字化けしない)。

`Id` には winget コミュニティリポジトリの PackageIdentifier(`Git.Git` など)だけでなく、Microsoft Store の
プロダクトID(`XP89DCGQ3K6VLD` = PowerToys, `9PGPPQ5ZDN2K` = Clibor など)もそのまま指定できる。
`winget search` の `ソース` 列が `msstore` のものがそれにあたる。Store 経由のパッケージは
`--scope user` を受け付けないことがあり、その場合ユーザー版では失敗して管理者版へのフォールバックが
案内される。

インストール後にPATHが正しく通っているか確認したいパッケージには、任意で `ExeName`
(コマンド名、例: `"pwsh.exe"`)を追加する。指定すると `Sync-PackagePath` が `Get-Command` で解決可能かを
確認し、解決できない場合はレジストリの `App Paths`(`HKLM`/`HKCU` の
`SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\<ExeName>`)からインストール先を特定して
ユーザーPATHに追記する(winget/MSIインストーラがPATHを更新しない場合の対策。実例: PowerShell 7 が
MSIXパッケージとして入り、`%LOCALAPPDATA%\Microsoft\WindowsApps` のエイリアス経由でしか解決できず、
かつそのフォルダがユーザーPATHに含まれていないケース)。

## CHANGELOG の更新(変更のたびに必須)

コードやドキュメントを変更したら、**同じ作業の中で** `CHANGELOG.md` の `## [Unreleased]` に追記する。
コミットしてから思い出して足すのではなく、変更とセットで書くこと。

- 見出しは `### 追加` / `### 変更` / `### 修正` / `### 削除` を使う(Keep a Changelog 準拠)。
- 書くのは「利用者から見て何が変わったか」と、必要ならその理由。関数名の羅列や diff の逐語的な
  説明は書かない(それは diff を読めば分かる)。
- `packages.json` へのパッケージ追加・削除も対象。利用者にとっては入るものが変わるため。
- 追記が不要なのは、CHANGELOG 自身の修正やタイポ修正など、利用者から見て何も変わらない場合だけ。
- コミット前に、ステージ内容へ `CHANGELOG.md` が入っているか `git diff --cached --name-only` で確認する。

このリポジトリはバージョンタグを打っていないため、`CHANGELOG.md` は日付とコミットハッシュで
区切っている。作業中は `## [Unreleased]` に書き足していき、それがコミットされてハッシュが確定したら、
**次の作業に着手するタイミングで**見出しを `## <YYYY-MM-DD> — <短縮ハッシュ>` に置き換え、
新しい `## [Unreleased]` をその上に作る。見出しを確定させるためだけのコミットは作らない。

## 変更の検証方法

**スクリプトを「動作確認のために」実行しないこと。** 実行はこのマシンに対して実際にソフトウェアの
インストール・更新・ユーザーPATHの書き換えを行う副作用を持つ。実行はユーザーが明示的に求めた場合に限る。

副作用なしで確認できること:
```powershell
# packages.json が壊れていないか(件数が返れば妥当なJSON)
(Get-Content .\packages.json -Raw | ConvertFrom-Json).Count

# スクリプトを実行せずに構文だけ検証する
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\Install-DevEnvironment.ps1).Path, [ref]$null, [ref]$errs) > $null
$errs

# 追加しようとしているパッケージIDが実在するか(インストールはしない)
winget show --id <PackageIdentifier> -e
```

## スクリプトを編集する際に維持すべき規約

- 冪等性: インストール前に `Test-WingetPackageInstalled`(内部で `winget list --id <id> -e` を使用)
  で確認し、Claude Code CLI のインストール前には `Get-Command claude` で確認する。導入済みの場合も
  スキップするだけでなく、winget パッケージは `winget upgrade --id <id> -e`、Claude Code CLI は
  `npm install -g @anthropic-ai/claude-code` を実行して最新版への更新を試みる(winget upgrade が
  「利用可能なアップグレードなし」(exit code `-1978335189` / `0x8A15002B`)を返した場合は最新版として
  スキップ扱いにする)。Claude Code CLI が `Updated` か `Skip (最新版)` かは、npm 実行の前後で
  `claude --version` を比較して判定している。
- エラーハンドリング: 冒頭に `$ErrorActionPreference = 'Stop'` があるが、これは winget/npm のような
  ネイティブコマンドの失敗には効かない。呼び出し直後に `$LASTEXITCODE` を判定し、失敗しても
  **中断せず** `Write-Warning` と `$results` への記録を行って次のパッケージへ進む — 1つのパッケージの
  失敗で環境構築全体が止まらないようにするため。新しいステップも同じ方針に揃える。
- 実行結果は `[PSCustomObject]`(`Name`, `Status`)の配列 `$results` に蓄積し、最後にサマリ表
  (`Format-Table -AutoSize`)として出力する — 新しいステップを追加する場合もこの報告パターンに揃える。
  `Sync-PackagePath` のように「何も報告することがない」場合は空配列 `@()` を返し、`$results +=` が
  何も足さないようにする。
- 終了コード: 個々のパッケージの失敗ではループを止めず、最後にサマリを出したうえで `Status` が
  `Failed*` の項目が1件でもあれば `exit 1` する。失敗判定はこの前方一致に依存しているため、
  新しい失敗ステータスを増やす場合も必ず `Failed` で始める文字列にすること。
- インストール後、`Update-SessionPath` が Machine + User の `Path` を現在のセッションにマージし、
  新しく導入されたツール(例: winget でインストールした Node.js)をシェルを再起動せずに使えるようにする。
  このマージは既存の `$env:Path` も保持する — セッション限定で足されたパス(`nvm use` 等)を消さないため。
- ユーザーPATHへの追記(`Add-UserPathEntry`)は `HKCU:\Environment` を
  `DoNotExpandEnvironmentNames` で読み、元の値種別(`REG_EXPAND_SZ`)のまま書き戻す。
  `[Environment]::GetEnvironmentVariable('Path','User')` は `%NVM_HOME%` のような参照を展開した値を返し、
  それを書き戻すと参照が実パスで焼き付いてしまうため、この API を PATH の読み書きに使ってはならない
  (このリポジトリは NVM for Windows を導入するので実害が出る)。レジストリ直書きでは `WM_SETTINGCHANGE` が
  飛ばないので、`Publish-EnvironmentChange` で明示的に通知する。
- コンソール出力・コメントは日本語で書かれている。この2つのスクリプトを編集する際はそれに合わせる。
- 文字コード: 改行は LF、**両スクリプトとも UTF-8 BOM付きで保存する**。READMEが案内する
  `powershell -ExecutionPolicy Bypass -File ...` の `powershell` は Windows PowerShell 5.1 であり、
  5.1 は BOM の無い UTF-8 を ANSI として読む。日本語文字列が文字化けして終端クォートまで壊れるため、
  BOM を落とすと**スクリプトが構文エラーで起動しなくなる**(実測: BOMを外すと 5.1 のパーサで10件のエラー、
  BOM付きなら0件)。エディタや自動整形でBOMが落ちていないか、編集後に必ず確認すること。

## README との関係

`README.md` はエンドユーザー向け(事前準備、実行方法、アンインストール手順)。パッケージ一覧は
README には書かず `packages.json` を参照させる方針なので、パッケージを追加しても README の更新は不要
(ただし `CHANGELOG.md` への追記は必要)。スクリプトの挙動やオプションを変えた場合のみ README を追随させる。

`CHANGELOG.md` は「いつ何が変わったか」の履歴、`README.md` は「今どう使うか」の説明、
このファイルは「どう変更するか」の規約、という役割分担にする。
