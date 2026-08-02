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
<왜 이 작업을 하는가(무엇이 문제/필요인가) -> 이 PR이 무엇을 하는가 -> 그렇게 한 근거. (필수)>

## Implementation
<이 PR을 구현하기 위해 어떻게 했는가. (선택: 없으면 N/A)>

## Remarks
<주의사항, 후속 작업, 리뷰 포인트 등. (선택: 없으면 N/A)>
```

**도식(선택)**: 구조·흐름 변화가 말로만 설명하기 복잡하면 Implementation에 `mermaid` 코드블록을 넣어도 좋다(GitHub PR 본문이 자동 렌더, 노드는 텍스트에 맞춰 자동 크기 조정이라 짤림 없음). 꼭 필요할 때만 간결하게.

**읽히게 쓰기 (형태 규칙)**: 리뷰어가 훑어서 파악할 수 있어야 한다. 형태는 취향이 아니라 **담는 데이터의 모양**이 정한다.

- **표 / 불릿 / 문장 고르기**: 같은 항목을 여러 대상에 반복하면 **표**(열: 대상 · 현재 · 변경 후), 서로 다른 사실 2~3개면 불릿, 한 문장이면 그냥 문장.
- **한 불릿 = 한 사실**: `현재 → 목표`를 한 문장에 욱여넣지 않는다. 조건에 따라 결과가 갈리면 조건을 행으로 하는 표로.
- **나열은 4개부터 문장에서 뺀다**: 클래스·파일·옵션 이름을 넷 넘게 쉼표로 잇지 않는다. 독자가 개별 이름을 확인할 일이 있으면 표나 목록으로 분리하고, 범위 감만 필요하면 **기준 + 개수**로 압축한다 (예: "`Wrapper`를 구현하는 7개 클래스, 상속 포함 12개 타입").
- **반복은 서두로**: 여러 항목의 현재 상태가 같으면 앞에 한 번만 쓰고, 표에는 달라지는 것만 남긴다.
- **성격이 다르면 블록을 나눈다**: 동작·적용 범위·제외 대상·무변경처럼 종류가 다른 정보를 한 불릿 목록에 섞지 않는다.

Rules: **Purpose is required.** Implementation and Remarks are optional and become `N/A` when there is nothing to say. **톤**: 오픈소스 IT 개발자가 PR에 쓰듯 담백하고 자연스럽게. 공식 문서투·격식체·한자어 남발·수동태·논문투를 피하고, 흔한 개발 용어(오버로드, 커밋, 롤백, 엣지 케이스 등)는 억지로 번역하지 말고 그대로 쓴다. **문체**: 짧은 문장(한 문장 한 생각), Purpose는 **문제 -> 한 일 -> 근거** 흐름. 거창한 표현(예: "~를 처음 연다")·과한 압축은 피하고, 전문용어는 꼭 필요한 것만 풀어 쓴다. 핵심만. em-dash(`—`)는 쓰지 않는다: 쉼표·콜론·괄호·마침표로 대체.

## Step 5: Output

Print the title line and the body as one copy-paste block. **Do not create the PR.** If the user wants to open it, show (and run only when they explicitly ask) the command:

```bash
gh pr create --base <base> --title "<title>" --body "<body>"
```
