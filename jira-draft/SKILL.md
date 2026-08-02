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

#### Specification Changes 판단 기준

이 섹션은 **QA와 매뉴얼 담당자가 읽는 곳**이다. 판단 기준은 하나: **이 작업 때문에 테스트나 문서를 고쳐야 하는가.** "사양"을 SQL 문법 변경 같은 큰 것으로만 좁게 보지 말 것. 아래 중 하나라도 달라지면 **없음이 아니다**:

- **동작**: 쿼리 결과, 기본 동작, 에러 코드·메시지, 로그·출력 포맷
- **인터페이스**: SQL 문법, 함수·API 시그니처, JDBC 동작, CLI 옵션
- **설정**: 파라미터 추가·삭제, 기본값·허용 범위
- **산출물·의존성**: 라이브러리 버전, 배포 jar 구성, 파일 경로·이름, 지원 JDK·플랫폼
- **제약**: 지원 범위, 호환성, 성능 보장치

**형식**: 항목마다 `현재 → 목표`를 버전·경로·값까지 구체적으로 쓰고, 항목이 많으면 표로. 바뀌지 않는 것도 함께 못박으면 좋다 (예: "그 외 라이브러리·경로 변경 없음").

**정말 없음인 경우**: 밖에서 관찰되는 것이 하나도 안 바뀌는 순수 내부 리팩터링뿐이다. 그때도 맨 "없음"이 아니라 무엇이 그대로인지 한 줄로 적는다 (예: "없음 (동작·인터페이스·산출물 구성 동일)").

#### 읽히게 쓰기 (형태 규칙)

읽는 사람이 훑어서 파악할 수 있어야 한다. 형태는 취향이 아니라 **담는 데이터의 모양**이 정한다.

- **표 / 불릿 / 문장 고르기**: 같은 항목을 여러 대상에 반복하면 **표**(열: 대상 · 현재 · 변경 후), 서로 다른 사실 2~3개면 불릿, 한 문장이면 그냥 문장.
- **한 불릿 = 한 사실**: `현재 → 목표`를 한 문장에 욱여넣지 않는다. 조건에 따라 결과가 갈리면 조건을 행으로 하는 표로.
- **나열은 4개부터 문장에서 뺀다**: 클래스·파일·옵션 이름을 넷 넘게 쉼표로 잇지 않는다. 독자가 개별 이름을 확인할 일이 있으면 표나 목록으로 분리하고, 범위 감만 필요하면 **기준 + 개수**로 압축한다 (예: "`Wrapper`를 구현하는 7개 클래스, 상속 포함 12개 타입").
- **반복은 서두로**: 여러 항목의 현재 상태가 같으면 앞에 한 번만 쓰고, 표에는 달라지는 것만 남긴다.
- **성격이 다르면 블록을 나눈다**: 동작·적용 범위·제외 대상·무변경처럼 종류가 다른 정보를 한 불릿 목록에 섞지 않는다.

Rules: **Description은 서술체**(읽는 사람이 이해하기 쉽게, 한두 문단), **그 외 섹션은 개조식**(한 항목 한 줄, 핵심만). 빈 섹션은 생략하지 말고 `없음` 또는 `(확인 필요)`로 남긴다 (`Additional Information`만 정보 없으면 생략 가능). em-dash(`—`)는 쓰지 않는다: 쉼표·콜론·괄호·마침표로 대체.

## Step 4: Output

Print the draft in one copy-paste block: the English title line, then the Korean body. Do not post to JIRA: tell the user to paste it into a new CUBRID JIRA issue.

(If CUBRID JIRA renders wiki markup rather than Markdown in your project, convert `## X` to `h2. X` and `- ` to `* ` when pasting.)
