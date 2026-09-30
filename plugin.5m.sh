#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# =========================================================
# 設定ファイル（チェック対象リポジトリ）の読み込み
# デフォルト: このスクリプトと同じフォルダの github-prs.conf
# (.swiftbar パッケージ内では plugin.* 以外はプラグインとして扱われない)
# 環境変数 GITHUB_PRS_CONFIG で上書き可能
# 書式は同じフォルダの github-prs.conf.example を参照
# =========================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${GITHUB_PRS_CONFIG:-$SCRIPT_DIR/github-prs.conf}"
REPOS=()
AUTHOR_PRIORITY=()
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi
if [ ${#REPOS[@]} -eq 0 ]; then
  echo "⚠️ 設定なし"
  echo "---"
  echo "設定ファイルに REPOS を定義してください"
  echo "$CONFIG_FILE"
  exit 0
fi

# 作成者ごとの表示優先度・アイコン（"login|icon" 形式、上ほど優先。"*" はその他全員）
[ ${#AUTHOR_PRIORITY[@]} -eq 0 ] && AUTHOR_PRIORITY=("*|🧑")
AUTHOR_RULES=$(printf '%s\n' "${AUTHOR_PRIORITY[@]}" | jq -R -s '
  split("\n") | map(select(length > 0))
  | to_entries
  | map((.value | split("|")) as $p | {login: $p[0], icon: ($p[1] // ""), rank: .key})
')

MY_USER=$(gh api user --jq .login 2>/dev/null)
if [ -z "$MY_USER" ]; then
  echo "⚠️ 未ログイン"
  exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# リポジトリ数が多いので並列取得する
# 表示順を設定ファイルの REPOS 順にするため、インデックスを付けて保持する
for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  (
    REPO_NAME="${REPO#*/}"
    PRS=$(gh pr list -R "$REPO" --search "is:open involves:@me" \
      --json number,title,url,author,reviews,reviewRequests 2>/dev/null)
    if [ -n "$PRS" ] && [ "$PRS" != "[]" ]; then
      echo "$PRS" | jq --arg repo "$REPO_NAME" --arg full "$REPO" --argjson idx "$i" \
        'map(. + {repo: $repo, repo_full: $full, repo_index: $idx})' \
        > "$WORK_DIR/$(printf '%04d' "$i").json"
    fi
  ) &
done
wait

ALL_PRS=$(cat "$WORK_DIR"/*.json 2>/dev/null | jq -s 'add // []')
[ -z "$ALL_PRS" ] && ALL_PRS="[]"

# 必要なフィールドだけに整形する
BASE_PRS=$(echo "$ALL_PRS" | jq --arg me "$MY_USER" --argjson rules "$AUTHOR_RULES" '
  # "*" が未指定なら、リストにない作成者は最後尾・🧑 扱い
  ($rules | map(select(.login == "*")) | first // {icon: "🧑", rank: ($rules | length)}) as $default
  | map((.author.login // "ghost") as $login
    | ($rules | map(select(.login == $login)) | first // $default) as $rule
    | {
    key: "\(.repo_full)#\(.number)",
    repo_full: .repo_full,
    number: .number,
    title: .title,
    url: .url,
    repo: .repo,
    repo_index: .repo_index,
    author: $login,
    author_rank: $rule.rank,
    author_icon: $rule.icon,
    approved_by_me: (((.reviews // []) | map(select(.author.login == $me and .state == "APPROVED"))) | length > 0),
    reviewed_by_me: (((.reviews // []) | map(select(.author.login == $me))) | length > 0),
    my_last_review_at: (((.reviews // []) | map(select(.author.login == $me) | .submittedAt)) | max),
    pending_request: (((.reviewRequests // []) | map(select(.login == $me))) | length > 0)
  })
')
[ -z "$BASE_PRS" ] && BASE_PRS="[]"

# 「再レビュー依頼」の判定:
# Comment のみのレビューではレビューリクエストが解除されないため、reviewRequests の
# スナップショットだけでは初回依頼と再依頼を区別できない。timeline の review_requested
# イベント時刻が自分の最終レビューより後かどうかで判定する。
# 対象は「自分がレビュー済み かつ 現在レビュー依頼中」の PR のみ（API 呼び出しを節約）。
REQ_DIR="$WORK_DIR/rereq"
mkdir -p "$REQ_DIR"

while read -r RF NUM; do
  [ -z "$RF" ] && continue
  (
    gh api "repos/$RF/issues/$NUM/timeline" --paginate 2>/dev/null \
      | jq -s --arg me "$MY_USER" --arg key "$RF#$NUM" '
          {
            key: $key,
            last_request_at: ([.[] | .[]?
              | select(.event == "review_requested" and ((.requested_reviewer.login // "") == $me))
              | .created_at] | max)
          }' \
      > "$REQ_DIR/$(echo "$RF" | tr '/' '_')_$NUM.json"
  ) &
done < <(echo "$BASE_PRS" | jq -r '.[] | select(.reviewed_by_me and .pending_request) | "\(.repo_full) \(.number)"')
wait

LAST_REQS=$(cat "$REQ_DIR"/*.json 2>/dev/null | jq -s 'map({(.key): .last_request_at}) | add // {}')
[ -z "$LAST_REQS" ] && LAST_REQS="{}"

echo "$BASE_PRS" | jq -r --arg me "$MY_USER" --argjson reqs "$LAST_REQS" '
  map(. + {
    # 自分の最終レビューより後にレビュー依頼イベントがある = 明示的な再依頼
    re_requested: (($reqs[.key] // null) as $req
      | ($req != null) and ((.my_last_review_at // "") < $req))
  })
  | {
      # 未レビュー（自分のレビュー未実施 or 再レビュー依頼）
      # 優先度順（再レビュー依頼 > AUTHOR_PRIORITY 順 > REPOS 順）にソート
      untouched_prs: (
        map(select(.author != $me and ((.reviewed_by_me | not) or .re_requested)))
        | sort_by([(if .re_requested then 0 else 1 end), .author_rank, .repo_index])
      ),
      # コメント / 修正依頼はしたが Approve していない（再依頼分は未レビューへ）
      commented_prs: (map(select(.author != $me and .reviewed_by_me and (.approved_by_me | not) and (.re_requested | not))) | sort_by([.author_rank, .repo_index])),
      my_prs: (map(select(.author == $me)) | sort_by(.repo_index)),
      approved_prs: (map(select(.author != $me and .approved_by_me and (.re_requested | not))) | sort_by([.author_rank, .repo_index]))
    }
  | [
      "👀 \( .untouched_prs | length ) / 💬 \( .commented_prs | length ) / 🚀 \( .my_prs | length )",
      "---",
      "👀 未レビュー（自分のレビュー未実施・再レビュー依頼含む）",
      ( if (.untouched_prs | length) == 0 then "  (なし)" else (.untouched_prs[] | "  \(if .re_requested then "🔁 " else "" end)\(.author_icon) [\(.repo)#\(.number)] \(.title) (@\(.author)) | href=\(.url)") end ),
      "---",
      "💬 レビュー済み・未Approve（コメント/修正依頼）",
      ( if (.commented_prs | length) == 0 then "  (なし)" else (.commented_prs[] | "  \(.author_icon) [\(.repo)#\(.number)] \(.title) (@\(.author)) | href=\(.url)") end ),
      "---",
      "🚀 自分が作成したPR",
      ( if (.my_prs | length) == 0 then "  (なし)" else (.my_prs[] | "  [\(.repo)#\(.number)] \(.title) | href=\(.url)") end ),
      "---",
      "✅ 自分がApprove済みのPR（Open）",
      ( if (.approved_prs | length) == 0 then "  (なし)" else (.approved_prs[] | "  \(.author_icon) [\(.repo)#\(.number)] \(.title) (@\(.author)) | href=\(.url)") end )
    ]
  | .[]
'
