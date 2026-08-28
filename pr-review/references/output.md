# Output

**This skill posts nothing and edits nothing.** It hands the user a report. They decide whether any line of it is worth posting, and they post it themselves. No `gh pr review`, no `gh pr comment`, no `gh api ... /comments`, no edits to the reviewed code, not even in the scratch worktree. Show the posting command only if the user asks for it.

The report is written in Korean, addressed to a colleague, and formatted so the user can copy any single finding into a PR comment as-is. No em-dash: use commas, colons, parentheses, periods.

## The survival test

Every finding is judged before it ships by asking one question: **what would review-triage rule this?** That sibling skill judges incoming review comments as 타당 / 부분 / 부당 / 범위 밖 / 취향 / 확인필요, on evidence rather than on the reviewer's authority.

- Would be ruled **부당** (wrong, misread, already handled): delete it, or demote it to a 질문 that asks instead of asserts. A finding that comes back 부당 costs the author time and costs you the credibility that makes the next twenty findings land. **부당 하나가 무발견보다 나쁩니다.**
- Would be ruled **부분** (the observation lands, the suggestion does not): this is the likeliest ruling on any finding that ships a `힌트(미검증)`, because the diagnosis can be right while the patch is wrong. Split it yourself before the author has to, in the finding itself: say which part is grounded (the 근거 line) and which part is the unverified suggestion, so the author can take the first without arguing about the second. 지적과 제안을 한 덩어리로 내면 부분이 부당처럼 읽히고, 맞는 지적까지 같이 버려집니다.
- Would be ruled **범위 밖**: it does not belong in 결함. Move it to the 범위 밖 section, marked as a follow-up.
- Would be ruled **취향**: keep it only if a project convention backs it (tree locality or file locality, see `contract.md`), and then it is 판단 사항, not 결함.
- Would be ruled **확인필요**: that is the author saying "I cannot tell what you mean". Write it as a 질문 with the specific thing you could not establish.

Apply 범위 밖 to yourself with the same severity you would apply it to someone else. A correct observation about something this PR never set out to do is a follow-up suggestion, clearly separated, never mixed into the defect list.

## Report skeleton

```
## PR #1629 리뷰 (CUBRID/cubrid-testcases-private)

- 계약 출처: PR 본문(변환 규칙 1~5, 제외 목록 3건), CUBRIDQA-1234 완료 조건(사용자 붙여넣기)
- 커버리지: 변경 파일 12개 중 12개 전문 확인 (샘플링 없음)
- 작업 트리: refs/pr-review/1629 워크트리(스크래치). 사용자 저장소의 체크아웃/브랜치는 건드리지 않았습니다.
- 이 보고서는 어디에도 게시하지 않았고, 코드도 수정하지 않았습니다. 올릴지 말지는 직접 정하시면 됩니다.

### 결함 (2건)
### 판단 사항 (1건)
### 범위 밖 / 후속 제안 (2건)
### 질문 (3건)
```

**Coverage line is mandatory.** The user requires that every changed file is read in full, and the line is the proof:

- The denominator is the changed-file count printed by `fetch_pr.sh`, not the number of files anyone happened to open.
- `변경 파일 12개 중 12개 전문 확인 (샘플링 없음)` when complete.
- When a file genuinely could not be read in full (binary, generated, several MB), name it and say why, and mark every finding in that file as reduced confidence: `변경 파일 12개 중 11개 전문 확인, testdata/dump.bin은 바이너리라 미확인`.
- Never round up. If it is 11 of 12, the line says 11.
- **Coverage is per pass, not per agent.** A file that no agent carrying pass P read in full is not covered for pass P, and the line says so: `변경 파일 12개 중 12개 전문 확인, 단 관례 대조(패스 9)는 java 8개만 대조`. Never union partial per-agent lists into a full-coverage claim.
- When the size gate in SKILL.md Step 3 applied, the header carries the agreed scope **instead of** a full-coverage claim, and names what was left out: `합의 범위: 변경 파일 120개 중 운영 코드 34개만 전문 확인 (사용자와 사전 합의), 생성 파일·테스트 데이터 86개는 미확인`.

