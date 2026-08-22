#!/usr/bin/env bash
# Everything pr-draft needs to start drafting, in one call.
#   pr_context.sh [base-ref]
# Without a base it resolves one: the remote's own default branch first, then the usual
# candidates. Resolving it inline meant several trial-and-error `git rev-parse` calls.
set -uo pipefail
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repository" >&2; exit 2; }

BR="$(git rev-parse --abbrev-ref HEAD)"
KEY="$(printf '%s' "$BR" | grep -oE '[A-Za-z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')"

BASE="${1:-}"
if [ -n "$BASE" ]; then
  git rev-parse --verify -q "$BASE" >/dev/null 2>&1 || { echo "error: base '$BASE' does not exist here" >&2; exit 2; }
else
  # the remote's declared default branch (main / develop / master), then fallbacks
  for remote in upstream origin; do
    d="$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
    [ -n "$d" ] && git rev-parse --verify -q "$d" >/dev/null 2>&1 && { BASE="$d"; break; }
  done
  if [ -z "$BASE" ]; then
    for r in upstream/main origin/main main upstream/develop origin/develop develop \
             upstream/master origin/master master; do
      git rev-parse --verify -q "$r" >/dev/null 2>&1 && { BASE="$r"; break; }
    done
  fi
fi
[ -n "$BASE" ] || { echo "error: no base branch found. Pass one explicitly." >&2; exit 2; }

N="$(git rev-list --count "$BASE..HEAD" 2>/dev/null || echo 0)"
echo "branch : $BR"
echo "key    : ${KEY:-(none in the branch name: ask the user)}"
echo "base   : $BASE  ($N commit(s) ahead)"
echo "repo   : $(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' || echo '?')"

echo
echo "commits:"
git log "$BASE..HEAD" --oneline || true

echo
echo "changed files:"
git diff "$BASE...HEAD" --stat || true

# test-only? tells pr-draft whether the TC template is even a candidate (it still needs --tc)
PROD="$(git diff "$BASE...HEAD" --name-only | grep -vcE '(^|/)(test|tests)/' || true)"
echo
echo "non-test files changed: ${PROD:-0}"
