#!/usr/bin/env bash
# Scaffold a work-record markdown in the public work-docs repo from the template.
#   new_worklog.sh <ISSUE-KEY|topic> [slug]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${WORK_DOCS_REPO:-${WORKLOG_DOCS_REPO:-$HOME/Devel/work-docs}}"
TEMPLATE="$HERE/worklog-template.md"

KEY="${1:?usage: new_worklog.sh <ISSUE-KEY|topic> [slug]}"
SLUG="${2:-}"

[ -d "$REPO/.git" ] || { echo "error: docs repo not found at $REPO — clone your public work-docs repo there, or set WORKLOG_DOCS_REPO." >&2; exit 2; }
[ -f "$TEMPLATE" ] || { echo "error: template missing: $TEMPLATE" >&2; exit 2; }

# Split a leading PROJECT-NUMBER key (case-insensitive) from an optional -slug tail,
# so the KEY is ALWAYS uppercase in the filename (folder stays lowercase).
key_re='^[A-Za-z][A-Za-z0-9]*-[0-9]+'
if printf '%s' "$KEY" | grep -qiE "${key_re}(-.*)?$"; then
  keypart="$(printf '%s' "$KEY" | grep -oiE "$key_re" | head -1)"
  tail="${KEY#"$keypart"}"                                         # '' or '-slug'
  title="$(printf '%s' "$keypart" | tr '[:lower:]' '[:upper:]')"   # CBRD-1234
  folder="$title"                                                  # CBRD-1234 (folder key also uppercase)
  name="$title$tail"
  [ -n "$SLUG" ] && name="$name-$SLUG"
else
  # topic (no issue key): sanitize, or a Korean/spaced topic becomes a directory with spaces
  # and 'a/b' would create stray nested directories after mkdir -p.
  title="$(printf '%s' "$KEY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9._-' \
           | sed -E 's/-+/-/g; s/^[-._]+//; s/[-._]+$//')"
  printf '%s' "$title" | grep -qE '[a-z0-9]' || {
    echo "error: topic must be an issue key (CBRD-1234) or ASCII kebab-case (got '$KEY')." >&2; exit 2; }
  folder="$title"; name="$title"; [ -n "$SLUG" ] && name="$title-$SLUG"
fi

file="$REPO/$folder/$name.md"
[ -e "$file" ] && { echo "error: already exists: $file (edit it directly)" >&2; exit 2; }
mkdir -p "$REPO/$folder"
sed -e "s/{{KEY}}/$title/g" -e "s/{{DATE}}/$(date +%F)/g" "$TEMPLATE" > "$file"

echo "created: $file"
origin="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
if [ -n "$origin" ]; then
  slugpath="$(printf '%s' "$origin" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  branch="$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  echo "will publish at: https://github.com/$slugpath/blob/$branch/$folder/$name.md"
fi
