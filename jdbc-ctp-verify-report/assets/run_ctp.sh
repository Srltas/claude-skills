#!/usr/bin/env bash
# Orchestrate CUBRID JDBC driver verification via CTP:
#   build the driver → deploy the jar → run the CTP JDBC suite → parse → diff vs a baseline.
# The report is generated afterward by the skill (Step 4), not here.
#
# Usage:
#   run_ctp.sh --baseline <json|result-dir|test-jdbc.xml> [options]
# Options:
#   --jdbc-repo <path>   driver source (default ~/Devel/JDBC/devel)
#   --ctp-home <path>    CTP home (default ~/Devel/JDBC/jdbc-verification/cubrid-testtools/CTP)
#   --cubrid <path>      CUBRID install dir where the jar deploys ($CUBRID/jdbc/) — default: $CUBRID
#   --conf <file>        CTP jdbc conf (default <ctp-home>/conf/jdbc.conf)
#   --no-build           skip the driver build (use the already-deployed jar)
#   --out <dir>          output dir (default ./ctp-out)
set -euo pipefail

JDBC_REPO="$HOME/Devel/JDBC/devel"
CTP_HOME="$HOME/Devel/JDBC/jdbc-verification/cubrid-testtools/CTP"
CUBRID_DIR="${CUBRID:-}"
CONF=""
OUT="./ctp-out"
BASELINE=""
NO_BUILD=0
CLEANUP=1
PARSE="${PARSE_CTP:-$HOME/.claude/skills/jdbc-ctp-verify-report/assets/parse_ctp.py}"

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) BASELINE="$2"; shift 2;;
    --jdbc-repo) JDBC_REPO="$2"; shift 2;;
    --ctp-home) CTP_HOME="$2"; shift 2;;
    --cubrid) CUBRID_DIR="$2"; shift 2;;
    --conf) CONF="$2"; shift 2;;
    --no-build) NO_BUILD=1; shift;;
    --no-cleanup) CLEANUP=0; shift;;
    --out) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$BASELINE" ] || { echo "ERROR: --baseline required (.json | result dir | test-jdbc.xml)" >&2; exit 2; }
[ -f "$PARSE" ] || { echo "ERROR: parse_ctp.py not found at $PARSE (set PARSE_CTP)" >&2; exit 2; }
[ -n "$CUBRID_DIR" ] || { echo "ERROR: CUBRID install dir unknown — set \$CUBRID or pass --cubrid" >&2; exit 2; }
CONF="${CONF:-$CTP_HOME/conf/jdbc.conf}"
mkdir -p "$OUT"

# --- self-cleanup: on exit, prune orphaned anonymous CUBRID test-DB volumes left behind
#     by recreated containers (dangling=true skips volumes attached to any running OR
#     stopped container; the 64-hex filter preserves named volumes like jenkins_jenkins-data).
#     Disable with --no-cleanup.
CLI="$(command -v docker || command -v podman || echo docker)"
cleanup_orphans() {
  [ "$CLEANUP" -eq 1 ] || return 0
  local vols
  vols="$("$CLI" volume ls -qf dangling=true 2>/dev/null | grep -E '^[0-9a-f]{64}$' || true)"
  [ -n "$vols" ] || return 0
  echo "cleanup: removing $(printf '%s\n' "$vols" | wc -l | tr -d ' ') orphaned anonymous volume(s)"
  printf '%s\n' "$vols" | xargs -r "$CLI" volume rm >/dev/null 2>&1 || true
}
trap cleanup_orphans EXIT

# --- 1. build the driver ---
if [ "$NO_BUILD" -eq 0 ]; then
  echo "===== build driver ($JDBC_REPO) ====="
  ( cd "$JDBC_REPO" && ./build.sh ) 2>&1 | tee "$OUT/build.log"
fi
JAR="$JDBC_REPO/cubrid_jdbc.jar"
[ -f "$JAR" ] || JAR="$(ls -t "$JDBC_REPO"/cubrid-jdbc-*.jar 2>/dev/null | grep -v -- '-sources\|-javadoc' | head -1 || true)"
[ -f "$JAR" ] || { echo "ERROR: built driver jar not found under $JDBC_REPO" >&2; exit 1; }
echo "driver jar: $JAR"

# --- 2. deploy jar into the CUBRID install ---
cp "$JAR" "$CUBRID_DIR/jdbc/cubrid_jdbc.jar"
echo "deployed → $CUBRID_DIR/jdbc/cubrid_jdbc.jar"

# --- 3. run CTP JDBC suite ---
echo "===== CTP run ====="
"$CTP_HOME/bin/ctp.sh" jdbc -c "$CONF" 2>&1 | tee "$OUT/ctp.log" || true

# --- 4. parse results ---
RES="$CTP_HOME/result/jdbc/current_runtime_logs"
python3 "$PARSE" parse "$RES" "$OUT/after.json"

# --- 5. resolve baseline → baseline.json ---
case "$BASELINE" in
  *.json) cp "$BASELINE" "$OUT/baseline.json";;
  *) python3 "$PARSE" parse "$BASELINE" "$OUT/baseline.json" >/dev/null;;
esac

# --- 6. diff ---
echo "===== diff (baseline → after) ====="
python3 "$PARSE" diff "$OUT/baseline.json" "$OUT/after.json" | tee "$OUT/diff.txt"
echo
echo "Done. baseline.json / after.json / diff.txt in $OUT — feed these to the report step (Step 4)."
