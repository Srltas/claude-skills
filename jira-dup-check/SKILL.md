---
name: jira-dup-check
description: "Check a CUBRID Jira issue draft against existing issues before it is filed: search with several Korean and English phrasings, read the top candidates, and judge each as duplicate, related, or unrelated with reasons. jira-draft runs it on new drafts. To read a known issue, use jira-fetch. Triggers on phrases like '이 이슈 이미 있는지 봐줘', '중복 이슈 확인해줘', '등록 전에 중복 검사'."
argument-hint: "[draft text | file | ISSUE-KEY]"
allowed-tools:
  - "Bash(python3 ${CLAUDE_SKILL_DIR}/assets/search_jira.py *)"
---

# Check a Jira draft for duplicates

Before a CUBRID Jira issue is filed, find existing issues that already report the same problem or are worth linking, and judge each one. Advisory only: it writes nothing to Jira and never files the issue.

## Step 1: Get the draft

Use the title and description being prepared: from `$ARGUMENTS`, a file the user names, or a jira-draft output in this session. Note the project it will be filed in (CBRD unless the draft says APIS, TOOLS, ...). If the user gives an existing key to check, fetch it with **jira-fetch**, use its title and description as the draft, and pass the key to `--exclude`.

## Step 2: Write the search phrases

Write 5 to 8 short phrases (2 to 4 words each) that an earlier report of the same problem would contain. Every word of a phrase must match, so keep each phrase narrow and use several:

- Identifiers verbatim: function, file, and parameter names, error codes and message text, the SQL constructs that matter (e.g. `pgbuf_timed_sleep`, `ER_LK_UNILATERALLY_ABORTED`, `LEFT OUTER JOIN`).
- The symptom (what a user sees) and the cause (what the code does wrong), each in English and in Korean: the same defect is often filed once in each language, once by symptom and once by cause.
- Korean words as stems without particles (`병합`, not `병합하면`); the script adds a prefix wildcard to Korean words.
- Leave out words that match everything: CUBRID, 오류, error, issue, 문제, version numbers.

## Step 3: Search

```bash
python3 ${CLAUDE_SKILL_DIR}/assets/search_jira.py --title "<the draft's title>" "phrase one" "phrase two" "phrase three"
```

It runs one `text ~` query per phrase (summary, description, comments) plus one that ranks issues by how many title words they share (it catches near-identical titles that narrow phrases miss), merges the results so that issues found by more queries rank higher, and prints the top 15 with type, status, resolution, fix versions, created date, and the start of the description. It logs in when `JIRA_USER` and `JIRA_PASSWORD` are set, so restricted comments and internal projects are searched too, and falls back to anonymous access. Options: `--project APIS` (or `CBRD,CUBRIDQA`), `--top 25`, `--exclude CBRD-1234`, `--excerpt 600`.

The per-query counts come first. A phrase with 0 hits is too narrow (drop a word); one with hundreds is too broad (add a distinguishing word). Adjust and re-run at most twice.

## Step 4: Judge each candidate

Read the summaries and excerpts. For the few that might match, read the full text with **jira-fetch** before deciding. Judge on facts, not on shared words:

- **중복**: the same defect or request: the same failing behavior under the same conditions, or the same root cause.
- **관련**: the same area or function, or a partial overlap; worth linking, not the same problem.
- **무관**: everything else; leave it out of the report.

For a duplicate that is already Fixed, give its Fix Version so the reporter can check whether their build has the fix.

## Step 5: Report

```markdown
## 중복 검사: <초안 제목>
검색어 <N>개로 후보 <N>건 검토: 중복 의심 <N>건, 관련 <N>건

| 이슈 | 상태 | 판정 | 근거 |
|---|---|---|---|
| CBRD-1234 <제목 요약> | Resolved / Fixed (<Fix Version>) | 중복 | <같은 함수, 같은 조건, 같은 증상처럼 일치하는 사실> |

다음 행동: <중복이면 등록하지 말고 기존 이슈에 재현 정보를 댓글로 추가 / 관련이면 링크를 걸어 등록 / 없으면 그대로 등록>
```

If anything is judged 중복, stop before the issue is filed and let the user decide. When nothing fits, say so and list the phrases used, so the user can see what was searched.

## Limits

- Word search, so recall depends on the phrases. Measured on 2026-11-09 on the 50 CBRD issues closed as Duplicate whose original came first (the set in CBRD-27978), searching summary and description as of each duplicate's creation: the original was in the top 10 for 38 of 50 (title pasted as one query: 3; title words joined by OR: 31), and for 6 of the 10 pairs written in different languages (title words: 2). Most misses share almost no words with their original, such as a regression core dump linked to the change that caused it. Re-measure with `python3 ${CLAUDE_SKILL_DIR}/assets/eval_pairs.py --help`.
- Without a login, restricted comments and links are invisible.
