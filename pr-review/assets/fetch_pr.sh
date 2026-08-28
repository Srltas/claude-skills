#!/usr/bin/env bash
# fetch_pr.sh - put someone else's pull request on this machine so it can be reviewed in depth.
#
#   fetch_pr.sh <PR-URL | OWNER/REPO N | N> [JIRA-KEY] [options]
#   fetch_pr.sh <PR-URL | OWNER/REPO N | N> --cleanup
#
# Options
#   --jira KEY     Jira issue key for this PR (also accepted as a bare positional, e.g. HHH-20650)
#   --repo O/R     force the repository, when the input is only a number
#   --repo-dir DIR force WHICH local clone to use, when several of them match (see 2 below)
#   --cleanup      remove the worktree and the refs this script created, then exit
#   --force        allow replacing a non-worktree directory sitting in the scratch slot
#   -h, --help     this text
#
# What it does
#   1. parses OWNER/REPO and the PR number - the number after /pull/, never "the last number in
#      the string", because .../pull/6055#discussion_r234 would otherwise yield the comment id
#   2. finds an existing clone of OWNER/REPO on this machine (any remote, git@ or https, with or
#      without .git, owner case-insensitive) - origin is often the reviewer's own fork, so every
#      remote is matched, not just origin. The same repository is often cloned several times; the
#      choice is ranked, never "whichever the filesystem yielded first": a CLEAN working tree
#      beats a dirty one, then origin beats another remote, then the shortest path. The chosen
#      clone, its working-tree state and every other clone that matched are all printed, so the
#      choice is visible and --repo-dir can overrule it
#   3. fetches refs/pull/<N>/head into refs/pr/<N> and expands it as a git WORKTREE under a
#      scratch directory, plus the base branch into refs/pr-base/<N> so the diff is computable
#   4. clones into a scratch cache (reused on later runs) when the repo is not on this machine
#   5. prints the review header: repo, PR, title, author, base/head/merge-base, worktree path,
#      and EVERY changed file with its +/- counts - the reviewer reads all of them, no sampling
#
# What it never does
#   never `gh pr checkout`, never `git checkout`/`switch` in the user's own working tree, never
#   touches their branches or refs/heads/*, never pushes, never posts anything anywhere.
#   Everything it creates is listed in the CLEANUP block and removed by --cleanup.
#
# Env
#   PR_REVIEW_SCRATCH       scratch root        (default ${XDG_CACHE_HOME:-~/.cache}/pr-review)
#   PR_REVIEW_SEARCH_ROOT   where clones live   (default ~/Devel)
#   PR_REVIEW_SEARCH_DEPTH  find maxdepth       (default 4)
#   PR_REVIEW_REPO_DIR      the clone to use    (same as --repo-dir; skips the search entirely)
#
# Exit codes: 0 ok, 2 usage/environment, 3 PR or repo not reachable, 4 git failure.

set -uo pipefail
export LC_COLLATE=C          # so [A-Z] in patterns means A-Z, not a locale's mixed-case order

SCRATCH_ROOT="${PR_REVIEW_SCRATCH:-${XDG_CACHE_HOME:-$HOME/.cache}/pr-review}"
SEARCH_ROOT="${PR_REVIEW_SEARCH_ROOT:-$HOME/Devel}"
SEARCH_DEPTH="${PR_REVIEW_SEARCH_DEPTH:-4}"
REPO_DIR_OVERRIDE="${PR_REVIEW_REPO_DIR:-}"
CACHE_DIR="$SCRATCH_ROOT/cache"
SELF="$0"
SELF_ABS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
TAB="$(printf '\t')"

die()  { printf 'error: %s\n' "$1" >&2; exit "${2:-2}"; }   # $2 = exit code, never part of the text
warn() { printf 'warning: %s\n' "$*" >&2; }
usage() { sed -n '2,42p' "$SELF" 2>/dev/null | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- argument parsing

CLEANUP=0; FORCE=0; JIRA=""; REPO=""; N=""; POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage; exit 0;;
    --cleanup)   CLEANUP=1;;
    --force)     FORCE=1;;
    --jira)      shift; JIRA="${1:-}"; [ -n "$JIRA" ] || die "--jira needs an issue key";;
    --jira=*)    JIRA="${1#--jira=}";;
    --repo)      shift; REPO="${1:-}"; [ -n "$REPO" ] || die "--repo needs OWNER/REPO";;
    --repo=*)    REPO="${1#--repo=}";;
    --repo-dir)  shift; REPO_DIR_OVERRIDE="${1:-}"
                 [ -n "$REPO_DIR_OVERRIDE" ] || die "--repo-dir needs a directory";;
    --repo-dir=*) REPO_DIR_OVERRIDE="${1#--repo-dir=}";;
    --)          shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done; break;;
    -*)          die "unknown option '$1' (see --help)";;
    *)           POS+=("$1");;
  esac
  shift