The 계약 출처 line carries the 계약 결손 notice from `contract.md` when no contract was available, and then the report header also says the whole thing runs at reduced confidence.

## The four sections are hard-separated

Never blend them. The separation is the thing that makes the defect list trustworthy.

| 절 | 뜻 | 넣기 위한 조건 |
|----|----|---------------|
| **결함** | 계약 위반이거나 동작이 틀림 | 근거가 file:line, 스펙/매뉴얼 문장, 또는 실제 실행 결과. 왜 그렇게 되어 있는지(이력)까지 확인함 |
| **판단 사항** | 어느 쪽도 맞고 작성자가 정할 문제 | 양쪽 선택지와 각각의 결과를 쓸 수 있음 |
| **범위 밖 / 후속 제안** | 관찰은 맞지만 이 PR이 하기로 한 일이 아님 | 이번에 반영할 필요가 없다고 명시 |
| **질문** | 근거를 못 세웠거나 의도를 모름 | 단정하지 않고 물어봄. 무엇을 확인 못 했는지 밝힘 |

Anything you cannot ground goes to **질문**. That is the default, not the failure case: you do not know why this code is the way it is, and asserting a defect you have misread is the characteristic failure of reviewing other people's work.

## Ranking

결함 is ordered by severity, top first. The other three sections are ordered by file path.

1. 동작이 틀리거나 데이터가 깨짐 (잘못된 결과, 통과해서는 안 되는 테스트가 통과)
2. 선언한 계약 위반 (PR 본문 규칙 미이행, 이슈 완료 조건 미충족, 선언한 카운트와 실제 불일치)
3. 커버리지 누락 (집합의 미포함 멤버, 변환 안 된 잔여 사이트)
4. 유지보수성 (이름과 동작 불일치, 파일 내부 규칙과 어긋난 블록)

## Anatomy of a finding

```
### [태그] path/to/File.java:142
<관찰: 한두 문장. 합법이거나 의도적일 수 있음을 먼저 인정하고 나서 지적>
- 근거: <file:line, 스펙/매뉴얼 문장, 또는 실제로 돌린 결과>
- 이력: blame/log 결과 한 줄, 또는 "해당 없음(신규 코드)"
- 반증 시도: 무엇으로 이 지적을 죽여보려 했고 왜 안 죽었는지
- 비용: <고치면 얼마나 드는지. 한 줄인지, 픽스처가 필요한지>
- 힌트(미검증): <제안 코드>
```

**이력** and **반증 시도** are Pass 2's output, and they are **required on every 결함**, with no exception: a defect with no line for either was filed without checking why the code is the way it is, which is the exact failure this skill exists to prevent. `이력` quotes the blame or log result on those lines, or says `해당 없음(신규 코드)` when the lines are new in this PR, and that is a finding, not a blank. `반증 시도` names what you tried in order to kill your own finding (the sibling that turned out to differ, the prior PR that turned out to settle something else, the exclusion list that turned out not to name this file) and why it survived. 판단 사항 and 범위 밖 carry 이력 whenever the history bears on the choice; in 질문 the 확인한 것 / 확인 못 한 것 lines already carry the same content.

**태그** is derived from *this* PR's own contract ledger (`contract.md`), not from a fixed taxonomy. It quotes the contract's own words: `[변환 규칙 3 미적용]`, `[제외 목록 불일치]`, `[선언 카운트 7 vs 실제 8]`, `[스펙 갭]`. If the PR declared no rules, no such tag exists, and a plain one (`[잔여 사이트]`, `[이름과 동작 불일치]`, `[파일 내 규칙 불일치]`) is used instead. Do not manufacture a rule number the body never wrote.

**file:line** is mandatory on every finding in every section, because the user posts these themselves and GitHub needs the anchor. Use the path as it appears in the PR, and the line number in the head revision.

**비용** is what made the corpus land: the author fixed exactly the item that was described as cheap. Say which it is. "인자 하나 추가, 한 줄입니다" and "이건 SP 픽스처가 필요해서 이번에 넣기엔 큽니다" produce different and correct decisions.

**힌트** is labelled as a hint, always, unless you actually compiled it. One expert's suggested line did not compile because the class was package-private: the finding was right and the patch was wrong. Label honestly:

- `힌트(미검증):` you wrote it but did not compile it.
- `확인함(javac):` you compiled it, and you say against what: `확인함: javac -cp lib/cubrid-jdbc.jar 로 컴파일됨`.
- If you did not verify the symbol exists in the artifact the build resolves, do not suggest calling it.

## Evidence bar

Every 결함 quotes at least one of these:

- **file:line** in the tree (including a sibling file that establishes the convention, or `git blame` output that establishes the history).
- **A spec or manual statement**: the CUBRID manual, the JDBC/JPA spec, the test framework's documented behaviour. Quote it, do not paraphrase from memory.
- **A run you actually performed**: a compile, a test, a query, `javap` output. Say the command.

These are **not** evidence: "일반적으로 그렇다", "보통 이렇게 씁니다", 기억, 습관, 다른 프로젝트에서 본 것. A claim resting on those is not downgraded to a weaker defect. It becomes a **질문**, or it is dropped.

Specific traps that produce 부당 rulings, each answered by a step in `contract.md`:

- Asserting a symbol exists because it exists in the newest upstream source, when the checked-in jar predates it. Compile against the resolved artifact first.
- Calling a shape wrong when `git blame` shows it was deliberately made that way, and the reason still holds.
- Calling an omission a gap when the PR body's exclusion list already names it. If the exclusion has a stated reason, there is no finding. If it has none, the finding is "사유를 본문에 적어주세요", not "빠졌습니다".
- Matching a declared count and concluding the set is complete.
- Reporting a semantic delta (an assertion that got stronger, a previously swallowed exception now mandatory) as a defect when it is the point of the PR. It is a defect only if it creates a failure elsewhere, and then you name where.

## Korean templates

Written to be handed to the author as-is. Colleague's voice: acknowledge that the code is legal or intentional before pointing at it, say what a fix costs, and grant the exception yourself when the author plausibly had a reason.

### 결함

```
### [변환 규칙 3 미적용] src/test/java/com/cubrid/FooTest.java:142
지금 코드도 동작에는 문제 없고 테스트도 통과합니다. 다만 PR 본문 변환 규칙 3
("모든 assertEquals에 메시지 인자를 넣는다")을 이 블록만 안 따랐습니다.
- 근거: 같은 파일 88, 104행은 메시지를 넣었고 142행만 2인자입니다.
- 이력: 142행은 이번 PR에서 새로 들어온 줄이라 이전 이력은 해당 없음(신규 코드)입니다.
- 반증 시도: 이미 다른 데서 처리됐나부터 봤습니다. 같은 파일과 헬퍼(TestSupport.java)에
  메시지를 자동으로 붙이는 래퍼가 있는지 찾았지만 없고, 142행은 원본 assertEquals를 직접 부릅니다.
  그다음 이 블록만 예외로 두는 규칙이 있나 싶어 본문 제외 목록과 파일 내 주석을 봤는데
  둘 다 이 블록을 언급하지 않습니다.
- 비용: 인자 하나 추가라 한 줄입니다.
- 힌트(미검증): assertEquals("row count after insert", 3, rs.getInt(1))
  지적(규칙 3 미적용)은 88, 104행 대조로 확인했고, 위 한 줄은 컴파일 안 해본 제안입니다.
```

```
### [선언 카운트 7 vs 실제 8] src/test/java/com/cubrid/BarTest.java:1
본문에 "상속 클래스 7개 전부 변환"이라고 쓰셨는데, 트리에서 세어보니 8개입니다.
빠진 건 BazIT 하나입니다.
- 근거: rg -l 'extends AbstractFooTest' 결과 8건, 그중 BazIT.java만 이번 변경에 없습니다.
- 이력: git log 기준 BazIT.java는 def5678(2023) 이후 변경이 없고, 그 커밋에도 이번 변환에서
  빼야 할 이유는 없습니다.
- 반증 시도: 다른 데서 이미 커버되나부터 봤습니다. BazIT의 상위 클래스와 같은 패키지에
  이 검증을 대신하는 테스트가 있는지, 그리고 BazIT가 빌드·스위트에서 제외돼 있는지 확인했는데
  (pom.xml, surefire 제외 목록) 둘 다 아니고 BazIT는 실제로 실행됩니다.
  그다음 일부러 뺀 건가 싶어 본문 제외 목록 3건과 최근 머지된 같은 파일 PR을 확인했는데,
  BazIT를 언급한 곳이 없습니다.
- 비용: BazIT는 이미 setUp()에서 CUBRIDConnection을 들고 있어서(BazIT.java:41)
  다른 7개와 같은 형태로 두 줄이면 됩니다. 새 픽스처는 필요 없습니다.
- 힌트(미검증): 다른 7개와 동일한 형태
의도적으로 뺀 거면 본문 제외 목록에 한 줄만 적어주시면 됩니다.
```

