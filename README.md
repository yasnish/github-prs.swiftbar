# github-prs.swiftbar

複数の GitHub リポジトリから「自分が関わっている Open な PR」を集めて、macOS のメニューバーに表示する [SwiftBar](https://github.com/swiftbar/SwiftBar) プラグインです。

```
👀 3 / 💬 1 / 🚀 2
---
👀 未レビュー（自分のレビュー未実施・再レビュー依頼含む）
  🔁 🧑 [my-app#120] feat: ログイン画面を刷新 (@alice)
  🧑 [api#45] fix: タイムアウト値を調整 (@bob)
  📦 [my-app#118] chore(deps): bump react from 19.0.0 to 19.1.0 (@app/dependabot)
---
💬 レビュー済み・未Approve（コメント/修正依頼）
  🧑 [api#40] refactor: 認証ミドルウェアを整理 (@carol)
---
🚀 自分が作成したPR
  [my-app#119] docs: README を更新
  [api#44] test: E2E テストを追加
---
✅ 自分がApprove済みのPR（Open）
  (なし)
```

各項目をクリックすると、ブラウザで PR が開きます。

## 表示内容

| セクション | 内容 |
|---|---|
| 👀 未レビュー | 自分がまだレビューしていない PR と、レビュー後に再度レビュー依頼された PR（🔁） |
| 💬 レビュー済み・未Approve | コメントや修正依頼はしたが、まだ Approve していない PR |
| 🚀 自分が作成した PR | 自分が作成者の PR |
| ✅ Approve 済み | 自分が Approve した、まだ Open の PR |

メニューバーには 👀 / 💬 / 🚀 の件数が表示されます。

### 再レビュー依頼（🔁）の判定

GitHub では、コメントだけのレビューをしてもレビュー依頼が解除されません。そのため、現在レビュー依頼中かどうかだけでは、初回の依頼と再依頼を区別できません。
このプラグインは PR の timeline を参照し、**自分の最後のレビューより後にレビュー依頼イベントがあるか**で再依頼を判定しています。

## 必要なもの

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) 2.1.0 以降（`.swiftbar` パッケージプラグイン対応版）
- [GitHub CLI (`gh`)](https://cli.github.com/)（`gh auth login` でログイン済みであること）
- [jq](https://jqlang.github.io/jq/)

```sh
brew install --cask swiftbar
brew install gh jq
gh auth login
```

## インストール

SwiftBar のプラグインフォルダに、フォルダ名を `.swiftbar` で終わる名前にして clone します。

```sh
cd "<SwiftBar のプラグインフォルダ>"
git clone https://github.com/yasnish/github-prs.swiftbar.git
cd github-prs.swiftbar
cp github-prs.conf.example github-prs.conf
```

`github-prs.conf` を編集したあと、SwiftBar のメニューから「Refresh All」を実行してください。

## 設定

設定は `github-prs.conf` に書きます。このファイルは `.gitignore` で除外しているため、リポジトリには含まれません。

```bash
# チェックしたいリポジトリ（"owner/repo" 形式）
# 表示順はここに書いた順になります
REPOS=(
  "your-org/my-app"
  "your-org/api"
)

# PR 作成者ごとの表示優先度とアイコン（"login|icon" 形式）
AUTHOR_PRIORITY=(
  "*|🧑"
  "app/github-actions|🤖"
  "app/dependabot|📦"
)
```

### `REPOS`

チェックしたいリポジトリを `owner/repo` 形式で並べます。ローカルに clone しておく必要はありません。

### `AUTHOR_PRIORITY`

PR 作成者ごとの表示順とアイコンを決めます。

- 上に書いた作成者ほど上に表示されます
- `*` は、リストにないすべての作成者（人間など）を表します
- `*` を書かなかった場合、リストにない作成者は最後尾に 🧑 で表示されます
- アイコンは省略できます（`"app/dependabot"` のように名前だけでも可）
- `AUTHOR_PRIORITY` 自体を書かなかった場合は、全員が 🧑・同じ順位として扱われます

### 並び順

各セクション内の PR は、次の順に並びます。

1. 再レビュー依頼（🔁）の PR（👀 未レビューのみ）
2. `AUTHOR_PRIORITY` の順
3. `REPOS` の順
4. 同じリポジトリ内では、新しい PR が先

### 設定ファイルの場所を変える

環境変数 `GITHUB_PRS_CONFIG` で、設定ファイルのパスを指定できます。

## 更新間隔

更新間隔は、ファイル名 `plugin.5m.sh` の `5m` の部分で決まります（例: `plugin.10m.sh` にすると 10 分ごと）。
書き方は [SwiftBar のドキュメント](https://github.com/swiftbar/SwiftBar#plugin-naming) を参照してください。

## License

[MIT](LICENSE)
