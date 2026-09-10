# windows-devenv-setup

Windows初期環境構築用のブートストラップスクリプト。`packages.json` に列挙した開発に必要なパッケージをwingetで、Claude Code CLIをnpmでインストールする。すでにインストール済みのツールは自動でスキップされるため、何度実行しても安全。導入されるパッケージの具体的な一覧は `packages.json` を参照。

## 事前準備

- **管理者権限を推奨**: 一部のwingetパッケージ(マシンスコープでのインストール)は管理者権限が必要な場合があります。エラーが出る場合は管理者としてターミナルを開き直してください。管理者権限が使えない環境では、代わりに [ユーザー権限専用版](#ユーザー権限専用版-管理者権限なし) を使用してください。
- **実行ポリシー**: 未署名のローカルスクリプトのため、環境によっては実行がブロックされます。その場合は以下のいずれかで実行してください。
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\Install-DevEnvironment.ps1
  ```
- **Microsoft Store系パッケージ**: `packages.json` 内のパッケージによっては Microsoft Store 経由で配布されているものがあり、環境によってはStoreへのサインインや利用規約への同意プロンプトが表示されることがあります。

## 使い方

```powershell
cd C:\Dev\windows-devenv-setup
.\Install-DevEnvironment.ps1
```

## ユーザー権限専用版(管理者権限なし)

管理者権限を持たない/使いたくない環境向けに `Install-DevEnvironment-User.ps1` を用意している。`packages.json` は通常版と共通で、winget のインストールを `--scope user` で実行する点のみ異なる。

```powershell
cd C:\Dev\windows-devenv-setup
.\Install-DevEnvironment-User.ps1
```

- パッケージによってはインストーラがユーザースコープに対応しておらず、インストールに失敗する場合がある(その場合はメッセージにヒントが表示される)。その際は管理者権限で `Install-DevEnvironment.ps1` を実行してください。
- 管理者権限で実行した場合でも動作はするが、警告が表示される(このスクリプトはユーザー権限のみでの利用を想定しているため)。
- Claude Code CLI (npm) のインストール手順も含まれる。

## パッケージの追加・削除

`packages.json` を編集する(winget パッケージのみ対象)。両スクリプト(`Install-DevEnvironment.ps1` / `Install-DevEnvironment-User.ps1`)で共通のファイルを参照する。

```json
{ "Id": "<wingetのPackageIdentifier>", "Name": "<表示名>" }
```

を配列に追加/削除するだけでよい。`winget search <キーワード>` でPackageIdentifierを調べられる。

Claude Code CLI (npm パッケージ)はスクリプト内に直接記述されている。

## アンインストール

個別のwingetパッケージをアンインストールする場合:

```powershell
winget uninstall --id <wingetのPackageIdentifier> -e
```

`packages.json` に列挙されているパッケージを一括でアンインストールする場合:

```powershell
Get-Content .\packages.json -Raw | ConvertFrom-Json | ForEach-Object {
    winget uninstall --id $_.Id -e
}
```

Claude Code CLI (npm) をアンインストールする場合:

```powershell
npm uninstall -g @anthropic-ai/claude-code
```