### 판단 사항

```
### [판단 사항] src/test/java/com/cubrid/FooTest.java:77
둘 다 맞는 선택이라 정하시면 됩니다.
지금처럼 두면 실패 시 기대값이 안 보이고, 메시지를 넣으면 CI 로그만 보고 원인을 압니다.
대신 이 파일 나머지는 메시지가 없어서, 넣으면 이 블록만 튑니다.
```

### 범위 밖 / 후속 제안

```
### [범위 밖 / 후속] src/test/java/com/cubrid/QuxTest.java:30
이 PR 범위는 아닙니다. 이번에 반영 안 하셔도 되고, 후속으로만 남깁니다.
QuxTest는 아직 예전 형태인데, 이 PR이 하기로 한 대상 목록에 없습니다.
- 비용: 별도 PR 하나 정도입니다.
```

### 질문

```
### [질문] src/test/java/com/cubrid/BarTest.java:57
이전에는 setUp()에서 SQLException을 잡아서 삼켰는데 이번에 그대로 던지게 바뀌었습니다.
의도한 변경이 맞는지 확인 부탁드립니다.
- 확인한 것: git blame 기준 이 catch는 abc1234(2021)에서 들어갔고, 커밋 메시지에
  이유가 없습니다.
- 확인 못 한 것: 그때 어떤 환경에서 이 예외가 났는지까지는 못 찾았습니다.
의도한 거면 이대로 두시면 됩니다.
```

### 마무리 (보고서 끝)

```
게시는 안 했습니다. 코드도 안 건드렸습니다.
위 항목 중 올릴 것만 골라서 직접 붙여넣으시면 됩니다.
결함 2건 중 첫 번째가 한 줄짜리라 그것만 올려도 이득이 큽니다.
```

If the PR is on an English-language upstream repository, keep the user-facing report in Korean and render only the selected finding text in English when the user asks for it.

## Before handing over

- [ ] Coverage line states the real numbers against the `fetch_pr.sh` changed-file count, per pass, and every file it claims was read in full. If the size gate applied, the header carries the 합의 범위 line instead and names what was left out.
- [ ] Every 결함 carries 태그, file:line, 근거, 이력, 반증 시도, 비용, and a labelled 힌트.
- [ ] Every 결함 has an 이력 line (blame/log, or `해당 없음(신규 코드)`) and a 반증 시도 line. No blanks, no "확인 안 함": a finding missing either did not run Pass 2 and does not ship.
- [ ] **Every 반증 시도 line searched for "이미 처리됨" specifically**, not only for "was this excluded on purpose". Name which of grounding-bar item 3 you looked for: the existing guard, the test that already covers it elsewhere, the caller that cannot reach that state, or the type that rules the value out. A line that only asked about the author's intent has not run the search that catches the single most common 부당 ruling, and the finding ships as a 질문 until it has.
- [ ] Every 태그 traces to a row in the contract ledger, or is a plain tag because the PR declared no rules.
- [ ] Every finding survived the review-triage test. Anything that would come back 부당 is gone or is now a 질문.
- [ ] Every finding carrying a 힌트(미검증) says which part is grounded and which part is the unverified suggestion, so it cannot come back 부분 with the whole thing discarded.
- [ ] Nothing correct-but-out-of-scope is sitting in 결함.
- [ ] No 근거 rests on memory, habit, or "일반적으로".
- [ ] Every suggested patch says whether it was compiled.
- [ ] Nothing was posted. Nothing was edited. The user's branch is where it was.
