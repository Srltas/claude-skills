# claude-skills justfile
# Link each skill in this repo into ~/.claude/skills, so edits here are live without reinstalling.

# Link every skill into ~/.claude/skills. A copy left by an earlier install is moved to the
# Trash only when it matches this repo; a copy that differs is reported and left alone.
install:
    #!/usr/bin/env bash
    set -euo pipefail
    dest="$HOME/.claude/skills"
    mkdir -p "$dest"
    for f in */SKILL.md; do
      d="${f%/SKILL.md}"; t="$dest/$d"
      if [ -e "$t" ] && [ ! -L "$t" ]; then
        if ! diff -rq -x .DS_Store -x __pycache__ "$d" "$t" >/dev/null 2>&1; then
          echo "skip $d: $t is a copy that differs from this repo; move it away and re-run" >&2
          continue
        fi
        mkdir -p "$HOME/.Trash"
        mv "$t" "$HOME/.Trash/$d-copy-$(date +%Y%m%d-%H%M%S)"
      fi
      ln -sfn "$PWD/$d" "$t"
      echo "linked $d"
    done

# Same as install
reinstall: install

# Pull the latest commits (linked skills see them at once), then link any new skill
update:
    git pull --ff-only
    just install

# List this collection's skills and whether each one is linked
list:
    #!/usr/bin/env bash
    for f in */SKILL.md; do
      d="${f%/SKILL.md}"
      name="$(sed -n 's/^name: *//p' "$f" | head -1)"
      if [ "$(readlink "$HOME/.claude/skills/$d")" = "$PWD/$d" ]; then s=linked; else s="not linked"; fi
      printf '%-28s %s\n' "$name" "$s"
    done

# Unlink one skill (e.g. `just remove skill-create`); the skill stays in this repo
remove skill:
    #!/usr/bin/env bash
    set -euo pipefail
    t="$HOME/.claude/skills/{{ skill }}"
    [ -L "$t" ] || { echo "$t is not a link" >&2; exit 1; }
    rm "$t"
    echo "unlinked {{ skill }}"

# Check every skill against the conventions, then run the official validator on copies
# (the validator does not follow symlinks)
check:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 tools/check_skills.py
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/.claude/skills"
    for f in */SKILL.md; do cp -R "${f%/SKILL.md}" "$tmp/.claude/skills/"; done
    claude plugin validate "$tmp/.claude/skills"
