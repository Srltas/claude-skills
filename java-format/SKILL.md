---
name: java-format
description: "Format Java files in place with google-java-format (AOSP style): the changed, staged, or all files, or given paths. Asks which formatter version to use. Use before committing Java changes. Triggers on phrases like '포맷 확인해줘', 'google-java-format 적용', '자바 포맷 맞춰줘'."
argument-hint: "<changed|staged|all|FILE...> [--version 1.7 or 1.32.0]"
allowed-tools:
  - "Bash(bash ${CLAUDE_SKILL_DIR}/assets/format.sh *)"
---

# Apply google-java-format

Format Java files with google-java-format in **AOSP style, replaced in place** (`-a -r`). Handles the four scopes: changed, staged, all, or explicit paths.

## Step 1: Pick the version

Ask the user which google-java-format version to use (commonly `1.7` or `1.32.0`) unless they already said it. Projects pin different versions to match their CI, so do not assume a default.

## Step 2: Run

```bash
bash ${CLAUDE_SKILL_DIR}/assets/format.sh --version <ver> <changed|staged|all|FILE...>
```

- `changed`: working-tree changes (`git diff --diff-filter=ACM -- '*.java'`)
- `staged`: staged files (`git diff --cached …`)
- `all`: every `*.java` under the current directory
- or one or more file / directory paths

The helper resolves the jar in this order (no hardcoded personal path): `GJF_JAR` (explicit jar path) → `$GJF_DIR/google-java-format-<ver>-all-deps.jar` if `GJF_DIR` is set (point it at your local jar folder, e.g. `export GJF_DIR="$HOME/Driver/google-java-format"`) → the cache `~/.cache/claude-skills/google-java-format/` → otherwise auto-download that version from GitHub releases into the cache. Needs `java` on PATH (and `curl` only if it has to download).

## Step 3: Report

Say how many files were formatted. This edits files **in place**, so suggest reviewing `git diff` before staging. For the `all` scope on a large tree, confirm the scope with the user first (it can touch many files).

Notes: style is AOSP (4-space) via `-a`, matching your convention. To format a specific file, pass its path instead of a scope word.
