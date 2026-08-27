#!/usr/bin/env bash
# Everything a self-review needs about the CURRENT, possibly unfinished work, in one call.
#   review_context.sh [base-ref] [--residual <regex>] [--sample-lines N]
#
# This runs mid-work, so uncommitted and untracked changes count as part of the work
# and are reported separately from what is already committed.
#
# It GATHERS. It does not judge, does not edit, does not post. Every number below is
# raw material for the review; the reviewer decides what any of it means.
set -uo pipefail

usage() {
  cat <<'EOF'
usage: review_context.sh [base-ref] [--residual <regex>] [--sample-lines N]

  base-ref         compare against this ref. Default: the remote's own default branch
                   (refs/remotes/*/HEAD), then main / develop / master.
  --residual RE    count this extended regex as THE leftover pattern, instead of
                   inferring candidates from the lines the diff deleted.
  --sample-lines N how many lines of the convention sample file to print (default 35).
EOF
}

BASE=""
RESIDUAL=""
SAMPLE_LINES=35
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --residual) [ $# -ge 2 ] || { echo "error: --residual needs a regex" >&2; exit 2; }; RESIDUAL="$2"; shift 2 ;;
    --residual=*) RESIDUAL="${1#*=}"; shift ;;
    --sample-lines) [ $# -ge 2 ] || { echo "error: --sample-lines needs a number" >&2; exit 2; }; SAMPLE_LINES="$2"; shift 2 ;;
    --sample-lines=*) SAMPLE_LINES="${1#*=}"; shift ;;
    --*) echo "error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *) if [ -z "$BASE" ]; then BASE="$1"; shift; else echo "error: too many arguments" >&2; exit 2; fi ;;
  esac
done
case "$SAMPLE_LINES" in (''|*[!0-9]*) echo "error: --sample-lines must be a number" >&2; exit 2 ;; esac

export LC_ALL=C   # so sort, join and grep agree on byte order
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repository" >&2; exit 2; }
GIT() { git -c core.quotepath=false "$@"; }

# caps, so the output stays readable. Nothing is dropped silently: every cap prints what it omitted.
MAX_COMMITS=30
MAX_FILES=40
MAX_DIRS=12
MAX_SIBLINGS=12
MAX_TOKENS=8
MAX_DETAIL=5          # residual patterns reported with per-file line numbers
MAX_LINENOS=8
MAX_SCAN=400          # files scanned when counting a residual pattern
MAX_INDENT_ROWS=15
MAX_INDENT_WIDTHS=6   # minority indent widths reported per file
MAX_SUBDIRS=12        # immediate subdirectories listed per changed directory

TMP="$(mktemp -d "${TMPDIR:-/tmp}/review_context.XXXXXX")" || { echo "error: cannot create temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---------------------------------------------------------------- 1. where you are
BR="$(GIT symbolic-ref --short -q HEAD 2>/dev/null)"
[ -n "$BR" ] || BR="$(GIT rev-parse --short HEAD 2>/dev/null)"
[ -n "$BR" ] || BR="(detached or unborn)"
HAVE_HEAD=0
GIT rev-parse --verify -q HEAD >/dev/null 2>&1 && HAVE_HEAD=1

if [ -n "$BASE" ]; then
  GIT rev-parse --verify -q "$BASE" >/dev/null 2>&1 || { echo "error: base '$BASE' does not exist here" >&2; exit 2; }
else
  for remote in upstream origin; do
    d="$(GIT symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
    if [ -n "$d" ] && GIT rev-parse --verify -q "$d" >/dev/null 2>&1; then BASE="$d"; break; fi
  done
  if [ -z "$BASE" ]; then
    for r in upstream/main origin/main main upstream/develop origin/develop develop \
             upstream/master origin/master master; do
      GIT rev-parse --verify -q "$r" >/dev/null 2>&1 && { BASE="$r"; break; }
    done
  fi
fi

MB=""
NOTE_BASE=""
if [ "$HAVE_HEAD" = 0 ]; then
  NOTE_BASE="no commit on this branch yet (unborn HEAD): everything below is uncommitted work."
elif [ -z "$BASE" ]; then
  NOTE_BASE="no base branch found. Committed work cannot be separated from the base; pass a base ref explicitly."
else
  MB="$(GIT merge-base "$BASE" HEAD 2>/dev/null || true)"
  if [ -z "$MB" ]; then
    NOTE_BASE="'$BASE' and HEAD have no common ancestor. Committed work is not comparable; pass a different base."
  elif [ "$MB" = "$(GIT rev-parse HEAD)" ]; then
    NOTE_BASE="base and HEAD are the same commit: nothing is committed on top of the base yet, so only uncommitted work shows up."
  fi
fi

# the branch name first. Commit subjects are a fallback, but only subjects of THIS
# branch's own commits: base history would hand back somebody else's key.
KEY="$(printf '%s' "$BR" | grep -oE '[A-Za-z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')"
KEY_SRC="branch name"
if [ -z "$KEY" ] && [ -n "$MB" ] && [ "$MB" != "$(GIT rev-parse HEAD)" ]; then
  KEY="$(GIT log "$MB..HEAD" --format=%s 2>/dev/null | grep -oE '\[?[A-Za-z]+-[0-9]+\]?' | tr -d '[]' | head -1 | tr '[:lower:]' '[:upper:]')"
  KEY_SRC="this branch's commit subjects"
fi

echo "=== 1. where you are ==============================================="
echo "repo    : $(GIT remote get-url origin 2>/dev/null | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##' || echo '(no origin)')"
echo "branch  : $BR"
echo "base    : ${BASE:-(none resolved)}${MB:+  (merge-base $(GIT rev-parse --short "$MB"))}"
echo "issue   : ${KEY:-(none found)}${KEY:+  [from $KEY_SRC]}"
[ -n "$NOTE_BASE" ] && echo "note    : $NOTE_BASE"
echo
echo "The issue key is a lead, not a contract. Fetch the issue itself and quote its"
echo "Acceptance Criteria / Specification Changes verbatim before reading any diff."

# ---------------------------------------------------------------- 2. state of the work
: > "$TMP/committed.txt"; : > "$TMP/staged.txt"; : > "$TMP/unstaged.txt"; : > "$TMP/untracked.txt"
: > "$TMP/work.tsv"

if [ -n "$MB" ]; then
  GIT diff --numstat --no-renames "$MB..HEAD" 2>/dev/null | awk -F'\t' 'NF>=3{print $3}' > "$TMP/committed.txt"
  GIT diff --numstat --no-renames "$MB" 2>/dev/null > "$TMP/work.tsv"
else
  GIT diff --numstat --no-renames HEAD 2>/dev/null > "$TMP/work.tsv"
fi
GIT diff --numstat --no-renames --cached 2>/dev/null | awk -F'\t' 'NF>=3{print $3}' > "$TMP/staged.txt"
GIT diff --numstat --no-renames         2>/dev/null | awk -F'\t' 'NF>=3{print $3}' > "$TMP/unstaged.txt"
GIT ls-files --others --exclude-standard 2>/dev/null > "$TMP/untracked.txt"

n_committed_files=$(sort -u "$TMP/committed.txt" | grep -c . || true)
n_staged=$(sort -u "$TMP/staged.txt" | grep -c . || true)
n_unstaged=$(sort -u "$TMP/unstaged.txt" | grep -c . || true)
n_untracked=$(grep -c . "$TMP/untracked.txt" || true)
n_commits=0
[ -n "$MB" ] && n_commits="$(GIT rev-list --count "$MB..HEAD" 2>/dev/null || echo 0)"

echo
echo "=== 2. state of the work =========================================="
echo "committed on this branch : $n_commits commit(s), $n_committed_files file(s)"
echo "staged, not committed    : $n_staged file(s)"
echo "unstaged in working tree : $n_unstaged file(s)"
echo "untracked (new files)    : $n_untracked file(s)"

if [ "$n_commits" -gt 0 ]; then
  echo
  echo "commits (newest first):"
  GIT log "$MB..HEAD" --format='  %h %s' 2>/dev/null | head -"$MAX_COMMITS"
  if [ "$n_commits" -gt "$MAX_COMMITS" ]; then
    echo "  ... $((n_commits - MAX_COMMITS)) older commit(s) omitted"
  fi
fi

if [ "$n_commits" = 0 ] && [ "$n_staged" = 0 ] && [ "$n_unstaged" = 0 ] && [ "$n_untracked" = 0 ]; then
  echo
  echo "no changes at all against ${BASE:-the base}: nothing to review here."
  echo "check you are on the right branch, or pass a different base ref."
  exit 0
fi

# ---------------------------------------------------------------- 3. changed files
in_set() { grep -Fxq -- "$1" "$2" 2>/dev/null; }

: > "$TMP/files.txt"
awk -F'\t' 'NF>=3{print $3}' "$TMP/work.tsv" >> "$TMP/files.txt"
cat "$TMP/untracked.txt" >> "$TMP/files.txt"
sort -u -o "$TMP/files.txt" "$TMP/files.txt"
n_files=$(grep -c . "$TMP/files.txt" || true)

: > "$TMP/table.txt"
tot_add=0; tot_del=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  add=""; del=""
  line="$(awk -F'\t' -v p="$f" 'NF>=3 && $3==p {print $1"\t"$2; exit}' "$TMP/work.tsv")"
  if [ -n "$line" ]; then
    add="${line%%	*}"; del="${line##*	}"
  elif in_set "$f" "$TMP/untracked.txt"; then
    if [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null; then
      add="$(wc -l < "$f" 2>/dev/null | tr -d ' ')"; del=0
    else
      add="-"; del="-"
    fi
  fi
  [ -n "$add" ] || { add="?"; del="?"; }
  case "$add" in (''|*[!0-9]*) : ;; (*) tot_add=$((tot_add + add)) ;; esac
  case "$del" in (''|*[!0-9]*) : ;; (*) tot_del=$((tot_del + del)) ;; esac
  st=""
  in_set "$f" "$TMP/committed.txt" && st="${st}C" || st="${st}-"
  in_set "$f" "$TMP/staged.txt"    && st="${st}S" || st="${st}-"
  in_set "$f" "$TMP/unstaged.txt"  && st="${st}U" || st="${st}-"
  in_set "$f" "$TMP/untracked.txt" && st="${st}N" || st="${st}-"
  printf '  %s  %6s %6s  %s\n' "$st" "+$add" "-$del" "$f" >> "$TMP/table.txt"
done < "$TMP/files.txt"

echo
echo "=== 3. changed files =============================================="
echo "  $n_files file(s), +$tot_add/-$tot_del"
echo "  state: C=committed on branch  S=staged  U=unstaged  N=untracked/new"
head -"$MAX_FILES" "$TMP/table.txt"
if [ "$n_files" -gt "$MAX_FILES" ]; then
  echo "  ... $((n_files - MAX_FILES)) more file(s), names only (counts: git diff --stat):"
  tail -n +$((MAX_FILES + 1)) "$TMP/table.txt" \
    | sed -E 's/^[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/      /'
fi

# ---------------------------------------------------------------- build the full diff once
: > "$TMP/full.diff"
if [ -n "$MB" ]; then
  GIT diff --no-renames -U0 "$MB" >> "$TMP/full.diff" 2>/dev/null
elif [ "$HAVE_HEAD" = 1 ]; then
  GIT diff --no-renames -U0 HEAD >> "$TMP/full.diff" 2>/dev/null
fi
grep '^-' "$TMP/full.diff" 2>/dev/null | grep -v '^---' | sed 's/^-//' > "$TMP/minus.txt"
grep '^+' "$TMP/full.diff" 2>/dev/null | grep -v '^+++' | sed 's/^+//' > "$TMP/plus.txt"
# untracked files are pure addition: their whole content belongs on the plus side
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null && cat "$f" >> "$TMP/plus.txt"
done < "$TMP/untracked.txt"

n_minus=$(wc -l < "$TMP/minus.txt" | tr -d ' ')
n_plus=$(wc -l < "$TMP/plus.txt" | tr -d ' ')

# ---------------------------------------------------------------- 4a. unchanged siblings
awk '{ n=split($0,a,"/"); if (n>1) print substr($0, 1, length($0)-length(a[n])-1); else print "." }' \
  "$TMP/files.txt" | sort -u > "$TMP/dirs.txt"
n_dirs=$(grep -c . "$TMP/dirs.txt" || true)

echo
echo "=== 4a. completeness: siblings NOT touched ========================"
echo "Same directory, same kind of file, left alone. Each is a candidate for"
echo "'the contract covers this too' or 'this one keeps the old shape'."
echo "The immediate subdirectories follow the files: an untouched sibling is not always"
echo "a single file, and a subtree marked [untouched] is the same candidate at scale."
shown=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if [ "$shown" -ge "$MAX_DIRS" ]; then break; fi
  if [ "$d" = "." ]; then
    GIT ls-files --cached -- . 2>/dev/null | awk '{ if (index($0,"/")==0) print }' > "$TMP/all_in_dir.txt"
  else
    GIT ls-files --cached -- "$d/" 2>/dev/null | awk -v p="$d/" '{ r=substr($0, length(p)+1); if (index(r,"/")==0) print }' > "$TMP/all_in_dir.txt"
  fi
  # changed here, untracked ones included, so the count is of the real work
  awk -v p="$d" '{ n=split($0,a,"/"); dir=(n>1)? substr($0,1,length($0)-length(a[n])-1) : "."; if (dir==p) print }' \
    "$TMP/files.txt" > "$TMP/changed_in_dir.txt"
  grep -Fxv -f "$TMP/files.txt" "$TMP/all_in_dir.txt" 2>/dev/null | sort -u > "$TMP/sib_in_dir.txt"
  c_ch=$(grep -c . "$TMP/changed_in_dir.txt" || true)
  c_sib=$(grep -c . "$TMP/sib_in_dir.txt" || true)
  echo
  echo "  $d/   [$c_ch changed, $c_sib untouched]"
  if [ "$c_sib" = 0 ]; then
    echo "    (none: every tracked file in this directory is part of the change)"
  else
    # same-extension siblings first: those are the ones the same contract usually covers
    sed -n 's/.*\.\([A-Za-z0-9_]\{1,\}\)$/\1/p' "$TMP/changed_in_dir.txt" | sort -u > "$TMP/exts.txt"
    if [ -s "$TMP/exts.txt" ]; then
      EXTRE="\.($(paste -sd'|' - < "$TMP/exts.txt"))\$"
      grep -E "$EXTRE" "$TMP/sib_in_dir.txt" > "$TMP/sib_same.txt" 2>/dev/null
      grep -vE "$EXTRE" "$TMP/sib_in_dir.txt" > "$TMP/sib_other.txt" 2>/dev/null
    else
      cp "$TMP/sib_in_dir.txt" "$TMP/sib_same.txt"; : > "$TMP/sib_other.txt"
    fi
    c_same=$(grep -c . "$TMP/sib_same.txt" || true)
    c_other=$(grep -c . "$TMP/sib_other.txt" || true)
    awk -v p="$d/" '{ if (substr($0,1,length(p))==p) print "    " substr($0,length(p)+1); else print "    " $0 }' \
      "$TMP/sib_same.txt" > "$TMP/sib_same_r.txt"
    head -"$MAX_SIBLINGS" "$TMP/sib_same_r.txt"
    if [ "$c_same" -gt "$MAX_SIBLINGS" ]; then
      echo "    ... $((c_same - MAX_SIBLINGS)) more untouched sibling(s) of the same type:"
      tail -n +$((MAX_SIBLINGS + 1)) "$TMP/sib_same_r.txt" | sed 's/^    /      /'
    fi
    [ "$c_other" -gt 0 ] && echo "    (+ $c_other untouched file(s) of other types in this directory)"
  fi

  # a sibling that was not touched can be a whole subdirectory, not just a file, so the
  # immediate subdirectories are listed too, with how many files each holds (tracked +
  # untracked, recursive) and whether this change reaches into it at all.
  if [ "$d" = "." ]; then
    P=""
    GIT ls-files --cached -- . 2>/dev/null > "$TMP/paths_in_dir.txt"
  else
    P="$d/"
    GIT ls-files --cached -- "$d/" 2>/dev/null > "$TMP/paths_in_dir.txt"
  fi
  awk -v p="$P" 'p=="" || substr($0,1,length(p))==p' "$TMP/untracked.txt" >> "$TMP/paths_in_dir.txt"
  sort -u -o "$TMP/paths_in_dir.txt" "$TMP/paths_in_dir.txt"
  SUB_AWK='{ r = substr($0, length(p)+1); i = index(r, "/"); if (i > 1) print substr(r, 1, i-1) }'
  awk -v p="$P" "$SUB_AWK" "$TMP/paths_in_dir.txt" | sort | uniq -c \
    | awk '{ c=$1; $1=""; sub(/^ +/,""); printf "%s\t%s\n", c, $0 }' > "$TMP/subdirs.txt"
  awk -v p="$P" "$SUB_AWK" "$TMP/files.txt" | sort | uniq -c \
    | awk '{ c=$1; $1=""; sub(/^ +/,""); printf "%s\t%s\n", c, $0 }' > "$TMP/subdirs_touched.txt"
  c_sub=$(grep -c . "$TMP/subdirs.txt" || true)
  if [ "$c_sub" = 0 ]; then
    echo "    subdirectories: (none)"
  else
    echo "    subdirectories ($c_sub, immediate; counts are files below them):"
    si=0
    while IFS="$(printf '\t')" read -r cnum sname; do
      [ -n "$sname" ] || continue
      si=$((si + 1)); [ "$si" -gt "$MAX_SUBDIRS" ] && continue
      tch="$(awk -F'\t' -v s="$sname" '$2==s {print $1; exit}' "$TMP/subdirs_touched.txt")"
      if [ -n "$tch" ]; then mark="[$tch changed below]"; else mark="[untouched]"; fi
      printf '      %-40s %5s file(s)  %s\n' "$sname/" "$cnum" "$mark"
    done < "$TMP/subdirs.txt"
    if [ "$c_sub" -gt "$MAX_SUBDIRS" ]; then
      echo "      ... $((c_sub - MAX_SUBDIRS)) more subdirectory(ies), names only:"
      awk -F'\t' -v n="$MAX_SUBDIRS" 'NR > n { print "        " $2 "/" }' "$TMP/subdirs.txt"
    fi
  fi
  shown=$((shown + 1))
done < "$TMP/dirs.txt"
if [ "$n_dirs" -gt "$MAX_DIRS" ]; then
  echo
  echo "  ... $((n_dirs - MAX_DIRS)) more changed directory(ies), not expanded, names only:"
  tail -n +$((MAX_DIRS + 1)) "$TMP/dirs.txt" | sed 's|^|    |; s|$|/|'
fi

# ---------------------------------------------------------------- 4b. residual patterns
# regex that matches a call-like token, or an annotation, without matching longer identifiers
mk_regex() {
  case "$1" in
    @*) printf '%s([^A-Za-z0-9_]|$)' "$1" ;;
    *)  printf '(^|[^A-Za-z0-9_])%s[[:space:]]*\\(' "$1" ;;
  esac
}

# occurrences (not lines) of an ERE across a newline-separated file list, capped.
# one grep run over the whole list: per-file grep is minutes slower on a big tree.
count_in_list() {
  if [ ! -s "$2" ]; then printf '0'; return; fi
  head -"$MAX_SCAN" "$2" | tr '\n' '\0' \
    | xargs -0 grep -hoIE -e "$1" -- 2>/dev/null | grep -c . || true
}

# file:line hits of an ERE across a file list, grouped per file, capped both ways.
# past the cap the line numbers are dropped but the NAMES never are: every remaining
# file is still printed, so a reader can open it, and no hit is lost to a bare count.
hits_in_list() {
  [ -s "$2" ] || return 0
  head -"$MAX_SCAN" "$2" | tr '\n' '\0' \
    | xargs -0 grep -nHIE -e "$1" -- 2>/dev/null \
    | awk -F: -v maxl="$MAX_LINENOS" -v maxf=25 '
        { f=$1; l=$2
          if (!(f in seen)) { seen[f]=1; order[++k]=f }
          cnt[f]++
          if (n[f] < maxl) { lines[f] = lines[f] (n[f] ? "," : "") l; n[f]++ }
        }
        END {
          for (i = 1; i <= k && i <= maxf; i++) {
            f = order[i]
            printf "      %s  (%d line(s)): %s%s\n", f, cnt[f], lines[f], (cnt[f] > maxl ? ",..." : "")
          }
          if (k > maxf) {
            printf "      ... %d more file(s) carry it, names only (no line numbers):\n", k - maxf
            for (i = maxf + 1; i <= k; i++) printf "        %s  (%d line(s))\n", order[i], cnt[order[i]]
          }
          if (k == 0) print "NONE"
        }'
}

# tokens of a side of the diff, as "token<TAB>count", sorted by token
tok_counts() {
  { grep -oaE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$1" 2>/dev/null | tr -d ' \t' | sed 's/(//'
    grep -oaE '@[A-Za-z][A-Za-z0-9_]*' "$1" 2>/dev/null
  } | grep -vxE '(if|for|foreach|while|switch|catch|return|new|do|else|try|synchronized|instanceof|super|this|sizeof|function|def)' \
    | sort | uniq -c | awk '{print $2"\t"$1}' | sort -k1,1
}

# all siblings of all changed dirs, for the "still there next door" count
: > "$TMP/all_siblings.txt"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if [ "$d" = "." ]; then
    GIT ls-files --cached -- . 2>/dev/null | awk '{ if (index($0,"/")==0) print }' >> "$TMP/all_siblings.txt"
  else
    GIT ls-files --cached -- "$d/" 2>/dev/null | awk -v p="$d/" '{ r=substr($0, length(p)+1); if (index(r,"/")==0) print }' >> "$TMP/all_siblings.txt"
  fi
done < "$TMP/dirs.txt"
sort -u "$TMP/all_siblings.txt" | grep -Fxv -f "$TMP/files.txt" > "$TMP/siblings.txt" 2>/dev/null
n_sib_total=$(grep -c . "$TMP/siblings.txt" || true)

# only the changed files that still exist (deleted ones cannot hold leftovers)
: > "$TMP/live_files.txt"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && printf '%s\n' "$f" >> "$TMP/live_files.txt"
done < "$TMP/files.txt"

echo
echo "=== 4b. completeness: what the change removes, that is still there ="
: > "$TMP/detail.txt"

if [ -n "$RESIDUAL" ]; then
  echo "pattern (given): $RESIDUAL"
  rc=$(count_in_list "$RESIDUAL" "$TMP/live_files.txt")
  rs=$(count_in_list "$RESIDUAL" "$TMP/siblings.txt")
  echo "  remaining in the changed files : $rc"
  echo "  remaining in untouched siblings: $rs  (over $n_sib_total sibling file(s); at most $MAX_SCAN are scanned)"
  printf '%s\n' "$RESIDUAL" > "$TMP/detail.txt"
elif [ "$n_minus" = 0 ]; then
  echo "the diff deletes no lines ($n_plus added, 0 deleted), so there is no"
  echo "old pattern to infer. Pass --residual '<regex>' if you know what this replaces."
else
  tok_counts "$TMP/minus.txt" > "$TMP/d.tsv"
  tok_counts "$TMP/plus.txt"  > "$TMP/a.tsv"
  join -t "$(printf '\t')" -a 1 -e 0 -o 0,1.2,2.2 "$TMP/d.tsv" "$TMP/a.tsv" 2>/dev/null > "$TMP/joined.tsv"
  # a token removed at least twice and not put back is the strong signal. On a small
  # change nothing clears that bar, so fall back to removed-once rather than print nothing.
  for min_del in 2 1; do
    awk -F'\t' -v m="$min_del" '$2>=m && $2>$3 { printf "%d\t%s\t%d\t%d\n", $2-$3, $1, $2, $3 }' "$TMP/joined.tsv" \
      | sort -rn -k1,1 | head -"$MAX_TOKENS" > "$TMP/cand.tsv"
    n_cand=$(grep -c . "$TMP/cand.tsv" || true)
    [ "$n_cand" -ge 3 ] && break
  done
  if [ "$n_cand" = 0 ]; then
    echo "no token is clearly net-removed by this diff (deleted $n_minus line(s), added $n_plus)."
    echo "inference gives nothing here: read the minus side yourself, or pass --residual '<regex>'."
  else
    echo "inferred from the diff's DELETED lines: tokens the change removes more than it adds."
    echo "'still' counts are occurrences in the current content, after the change."
    printf '  %-24s %6s %6s %8s %10s\n' "token" "del" "add" "still" "siblings"
    # shellcheck disable=SC2034  # net is the sort key, columns below show del/add
    while IFS="$(printf '\t')" read -r net tok dcount acount; do
      [ -n "$tok" ] || continue
      re="$(mk_regex "$tok")"
      still=$(count_in_list "$re" "$TMP/live_files.txt"); still=${still:-0}
      sib=$(count_in_list "$re" "$TMP/siblings.txt"); sib=${sib:-0}
      printf '  %-24s %6s %6s %8s %10s\n' "$tok" "$dcount" "$acount" "$still" "$sib"
      [ "$still" -gt 0 ] && printf '%s\n' "$tok" >> "$TMP/detail.txt"
    done < "$TMP/cand.tsv"
    echo
    echo "  (siblings column covers $n_sib_total untouched file(s); at most $MAX_SCAN are scanned)"
    echo "  a nonzero 'still' is a partial conversion candidate, NOT a defect: it may be"
    echo "  a declared exclusion. Check the exclusion's exact wording before reporting it."
  fi
fi

# per-file line numbers for the strongest few, so findings can cite exact sites
if [ -s "$TMP/detail.txt" ]; then
  echo
  echo "  where they still are (changed files first):"
  di=0
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    di=$((di + 1)); [ "$di" -gt "$MAX_DETAIL" ] && break
    if [ -n "$RESIDUAL" ]; then re="$tok"; else re="$(mk_regex "$tok")"; fi
    echo "  - $tok"
    out="$(hits_in_list "$re" "$TMP/live_files.txt")"
    if [ -z "$out" ] || [ "$out" = "NONE" ]; then
      echo "      (none left in the changed files: only untouched siblings still carry it)"
    else
      printf '%s\n' "$out"
    fi
  done < "$TMP/detail.txt"
fi

# ---------------------------------------------------------------- 5. local convention sample
echo
echo "=== 5. local convention sample ===================================="

# Leading-whitespace profile of one file: indent_profile <file> <pad>.
# The rule, applied identically to every file, with no reference to any language:
#   - skip blank lines, and lines whose first non-blank character is '*' (a block-comment
#     continuation is indented by the comment above it, not by the code grid);
#   - bucket every remaining indented line by its leading-space RUN LENGTH; lines led by
#     a tab go to their own bucket;
#   - the larger of (tab-led, space-led) is the file's style. For a space file, unit =
#     the SMALLEST run length used by at least 10% of the indented lines and by at least
#     2 of them; if no width clears that, the smallest width seen. Smallest, not
#     commonest: the commonest width is whichever nesting level the file happens to spend
#     its lines at, and taking it would call the file's own step a minority;
#   - a width that is not a whole multiple of unit is a MINORITY width, and is printed
#     with its line numbers. So is the smaller of tab-led/space-led.
# This is why a 3-space block inside a 4-space file is reported: 3 % 4 != 0. Counting
# only tabs against spaces cannot see it, because both blocks are spaces.
# Continuation lines aligned under an open bracket also land here; they are leads to
# read, not defects, exactly like every other number this script prints.
indent_profile() {
  awk -v name="$1" -v pad="$2" -v maxl="$MAX_LINENOS" -v maxw="$MAX_INDENT_WIDTHS" '
    function srt(a, n,   i, j, t) {
      for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j+1] = a[j]; a[j+1] = t }
    }
    function nums(s, c) { return s (c > maxl ? ",..." : "") }
    {
      line = $0; sub(/\r$/, "", line)
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*\*/) next
      if (line ~ /^\t/) { tabn++; if (tn < maxl) { tl = tl (tn ? "," : "") NR; tn++ }; next }
      if (line !~ /^ /) next
      w = match(line, /[^ ]/) - 1
      cnt[w]++; total++
      if (nl[w] < maxl) { ln[w] = ln[w] (nl[w] ? "," : "") NR; nl[w]++ }
    }
    END {
      ng = 0; no = 0
      if (total + tabn == 0) { printf "%s%-52s (no indented lines)\n", pad, name; exit }
      if (tabn > total) {
        printf "%s%-52s tab=%-5d space=%-5d unit=tab\n", pad, name, tabn, total
        for (k in cnt) o[++no] = k + 0
        srt(o, no)
        for (i = 1; i <= no && i <= maxw; i++)
          printf "%s    minority: %d space(s), %d line(s): %s\n", pad, o[i], cnt[o[i]], nums(ln[o[i]], cnt[o[i]])
        if (no > maxw) printf "%s    ... %d more space width(s) here\n", pad, no - maxw
        exit
      }
      nw = 0
      for (k in cnt) all[++nw] = k + 0
      srt(all, nw)
      thr = total * 0.10; if (thr < 2) thr = 2
      unit = 0
      for (i = 1; i <= nw; i++) if (cnt[all[i]] >= thr) { unit = all[i]; break }
      if (unit == 0) unit = all[1]
      for (i = 1; i <= nw; i++) { if (all[i] % unit == 0) g[++ng] = all[i]; else o[++no] = all[i] }
      grid = ""
      for (i = 1; i <= ng && i <= 8; i++) grid = grid sprintf("%s%dx%d", (i > 1 ? " " : ""), g[i], cnt[g[i]])
      if (ng > 8) grid = grid " ..."
      printf "%s%-52s space=%-5d tab=%-5d unit=%d  [%s]\n", pad, name, total, tabn + 0, unit, grid
      for (i = 1; i <= no && i <= maxw; i++)
        printf "%s    minority: %d space(s), %d line(s): %s\n", pad, o[i], cnt[o[i]], nums(ln[o[i]], cnt[o[i]])
      if (no > maxw) printf "%s    ... %d more off-unit width(s) here\n", pad, no - maxw
      if (tabn > 0) printf "%s    minority: tab-led, %d line(s): %s\n", pad, tabn, nums(tl, tabn)
    }' "$1"
}

