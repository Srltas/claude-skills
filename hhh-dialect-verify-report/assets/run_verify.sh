#!/usr/bin/env bash
# Orchestrate CUBRID dialect verification across versions:
#   for each version → start CUBRID, run hibernate-core suite, parse results;
#   diff each vs the baseline; emit a consolidated summary.json.
# The report is generated afterward by the skill (Step 4), not here.
#
# Usage:
#   run_verify.sh --baseline <baseline.json|.tgz|results-dir> [options]
# Options:
#   --versions 10.2,11.4     comma list (default: 11.4)
#   --all-versions           shorthand for 10.2,11.0,11.2,11.3,11.4
#   --tests '<filter>'       Gradle --tests filter (fast iteration; omit for full suite)
#   --repo <path>            hibernate repo (default: ~/Devel/hibernate)
#   --out <dir>              output dir (default: ./verify-out)
#   --skip-run               reuse existing target/test-results (don't run gradle) — for re-summarizing
set -euo pipefail

REPO="$HOME/Devel/hibernate"
OUT="./verify-out"
VERSIONS="11.4"
BASELINE=""
TESTS=""
SKIP_RUN=0
PARSE="${PARSE_RESULTS:-$HOME/.claude/skills/hhh-dialect-verify/assets/parse_results.py}"

while [ $# -gt 0 ]; do
  case "$1" in
    --versions) VERSIONS="$2"; shift 2;;
    --all-versions) VERSIONS="10.2,11.0,11.2,11.3,11.4"; shift;;
    --baseline) BASELINE="$2"; shift 2;;
    --tests) TESTS="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --skip-run) SKIP_RUN=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$BASELINE" ] || { echo "ERROR: --baseline required (.json | .tgz | results-dir)" >&2; exit 2; }
[ -f "$PARSE" ] || { echo "ERROR: parse_results.py not found at $PARSE (install hhh-dialect-verify, or set PARSE_RESULTS)" >&2; exit 2; }
mkdir -p "$OUT"
RESULTS_DIR="$REPO/hibernate-core/target/test-results/test"

# --- resolve baseline -> $OUT/baseline.json ---
case "$BASELINE" in
  *.json) cp "$BASELINE" "$OUT/baseline.json";;
  *.tgz|*.tar.gz)
    btmp="$OUT/_baseline_extract"; rm -rf "$btmp"; mkdir -p "$btmp"
    tar xzf "$BASELINE" -C "$btmp"
    bdir="$(find "$btmp" -type d -path '*test-results/test' | head -1)"
    [ -n "$bdir" ] || { echo "ERROR: no test-results/test dir inside $BASELINE" >&2; exit 1; }
    python3 "$PARSE" parse "$bdir" "$OUT/baseline.json" >/dev/null;;
  *) python3 "$PARSE" parse "$BASELINE" "$OUT/baseline.json" >/dev/null;;
esac
echo "baseline → $OUT/baseline.json"

# --- per-version run + parse ---
IFS=',' read -ra VLIST <<< "$VERSIONS"
SUMARGS=()
for v in "${VLIST[@]}"; do
  echo "===== CUBRID $v ====="
  if [ "$SKIP_RUN" -eq 0 ]; then
    CUBRID_IMAGE="docker.io/cubrid/cubrid:$v" "$REPO/db.sh" cubrid
    ( cd "$REPO" && ./gradlew :hibernate-core:test -Pdb=cubrid -Plog-test-progress=true --stacktrace --no-daemon \
        ${TESTS:+--tests "$TESTS"} ) 2>&1 | tee "$OUT/run-$v.log" || true
  fi
  python3 "$PARSE" parse "$RESULTS_DIR" "$OUT/$v.json"
  SUMARGS+=("$v=$OUT/$v.json")
done

# --- consolidate ---
echo "===== summary ====="
python3 "$PARSE" summarize "$OUT/baseline.json" "$OUT/summary.json" "${SUMARGS[@]}"
echo
echo "Done. Feed $OUT/summary.json to the report step (Step 4)."
