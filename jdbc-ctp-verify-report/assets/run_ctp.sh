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
PARSE="${PARSE_CTP:-$(cd "$(dirname "$0")" && pwd)/parse_ctp.py}"

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

# The CTP run overwrites $CTP_HOME/result, so a baseline pointing there would be re-parsed from
# post-run XML and every diff would come out +0/-0. Resolve it first, and refuse that path.
RES="$CTP_HOME/result/jdbc/current_runtime_logs"
case "$(cd "$(dirname "$BASELINE")" 2>/dev/null && pwd || echo "$BASELINE")" in
  "$CTP_HOME/result"*) echo "ERROR: --baseline points inside $CTP_HOME/result, which this run overwrites." >&2
                       echo "       Use a saved baseline.json (or a copy taken before the run)." >&2; exit 2;;
esac
case "$BASELINE" in
  *.json) cp "$BASELINE" "$OUT/baseline.json";;
  *) python3 "$PARSE" parse "$BASELINE" "$OUT/baseline.json" >/dev/null;;
esac
echo "baseline: $BASELINE -> $OUT/baseline.json"

# --- self-cleanup: on exit, prune anonymous volumes THIS RUN left behind.
#     Scoped by a before/after snapshot: a dangling anonymous volume is removed only if it did
#     not exist when the script started. Without that snapshot the dangling+64-hex filter matches
#     every project's orphaned volume on the machine, not just CUBRID test DBs.
#     Disable with --no-cleanup.
CLI="$(command -v docker || command -v podman || echo docker)"
VOLS_BEFORE="$("$CLI" volume ls -q 2>/dev/null | sort || true)"
cleanup_orphans() {
  [ "$CLEANUP" -eq 1 ] || return 0
  local vols
  local dangling
  dangling="$("$CLI" volume ls -qf dangling=true 2>/dev/null | grep -E '^[0-9a-f]{64}$' | sort || true)"
  [ -n "$dangling" ] || return 0
  # only the ones that appeared during this run
  vols="$(comm -13 <(printf '%s\n' "$VOLS_BEFORE") <(printf '%s\n' "$dangling") || true)"
  [ -n "$vols" ] || { echo "cleanup: no volume created by this run is dangling; nothing removed"; return 0; }
  echo "cleanup: removing $(printf '%s\n' "$vols" | wc -l | tr -d ' ') anonymous volume(s) created by this run"
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

# --- 4. parse results (baseline was resolved before the run) ---
python3 "$PARSE" parse "$RES" "$OUT/after.json"
python3 - "$OUT/after.json" <<'EOF' || exit 2
import json,sys
d=json.load(open(sys.argv[1]))
if not d.get("total"):
    print("ERROR: CTP produced no parsed cases (total=0). Not writing a report from an empty run;",
          "see ctp.log.", file=sys.stderr); sys.exit(2)
EOF

# --- 6. diff ---
echo "===== diff (baseline → after) ====="
python3 "$PARSE" diff "$OUT/baseline.json" "$OUT/after.json" | tee "$OUT/diff.txt"
echo
echo "Done. baseline.json / after.json / diff.txt in $OUT — feed these to the report step (Step 4)."