# indentation, per changed file, so an inconsistency inside the change is visible too
echo "indentation of the changed files (leading-space run-length histogram per file):"
echo "  [WxN ...] is the on-unit grid: width W on N line(s). unit = the smallest leading-space"
echo "  width the file uses on >=10% of its indented lines; any width that is NOT a multiple"
echo "  of it, and the smaller of tab-led/space-led, is listed as 'minority' with its line"
echo "  numbers. Blank lines and '*' block-comment continuations are skipped."
rows=0
: > "$TMP/indent_omitted.txt"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue
  rows=$((rows + 1))
  if [ "$rows" -gt "$MAX_INDENT_ROWS" ]; then printf '    %s\n' "$f" >> "$TMP/indent_omitted.txt"; continue; fi
  indent_profile "$f" "  "
done < "$TMP/live_files.txt"
if [ "$rows" -gt "$MAX_INDENT_ROWS" ]; then
  echo "  ... $((rows - MAX_INDENT_ROWS)) more file(s), not profiled, names only:"
  cat "$TMP/indent_omitted.txt"
fi

# pick a sibling to read the unwritten rules off: the commonest extension among the
# changed files, and the longest such sibling, since a long file shows more habits
SAMPLE=""
EXT="$(sed -n 's/.*\.\([A-Za-z0-9_]\{1,\}\)$/\1/p' "$TMP/live_files.txt" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')"
if [ -n "$EXT" ] && [ -s "$TMP/siblings.txt" ]; then
  SAMPLE="$(grep -E "\.$EXT\$" "$TMP/siblings.txt" 2>/dev/null | head -"$MAX_SCAN" | while IFS= read -r s; do
              [ -f "$s" ] && printf '%s\t%s\n' "$(wc -l < "$s" 2>/dev/null | tr -d ' ')" "$s"
            done | sort -rn | head -1 | cut -f2-)"