done

# Order matters: URL first (it also contains a slash), then OWNER/REPO (a slash rules out a Jira
# key), then a bare number, then a Jira key.
for a in ${POS+"${POS[@]}"}; do
  case "$a" in
    *github.com*/pull/*|*github.com*/pulls/*)
      # the number AFTER /pull/ - a review permalink ends in #discussion_r<id>, and taking the
      # last number in the string would silently review the wrong thing
      n="$(printf '%s' "$a" | sed -nE 's#^.*/pulls?/([0-9]+).*$#\1#p')"
      r="$(printf '%s' "$a" | sed -nE 's#^.*github\.com[:/]+([^/]+)/([^/]+)/pulls?/[0-9]+.*$#\1/\2#p')"
      [ -n "$n" ] || die "could not parse a PR number out of '$a'"
      N="$n"; [ -n "$REPO" ] || REPO="${r%.git}"
      ;;
    */*)
      r="${a%/}"; r="${r%.git}"
      case "$r" in
        # a clone or repo URL: collapsed to OWNER/REPO once the helpers below are defined
        *://*|*@*|*github.com*) REPO="$r";;
        */*/*) die "'$a' is not OWNER/REPO";;
        *)     REPO="$r";;
      esac
      ;;
    "#"[0-9]*|[0-9]*)
      b="${a#\#}"
      case "$b" in (*[!0-9]*) die "'$a' is not a PR number";; esac
      N="$b"
      ;;
    *)
      if printf '%s' "$a" | grep -qE '^[A-Z][A-Z0-9_]*-[0-9]+$'; then
        [ -n "$JIRA" ] || JIRA="$a"
      else
        die "cannot tell what '$a' is (expected a PR URL, OWNER/REPO, a number, or a JIRA key)"
      fi
      ;;
  esac
done

[ -n "$N" ] || { usage >&2; echo >&2; die "no PR number given"; }
command -v git >/dev/null 2>&1 || die "git not found"

# ---------------------------------------------------------------- helpers

# github.com:Owner/Repo.git, https://github.com/Owner/Repo, ssh://git@github.com/Owner/Repo/
# all collapse to Owner/Repo (case preserved; callers lowercase it for comparison).
normalize_remote() {
  printf '%s' "$1" \
    | sed -E 's#^[A-Za-z0-9+.-]+://##; s#^[^@/]+@##; s#^([^/:]+):#\1/#' \
    | sed -E 's#/+$##; s#\.git$##' \
    | awk -F/ 'NF>=2 {print $(NF-1) "/" $NF}'
}

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# the main (or bare) repository directory backing a worktree path
repo_dir_of_worktree() {
  local wt="$1" common
  # A real worktree root always carries its own .git. Without this test git would walk UP the
  # tree, and a junk directory sitting inside some enclosing repository would look like a
  # worktree of it - which is how unrelated data gets deleted.
  [ -e "$wt/.git" ] || return 1
  common="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || common="$(cd "$wt" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"
  [ -n "$common" ] || return 1
  case "$common" in
    /*) ;;
    *)  common="$(cd "$wt" 2>/dev/null && cd "$common" 2>/dev/null && pwd)" || return 1;;
  esac
  case "$common" in
    */.git) dirname "$common";;
    *)      printf '%s\n' "$common";;   # bare repository
  esac
}

# How much of the user's own work is sitting in a clone: "clean", "bare", or "dirty:<N>:<M>"
# (N changed tracked files, M untracked). Used both to rank candidates and to tell the reviewer
# that this run touched a repository they are working in.
worktree_state() {
  local d="$1" st all untracked
  [ "$(git -C "$d" rev-parse --is-bare-repository 2>/dev/null)" = "true" ] && { echo "bare"; return 0; }
  # one status call: "??" lines are the untracked ones, everything else is a real change
  st="$(git -C "$d" status --porcelain 2>/dev/null)" || { echo "unknown"; return 0; }
  all="$(printf '%s' "$st" | grep -c . | tr -d ' ')"
  [ "${all:-0}" -eq 0 ] && { echo "clean"; return 0; }
  untracked="$(printf '%s' "$st" | grep -c '^??' | tr -d ' ')"
  echo "dirty:$((all - untracked)):${untracked:-0}"
}

# worktree_state's string as one readable phrase
state_text() {
  local rest
  case "$1" in
    clean)   echo "clean";;
    bare)    echo "bare repository, no working tree";;
    dirty:*) rest="${1#dirty:}"; echo "${rest%%:*} changed, ${rest##*:} untracked";;
    *)       echo "unknown";;
  esac
}

