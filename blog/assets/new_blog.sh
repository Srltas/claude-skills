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

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9._-'; }
slug_l="$(slugify "$SLUG")"
[ -n "$slug_l" ] || { echo "error: empty slug after sanitizing" >&2; exit 2; }

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