fi
[ -z "$SAMPLE" ] && [ -s "$TMP/siblings.txt" ] && SAMPLE="$(head -1 "$TMP/siblings.txt")"

echo
if [ -z "$SAMPLE" ] || [ ! -f "$SAMPLE" ]; then
  echo "no untouched sibling file to sample: this change covers its directories entirely."
  echo "derive conventions from the nearest parent directory instead, and say so when you"
  echo "report a style finding."
else
  echo "sample sibling: $SAMPLE  ($(wc -l < "$SAMPLE" | tr -d ' ') lines)"
  echo "  its own indentation profile, same rule as above (this is the neighbour's habit,"
  echo "  so compare its unit against the unit of the files you changed):"
  indent_profile "$SAMPLE" "  "
  wild=$(grep -acE '^[[:space:]]*import .*\*;' "$SAMPLE" 2>/dev/null || true)
  stat=$(grep -acE '^[[:space:]]*import static ' "$SAMPLE" 2>/dev/null || true)
  echo "  imports: wildcard=$wild static=$stat"
  echo "  first $SAMPLE_LINES lines (tabs shown as <TAB>):"
  head -"$SAMPLE_LINES" "$SAMPLE" | awk '{ gsub(/\t/, "<TAB>"); print "    " $0 }'
  tl=$(wc -l < "$SAMPLE" | tr -d ' ')
  [ "$tl" -gt "$SAMPLE_LINES" ] && echo "    ... $((tl - SAMPLE_LINES)) more line(s) not shown"
fi

echo
echo "==================================================================="
echo "gathered, not judged. Counts here are leads: every one still needs the"
echo "contract (issue AC, declared rules, or the neighbours' own habit) quoted"
echo "against it before it becomes a finding."
