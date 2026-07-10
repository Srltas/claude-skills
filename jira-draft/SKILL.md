---
name: jira-draft
description: "Draft a CUBRID JIRA issue (bug or task) with a concise English title and a Korean, bullet-style (개조식) body under English section headers. Use when you need to write up a CUBRID JIRA issue from the current work: a bug report (Description / Test Build / Repro / Expected / Actual / Additional Info) or a task/improvement (Description / Specification Changes / Implementation / Acceptance Criteria / Definition of Done). Produces a copy-paste draft only; it does not post to JIRA. It is the reverse of jira-fetch (which downloads an issue). Triggers on phrases like 'CUBRID JIRA 이슈 작성', 'jira 버그 리포트 초안', '이 작업 jira 이슈로 정리', 'draft a CUBRID jira issue', 'write a jira bug report'."
argument-hint: "bug|task [subject]"
---

# Draft a CUBRID JIRA issue

Write a ready-to-paste CUBRID JIRA issue from the current work. **Title in concise English; body in Korean, 개조식 (bullet points, 핵심만); section headers in English.** This produces a draft only. You paste it into JIRA; the skill does not post.

## Step 1 — Pick the type

- **bug** — something is broken / misbehaving.
- **task** — non-bug work (개선 / 기능 / 일반 작업).

Infer from the context; ask only if it is genuinely unclear.

## Step 2 — Gather the facts

Pull the specifics from the session (or ask the user):

- bug: 증상, 빌드/버전, 재현 절차, 기대 vs 실제.
- task: 무엇을·왜, 사양 변경 여부, 구현 방향, 완료 조건.

Do not invent. If a field is unknown, write `(확인 필요)` rather than guessing. (Optional: verify CUBRID behavior or terms with **cubrid-manual** before asserting.)

## Step 3 — Write the draft

**Title (English, concise):** `[<AREA>] <short summary>` — one line, specific, no trailing period. Example: `[JDBC] getObject(LocalDateTime) throws on TIMESTAMP column`.

**Body (Korean, 개조식)** under the English headers for the chosen type:

### bug

```markdown
## Description
- 무엇이 문제인지 한두 줄
## Test Build
- 빌드/버전/브랜치 (예: 11.3 latest, commit abc123)
## Repro
- 재현 절차 1
- 재현 절차 2
## Expected Result
- 기대 동작
## Actual Result
- 실제 동작 (에러/로그 요약)
## Additional Information
- (선택) 로그, 환경, 참고 링크
```

### task

```markdown
## Description
- 무엇을, 왜
## Specification Changes
- 사양 변경점 (없으면 "없음")
## Implementation
- 구현 방향 / 범위
## Acceptance Criteria
- 완료로 인정되는 조건 (검증 가능하게)
## Definition of Done
- 코드 / 테스트 / 문서 등 완료 기준
```

Rules: 개조식 불릿, 한 항목 한 줄, 핵심만. 빈 섹션은 생략하지 말고 `없음` 또는 `(확인 필요)`로 남긴다 (`Additional Information`만 정보 없으면 생략 가능).

## Step 4 — Output

Print the draft in one copy-paste block: the English title line, then the Korean body. Do not post to JIRA — tell the user to paste it into a new CUBRID JIRA issue.

(If CUBRID JIRA renders wiki markup rather than Markdown in your project, convert `## X` to `h2. X` and `- ` to `* ` when pasting.)