# the remote of clone $1 that points at repository $2 (lowercased owner/repo); origin wins
remote_matching() {
  local d="$1" want="$2" rname url pick=""
  while IFS= read -r rname; do
    [ -n "$rname" ] || continue
    url="$(git -C "$d" remote get-url "$rname" 2>/dev/null)" || continue
    [ "$(lc "$(normalize_remote "$url")")" = "$want" ] || continue
    [ "$rname" = "origin" ] && { printf 'origin'; return 0; }
    [ -n "$pick" ] || pick="$rname"
  done < <(git -C "$d" remote 2>/dev/null)
  [ -n "$pick" ] || return 1
  printf '%s' "$pick"
}

# Sets FOUND_DIR / FOUND_REMOTE / FOUND_STATE to the best clone of $1 (lowercased owner/repo)
# under $SEARCH_ROOT, and FOUND_OTHERS[] / FOUND_OTHER_COUNT to the clones that also matched but
# were not chosen. Returns 1 when nothing matched. It sets globals instead of printing because
# the caller must be able to report the ones it did NOT pick.
#
# The same repository is often cloned several times (three copies of cubrid-testcases-private on
# the machine this was written on, all matching through 'upstream', all scoring the same), so
# ranking on the remote score alone left the choice to whatever order find(1) walked the disk -
# arbitrary, and silent about it. Ranked, in order:
#   1. a CLEAN working tree beats a dirty one    - do not park refs in a repo mid-edit if a quiet
#                                                  copy is available
#   2. the remote score below                    - origin beats another remote, a directory named
#                                                  after the repo beats one that is not, a real
#                                                  repository beats a linked worktree
#   3. the shortest path, then the name          - so two equal candidates still rank the same way
#                                                  on every run, on every machine
find_local_repo() {
  local want="$1" gitent dir rname url score best_remote best_score state clean
  local lines="" sorted cand_dir cand_remote cand_state i=0
  FOUND_DIR=""; FOUND_REMOTE=""; FOUND_STATE=""; FOUND_OTHERS=(); FOUND_OTHER_COUNT=0
  [ -d "$SEARCH_ROOT" ] || return 1
  while IFS= read -r gitent; do
    dir="$(dirname "$gitent")"
    case "$dir/" in "$SCRATCH_ROOT"/*) continue;; esac
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue
    best_remote=""; best_score=-1
    while IFS= read -r rname; do
      [ -n "$rname" ] || continue
      url="$(git -C "$dir" remote get-url "$rname" 2>/dev/null)" || continue
      [ "$(lc "$(normalize_remote "$url")")" = "$want" ] || continue
      score=0
      [ "$rname" = "origin" ] && score=$((score + 2))
      [ "$(lc "$(basename "$dir")")" = "${want##*/}" ] && score=$((score + 1))
      [ -d "$dir/.git" ] && score=$((score + 1))
      if [ "$score" -gt "$best_score" ]; then
        best_score="$score"
        best_remote="$rname"
      fi
    done < <(git -C "$dir" remote 2>/dev/null)
    [ -n "$best_remote" ] || continue
    state="$(worktree_state "$dir")"
    case "$state" in dirty:*) clean=1;; *) clean=0;; esac
    # sort key: clean first, then the remote score (inverted, so smaller is better), then the
    # shortest path, then the path itself
    lines="$lines$(printf '%d\t%d\t%04d\t%s\t%s\t%s' \
      "$clean" "$((9 - best_score))" "${#dir}" "$dir" "$best_remote" "$state")
"
  done < <(find "$SEARCH_ROOT" -maxdepth "$SEARCH_DEPTH" \
             \( -name node_modules -o -name .Trash -o -name Library \) -prune -o \
             -name .git -prune -print 2>/dev/null)
  [ -n "$lines" ] || return 1
  sorted="$(printf '%s' "$lines" | sort -t"$TAB" -k1,1n -k2,2n -k3,3n -k4,4)"
  while IFS="$TAB" read -r _ _ _ cand_dir cand_remote cand_state; do
    [ -n "$cand_dir" ] || continue
    if [ "$i" -eq 0 ]; then
      FOUND_DIR="$cand_dir"; FOUND_REMOTE="$cand_remote"; FOUND_STATE="$cand_state"
    else
      FOUND_OTHERS[$((i - 1))]="$(printf '%s\t%s\t%s' "$cand_dir" "$cand_remote" "$cand_state")"
      FOUND_OTHER_COUNT="$i"
    fi
    i=$((i + 1))
  done <<<"$sorted"
  [ -n "$FOUND_DIR" ]
}

FOUND_DIR=""; FOUND_REMOTE=""; FOUND_STATE=""; FOUND_OTHERS=(); FOUND_OTHER_COUNT=0

