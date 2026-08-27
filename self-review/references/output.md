# Evidence bar, tag minting, and the output template

## 근거 기준

Inherited from the **review-triage** skill and applied inward, to your own work instead of to someone else's comments.

Every finding needs at least one checkable thing, **quoted in the output**:

- the code itself, as `path/File.java:L69-72`, with the line numbers taken from a real read
- a manual or spec statement (**cubrid-manual**, **cmt-manual**, the JDBC/JPA spec) or the issue's own words
- a run you actually performed: a build, a test, `javap -p`, a `grep -c` with its count, a query

These are **not** evidence: "일반적으로 그렇다", "보통 이렇게 씁니다", 기억, 관례 with no sibling file cited, and reasoning that sounds right but was never checked.

Additional rules for this skill:

- **Counts come from a command whose text you show.** Never estimate a count, and never round one.
- **Refute yourself first.** Look for what would make the finding wrong: an existing guard, a test that already covers it, a call site that cannot reach the state, a fix already present elsewhere in the change set. A finding survives only if you failed to refute it.
- **A suggested patch is a hint unless you compiled it.** Label it. A finding can be entirely right while its proposed line does not compile (a helper whose type is package-private, for instance): say which part you verified and defer the rest to the implementation.
- **Unverifiable goes out as 확인필요**, with the exact question and the command that would settle it. Never a guess, never a hedged claim dressed as a finding.
- **Kill your own suggestion out loud** when it conflicts with a constraint the work declared. A self-refuted finding, reported as such, is what buys credibility for the rest.

## Tags come from this work's contract, not from a taxonomy

Mint the tag vocabulary per change, before writing any finding:

1. **Enumerate the contract clauses**, in priority order: (a) the issue's AC / Specification Changes / Implementation notes; (b) the rules, exclusions, counts, and design goals the author declared, which at this stage live in the commit subjects and in what the author told you, not in a PR body; (c) the de facto conventions of adjacent code, used only when (a) and (b) are silent.
2. **The tag names the clause in the clause's own words**, never a category word substituted for the clause's own noun and never a translation of it. A numbered clause is tagged by its number (`[변환 규칙 3 미적용]`). A counted clause is tagged by its count and by which member failed (`[AC "핸들러 4개" 중 4번째]`). An unnumbered, uncounted clause is tagged by the distinguishing phrase the clause itself uses, quoted. If the tag ends up containing no word from the clause, you have drifted back into a taxonomy and the reader can no longer tell which promise the finding is about.
3. **The tag names the failure mode against that clause**, not the code smell: 미적용 (declared, not applied), 누락 (in scope, not done), 갭 (required, not verified).
4. **Findings with no clause get an invariant tag** and must be labelled as the reviewer's own addition: `[전제 확인]`, `[실패 경로 자원 누수]`, `[사각지대]`, `[중복]`. Keep this set small.
5. **Append a modifier after `·` or `,`** carrying disposition or evidence: severity (`·경미`), counted scope (`, 같은 파일 안 7곳`), framing (`, 파일 안 일관성`), rarity (`, 유일 사례`), ownership (`, 판단 사항`). The modifier is where calibration lives and it is what stops nine findings from reading as nine blockers.
6. If the work earns no tags at all, because nothing declares anything, that absence is finding #0.

## Output

Ranked by severity inside buckets, buckets ordered by authority. No em-dash anywhere in the output: use commas, colons, parentheses, periods. Tone is plain and direct, an open-source reviewer's voice, no praise openers.

**This skill posts nothing and edits nothing.** No comment, no reply, no commit, no push, no file change, no formatter run. It reports, and the author decides. Once the PR exists and other people have commented on it, **review-triage** is the skill for that direction. Use **commit** for the recorded decision and **ci-check** for the run.

### Coverage is a required field, not a flourish

Every review declares what it actually opened, as a triple: **전체 정독 파일 수 / 표본 대조 파일 수 / 열지 않은 파일 수**. A review without it cannot be checked, because no reader can tell whether a claim like "이 변경 안에서 유일한 지점" rests on all 45 changed files or on 17 sampled ones. State the triple even when the answer is flattering.

- **The three numbers partition the change set** and must sum to the file count in the heading. Classify each changed file exactly once: **전체 정독** = opened and read end to end, **표본 대조** = opened only around the changed lines, or reached by grep or a pattern search, never read whole, **열지 않은** = not opened in this review at all.
- **Reads outside the change set get their own separate count** (siblings consulted for convention, spec or manual pages, driver source, build output). They never promote a change-set file into 전체 정독.
- **The numbers come from reads you can name.** Under fan-out the triple is the union of the agents' `commands_run`, never the orchestrator's own reads alone and never an estimate. A file you cannot show a read for is 열지 않은, whatever you believe an agent did with it.
- **A scope claim is admissible only inside the coverage it stands on.** Any claim quantifying over the change (유일 사례, 전부 변환됨, 잔존 지점 없음, 이 파일에만 있음, and every count carried in a tag or a modifier) requires one of two things: every file that could hold the pattern is in 전체 정독, or a repo-wide command whose text and output you show. With neither, restate the claim at the scope you actually covered ("표본 17개 파일 기준") or drop it. This binds 통과 확인 as much as the finding buckets: a passing verdict may not claim coverage the triple does not support.
- **Mirror the sampled and unopened numbers into 정적 리뷰 한계**, naming the files or the class of files left unread and the command that would close the gap. That section is where the reader learns what the finding list structurally could not have seen. A review that read everything states its N / 0 / 0 there too, since that is what makes its scope claims usable.

### Korean output template

