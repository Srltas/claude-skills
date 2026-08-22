---
name: pr-draft
description: "Draft a pull request (title + body) from the current branch's commits and diff. The title is [XXX-0000] plus a concise, easy-to-understand English summary (the key is taken from the branch name); the body is Korean in three sections: Purpose (required, why this PR exists), Implementation (optional, how it was built), Remarks (optional, notes). Optional sections become N/A when empty. Passing `--tc` switches to a compact TC template for CMT (cubrid-migration) unit-test PRs only, summarized in a few lines with real counts (@Nested groups, tests run, `// DEFECT:` markers, suite before -> after); it is never selected automatically. Produces a copy-paste draft only; it does not create the PR. Triggers on phrases like 'PR 초안 작성', 'pr-draft', '이 브랜치 PR로 정리', 'draft a PR', 'PR 제목이랑 본문 만들어줘'."
argument-hint: "[base-branch] [--tc for CMT unit-test PR]"
---

# Draft a pull request

Turn the current branch into a ready-to-paste PR title and body, grounded in the real commits and diff. Draft only: it does not create the PR.

## Step 1: Context and changes (one call)

```bash
bash <skill-base-dir>/assets/pr_context.sh [base-ref]
```

Prints the branch, the issue key taken from the branch name, the resolved base, the commit list, the changed-file stat, and how many non-test files changed. Pass a base only when the user names one (`--tc` is a body-template flag, not a base).

It resolves the base from the remote's own default branch, so a `develop`-based CUBRID repo works as well as a `main`-based one. If it reports no key, ask the user for it; if it cannot find a base, ask.

Then read the key hunks of the diff (`git diff <base>...HEAD -- <path>`) where you need detail. Draft from what actually changed, not from memory.

## Step 2: Title

`[XXX-0000] <summary>`

- `[XXX-0000]` is the key from Step 1 (e.g. `[HHH-20527]`, `[CBRD-1234]`).
- `<summary>` is concise **English** using easy words anyone can understand, one line, no trailing period.

## Step 3: Body (Korean, three sections)

There are two body templates, and the default one is the default.

- **Default**: use it unless told otherwise.
- **TC template**: for **CMT (cubrid-migration) unit-test PRs only**. Select it only when the user passes `--tc` or says so explicitly ("TC PR", "단위 테스트 PR"). **Never switch to it just because the diff is test-only**: on another repo's test PR it would inject CMT-only wording (the Tibero convention, `-Punit-test`).

When `--tc` is given, confirm the target really is CMT. Either check is enough:

```bash
git remote get-url origin | grep -q cubrid-migration
grep -q "<id>unit-test</id>" pom.xml
```

If it is not CMT, do not use the template: ask the user first (that repo has no `mvn -B -Punit-test test` and no Tibero convention). The other way round, if `--tc` was not given but this looks like a CMT test-only PR, do not switch on your own: ask in one line whether to use the TC template.

### Default

```markdown
## Purpose
<왜 이 작업을 하는가(무엇이 문제/필요인가) -> 이 PR이 무엇을 하는가 -> 그렇게 한 근거. (필수)>

## Implementation
<이 PR을 구현하기 위해 어떻게 했는가. (선택: 없으면 N/A)>

## Remarks
<주의사항, 후속 작업, 리뷰 포인트 등. (선택: 없으면 N/A)>
```

### TC template (CMT unit tests)

```markdown
## Purpose
<대상 클래스가 무엇이고 왜 테스트가 필요한가 (2~3줄)>
<레거시에서 회수했는지, 신규인지. 프로덕션 변경 여부>

## Implementation
- <테스트 클래스명> 추가: <@Nested 그룹 수>, 실행 <N>개
- 양식은 기존 Tibero 테스트를 따름
- <특이사항 있으면 한 줄>

## Remarks
- characterization test. 결함 <N>건은 `// DEFECT:` 표시 (별도 이슈)
- `mvn -B -Punit-test test`: <이전> -> <이후>, 실패 0
- <후속 PR 언급>
```

**Keep it very short.** One line per bullet, numbers first. Do not enumerate what each test checks: the reviewer reads the code. Drop a line that does not apply (특이사항, 후속 PR) instead of filling it with `N/A`.

**Get the numbers for real** (never guess):

```bash
grep -c "@Nested" <test-file>       # @Nested group count
grep -c "// DEFECT:" <test-file>    # defect markers
mvn -B -Punit-test test             # read "Tests run: N, Failures: 0"
```

`실행 <N>개` is the count for **this test class**; the `<이전> -> <이후>` in Remarks is the **whole suite**. Parameterized tests expand, so never count `@Test` occurrences: read `Tests run` from an actual run. Get the "before" number by running the same command on the base, or from the previous PR.

**Diagram (optional)**: when a structural or flow change is hard to explain in words, a `mermaid` block in Implementation is fine (GitHub renders it in the PR body, and nodes auto-size to their text so labels never clip). Only when it genuinely helps, and keep it small.

**Write it to be read (shape rules)**: a reviewer should get it by skimming. Shape is not a matter of taste: **the shape of the data decides it.**

- **Table / bullets / sentence**: the same field repeated across several targets is a **table** (columns: 대상 · 현재 · 변경 후); two or three unrelated facts are bullets; one fact is just a sentence.
- **One bullet = one fact**: never cram `현재 → 목표` into a single sentence. When the result differs by condition, make the condition the row of a table.
- **Pull a list of four or more out of the sentence**: do not chain more than four class/file/option names with commas. Split them into a table or list when the reader needs each name; compress to **기준 + 개수** when they only need the scope (e.g. "`Wrapper`를 구현하는 7개 클래스, 상속 포함 12개 타입").
- **Say a shared fact once, up front**: when several rows share the same current state, state it once before the table and leave only what differs inside it.
- **Split blocks that differ in kind**: do not mix behavior, scope, exclusions, and no-change into one bullet list.

Rules: **Purpose is required.** Implementation and Remarks are optional and become `N/A` when there is nothing to say. **Tone**: write like an open-source developer writing a PR, plain and natural. Avoid 공식 문서투, 격식체, 한자어 남발, 수동태, 논문투, and keep the usual dev loanwords as they are (오버로드, 커밋, 롤백, 엣지 케이스). **Style**: short sentences, one thought each; Purpose follows **문제 -> 한 일 -> 근거**. Skip grand phrasing (e.g. "~를 처음 연다") and over-compression, and spell out only the jargon that needs it. Essentials only. No em-dash (`—`): use commas, colons, parentheses, periods.

## Step 4: Output

Print the title line and the body as one copy-paste block. **Do not create the PR.** If the user wants to open it, show (and run only when they explicitly ask) the command:

```bash
gh pr create --base <base> --title "<title>" --body "<body>"
```