# the other clones that matched, one indented line each, through the printer passed as $1
print_other_candidates() {
  local emit="$1" entry rest o_dir o_remote o_state
  [ "$FOUND_OTHER_COUNT" -gt 0 ] || return 0
  "$emit" "$FOUND_OTHER_COUNT other local clone(s) matched and were NOT used:"
  for entry in ${FOUND_OTHERS+"${FOUND_OTHERS[@]}"}; do
    o_dir="${entry%%"$TAB"*}"; rest="${entry#*"$TAB"}"
    o_remote="${rest%%"$TAB"*}"; o_state="${rest##*"$TAB"}"
    "$emit" "  $o_dir  (remote '$o_remote', $(state_text "$o_state"))"
  done
  "$emit" "  to use one of them instead:  --repo-dir <path>   (or PR_REVIEW_REPO_DIR=<path>)"
}

# turn gh's stderr into one actionable sentence
diagnose_gh() {
  case "$1" in
    *"Could not resolve to a PullRequest"*|*"no pull requests found"*|*"Not Found"*)
      echo "PR #$N does not exist in ${REPO:-that repo} (wrong number, or wrong repository)";;
    *"Could not resolve to a Repository"*|*"HTTP 404"*)
      echo "cannot see ${REPO:-the repository}: it does not exist, is private, or your token has no access to it";;
    *"HTTP 401"*|*"authentication required"*|*"gh auth login"*|*"not logged into"*)
      echo "gh is not authenticated: run 'gh auth login'";;
    *SAML*|*SSO*)
      echo "this organization requires SSO authorization for your token: authorize it, then retry";;
    *"dial tcp"*|*"no such host"*|*"lookup "*|*"i/o timeout"*|*"connection refused"*|*"network is unreachable"*|*"TLS handshake"*)
      echo "no network: github.com is unreachable from here";;
    *) echo "gh could not read the PR";;
  esac
}

jira_url() {
  [ -n "${1:-}" ] || { echo ""; return 0; }
  case "${1%%-*}" in
    HHH|HSEARCH|HV|HCANN|HR|JPA)        echo "https://hibernate.atlassian.net/browse/$1";;
    CBRD|TOOLS|APIS|CUBRIDQA|CBRDTOOL)  echo "http://jira.cubrid.org/browse/$1";;
    *) echo "";;
  esac
}

# ---------------------------------------------------------------- repository resolution

# A repository given as a URL ("git@github.com:owner/repo.git") collapses to OWNER/REPO here,
# where normalize_remote finally exists.
case "$REPO" in
  *://*|*@*|*github.com*) REPO="$(normalize_remote "$REPO")";;
esac

# A bare number and no --repo: take the repository from the current directory, without network.
if [ -z "$REPO" ]; then
  url="$(git -C . remote get-url upstream 2>/dev/null || git -C . remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] && REPO="$(normalize_remote "$url")"
  if [ -z "$REPO" ] && command -v gh >/dev/null 2>&1; then
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
fi
REPO_NAME="${REPO##*/}"
WT=""
[ -n "$REPO_NAME" ] && WT="$SCRATCH_ROOT/$REPO_NAME-pr$N"

# ---------------------------------------------------------------- cleanup mode

