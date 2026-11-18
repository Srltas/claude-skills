#!/usr/bin/env bash
# Render every figure of a work-docs note so it can be looked at before the commit:
# each SVG the note links (![..](x.svg)) at its natural size with headless Chrome, and each
# mermaid block through Kroki. Prints the PNG paths to read.
#   render_check.sh <note.md> [out-dir]
set -euo pipefail

MD="${1:?usage: render_check.sh <note.md> [out-dir]}"
[ -f "$MD" ] || { echo "error: no such note: $MD" >&2; exit 2; }
TMP="${TMPDIR:-/tmp}"
OUT="${2:-$(mktemp -d "${TMP%/}/render-check.XXXXXX")}"
mkdir -p "$OUT"
DIR="$(cd "$(dirname "$MD")" && pwd)"

CHROME=""
for c in "${CHROME_BIN:-}" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome 2>/dev/null || true)" "$(command -v chromium 2>/dev/null || true)" \
         "$(command -v chromium-browser 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then CHROME="$c"; break; fi
done

svgs="$(grep -oE '\]\([^)]+\.svg\)' "$MD" | sed -E 's/^\]\(//; s/\)$//' | sort -u || true)"
if [ -n "$svgs" ] && [ -z "$CHROME" ]; then
  echo "error: no Chrome found to render the SVG files; set CHROME_BIN" >&2
  exit 2
fi
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  f="$DIR/$rel"
  [ -f "$f" ] || { echo "missing: $rel"; continue; }
  size="$(sed -n 's/.*viewBox="0 0 \([0-9.]*\) \([0-9.]*\)".*/\1 \2/p' "$f" | head -1)"
  [ -n "$size" ] || { echo "no viewBox: $rel"; continue; }
  w="$(printf '%.0f' "${size% *}")"; h="$(printf '%.0f' "${size#* }")"
  png="$OUT/$(basename "$rel" .svg).png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --screenshot="$png" --window-size="$w,$h" "file://$f" >/dev/null 2>&1 || true
  if [ -s "$png" ]; then echo "$png"; else echo "render failed: $rel"; fi
done <<< "$svgs"

awk -v out="$OUT" '
  /^```mermaid/ { n++; f = sprintf("%s/mermaid-%d.mmd", out, n); inblock = 1; next }
  /^```/        { if (inblock) { inblock = 0; close(f) } ; next }
  inblock       { print > f }
' "$MD"
for m in "$OUT"/mermaid-*.mmd; do
  [ -e "$m" ] || break
  png="${m%.mmd}.png"
  if curl -sf -X POST "${KROKI_URL:-https://kroki.io}/mermaid/png" -H 'Content-Type: text/plain' \
       --data-binary @"$m" -o "$png"; then
    echo "$png"
  else
    echo "kroki failed: $m (fix the syntax or set KROKI_URL)"
  fi
done
