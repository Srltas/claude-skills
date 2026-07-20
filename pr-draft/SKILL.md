---
name: pr-draft
description: "Draft a pull request (title + body) from the current branch's commits and diff. The title is [XXX-0000] plus a concise, easy-to-understand English summary (the key is taken from the branch name); the body is Korean in three sections: Purpose (required, why this PR exists), Implementation (optional, how it was built), Remarks (optional, notes). Optional sections become N/A when empty. Produces a copy-paste draft only; it does not create the PR. Triggers on phrases like 'PR 초안 작성', 'pr-draft', '이 브랜치 PR로 정리', 'draft a PR', 'PR 제목이랑 본문 만들어줘'."
argument-hint: "[base-branch]"
---

# Draft a pull request

Turn the current branch into a ready-to-paste PR title and body, grounded in the real commits and diff. Draft only: it does not create the PR.

## Step 1: Context

- Current branch: `git rev-parse --abbrev-ref HEAD`.
- **Key**: extract `PROJECT-NUMBER` from the branch name (e.g. `HHH-20527-modernize-...` -> `HHH-20527`). If the branch has no such key, ask the user for it.
- **Base**: use the first ref that exists, checked with `git rev-parse --verify <ref>`: `upstream/main`, then `origin/main`, then `main`. If `$ARGUMENTS` names a base, use that. If still unclear, ask.

## Step 2: Read the changes (grounding)

```bash
git log <base>..HEAD --oneline
git diff <base>...HEAD --stat
```

Read the key hunks of the diff if needed. Draft from what actually changed, not from memory.

## Step 3: Title

`[XXX-0000] <summary>`

- `[XXX-0000]` is the key from Step 1 (e.g. `[HHH-20527]`, `[CBRD-1234]`).
- `<summary>` is concise **English** using easy words anyone can understand, one line, no trailing period.

## Step 4: Body (Korean, three sections)

```markdown
## Purpose
<이 PR의 목적이 무엇인가. 왜 필요한지. (필수)>

## Implementation
<이 PR을 구현하기 위해 어떻게 했는가. (선택: 없으면 N/A)>

## Remarks
<주의사항, 후속 작업, 리뷰 포인트 등. (선택: 없으면 N/A)>
```

Rules: **Purpose is required.** Implementation and Remarks are optional and become `N/A` when there is nothing to say. Keep each section tight (핵심만). em-dash(`—`)는 쓰지 않는다: 쉼표·콜론·괄호·마침표로 대체.

## Step 5: Output

Print the title line and the body as one copy-paste block. **Do not create the PR.** If the user wants to open it, show (and run only when they explicitly ask) the command:

```bash
gh pr create --base <base> --title "<title>" --body "<body>"
```