if [ "$CLEANUP" -eq 1 ]; then
  cnote() { printf '%-17s  %s\n' "" "$1"; }   # a continuation line under the labels below
  # No repository known? If exactly one scratch worktree carries this PR number, that is the one.
  if [ -z "$WT" ] || [ ! -e "$WT" ]; then
    matches=()
    for d in "$SCRATCH_ROOT"/*-pr"$N"; do [ -e "$d" ] && matches+=("$d"); done
    if [ "${#matches[@]}" -eq 1 ]; then
      WT="${matches[0]}"
      b="$(basename "$WT")"; REPO_NAME="${b%-pr"$N"}"
    elif [ "${#matches[@]}" -gt 1 ]; then
      printf 'several scratch worktrees exist for PR #%s:\n' "$N" >&2
      printf '  %s\n' "${matches[@]}" >&2
      die "say which repository, e.g. --repo OWNER/REPO"
    fi
  fi

  # The worktree names its own repository, so that answer is exact; --repo-dir and the search are
  # only for the case where the worktree is already gone.
  RD=""
  if [ -n "$WT" ] && [ -e "$WT" ]; then
    RD="$(repo_dir_of_worktree "$WT" || true)"
  fi
  if [ -z "$RD" ] && [ -n "$REPO_DIR_OVERRIDE" ]; then
    RD="$(cd "$REPO_DIR_OVERRIDE" 2>/dev/null && pwd)" || RD=""
    [ -n "$RD" ] || die "--repo-dir: no such directory: $REPO_DIR_OVERRIDE"
    git -C "$RD" rev-parse --git-dir >/dev/null 2>&1 || die "--repo-dir: not a git repository: $RD"
  fi
  if [ -z "$RD" ] && [ -n "$REPO" ]; then
    find_local_repo "$(lc "$REPO")" && RD="$FOUND_DIR"
    if [ -z "$RD" ]; then
      d="$CACHE_DIR/${REPO%%/*}__${REPO##*/}.git"
      [ -d "$d" ] && RD="$d"
    fi
  fi

  if [ -n "$WT" ] && [ -e "$WT" ]; then
    if [ -n "$RD" ] && git -C "$RD" worktree remove --force "$WT" 2>/dev/null; then
      echo "removed worktree : $WT"
    else
      case "$WT" in
        "$SCRATCH_ROOT"/*-pr"$N")
          rm -rf "$WT" && echo "removed worktree : $WT (directory only; it was not registered)";;
        *)
          warn "refusing to delete '$WT': it is not inside $SCRATCH_ROOT";;
      esac
    fi
  else
    echo "worktree         : (nothing to remove)"
  fi

  if [ -n "$RD" ]; then
    git -C "$RD" worktree prune 2>/dev/null
    for ref in "refs/pr/$N" "refs/pr-base/$N"; do
      if git -C "$RD" show-ref --verify --quiet "$ref"; then
        if git -C "$RD" update-ref -d "$ref" 2>/dev/null; then
          echo "removed ref      : $ref  (in $RD)"
        else
          warn "could not delete $ref in $RD"
        fi
      fi
    done
    echo "repository       : $RD (branches, HEAD and working tree untouched)"
    echo "working tree     : $(state_text "$(worktree_state "$RD")")"
    print_other_candidates cnote
  else
    warn "could not locate the repository, so refs/pr/$N may still exist somewhere"
  fi
  echo "the cache clone under $CACHE_DIR is kept on purpose (next review of that repo is fast); delete it by hand to reclaim the disk"
  exit 0
fi

# ---------------------------------------------------------------- PR metadata (gh)

[ -n "$REPO" ] || die "cannot tell which repository: pass a PR URL, OWNER/REPO N, or --repo OWNER/REPO"
case "$REPO" in */*) ;; *) die "'$REPO' is not OWNER/REPO";; esac
REPO_NAME="${REPO##*/}"
WT="$SCRATCH_ROOT/$REPO_NAME-pr$N"

DEGRADED=0; GH_NO_REPO=0
TITLE=""; AUTHOR=""; BASE_REF=""; BASE_OID=""; HEAD_REF=""; HEAD_OID=""; STATE=""; DRAFT=""
GH_FILES=""; GH_ADD=""; GH_DEL=""; FORK_OWNER=""; BODY=""
PR_URL="https://github.com/$REPO/pull/$N"

if command -v gh >/dev/null 2>&1; then
  ERRF="$(mktemp -t fetchpr.XXXXXX)"
  META="$(gh pr view "$N" --repo "$REPO" \
    --json title,author,baseRefName,baseRefOid,headRefName,headRefOid,url,state,isDraft,changedFiles,additions,deletions,headRepositoryOwner,body \
    --jq '[.title, (.author.login // "(unknown)"), .baseRefName, .baseRefOid, .headRefName, .headRefOid,
           .url, .state, (.isDraft|tostring), (.changedFiles|tostring), (.additions|tostring),
           (.deletions|tostring), (.headRepositoryOwner.login // ""), (.body // "")] | @tsv' 2>"$ERRF")"
  RC=$?
  GH_ERR="$(cat "$ERRF" 2>/dev/null)"; rm -f "$ERRF"
  if [ "$RC" -ne 0 ] || [ -z "$META" ]; then
    DEGRADED=1
    GH_MSG="$(diagnose_gh "$GH_ERR")"
    GH_DETAIL="$(printf '%s' "$GH_ERR" | head -3 | tr '\n' ' ')"
    [ -n "$GH_DETAIL" ] && printf '  gh said: %s\n' "$GH_DETAIL" >&2
    case "$GH_ERR" in
      *"Could not resolve to a PullRequest"*)
        # gh reached GitHub and GitHub says there is no such PR: fetching cannot fix that
        die "$GH_MSG" 3;;
      *"Could not resolve to a Repository"*)
        # maybe only this token cannot see it - an existing local clone may still work
        GH_NO_REPO=1;;
    esac
    warn "$GH_MSG"
  else
    IFS="$TAB" read -r TITLE AUTHOR BASE_REF BASE_OID HEAD_REF HEAD_OID PR_URL STATE DRAFT \
                       GH_FILES GH_ADD GH_DEL FORK_OWNER BODY <<<"$META"
  fi
else
  DEGRADED=1
  warn "gh (GitHub CLI) not found: install it (brew install gh) and run 'gh auth login' to get title/author/base"
fi

# ---------------------------------------------------------------- find or make the repository

