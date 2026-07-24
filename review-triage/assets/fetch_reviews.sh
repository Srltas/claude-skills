#!/usr/bin/env bash
# Fetch a PR's review feedback (inline code comments + review summaries + PR-level comments),
# merged and readable, via the GitHub CLI.
#   fetch_reviews.sh [PR]        PR = number or URL; default = the current branch's PR
set -uo pipefail

command -v gh >/dev/null 2>&1 || { echo "error: gh (GitHub CLI) not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 2; }

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$REPO" ] || { echo "error: not in a GitHub repo, or gh is not authenticated" >&2; exit 2; }

PR="${1:-}"
if [ -z "$PR" ]; then
  N="$(gh pr view --json number -q .number 2>/dev/null || true)"
  [ -n "$N" ] || { echo "error: no PR found for the current branch. Pass a PR number or URL." >&2; exit 2; }
else
  N="$(printf '%s' "$PR" | grep -oE '[0-9]+' | tail -1)"
  [ -n "$N" ] || { echo "error: could not parse a PR number from '$PR'" >&2; exit 2; }
fi

echo "# PR #$N  ($REPO)"
gh pr view "$N" --json title,author,url -q '"title: \(.title)\nauthor: \(.author.login)\nurl: \(.url)"' 2>/dev/null || true

echo
echo "## Inline review comments (on code)"
gh api "repos/$REPO/pulls/$N/comments" --paginate --jq '
  .[] | "\n[inline #\(.id)] \(.user.login) (\(.user.type))  \(.path):\(.line // .original_line // "?")\(if .in_reply_to_id then "  (reply to #\(.in_reply_to_id))" else "" end)\n\(.body)"
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
