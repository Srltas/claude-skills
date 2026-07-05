#!/usr/bin/env bash
# Fetch JIRA issue(s) to local Markdown via Srltas/jira-to-md-downloader.
#   fetch_jira.sh [-o OUTDIR] ISSUE-KEY [ISSUE-KEY...]
# Credentials from env (JIRA_URL/JIRA_USER/JIRA_PASSWORD) or the tool's .envrc.
set -euo pipefail

TOOL_REPO="https://github.com/Srltas/jira-to-md-downloader.git"
TOOL_DIR="${JIRA_MD_TOOL_DIR:-$HOME/.cache/claude-skills/jira-to-md-downloader}"
OUTDIR="./jira"

KEYS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out) OUTDIR="${2:?-o needs a directory}"; shift 2;;
    -h|--help) echo "usage: fetch_jira.sh [-o OUTDIR] ISSUE-KEY [ISSUE-KEY...]"; exit 0;;
    --) shift; while [ $# -gt 0 ]; do KEYS+=("$1"); shift; done;;
    -*) echo "error: unknown option '$1'" >&2; exit 2;;
    *) KEYS+=("$1"); shift;;
  esac
done
[ ${#KEYS[@]} -eq 0 ] && { echo "error: no issue key given (e.g. CBRD-1234)" >&2; exit 2; }

command -v uv >/dev/null     || { echo "error: 'uv' not found — brew install uv" >&2; exit 2; }
command -v pandoc >/dev/null || { echo "error: 'pandoc' not found — brew install pandoc (the tool needs it)" >&2; exit 2; }

mkdir -p "$OUTDIR"
OUTDIR_ABS="$(cd "$OUTDIR" && pwd)"

# ensure the tool is present + deps synced (idempotent)
if [ ! -d "$TOOL_DIR/.git" ]; then
  echo "· cloning jira-to-md-downloader → $TOOL_DIR" >&2
  mkdir -p "$(dirname "$TOOL_DIR")"
  git clone --depth 1 "$TOOL_REPO" "$TOOL_DIR"
fi
( cd "$TOOL_DIR" && uv sync --quiet )

# credentials: env first, then the tool's .envrc as a fallback
if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_USER:-}" ] || [ -z "${JIRA_PASSWORD:-}" ]; then
  if [ -f "$TOOL_DIR/.envrc" ]; then set -a; . "$TOOL_DIR/.envrc" 2>/dev/null || true; set +a; fi
fi
if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_USER:-}" ] || [ -z "${JIRA_PASSWORD:-}" ]; then
  cat >&2 <<EOF
error: JIRA credentials not set. Export them (or put them in $TOOL_DIR/.envrc):
  export JIRA_URL="https://jira.cubrid.org"     # Hibernate: https://hibernate.atlassian.net
  export JIRA_USER="you@cubrid.com"
  export JIRA_PASSWORD="<password or personal access token>"
EOF
  exit 2
fi

echo "· fetching: ${KEYS[*]}  ->  $OUTDIR_ABS" >&2
( cd "$TOOL_DIR" && uv run jira-to-md-download -o "$OUTDIR_ABS" "${KEYS[@]}" )

echo "--- downloaded ---"
rc=0
for k in "${KEYS[@]}"; do
  f="$OUTDIR_ABS/$k.md"
  if [ -f "$f" ]; then echo "$f"; else echo "(missing: $k)"; rc=1; fi
done
exit $rc