CLONED=0
REPO_DIR_STATE="unknown"
if [ -n "$REPO_DIR_OVERRIDE" ]; then
  # An explicit choice overrules the ranking: the reviewer saw the candidate list and picked one.
  REPO_DIR="$(cd "$REPO_DIR_OVERRIDE" 2>/dev/null && pwd)" || REPO_DIR=""
  [ -n "$REPO_DIR" ] || die "--repo-dir: no such directory: $REPO_DIR_OVERRIDE"
  git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 ||
    die "--repo-dir: not a git repository: $REPO_DIR"
  REMOTE="$(remote_matching "$REPO_DIR" "$(lc "$REPO")" || true)"
  if [ -z "$REMOTE" ]; then
    warn "$REPO_DIR has no remote pointing at $REPO; fetching PR #$N straight from github.com"
    REMOTE="https://github.com/$REPO.git"
  fi
  REPO_DIR_STATE="$(worktree_state "$REPO_DIR")"
  SOURCE="your own clone, named by --repo-dir - left untouched: no checkout, no branch switch, no push"
elif find_local_repo "$(lc "$REPO")"; then
  REPO_DIR="$FOUND_DIR"
  REMOTE="$FOUND_REMOTE"
  REPO_DIR_STATE="$FOUND_STATE"
  SOURCE="your own clone - left untouched: no checkout, no branch switch, no push"
  # Say it now as well as in the report: if a later step dies, the reviewer still knows which of
  # their repositories this run wrote its refs into.
  [ "$FOUND_OTHER_COUNT" -gt 0 ] &&
    warn "$((FOUND_OTHER_COUNT + 1)) local clones of $REPO matched; chose $REPO_DIR ($(state_text "$REPO_DIR_STATE")) - the others are listed under 'source repo' below"
else
  [ "$GH_NO_REPO" -eq 1 ] &&
    die "$REPO is not visible to your GitHub token and is not cloned under $SEARCH_ROOT - nothing to review" 3
  REPO_DIR="$CACHE_DIR/${REPO%%/*}__${REPO_NAME}.git"
  REMOTE="origin"
  mkdir -p "$CACHE_DIR" || die "cannot create $CACHE_DIR"
  if [ -d "$REPO_DIR" ] && git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    SOURCE="scratch cache clone (reused)"
  else
    rm -rf "$REPO_DIR"
    echo "no clone of $REPO under $SEARCH_ROOT - cloning it into the scratch cache, this can take a while..." >&2
    GIT_TERMINAL_PROMPT=0 git clone --bare "https://github.com/$REPO.git" "$REPO_DIR" 2>&1 \
      | sed 's/^/  /' >&2
    if ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
      rm -rf "$REPO_DIR"
      if ! { command -v gh >/dev/null 2>&1 && gh repo clone "$REPO" "$REPO_DIR" -- --bare >/dev/null 2>&1; }; then
        rm -rf "$REPO_DIR"
        die "could not clone $REPO - no network, no access to it, or it does not exist" 3
      fi
    fi
    CLONED=1
    SOURCE="scratch cache clone (new)"
  fi
  REPO_DIR_STATE="$(worktree_state "$REPO_DIR")"
fi

