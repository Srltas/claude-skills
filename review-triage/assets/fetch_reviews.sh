#!/usr/bin/env bash
# Fetch a PR's review feedback (inline code comments + review summaries + PR-level comments),
# merged and readable, via the GitHub CLI.
#   fetch_reviews.sh [PR] [--include-resolved]
#     PR = number or URL; default = the current branch's PR
#     Comments in RESOLVED review threads are skipped by default (that discussion is settled);
#     pass --include-resolved to see them too.
set -uo pipefail

command -v gh >/dev/null 2>&1 || { echo "error: gh (GitHub CLI) not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 2; }

PR=""
INCLUDE_RESOLVED=0
for a in "$@"; do
  case "$a" in
    --include-resolved) INCLUDE_RESOLVED=1;;
    -*) echo "error: unknown option '$a' (only --include-resolved)" >&2; exit 2;;
    *) PR="$a";;
  esac
done

# A full PR URL carries its own owner/repo: use it, so a URL from another repo is not silently
# read as the current directory's PR of the same number. Otherwise fall back to the cwd repo.
REPO="$(printf '%s' "$PR" | sed -nE 's#^.*github\.com/([^/]+/[^/]+)/pulls?/[0-9]+.*$#\1#p')"
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$REPO" ] || { echo "error: not in a GitHub repo, or gh is not authenticated" >&2; exit 2; }
fi

if [ -z "$PR" ]; then
  N="$(gh pr view --json number -q .number 2>/dev/null || true)"
  [ -n "$N" ] || { echo "error: no PR found for the current branch. Pass a PR number or URL." >&2; exit 2; }
else
  N="$(printf '%s' "$PR" | grep -oE '[0-9]+' | tail -1)"
  [ -n "$N" ] || { echo "error: could not parse a PR number from '$PR'" >&2; exit 2; }
fi

echo "# PR #$N  ($REPO)"
gh pr view "$N" --repo "$REPO" --json title,author,url -q '"title: \(.title)\nauthor: \(.author.login)\nurl: \(.url)"' 2>/dev/null || true

# Resolution lives only on the review THREAD, and only in GraphQL: the REST comment payload has no
# resolved field. Collect the comment ids of resolved threads so they can be skipped.
SKIP='[]'; SKIPPED=0; WARN=""
if [ "$INCLUDE_RESOLVED" -eq 0 ]; then
  GQL="$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$n:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$n){
          reviewThreads(first:100){
            pageInfo{ hasNextPage }
            nodes{ isResolved comments(first:100){ nodes{ databaseId } } }
          }
        }
      }
    }' -F owner="${REPO%%/*}" -F repo="${REPO##*/}" -F n="$N" 2>/dev/null || true)"
  if [ -n "$GQL" ]; then
    SKIP="$(printf '%s' "$GQL" | jq -c '[.data.repository.pullRequest.reviewThreads.nodes[]? | select(.isResolved) | .comments.nodes[]?.databaseId]' 2>/dev/null || echo '[]')"
    SKIPPED="$(printf '%s' "$SKIP" | jq 'length' 2>/dev/null || echo 0)"
    [ "$(printf '%s' "$GQL" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' 2>/dev/null)" = "true" ] &&
      WARN="warning: more than 100 review threads; some resolved ones may not have been detected."
  else
    WARN="warning: could not read thread resolution (GraphQL failed); showing ALL comments, resolved included."
  fi
fi

echo
echo "## Inline review comments (on code)"
[ "$SKIPPED" -gt 0 ] && echo "(skipped $SKIPPED comment(s) in resolved threads; pass --include-resolved to see them)"
[ -n "$WARN" ] && echo "$WARN"
gh api "repos/$REPO/pulls/$N/comments" --paginate 2>/dev/null | jq -r --argjson skip "$SKIP" '
  .[] | select((.id as $i | $skip | index($i)) | not)
  | "\n[inline #\(.id)] \(.user.login) (\(.user.type))  \(.path):\(.line // .original_line // "?")\(if .in_reply_to_id then "  (reply to #\(.in_reply_to_id))" else "" end)\n\(.body)"
' 2>/dev/null || echo "(none)"

echo
echo "## Review summaries"
gh api "repos/$REPO/pulls/$N/reviews" --paginate --jq '
  .[] | select(.state != "PENDING") | select(((.body // "") | length) > 0 or .state == "APPROVED" or .state == "CHANGES_REQUESTED")
  | "\n[review \(.state)] \(.user.login) (\(.user.type))\n\(.body // "")"
' 2>/dev/null || echo "(none)"

echo
echo "## PR-level comments"
gh api "repos/$REPO/issues/$N/comments" --paginate --jq '
  .[] | "\n[comment #\(.id)] \(.user.login) (\(.user.type))\n\(.body)"
' 2>/dev/null || echo "(none)"
