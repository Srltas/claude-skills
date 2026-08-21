---
name: weekly-report
description: "Turn a list of JIRA issue keys into one short Korean line per issue, ready to paste into a weekly-report spreadsheet (one line per cell). Give it several keys (e.g. APIS-1111, TOOLS-4324) and it fetches each issue with the jira-fetch skill, reads the description, and compresses it into a single 개조식 line ending in 명사형: 대상 + 무엇을 하는가, no procedures or checklists. Summarizes what the issue IS, not progress or status. Use when writing the weekly report and you need each issue boiled down to one line. Triggers on phrases like '주간보고 정리', '주간 보고용으로 요약', '이 이슈들 한 줄로 정리', '주간보고 한 줄씩 만들어줘', 'weekly report lines for these issues'."
argument-hint: "<ISSUE-KEY> [ISSUE-KEY...]"
---

# Weekly-report lines from JIRA issues

Compress each issue into **one line** for the weekly-report spreadsheet: one line per cell, in the order the keys were given. Draft only, nothing is posted anywhere.

## Step 0: Prereq

The **jira-fetch** skill installed at `~/.claude/skills/jira-fetch/` (this skill calls its helper). Its constraints apply: only publicly readable projects (CBRD, TOOLS, APIS, ...) can be read; internal-only projects such as CUBRIDQA fail with `HTTP 401`.

## Step 1: Parse the keys

From `$ARGUMENTS`, take every `PROJECT-NUMBER`. Accept commas or spaces, a pasted issue URL, and lower case (`apis-1111` -> `APIS-1111`). Drop duplicates and **keep the order given**: the report rows should match what the user typed.

## Step 2: Fetch all of them in one call

```bash
bash ~/.claude/skills/jira-fetch/assets/fetch_jira.sh APIS-1111 TOOLS-4324 ...
```

The helper takes many keys at once, so call it **once** for the whole list. It writes `./jira/<KEY>.md` (title as `# heading`, then the description). Skip any key whose `.md` already exists: do not re-fetch. A key that cannot be read is simply reported as missing, and the rest still succeed.

## Step 3: Write one line per issue

Read each `<KEY>.md` and compress it. **The line answers "what is this issue", not "what did I do" or "what is its status".**

```
APIS-1088 JDBC 구버전 PROTOCOL 호환성 코드 제거
TOOLS-4888 CMT 단위 테스트 라이브러리 Java 8 지원 버전으로 업그레이드
```

Rules:

- **Form**: `<KEY> <요약>`, key first, one space, then the summary. No trailing period (it goes in a cell).
- **명사형 종결**: end on a noun form ("추가", "제거", "업그레이드", "검토"), the usual weekly-report register.
- **Length**: around 60 characters, 80 at the very most.
- **Content**: 대상 + 무엇을 하는가. One thread only.
- **Never list** the description's steps, checklists, sub-items, or affected files. Those belong in the issue, not the report line.
- **Do not just copy the title.** Titles are often vague (`[JDBC] PROTOCOL 호환성 제거 관련`): use the description to make the line concrete. If the title is already specific and complete, reusing its substance is fine.
- Drop the `[AREA]` bracket from the title; the key already identifies the area.
- No em-dash (`—`): use commas, colons, parentheses.

## Step 4: Output

Print the lines as one plain block in input order, nothing else interleaved, so the user can copy it straight into the sheet.

Then, if any key could not be read, list those separately with the reason and what would unblock them:

```
읽지 못함: CUBRIDQA-1509 (내부 전용 프로젝트, 내용을 알려주시면 그 줄만 채웁니다)
```

Do not invent a line for an issue you could not read, and do not guess from the key alone.

## Notes

- This skill keeps no history, so the same issue produces the same line every week. If the user wants the line to reflect only the latest change, they should say what changed and it goes into that line.
- Progress and status are out of scope by design: the line describes the issue. If the user asks for status too, get it from them rather than assuming.
