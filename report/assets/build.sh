#!/usr/bin/env bash
# Build a report .docx from its JSON spec, ensuring the toolchain first.
#   build.sh <spec.json> <out.docx>
# Folds the one-time dependency checks in, so building is a single call.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPEC="${1:?usage: build.sh <spec.json> <out.docx>}"
OUT="${2:?usage: build.sh <spec.json> <out.docx>}"
[ -f "$SPEC" ] || { echo "error: no such spec: $SPEC" >&2; exit 2; }

command -v node >/dev/null || { echo "error: node not found" >&2; exit 2; }
npm list -g docx >/dev/null 2>&1 || { echo "· installing docx (one-time)" >&2; npm install -g docx >/dev/null 2>&1 || { echo "error: npm install -g docx failed" >&2; exit 2; }; }

VENV="$HOME/.cache/claude-skills/report-venv"
[ -x "$VENV/bin/python" ] || { echo "· creating report venv (one-time)" >&2; python3 -m venv "$VENV" || exit 2; }
"$VENV/bin/python" -c "import matplotlib" 2>/dev/null || { echo "· installing matplotlib (one-time)" >&2; "$VENV/bin/pip" -q install matplotlib || exit 2; }

NODE_PATH="$(npm root -g)" REPORT_PY="$VENV/bin/python" node "$HERE/build_report.js" "$SPEC" "$OUT"
