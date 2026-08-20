#!/usr/bin/env bash
# Dispatch CUBRID's "Submodule bump (receiver)" workflow to pin one submodule to a commit.
#   bump_submodule.sh <submodule> <sha|latest> [--reanchor] [--run]
#
# Everything is validated BEFORE anything is dispatched. Without --run it only prints the exact
# gh command it would execute (dry run): nothing is triggered, nothing changes.
set -uo pipefail

PARENT="CUBRID/cubrid"
WORKFLOW="submodule-bump-receiver.yml"
BRANCH="develop"

die() { echo "error: $*" >&2; exit 2; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"

SUB_IN=""; SHA_IN=""; REANCHOR=0; RUN=0
for a in "$@"; do
  case "$a" in
    --reanchor) REANCHOR=1;;
    --run) RUN=1;;
    -h|--help) echo "usage: bump_submodule.sh <cubrid-jdbc|cubrid-cci|cubridmanager|jdbc|cci|cms> <sha|latest> [--reanchor] [--run]"; exit 0;;
    -*) die "unknown option '$a'";;
    *) if [ -z "$SUB_IN" ]; then SUB_IN="$a"; elif [ -z "$SHA_IN" ]; then SHA_IN="$a"; else die "unexpected argument '$a'"; fi;;
  esac
done
[ -n "$SUB_IN" ] || die "no submodule given (cubrid-jdbc | cubrid-cci | cubridmanager)"
[ -n "$SHA_IN" ] || die "no SHA given (a commit SHA, or 'latest' for the submodule's develop head)"

# ---- guard 1: only the three submodules this workflow accepts ----
case "$(printf '%s' "$SUB_IN" | tr '[:upper:]' '[:lower:]')" in
  jdbc|cubrid-jdbc)                                  SUB_PATH="cubrid-jdbc";   SUB_REPO="cubrid/cubrid-jdbc";;
  cci|cubrid-cci)                                    SUB_PATH="cubrid-cci";    SUB_REPO="CUBRID/cubrid-cci";;
  cms|manager|cubridmanager|cubrid-manager-server|manager-server)
                                                     SUB_PATH="cubridmanager"; SUB_REPO="CUBRID/cubrid-manager-server";;
  *) die "'$SUB_IN' is not a bumpable submodule. Allowed: cubrid-jdbc (jdbc), cubrid-cci (cci), cubridmanager (cms). Nothing was dispatched.";;
esac

# ---- guard 2: resolve to a real, full 40-char lower-case SHA in that submodule ----
case "$(printf '%s' "$SHA_IN" | tr '[:upper:]' '[:lower:]')" in
  latest|head|develop)
    TARGET="$(gh api "repos/$SUB_REPO/commits/$BRANCH" --jq .sha 2>/dev/null)"
    [ -n "$TARGET" ] || die "cannot read $SUB_REPO $BRANCH head";;
  *)
    printf '%s' "$SHA_IN" | grep -qiE '^[0-9a-f]{7,40}$' || die "'$SHA_IN' is not a commit SHA (7-40 hex chars) or 'latest'"
    TARGET="$(gh api "repos/$SUB_REPO/commits/$SHA_IN" --jq .sha 2>/dev/null)"
    [ -n "$TARGET" ] || die "commit '$SHA_IN' not found in $SUB_REPO";;
esac
TARGET="$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')"
# gh prints the API error body on stdout when a commit is missing, so validate the shape, not just emptiness.
printf '%s' "$TARGET" | grep -qE '^[0-9a-f]{40}$' || die "commit '$SHA_IN' not found in $SUB_REPO"

# ---- guard 3: the commit must already be on the submodule's develop ----
ST_DEV="$(gh api "repos/$SUB_REPO/compare/$BRANCH...$TARGET" --jq .status 2>/dev/null)"
case "$ST_DEV" in
  identical|behind) ;;
  ahead)    die "commit is not merged into $SUB_REPO $BRANCH yet. Merge it first. Nothing was dispatched.";;
  diverged) die "commit is not on $SUB_REPO $BRANCH (diverged history). Nothing was dispatched.";;
  *)        die "cannot compare $TARGET against $SUB_REPO $BRANCH";;
esac

# ---- guard 4: direction vs what the parent currently pins ----
PINNED="$(gh api "repos/$PARENT/contents/$SUB_PATH?ref=$BRANCH" --jq .sha 2>/dev/null)"
[ -n "$PINNED" ] || die "cannot read the currently pinned SHA of $SUB_PATH in $PARENT"
MOVE="$(gh api "repos/$SUB_REPO/compare/$PINNED...$TARGET" --jq .status 2>/dev/null)"
AHEAD="$(gh api "repos/$SUB_REPO/compare/$PINNED...$TARGET" --jq .ahead_by 2>/dev/null)"
case "$MOVE" in
  ahead) ;;
  identical) die "$SUB_PATH already pins $TARGET. Nothing to do, nothing was dispatched.";;
  behind)    die "that commit is BEHIND the pinned one ($PINNED). The workflow refuses to move backward: revert in $SUB_REPO and pin the revert commit instead. Nothing was dispatched.";;
  diverged)
    [ "$REANCHOR" -eq 1 ] || die "history looks rewritten (pinned commit is not an ancestor). Re-run with --reanchor only if the submodule was force-pushed. Nothing was dispatched.";;
  *) die "cannot compare the pinned SHA against the target";;
esac

# ---- summary ----
cat <<EOF
submodule : $SUB_PATH  ($SUB_REPO)
pinned now: $PINNED
target    : $TARGET
move      : $MOVE${AHEAD:+ (+$AHEAD commit(s))}
reanchor  : $([ "$REANCHOR" -eq 1 ] && echo "true  (non-fast-forward re-anchor)" || echo "false")
compare   : https://github.com/$SUB_REPO/compare/${PINNED:0:7}...${TARGET:0:7}
EOF

CMD=(gh workflow run "$WORKFLOW" --repo "$PARENT" --ref "$BRANCH"
     -f "submodule_path=$SUB_PATH" -f "target_sha=$TARGET")
[ "$REANCHOR" -eq 1 ] && CMD+=(-f "reanchor=true")

echo
if [ "$RUN" -ne 1 ]; then
  echo "dry run: nothing dispatched. To actually run it:"
  printf '  '; printf '%s ' "${CMD[@]}"; echo
  exit 0
fi

echo "dispatching..."
"${CMD[@]}" || die "gh workflow run failed"
echo "· dispatched. Watch it:  gh run list --repo $PARENT --workflow $WORKFLOW --limit 3"
