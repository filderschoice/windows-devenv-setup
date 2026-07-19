# windows-devenv-setup

Windows初期環境構築用のブートストラップスクリプト。`packages.json` に列挙した開発に必要なパッケージをwingetで、Claude Code CLIをnpmでインストールする。すでにインストール済みのツールは自動でスキップされるため、何度実行しても安全。導入されるパッケージの具体的な一覧は `packages.json` を参照。

## 事前準備

- **管理者権限を推奨**: 一部のwingetパッケージ(マシンスコープでのインストール)は管理者権限が必要な場合があります。エラーが出る場合は管理者としてターミナルを開き直してください。
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

## パッケージの追加・削除

`packages.json` を編集する(winget パッケージのみ対象)。

```json
{ "Id": "<wingetのPackageIdentifier>", "Name": "<表示名>" }
```

を配列に追加/削除するだけでよい。`winget search <キーワード>` でPackageIdentifierを調べられる。

Claude Code CLI (npm パッケージ)はスクリプト内に直接記述されている。
