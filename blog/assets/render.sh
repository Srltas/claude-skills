#!/usr/bin/env bash
# Render a diagram-as-code source to an image via the Kroki API (public service).
#   render.sh <source-file> [out-file]
# Diagram type is inferred from the source extension:
#   .mmd/.mermaid -> mermaid, .dot/.gv -> graphviz, .d2 -> d2, .puml/.plantuml -> plantuml
# Output format is inferred from the out-file extension (default .svg). For velog, render .png.
#   e.g. render.sh assets/diagram-1.mmd assets/diagram-1.png
set -euo pipefail

SRC="${1:?usage: render.sh <source-file> [out-file]  (e.g. render.sh assets/diagram-1.mmd assets/diagram-1.png)}"
[ -f "$SRC" ] || { echo "error: no such file: $SRC" >&2; exit 2; }
case "$SRC" in
  *.mmd|*.mermaid)   TYPE=mermaid;;
  *.dot|*.gv)        TYPE=graphviz;;
  *.d2)              TYPE=d2;;
  *.puml|*.plantuml) TYPE=plantuml;;
  *) echo "error: cannot infer diagram type from '$SRC' (use .mmd/.dot/.d2/.puml)" >&2; exit 2;;
esac
OUT="${2:-${SRC%.*}.svg}"
FMT="${OUT##*.}"
KROKI="${KROKI_URL:-https://kroki.io}"

command -v curl >/dev/null || { echo "error: curl not found" >&2; exit 2; }
if curl -sf -X POST "$KROKI/$TYPE/$FMT" -H "Content-Type: text/plain" --data-binary @"$SRC" -o "$OUT"; then
  echo "rendered: $OUT  ($TYPE -> $FMT)"
else
  echo "error: Kroki render failed (network, invalid $TYPE source, or unsupported format '$FMT'). Set KROKI_URL to a self-hosted instance if needed." >&2
  rm -f "$OUT"
  exit 1
fi
