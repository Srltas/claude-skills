#!/usr/bin/env bash
# Scaffold an exploration note (PoC / review / analysis / ...) in the public work-docs repo.
#   new_note.sh <category> <slug>       (date is added automatically)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${WORK_DOCS_REPO:-${WORKLOG_DOCS_REPO:-$HOME/Devel/work-docs}}"
TEMPLATE="$HERE/note-template.md"

CATEGORY="${1:?usage: new_note.sh <category> <slug>}"
SLUG="${2:?usage: new_note.sh <category> <slug>}"

[ -d "$REPO/.git" ] || { echo "error: docs repo not found at $REPO — clone your public work-docs repo there, or set WORK_DOCS_REPO." >&2; exit 2; }
[ -f "$TEMPLATE" ] || { echo "error: template missing: $TEMPLATE" >&2; exit 2; }

# ASCII kebab-case. Spaces become hyphens BEFORE non-ASCII is dropped, so a Korean input can
# otherwise survive as a string of bare hyphens and pass a non-empty check ("한글 슬러그" -> "--").
# Collapse and trim them, then require at least one alphanumeric.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9._-' \
    | sed -E 's/-+/-/g; s/^[-._]+//; s/[-._]+$//'
}
valid_slug() { printf '%s' "$1" | grep -qE '[a-z0-9]'; }
cat_l="$(slugify "$CATEGORY")"
slug_l="$(slugify "$SLUG")"
valid_slug "$cat_l" || { echo "error: category must be ASCII kebab-case (got '$CATEGORY'). Korean goes in the note body, not the path." >&2; exit 2; }
valid_slug "$slug_l" || { echo "error: slug must be ASCII kebab-case (got '$SLUG'). Korean goes in the note body, not the filename." >&2; exit 2; }
case "$cat_l" in .|..|*/*) echo "error: bad category '$cat_l'" >&2; exit 2;; esac

date_s="$(date +%F)"
rel="$cat_l/$date_s-$slug_l.md"
file="$REPO/$rel"
[ -e "$file" ] && { echo "error: already exists: $file (edit it directly)" >&2; exit 2; }
mkdir -p "$REPO/$cat_l"
sed -e "s/{{CATEGORY}}/$cat_l/g" -e "s/{{DATE}}/$date_s/g" "$TEMPLATE" > "$file"

echo "created: $file"
origin="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
if [ -n "$origin" ]; then
  slugpath="$(printf '%s' "$origin" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  branch="$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  echo "will publish at: https://github.com/$slugpath/blob/$branch/$rel"
fi
