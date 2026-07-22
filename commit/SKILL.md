---
name: commit
description: "Commit staged changes with a clean, single-line Conventional Commit subject in plain developer English. Use when the user wants to commit changes, write a commit message, or wrap up work with a conventional-commit title. Generates a `type(scope): summary` subject from the staged diff and commits it. Triggers on phrases like 'commit this', 'make a commit', 'write a commit message', 'git commit', 'commit my changes'."
argument-hint: "[optional message hint or scope]"
---

# Conventional-commit a change

Generate a single-line Conventional Commit subject from the staged changes and commit. Subject only: no body unless the user asks. Never push.

## Step 1: Check what is staged

```bash
git diff --cached --stat
```

- If something is staged, commit only that.
- If nothing is staged, show `git status -sb` and ask whether to stage everything (`git add -A`) or specific files. Do not stage silently.

## Step 2: Read the change

```bash
git diff --cached
```

Identify what actually changed (feature, bug fix, docs, refactor, tests, config) and the most-affected area (top-level dir, module, or file) to use as the scope.

## Step 3: Compose the subject

Format: `type(scope): summary`

- **type** (required): `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`, `style`.
- **scope** (optional): the module or dir touched, e.g. `commit`, `readme`, `dialect`. Omit if the change is broad.
- **summary**: imperative mood, lowercase, plain everyday developer English, no trailing period. Aim for <= 50 characters.

Good: `feat(commit): add conventional-commit skill`, `fix: handle empty staged diff`, `docs: clarify install steps`.

Avoid: vague summaries ("update stuff"), past tense ("added"), a capitalized or period-ended summary, or stacking multiple unrelated changes into one subject.

**No issue-key prefix**: never prepend a JIRA/issue key such as `[CUBRIDQA-1432]` or `[CBRD-1234]` to the subject, even if the repo's existing commit history uses that style. Always keep the Conventional Commit form `type(scope): summary` (`fix: …`, `refactor: …`, `ci: …`). If the commit relates to an issue, put the reference in the body or a trailer, not the subject.

If `$ARGUMENTS` is given, treat it as a hint for the scope or wording: still normalize it to the format above.

## Step 4: Confirm and commit

Show the proposed subject and confirm with the user (unless they already said to commit directly), then:

```bash
git commit -m "<subject>"
```

Title only. Add a body only if the user explicitly asks for one. Append any trailer your environment requires (e.g. a `Co-Authored-By:` line) without changing the subject. Never run `git push`: leave pushing to the user.
