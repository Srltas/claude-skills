#!/usr/bin/env bash
# Scaffold a velog-bound tech blog post folder in the public work-docs repo.
#   new_blog.sh <slug>       (date is added automatically)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${WORK_DOCS_REPO:-${WORKLOG_DOCS_REPO:-$HOME/Devel/work-docs}}"
TEMPLATE="$HERE/blog-template.md"

SLUG="${1:?usage: new_blog.sh <slug>}"
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
slug_l="$(slugify "$SLUG")"
valid_slug "$slug_l" || { echo "error: slug must be ASCII kebab-case (got '$SLUG'). Korean goes in the post body, not the folder name." >&2; exit 2; }

date_s="$(date +%F)"
rel="blog/$date_s-$slug_l"
absdir="$REPO/$rel"
[ -e "$absdir" ] && { echo "error: already exists: $absdir (edit it directly)" >&2; exit 2; }
mkdir -p "$absdir/assets"
cp "$TEMPLATE" "$absdir/index.md"

echo "created: $absdir/index.md"
echo "assets:  $absdir/assets/"
origin="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
if [ -n "$origin" ]; then
  slugpath="$(printf '%s' "$origin" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  branch="$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  echo "draft URL: https://github.com/$slugpath/blob/$branch/$rel/index.md"
fi