[ "$(git -C "$REPO_DIR" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] &&
  warn "$REPO_DIR is a SHALLOW clone: the merge-base may be missing and the diff too large. Run 'git -C $REPO_DIR fetch --unshallow' for an accurate review."

# ---------------------------------------------------------------- fetch the PR head and its base

# Fetch from the remote's URL rather than its name, and keep FETCH_HEAD unwritten where git
# supports it. Fetching by NAME would also move the user's refs/remotes/<remote>/* as a side
# effect - their "behind by N commits" would silently change - and this script touches nothing
# of theirs beyond the two refs it cleans up.
REMOTE_URL="$(git -C "$REPO_DIR" remote get-url "$REMOTE" 2>/dev/null)"
[ -n "$REMOTE_URL" ] || REMOTE_URL="$REMOTE"
FETCH_OPTS=(--quiet)
if { git fetch -h 2>&1 || true; } | grep -q -- 'write-fetch-head'; then
  FETCH_OPTS+=(--no-write-fetch-head)
fi
fetch_ref() { git -C "$REPO_DIR" fetch "${FETCH_OPTS[@]}" "$REMOTE_URL" "$@" 2>/dev/null; }

if ! fetch_ref "+refs/pull/$N/head:refs/pr/$N"; then
  if git -C "$REPO_DIR" show-ref --verify --quiet "refs/pr/$N"; then
    warn "could not fetch refs/pull/$N/head (offline?); reusing the refs/pr/$N already in $REPO_DIR"
  else
    die "could not fetch refs/pull/$N/head from remote '$REMOTE' of $REPO_DIR - PR #$N may not exist, or this is a network/access problem" 3
  fi
fi
HEAD_SHA="$(git -C "$REPO_DIR" rev-parse "refs/pr/$N^{commit}" 2>/dev/null)"
[ -n "$HEAD_SHA" ] || die "refs/pr/$N did not resolve to a commit" 4
if [ -n "$HEAD_OID" ] && [ "$HEAD_OID" != "$HEAD_SHA" ]; then
  warn "GitHub reports head $HEAD_OID but the fetched ref is $HEAD_SHA (force-push mid-run?); using the fetched one"
fi

# The base branch tip, kept in our own ref namespace so refs/heads/* is never written.
if [ -z "$BASE_REF" ]; then
  BASE_REF="$(git -C "$REPO_DIR" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)"
  BASE_REF="${BASE_REF#"$REMOTE"/}"
  [ -n "$BASE_REF" ] || BASE_REF="main"
  warn "base branch unknown (no PR metadata), assuming '$BASE_REF'"
fi
if fetch_ref "+refs/heads/$BASE_REF:refs/pr-base/$N"; then
  :
elif git -C "$REPO_DIR" show-ref --verify --quiet "refs/pr-base/$N"; then
  warn "could not refresh base branch '$BASE_REF'; using the copy fetched earlier"
else
  warn "base branch '$BASE_REF' could not be fetched (deleted after merge?)"
fi
# The exact commit GitHub diffs against, when the branch has moved on since.
if [ -n "$BASE_OID" ] && ! git -C "$REPO_DIR" cat-file -e "$BASE_OID^{commit}" 2>/dev/null; then
  fetch_ref "$BASE_OID" || true
fi

BASE_TIP=""
if [ -n "$BASE_OID" ] && git -C "$REPO_DIR" cat-file -e "$BASE_OID^{commit}" 2>/dev/null; then
  BASE_TIP="$BASE_OID"
elif git -C "$REPO_DIR" show-ref --verify --quiet "refs/pr-base/$N"; then
  BASE_TIP="$(git -C "$REPO_DIR" rev-parse "refs/pr-base/$N^{commit}" 2>/dev/null)"
fi
MERGE_BASE=""
[ -n "$BASE_TIP" ] && MERGE_BASE="$(git -C "$REPO_DIR" merge-base "$BASE_TIP" "$HEAD_SHA" 2>/dev/null)"

# ---------------------------------------------------------------- the worktree

mkdir -p "$SCRATCH_ROOT" || die "cannot create $SCRATCH_ROOT"
WT_NOTE="created"
if [ -e "$WT" ]; then
  OWNER_DIR="$(repo_dir_of_worktree "$WT" || true)"
  if [ -n "$OWNER_DIR" ] && [ "$(cd "$OWNER_DIR" 2>/dev/null && pwd)" = "$(cd "$REPO_DIR" 2>/dev/null && pwd)" ]; then
    if git -C "$WT" checkout --detach --force "$HEAD_SHA" >/dev/null 2>&1; then
      WT_NOTE="reused, moved to this PR's head"
    else
      git -C "$REPO_DIR" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
    fi
  elif [ -n "$OWNER_DIR" ]; then
    warn "$WT was a stale worktree of $OWNER_DIR (a different repository); removing it"
    git -C "$OWNER_DIR" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
    git -C "$OWNER_DIR" worktree prune >/dev/null 2>&1
  elif [ "$FORCE" -eq 1 ]; then
    warn "$WT is not a git worktree; removing it because --force was given"
    rm -rf "$WT"
  else
    die "$WT already exists and is not a git worktree. Move it aside, or rerun with --force."
  fi
fi
if [ ! -e "$WT" ]; then
  git -C "$REPO_DIR" worktree prune >/dev/null 2>&1
  echo "expanding the PR into a worktree (a large repository takes a few seconds)..." >&2
  WERR="$(mktemp -t fetchpr.XXXXXX)"
  if ! git -C "$REPO_DIR" worktree add --detach "$WT" "refs/pr/$N" >/dev/null 2>"$WERR"; then
    sed 's/^/  /' "$WERR" >&2; rm -f "$WERR"
    die "git worktree add failed for $WT" 4
  fi
  rm -f "$WERR"
  [ -d "$WT" ] || die "git worktree add produced no directory at $WT" 4
fi

# ---------------------------------------------------------------- the diff

FILES_TABLE=""; FILE_COUNT=0; ADD_TOTAL=0; DEL_TOTAL=0; DIFF_FROM=""
if [ -n "$MERGE_BASE" ]; then
  DIFF_FROM="$MERGE_BASE"
elif [ -n "$BASE_TIP" ]; then
  DIFF_FROM="$BASE_TIP"
  warn "no merge-base between the base and the PR head; diffing against the base tip directly"
fi
if [ -n "$DIFF_FROM" ]; then
  NUMSTAT="$(git -C "$REPO_DIR" diff --numstat -M "$DIFF_FROM" "$HEAD_SHA" 2>/dev/null)"
  if [ -n "$NUMSTAT" ]; then
    FILES_TABLE="$(printf '%s\n' "$NUMSTAT" | awk '
      { p=$3; for (i=4; i<=NF; i++) p = p " " $i
        a = ($1 == "-") ? "bin" : "+" $1
        d = ($2 == "-") ? "bin" : "-" $2
        printf "  %7s %7s  %s\n", a, d, p }')"
    FILE_COUNT="$(printf '%s\n' "$NUMSTAT" | grep -c . | tr -d ' ')"
    ADD_TOTAL="$(printf '%s\n' "$NUMSTAT" | awk '$1 != "-" {s += $1} END {print s + 0}')"
    DEL_TOTAL="$(printf '%s\n' "$NUMSTAT" | awk '$2 != "-" {s += $2} END {print s + 0}')"
  fi
fi

# ---------------------------------------------------------------- the report

if [ -z "$JIRA" ]; then
  JIRA="$(printf '%s %s %s\n' "$TITLE" "$HEAD_REF" "$BODY" \
          | grep -oE '\b[A-Z][A-Z0-9]{1,9}-[0-9]+\b' | head -1)"
fi
JURL="$(jira_url "${JIRA:-}")"

pad()  { printf '%-14s: %s\n' "$1" "$2"; }
cont() { printf '%-14s  %s\n' "" "$1"; }

echo "================================================================"
echo " PR REVIEW WORKTREE"
echo "================================================================"
pad "repo"          "$REPO"
pad "pr"            "#$N${STATE:+   [$STATE${DRAFT:+, draft=$DRAFT}]}"
pad "title"         "${TITLE:-(unknown - no PR metadata)}"
pad "author"        "${AUTHOR:-(unknown)}${FORK_OWNER:+   (head repo: $FORK_OWNER/$REPO_NAME)}"
pad "url"           "$PR_URL"
[ -n "$JIRA" ] && pad "jira" "$JIRA${JURL:+   $JURL}"
echo
pad "base branch"   "$BASE_REF"
pad "base sha"      "${BASE_TIP:-(unresolved)}"
pad "head ref"      "${HEAD_REF:-(unknown)}"
pad "head sha"      "$HEAD_SHA"
pad "merge-base"    "${MERGE_BASE:-(unresolved)}"
echo
pad "source repo"   "$REPO_DIR"
cont                "$SOURCE, via remote '$REMOTE'"
case "$REPO_DIR_STATE" in
  dirty:*)
    cont "working tree: UNCOMMITTED work of yours here ($(state_text "$REPO_DIR_STATE")). This run only ADDED refs/pr/$N, refs/pr-base/$N and the worktree below; your files, branches and HEAD were not touched.";;
  *)
    cont "working tree: $(state_text "$REPO_DIR_STATE")";;
