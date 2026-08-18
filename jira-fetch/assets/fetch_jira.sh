#!/usr/bin/env bash
# Fetch JIRA issue(s) to local Markdown via Srltas/jira-to-md-downloader.
#   fetch_jira.sh [-o OUTDIR] ISSUE-KEY|ISSUE-URL [more...]
# An issue URL works too: the key is extracted from it (e.g. .../browse/CBRD-1234).
# Credentials from env (JIRA_URL/JIRA_USER/JIRA_PASSWORD) or the tool's .envrc.
set -euo pipefail

TOOL_REPO="https://github.com/Srltas/jira-to-md-downloader.git"
TOOL_DIR="${JIRA_MD_TOOL_DIR:-$HOME/.cache/claude-skills/jira-to-md-downloader}"
OUTDIR="./jira"

# Accept a full issue URL as well as a bare key, and normalize to upper-case KEY-123.
# (Passing a browse URL straight through produced /rest/api/2/issue/http://... -> HTTP 404.)
normalize_key() {
  local raw="$1" k="$1"
  case "$raw" in
    *://*)
      k="$(printf '%s' "$raw" | sed -nE 's#^.*/(browse|issues)/([A-Za-z][A-Za-z0-9_]*-[0-9]+).*$#\2#p')"
      [ -n "$k" ] || k="$(printf '%s' "$raw" | grep -oE '[A-Za-z][A-Za-z0-9_]*-[0-9]+' | tail -1)"
      ;;
  esac
  k="$(printf '%s' "$k" | tr '[:lower:]' '[:upper:]')"
  if ! printf '%s' "$k" | grep -qE '^[A-Z][A-Z0-9_]*-[0-9]+$'; then
    echo "error: cannot read an issue key from '$raw' (expected CBRD-1234, or a URL like http://jira.cubrid.org/browse/CBRD-1234)" >&2
    return 1
  fi
  printf '%s' "$k"
}

KEYS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out) OUTDIR="${2:?-o needs a directory}"; shift 2;;
    -h|--help) echo "usage: fetch_jira.sh [-o OUTDIR] ISSUE-KEY|ISSUE-URL [more...]"; exit 0;;
    --) shift; while [ $# -gt 0 ]; do KEYS+=("$1"); shift; done;;
    -*) echo "error: unknown option '$1'" >&2; exit 2;;
    *) KEYS+=("$1"); shift;;
  esac
done
[ ${#KEYS[@]} -eq 0 ] && { echo "error: no issue key given (e.g. CBRD-1234)" >&2; exit 2; }

NORM=()
for k in "${KEYS[@]}"; do
  nk="$(normalize_key "$k")" || exit 2
  NORM+=("$nk")
done
KEYS=("${NORM[@]}")

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
# One unreadable key must not abort the batch: report per-key below instead.
( cd "$TOOL_DIR" && uv run jira-to-md-download -o "$OUTDIR_ABS" "${KEYS[@]}" ) || true

echo "--- downloaded ---"
rc=0
for k in "${KEYS[@]}"; do
  f="$OUTDIR_ABS/$k.md"
  if [ -f "$f" ]; then echo "$f"; else echo "(missing: $k)"; rc=1; fi
done
if [ $rc -ne 0 ]; then
  cat >&2 <<'EOF'
note: a missing issue is almost always one of
  HTTP 401  the configured account cannot read it. Internal-only projects (CUBRIDQA) are NOT
            reachable from this tool: open those in the browser instead.
  HTTP 404  wrong or non-existent key.
EOF
fi
exit $rc
