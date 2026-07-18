#!/usr/bin/env bash
# Apply google-java-format (AOSP style, in place) to Java files.
#   format.sh --version <ver> <changed|staged|all|FILE...>
# jar resolution: $GJF_JAR -> $GJF_DIR/<name> (if set) -> ~/.cache/<name> -> auto-download from GitHub releases into ~/.cache
set -uo pipefail

VER=""; SCOPE=""; FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VER="${2:-}"; shift 2;;
    changed|staged|all) SCOPE="$1"; shift;;
    -h|--help) echo "usage: format.sh --version <ver> <changed|staged|all|FILE...>"; exit 0;;
    -*) echo "error: unknown option: $1" >&2; exit 2;;
    *) FILES+=("$1"); shift;;
  esac
done

[ -n "$VER" ] || { echo "error: --version <ver> required (e.g. --version 1.32.0 or --version 1.7)" >&2; exit 2; }
[ -n "$SCOPE" ] || [ "${#FILES[@]}" -gt 0 ] || { echo "error: give a scope (changed|staged|all) or file paths" >&2; exit 2; }
command -v java >/dev/null 2>&1 || { echo "error: java not found on PATH" >&2; exit 2; }

name="google-java-format-$VER-all-deps.jar"
JAR="${GJF_JAR:-}"
if [ -z "$JAR" ]; then
  # search $GJF_DIR (your local jar folder, if set) then the cache; no hardcoded personal path
  for dir in "${GJF_DIR:-}" "$HOME/.cache/claude-skills/google-java-format"; do
    [ -n "$dir" ] || continue
    [ -f "$dir/$name" ] && { JAR="$dir/$name"; break; }
  done
fi
if [ -z "$JAR" ]; then
  cache="$HOME/.cache/claude-skills/google-java-format"; mkdir -p "$cache"
  JAR="$cache/$name"
  url="https://github.com/google/google-java-format/releases/download/v$VER/$name"
  command -v curl >/dev/null 2>&1 || { echo "error: need curl to download $name" >&2; exit 2; }
  echo "· downloading $name from GitHub releases" >&2
  curl -fsSL "$url" -o "$JAR" || { echo "error: download failed ($url) - check the version number" >&2; rm -f "$JAR"; exit 2; }
fi
[ -f "$JAR" ] || { echo "error: jar not found: $JAR" >&2; exit 2; }
echo "· jar: $JAR" >&2

if [ -n "$SCOPE" ]; then
  FILES=()
  if [ "$SCOPE" = changed ]; then
    while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < <(git diff --name-only --diff-filter=ACM -- '*.java')
  elif [ "$SCOPE" = staged ]; then
    while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < <(git diff --cached --name-only --diff-filter=ACM -- '*.java')
  elif [ "$SCOPE" = all ]; then
    while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < <(find . -name '*.java')
  fi
fi
[ "${#FILES[@]}" -gt 0 ] || { echo "no .java files for scope '${SCOPE:-files}'"; exit 0; }

echo "· formatting ${#FILES[@]} file(s) with google-java-format $VER (AOSP, in place)" >&2
printf '%s\0' "${FILES[@]}" | xargs -0 java -jar "$JAR" -a -r
echo "done: ${#FILES[@]} file(s)"
