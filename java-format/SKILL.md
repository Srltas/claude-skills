---
name: java-format
description: "Apply google-java-format (AOSP style, in place) to Java files: the changed files, the staged files, all files, or specific paths. It asks which google-java-format version to use (e.g. 1.7 or 1.32.0), resolves the jar (GJF_JAR, then $GJF_DIR if set, then a cache, else auto-downloads that version), and runs it. Use when you want to format Java code to the project style, before committing. Triggers on phrases like 'google-java-format 적용', '자바 코드 스타일 적용', '변경된 자바 포맷', 'format the java files', 'apply java formatting'."
argument-hint: "<changed|staged|all|FILE...> [--version 1.7 or 1.32.0]"
---

# Apply google-java-format

Format Java files with google-java-format in **AOSP style, replaced in place** (`-a -r`). Handles the four scopes: changed, staged, all, or explicit paths.

## Step 1: Pick the version

Ask the user which google-java-format version to use (commonly `1.7` or `1.32.0`) unless they already said it. Projects pin different versions to match their CI, so do not assume a default.

## Step 2: Run

```bash
bash <skill-base-dir>/assets/format.sh --version <ver> <changed|staged|all|FILE...>
```

- `changed`: working-tree changes (`git diff --diff-filter=ACM -- '*.java'`)
- `staged`: staged files (`git diff --cached …`)
- `all`: every `*.java` under the current directory
- or one or more file / directory paths

The helper resolves the jar in this order (no hardcoded personal path): `GJF_JAR` (explicit jar path) → `$GJF_DIR/google-java-format-<ver>-all-deps.jar` if `GJF_DIR` is set (point it at your local jar folder, e.g. `export GJF_DIR="$HOME/Driver/google-java-format"`) → the cache `~/.cache/claude-skills/google-java-format/` → otherwise auto-download that version from GitHub releases into the cache. Needs `java` on PATH (and `curl` only if it has to download).

## Step 3: Report

Say how many files were formatted. This edits files **in place**, so suggest reviewing `git diff` before staging. For the `all` scope on a large tree, confirm the scope with the user first (it can touch many files).

Notes: style is AOSP (4-space) via `-a`, matching your convention. To format a specific file, pass its path instead of a scope word.