esac
print_other_candidates cont
pad "worktree"      "$WT"
cont                "$WT_NOTE, detached at $HEAD_SHA"
echo
pad "files changed" "$FILE_COUNT   (+$ADD_TOTAL / -$DEL_TOTAL)"
if [ -n "$GH_FILES" ] && [ "$GH_FILES" != "$FILE_COUNT" ]; then
  cont "GitHub counts $GH_FILES files (+$GH_ADD / -$GH_DEL); the local numbers are the diff you will actually read"
fi

echo
echo "CHANGED FILES  (read every one of them, in full - no sampling)"
if [ -n "$FILES_TABLE" ]; then
  printf '%s\n' "$FILES_TABLE"
else
  echo "  (not computed) - the base or the merge-base is missing, so there is no file list."
  echo "  Look by hand:  git -C $WT log --oneline -20"
fi

echo
echo "READ IT HERE"
echo "  cd $WT"
echo "  git -C $WT diff ${DIFF_FROM:-<base>} $HEAD_SHA -- <file>"
echo "  git -C $WT log --oneline ${DIFF_FROM:+$DIFF_FROM..}$HEAD_SHA"
echo
echo "CLEANUP  (removes the worktree and the refs this created; nothing else is touched)"
echo "  $SELF_ABS $REPO $N --cleanup${REPO_DIR_OVERRIDE:+ --repo-dir $REPO_DIR}"
echo "  # or by hand:"
echo "  git -C $REPO_DIR worktree remove --force $WT"
echo "  git -C $REPO_DIR update-ref -d refs/pr/$N"
echo "  git -C $REPO_DIR update-ref -d refs/pr-base/$N"
[ "$CLONED" -eq 1 ] && echo "  # the cache clone stays for next time: rm -rf $REPO_DIR to reclaim the disk"
if [ "$DEGRADED" -eq 1 ]; then
  echo
  echo "NOTE: this ran without PR metadata (gh unavailable): title, author and base may be wrong or missing."
fi
exit 0
