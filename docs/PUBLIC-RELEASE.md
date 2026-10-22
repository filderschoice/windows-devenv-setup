# リポジトリ公開(public化)チェックリスト

このリポジトリを private から public に切り替える際の確認事項と手順。
2026-10-23 時点のレビュー結果と、リポジトリ側で対応済みの内容・公開前後にオーナーが行う作業をまとめる。

一度 public にした内容は、後から private に戻したり履歴を書き換えたりしても、fork・クローン・
キャッシュに残りうる。**「公開前に確認」の項目はすべて切り替え前に済ませること。**

## 1. レビュー結果(2026-10-23)

| 観点 | 結果 | 対応 |
| --- | --- | --- |
| 秘密情報(トークン・パスワード・鍵) | 全ブランチの全履歴で該当なし | 不要 |
| 個人のローカルパス | README に作者のローカルパス(`C:\Dev\...`)の手順があった。過去の履歴にも残るが、ユーザー名等を含まない汎用的なパス | README を `git clone` からの手順に変更。履歴は書き換えない |
| コミットのメールアドレス | 全コミットの author/committer が `filderschoice.dev@gmail.com`。公開すると誰でも参照できる | 開発用アドレスのため許容と判断(→ 2.3 で最終確認) |
| ライセンス | 未設定(公開しても第三者は利用・改変できない状態) | MIT で `LICENSE` を追加(→ 2.1 で最終確認) |
| 利用者への注意書き | スクリプトがソフトウェアを導入しPATHを書き換えること、利用規約に自動同意することの説明がなかった | README に「実行前の注意」を追加 |
| 脆弱性の連絡窓口 | なし | `SECURITY.md` を追加(GitHub の非公開報告を案内。→ 3 で機能を有効化) |
| 誤コミットの防止 | `.gitignore` がなく、Claude Code の個人設定(`.claude/settings.local.json`)を誤ってコミットしうる | `.gitignore` を追加 |
| 改行・文字コード | 作業ツリーは LF。`core.autocrlf=true` の環境で clone すると CRLF になりうる | `.gitattributes` で LF に固定。スクリプトの UTF-8 BOM は Git が保持するため対応不要 |
| サードパーティ素材の同梱 | なし(インストーラ等のバイナリは含まず、winget/npm から取得する) | 不要 |
| `CLAUDE.md` | 開発規約のみで秘密情報なし。公開しても問題ない | 不要 |

## 2. 公開前にオーナーが判断すること

### 2.1 ライセンスの確定

`LICENSE` は MIT で追加済み。別のライセンス(Apache-2.0 等)にしたい、または著作権者表記を変えたい場合は
公開前に差し替える。公開後の変更も可能だが、MIT で取得した人の権利は取り消せない。

### 2.2 `packages.json` の内容

公開すると作者が使っているソフトウェアの構成が分かる。現状は一般的な開発ツールのみで機微な情報は含まないと
判断しているが、社内専用ツールや組織固有のパッケージを追加していないか切り替え直前に見直す。

### 2.3 コミットのメールアドレス

履歴に残るアドレスを公開したくない場合は、**公開前に**次のどちらかを選ぶ。公開後に対処しても既存の
クローンからは消えない。

- 許容する(現状の判断。開発用のアドレスであるため)。
- 履歴を書き換える: `git filter-repo --mailmap` 等で GitHub の noreply アドレス
  (`<ID>+filderschoice@users.noreply.github.com`)に置き換え、force push する。全コミットのハッシュが
  変わるため、`CHANGELOG.md` の見出しに記載したコミットハッシュも書き直す必要がある。

今後のコミットで公開したくない場合は、GitHub の **Settings → Emails** で
「Keep my email addresses private」と「Block command line pushes that expose my email」を有効にし、
`git config user.email` を noreply アドレスに変更する。

## 3. GitHub リポジトリ設定

公開前に設定しておくもの:

- [ ] **About**(説明文・トピック)を設定する。例:
  ```powershell
  gh repo edit --description "winget と npm で Windows の開発環境を冪等に構築する PowerShell スクリプト" `
      --add-topic windows --add-topic winget --add-topic powershell --add-topic setup-script
  ```
- [ ] **Settings → Security**(Code security)で以下を有効にする(public リポジトリでは無料):
  - Secret scanning と Push protection(誤ってトークンを push するのを防ぐ)
  - Private vulnerability reporting(`SECURITY.md` が案内する報告窓口。無効のままだと報告できない)
- [ ] **Settings → General → Features**: 使わない機能(Projects など)を無効にする。Issues を受け付けない
  方針なら Issues も無効にする。
- [ ] **Settings → Actions → General**: 現状 Actions は使っていないため、「Disable actions」にしておくか、
  少なくとも fork からの PR のワークフロー実行に承認を必須にする。
- [ ] **Settings → Rules → Rulesets**(任意): `main` への force push と削除を禁止する。

## 4. 公開の切り替え

1. 作業ツリーがクリーンで、`origin/main` と一致していることを確認する。
   ```powershell
   git status -sb
   git fetch; git log origin/main..main --oneline
   ```
2. 最終スキャン(何も出力されなければよい)。
   ```powershell
   git log --all -p | Select-String -Pattern 'ghp_|gho_|github_pat_|sk-ant-|AKIA[0-9A-Z]{16}|BEGIN .*PRIVATE KEY|password\s*='
   ```
3. 公開する(Web なら **Settings → General → Danger Zone → Change visibility**)。
   ```powershell
   gh repo edit --visibility public --accept-visibility-change-consequences
   ```

## 5. 公開後の確認

- [ ] ログアウト状態(またはシークレットウィンドウ)で README・LICENSE が表示されることを確認する。
- [ ] **Insights → Community Standards** で README / LICENSE / Security policy が認識されていることを確認する。
- [ ] **Security** タブで Secret scanning のアラートが出ていないことを確認する。
- [ ] README の `git clone` 手順どおりに取得できることを確認する(スクリプトは実行しなくてよい)。

## 6. 公開後の運用で気をつけること

- コミットする内容はすべて即座に公開される。`packages.json` に組織固有のパッケージや社内のURLを
  入れない。
- Issue / PR に、利用者の環境のパス・ユーザー名を含むログが貼られることがある。必要に応じて編集・非表示にする。
- 外部からの PR でスクリプトを変更する場合は、インストール元(`Id`)や実行するコマンドが意図どおりかを
  必ず確認する。このスクリプトは利用者が管理者権限で実行することがあるため、悪意のある変更の影響が大きい。
