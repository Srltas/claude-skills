---
name: jira-draft
description: "Draft a CUBRID JIRA issue (bug or task) with a concise English title and a Korean body under English section headers (Description as easy-to-read prose; the other sections in bullet style, 개조식). Use when you need to write up a CUBRID JIRA issue from the current work: a bug report (Description / Test Build / Repro / Expected / Actual / Additional Info) or a task/improvement (Description / Specification Changes / Implementation / Acceptance Criteria / Definition of Done). Produces a copy-paste draft only; it does not post to JIRA. It is the reverse of jira-fetch (which downloads an issue). Triggers on phrases like 'CUBRID JIRA 이슈 작성', 'jira 버그 리포트 초안', '이 작업 jira 이슈로 정리', 'draft a CUBRID jira issue', 'write a jira bug report'."
argument-hint: "bug|task [subject]"
---

# Draft a CUBRID JIRA issue

Write a ready-to-paste CUBRID JIRA issue from the current work. **Title in concise English; section headers in English; body in Korean.** The **Description** reads as plain, easy-to-understand prose (a reader new to the issue should get it); the **other sections are 개조식** (bullet points, 핵심만). This produces a draft only. You paste it into JIRA; the skill does not post.

## Step 1: Pick the type

- **bug**: something is broken / misbehaving.
- **task**: non-bug work (개선 / 기능 / 일반 작업).

Infer from the context; ask only if it is genuinely unclear.

## Step 2: Gather the facts

Pull the specifics from the session (or ask the user):

- bug: 증상, 빌드/버전, 재현 절차, 기대 vs 실제.
- task: 무엇을·왜, 사양 변경 여부, 구현 방향, 완료 조건.

Do not invent. If a field is unknown, write `(확인 필요)` rather than guessing. (Optional: verify CUBRID behavior or terms with **cubrid-manual** before asserting.)

## Step 3: Write the draft

**Title (English, concise):** `[<AREA>] <short summary>`: one line, specific, no trailing period. Example: `[JDBC] getObject(LocalDateTime) throws on TIMESTAMP column`.

**Body (Korean, 개조식)** under the English headers for the chosen type:

### bug

```markdown
## Description
처음 보는 사람도 이해할 수 있게 문제 상황을 서술체로 설명 (한두 문단)
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
이 작업이 무엇이고 왜 필요한지 서술체로 설명 (한두 문단)
## Specification Changes
- 바뀌는 것의 `현재 → 목표` (무엇이 달라지는가)
## Implementation
- 그것을 어떻게 구현하는가 (내부 흐름·범위)
## Acceptance Criteria
- 완료로 인정되는 조건 (검증 가능하게)
## Definition of Done
- 코드 / 테스트 / 문서 등 완료 기준
```

#### What belongs in Specification Changes

QA and the manual writers read this section, so there is one test: **does this work force a test or a document to change?** Do not read "사양" narrowly as "an SQL syntax change". If any of these differs, the answer is **not 없음**:

- **동작**: query results, default behavior, error codes and messages, log or output format
- **인터페이스**: SQL syntax, function and API signatures, JDBC behavior, CLI options
- **설정**: parameters added or removed, defaults, allowed ranges
- **산출물·의존성**: library versions, the shipped jar set, file paths and names, supported JDK and platforms
- **제약**: supported scope, compatibility, performance guarantees

**Form**: write each item as `현재 → 목표`, concrete down to the version, path, or value, and use a table once there are several. Pinning down what does *not* change helps too (e.g. "그 외 라이브러리·경로 변경 없음").

**Genuinely 없음** covers only a pure internal refactor where nothing observable from outside changes. Even then, do not write a bare "없음": say in one line what stayed the same (e.g. "없음 (동작·인터페이스·산출물 구성 동일)").

#### Write it to be read (shape rules)

The reader should get it by skimming. Shape is not a matter of taste: **the shape of the data decides it.**

- **Table / bullets / sentence**: the same field repeated across several targets is a **table** (columns: 대상 · 현재 · 변경 후); two or three unrelated facts are bullets; one fact is just a sentence.
- **One bullet = one fact**: never cram `현재 → 목표` into a single sentence. When the result differs by condition, make the condition the row of a table.
- **Pull a list of four or more out of the sentence**: do not chain more than four class/file/option names with commas. Split them into a table or list when the reader needs each name; compress to **기준 + 개수** when they only need the scope (e.g. "`Wrapper`를 구현하는 7개 클래스, 상속 포함 12개 타입").
- **Say a shared fact once, up front**: when several rows share the same current state, state it once before the table and leave only what differs inside it.
- **Split blocks that differ in kind**: do not mix behavior, scope, exclusions, and no-change into one bullet list.

Rules: **Description is 서술체** (one or two easy paragraphs), **every other section is 개조식** (one line per item, essentials only). Do not drop an empty section: leave `없음` or `(확인 필요)` (only `Additional Information` may be omitted when there is nothing). No em-dash (`—`): use commas, colons, parentheses, periods.

## Step 4: Output

Print the draft in one copy-paste block: the English title line, then the Korean body. Do not post to JIRA: tell the user to paste it into a new CUBRID JIRA issue.

(If CUBRID JIRA renders wiki markup rather than Markdown in your project, convert `## X` to `h2. X` and `- ` to `* ` when pasting.)