Every finding entry carries the same fields, in this order, and a missing field means the finding is not finished: **제목** (the tag plus a one-sentence claim, a claim and not a topic), **근거(계약)** (the clause quoted verbatim, or the invariant named as your own addition), **근거(코드)** (`파일:행` from a read you performed), **실측** (the command and its output, mandatory whenever the claim carries a number or a scope word such as 유일/전부/잔존), **수정안** (paste-ready lines plus their compile status, or an explicit "none"), **대안** (what recording the decision would close, whenever the gap could be deliberate), **비용/심각도**. Drop a field that does not apply; never leave it filled with placeholder text. The worked entries below show the shape only, and their subject matter is arbitrary: fill them from the change in front of you.

````markdown
## 셀프 리뷰: <대상> (파일 N개, +A/-B, 미커밋 포함)

**리뷰 방법**: <실제로 한 것. 예: 이슈 AC 5개 절 원문 대조, 인접 파일 5개 관례 도출, `<빌드 명령>` 실행, 병렬 에이전트 5개(계약·전제·의미·사각·관례)>
**커버리지(필수)**: 전체 정독 <12>개 / 표본 대조 <17>개 / 열지 않은 <3>개 = 변경 파일 <32>개. 변경 밖 참조 <5>개(<인접 파일 4, 구현 소스 1>).
**계약 출처**: <Jira <ISSUE-KEY> (AC / Specification Changes / Implementation), 커밋 제목 8개. PR 본문 없음.>

### 통과 확인
- <구체적으로 무엇을 확인했고 왜 맞는지. 예: 만료·폐기·미발급 토큰 세 경우 모두 401 로 단언, 만료 검사가 서명 검사보다 먼저 도는 점 pin, `TokenFilterTest.java:L120` 확인>

### 계약 위반 (푸시 전 반영 권장, N건)

#### 1. [스펙 갭, AC "핸들러 4개" 중 4번째] <한 문장 주장>
- **근거(계약)**: AC 원문 "<그대로 인용>"
- **근거(코드)**: `path/File.java:L69-72`
- **실측**: `git grep -ln 'implements RequestHandler' src/` -> 4건, 이번 변경이 백오프를 적용한 곳은 3건
- **수정안**:
  ```java
  withBackoff(retryPolicy, () -> handle(req));
  ```
  (컴파일 미확인: `withBackoff` 가 package-private 이라 호출 위치에서 접근 가능한지 확인이 필요합니다.)
- **대안**: 이번 범위에서 빼려면 사유를 커밋 메시지 또는 이슈에 남기면 이 항목은 닫힙니다.
- **비용/심각도**: 낮음 / 중간

### 리뷰어 자체 발견 (계약에 없음, N건)

#### 2. [실패 경로 자원 누수, 같은 원인 2곳(41·75행)] <한 문장 주장>
- **근거(코드)**: 구 코드는 성공하든 예외가 나든 `finally` 에서 임시 디렉터리를 지웠는데, 람다로 옮기면서 정리가 성공 경로에서만 실행됩니다 (`MigrationRunnerTest.java:L41`).
- **수정안**: `try { runner.run(script); } finally { deleteRecursively(tmpDir); }` (컴파일 미확인)
- **비용/심각도**: 낮음 / 낮음 (실패 경로 한정)

### 사각지대 (작성자가 안 적어둔 케이스, N건)

#### 3. [사각지대, 멀티바이트] <한 문장 주장>
- **트리거 입력**: <이 값을 넣으면 깨집니다>
- **근거(매뉴얼)**: <매뉴얼 문장 인용 + 링크>
- **현재 상태**: 코드에도 테스트에도 이 입력을 배제하는 장치가 없습니다 (`path/File.java:L88`).

### 확인필요 (정적 리뷰로 판정 불가, N건)

#### 4. [전제 확인] <무엇이 불확실한지>
- **질문**: <작성자에게 물을 정확한 질문>
- **확인 명령**: `javap -p -classpath <resolved.jar> <FQCN> | grep '<멤버명>'`

### 선택 반영 (관례 기준, N건)

> 저장소에 문서화된 표준은 없고, 인접 파일(<파일 목록>) 관례 기준입니다. 반영 여부는 선택입니다.

- **[스타일, 파일 안 일관성]** 이 블록(`L69-72`)만 공백 3칸이고 파일의 나머지와 인접 테스트는 탭입니다.

### 정적 리뷰 한계 (실행으로만 확인 가능)
- **커버리지 기준**: 위 발견 목록은 전체 정독 <12>개 파일 기준입니다. 표본 대조 <17>개(<파일 또는 디렉터리>)는 변경된 줄 주변만 봤고, <3>개(<파일 목록>)는 열지 않았습니다. 이 범위 밖의 지점은 목록에 잡히지 않습니다.
- 표본 범위를 닫는 명령: `git grep -n '<패턴>' -- <경로>`
- <실행해야만 확인되는 항목을 구체적으로 나열. 예: 이번 변경이 새로 고정한 상수 <N>개(<상수명 목록>)가 실제 런타임 값과 일치하는지>
- 확인 명령: `<명령>`

### 판단 요약
- 계약 위반 N건은 푸시 전 반영을 권장합니다.
- 자체 발견 N건 중 <M>건은 심각도가 낮아 선택입니다.
- 선택 반영 N건은 관례 기준이라 근거가 가장 약한 묶음입니다.

이 리뷰는 보고만 합니다. 코드 수정, 포맷 적용, 커밋, 게시는 하지 않습니다.
````

If the conclusion is that the change is **directionally wrong** (right details, wrong layer or wrong mechanism, or built on a contract clause that is itself wrong), that verdict goes above every bucket as its own section, with what you would do instead and what evidence would settle it. If **nothing was found**, keep 통과 확인 and 정적 리뷰 한계 and drop the finding buckets: a clean result is credible only when it is specific.
