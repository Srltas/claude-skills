# Gathering the contracts (Step 1 in full)

The first act of a review is not "look for bugs". It is "write down what this change promised", because every finding must cite a promise, and the tag vocabulary is minted from these promises in their own words. Mid-work there is no PR body, so the promises are scattered across five sources. Collect them in this priority order and record each as a numbered clause you can quote verbatim. A0 comes before all of them and is not a promise source but a gate: it fixes *which implementation* the promises are being checked against.

## A0. SUT 해소: locate the implementation under review (gate)

Settle this before the contract sources, and before any pass is run or dispatched. A change under review is very often a test, a caller, a binding, a config, or a dialect that only means anything against an implementation that lives outside the repo you are reading. Every finding of the form "this set is incomplete", "this symbol does not exist in what you build against", "this error code is not what the implementation raises", "this behaviour differs from the version actually resolved" is not *weaker* without that implementation on disk: it is **unobtainable**. So this is a gate, and its output is recorded, not assumed.

Record three items, in your notes and verbatim in the packet every subagent receives.

**1. 구현 저장소 경로.** The tree that defines the behaviour the change asserts on or calls into, whenever that tree is not the repo you are reviewing (a driver, an engine, a server, a third-party library, another service). Resolve it mechanically, never by assumption: take a symbol the change uses that this repo does not define, and find the tree that does define it.

```bash
grep -hE '^import ' <changed files> | sort -u          # packages the change pulls in from outside
git grep -l 'class <Symbol>\b' -- .                    # empty result: the definition is external
git submodule status                                   # pinned sibling sources
```

Record the path plus its own revision (`git -C <path> rev-parse --short HEAD`, or the tag/branch), because "the implementation source" without a revision is not a citable authority.

**2. 해소된 의존 아티팩트와 빌드 식별자.** Not the newest checkout on disk, not what the IDE indexes: the artifact this tree actually compiles and runs against. Find it from the build's own resolution, then pin it with an id someone else can re-check.

```bash
# 무엇을 해소하는지는 빌드에게 묻는다 (gradle/maven, npm ls, pip show, go list -m 모두 같은 질문)
./gradlew -q dependencies --configuration testRuntimeClasspath | grep -i <artifact>
find <repo> -name '*.jar' -path '*lib*'                # 저장소에 커밋된 바이너리
shasum <repo>/<lib-dir>/<artifact>.jar                 # 재확인 가능한 식별자
unzip -p <jar> META-INF/MANIFEST.MF                    # version, build date
javap -p -classpath <jar> <FQCN> | head                # what the artifact truly exposes
```

If the source tree from item 1 and the artifact from item 2 are not the same build, the source tree has stopped being evidence for premise verification: report the divergence as its own finding, and verify every premise against the artifact, since that is what the test run and the build see.

**3. 미확보 시 리뷰 한계 한 줄.** Ask the user once for the path, naming what you need and why. If it does not arrive, write the limit literally, once in 정적 리뷰 한계 and again under every finding that depended on it:

> 구현체 미확보(<대상>): 소스 트리와 빌드 아티팩트를 확인하지 못해 열거·전제 검증을 수행하지 못했습니다. 이 리뷰의 근거는 이 저장소 내부로 한정됩니다.

A missing SUT downgrades passes 1, 2, and 3 to declared-scope-only, and that downgrade must be visible in the output rather than silently absorbed. Filling the gap from memory, from the symbol's name, or from how the API "usually" behaves is prohibited: absent the artifact, the honest output is 확인필요 with the command that would settle it.

## A1. The issue (highest authority)

Find the key from the branch and the commits (`assets/review_context.sh` already prints its best guess and says where it came from):

```bash
git rev-parse --abbrev-ref HEAD
git log --format='%s%n%b' <base>..HEAD | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | sort -u
```

Fetch it when the project is publicly readable (CBRD, TOOLS, APIS), via the **jira-fetch** skill:

```bash
bash ~/.claude/skills/jira-fetch/assets/fetch_jira.sh -o ./jira <ISSUE-KEY>
```

**CUBRIDQA is not reachable** (HTTP 401, internal-only). Do not attempt it and do not retry. Ask the user once, naming exactly what you need:

> CUBRIDQA-<번호> 는 자동으로 못 가져옵니다. 이슈의 **Acceptance Criteria / Specification Changes / Implementation / Definition of Done** 을 원문 그대로 붙여 주세요. 요약 말고 원문이 필요합니다 (지적할 때 그 문장을 그대로 인용합니다).

Copy the sections into your notes **verbatim**, as clauses `C1..Cn`, and type each one, because the type decides how it gets verified later. Type from the clause's own grammar, not from its subject matter: a digit or a size word makes it 개수, a plural or a category noun makes it 집합·범주, several properties conjoined in one sentence make it 표 행·논리곱, two independent axes make it 매트릭스, an if-then makes it 규칙, an "제외 / except / 단" carve-out makes it 제외, and whatever is left is 산문. One clause can carry two types (a counted set that is also a rule): record both and verify both, because satisfying one of them does not satisfy the other. The 예 column below is illustration only; the 검증 방식 column is the rule.

| 유형 | 예 | 검증 방식 |
|---|---|---|
| 개수 | "핸들러 4개", "호출 지점 24곳" | 소스에서 모집단을 전수 열거해 변경분과 차집합, 남은 원소를 `파일:행` 과 함께 보고 |
| 집합·범주 | "상속 클래스", "모든 구현체", "각 서브클래스", "관련 호출 지점" | 개수 절과 동일하게 처리: A4 외부 소스에서 전수 열거한 뒤 변경분과 차집합, 모집단 크기는 리뷰어가 직접 정했음을 명시 |
| 표 행·논리곱 | "400 응답 + 오류 코드 INVALID_RANGE + 메시지에 필드명 포함" | 절이 이어붙인 원자(타입/코드/메시지/상태/부수효과)로 쪼개 각 원자가 실제로 단언되는지 하나씩 확인, 하나라도 빠지면 그 절은 절반만 충족 |
| 매트릭스 | "인증/비인증 x 캐시 적중/미적중" | 두 축을 표로 그려 빈 칸을 지적, 축이 셋 이상이면 고정한 축과 그 값을 함께 적음 |
| 규칙 | "응답이 4xx 면 본문에 오류 코드까지 포함한다" | 술어로 바꿔 변경된 전 지점에 적용, 불성립 지점을 목록화 |
| 제외 | "이미 재시도 래퍼 안에 있는 호출은 제외" | 제외 문구를 문자 그대로 읽어 각 제외 지점이 정말 그 문구에 해당하는지 재확인, 제외 집합의 크기도 함께 보고 |
| 산문 | 배경 설명 | 근거로만 사용, 단독 지적 불가 |

**Enumeration is triggered by the set noun, not by the digit.** Any clause that names its target as a plural or as a category (구현체, 서브클래스, 상속 클래스, 호출 지점, 하위 타입, 관련 테스트, or any 모든 / 각 / 전부 / 나머지 quantifier) is a 집합·범주 clause and gets the 개수 treatment even though it contains no number: enumerate the population from the external source in A4, subtract what the change touched, and report the remainder. Because the clause supplies no number, you are the one fixing the population, so make it auditable: print 모집단 N, 변경 M, 차집합 N-M with the enumerating command and its output beside them, and name which A4 source N came from. A bare category noun with no enumerable source behind it is 검증 불가, declared as such in 정적 리뷰 한계; never settle it with a set you assembled from memory or from the diff itself (the diff is the thing being measured, so it cannot supply the yardstick).

If the issue and the code disagree, that is a finding of type "이슈 갱신 필요", not a defect. If the code follows a rule the issue never states, ask for the issue to be updated rather than the code reverted.

## A2. Branch commit messages (the stand-in for a PR body)

The author's own declarations live here mid-work. Read subjects **and bodies**:

```bash
base=$(git merge-base HEAD origin/develop 2>/dev/null || git merge-base HEAD origin/main)
git log --format='%h%n%s%n%b%n---' $base..HEAD
```

Treat every declarative sentence as binding, and pull out five kinds by name: declared rules, declared scope, declared exclusions, declared counts, declared deferrals. A count in a commit message is a claim you re-measure with your own command, never a number you copy forward into the review. A declared scope is checked in both directions: what falls inside it and was not done, and what falls outside it and was done anyway. A deferral ("나머지는 후속") closes a completeness finding only when it names what is being deferred; a bare "나머지" leaves the residue open and you report it. A commit that says "convert all X" while the tree still contains X is a completeness finding, and the commit message is the authority you cite.

Mid-work means the change is not only in commits. Gather all four layers, or you will review a subset and call it complete. `assets/review_context.sh` does this in one call; the equivalents by hand are:

```bash
git status --porcelain
git diff $base...HEAD > <scratch>/committed.diff
git diff --cached            > <scratch>/staged.diff
git diff                     > <scratch>/unstaged.diff
git ls-files --others --exclude-standard
```

Untracked files never appear in any diff and are the most common blind spot: read each one in full, since 100% of it is new code.

## A3. What the shape of the diff itself claims

With no body, the change still makes implicit promises. Write them down as clauses labeled `[추정 기준]` and confirm them with the user or disclose them as assumptions in the output. Never silently invent a contract and then fail the code against it.

- a mechanical rename, conversion, or format change claims **completeness**: every site, or a stated exclusion
- a new helper claims **all call sites converted**, and often "the old idiom is gone"
- a new test file claims **coverage of the unit it names**
- a new flag or option claims **both branches work**
- every function, test, and commit **name** claims a behaviour: read the name as the promise and the body as the evidence

Measure the change's own numbers yourself instead of trusting a summary:

Count the new form and the removed form separately: a sweep whose `+` count and `-` count disagree either converted something that was not the old idiom or left part of it behind, and that gap is a lead before you have read a single line.

```bash
grep -c '^+++ '            <scratch>/committed.diff   # 건드린 파일 수
grep -c '^+.*<새 관용구>'   <scratch>/committed.diff   # 새 형태가 들어간 줄 수
grep -c '^-.*<옛 관용구>'   <scratch>/committed.diff   # 옛 형태가 빠진 줄 수
```

Reconcile three ways: your count, any count in the commit messages, any count in the issue AC. Report matches as passing (this is what makes a reported mismatch credible) and mismatches as findings.

## A4. The external spec or source being implemented against (the enumeration authority)

A4 answers three question shapes, and nothing else answers them: **membership** (what the full population of the set a clause names is: which subclasses, which call sites, which endpoints, which config keys, which migration steps), **existence** (whether a symbol, constant, column, or option the change references is present in what the build actually resolves), and **requirement** (what the interface, spec, or manual obliges, as opposed to what the name suggests). Without A4, a 개수 or 집합·범주 clause cannot be checked at all, and reporting one as satisfied is a fabrication.

Pick the authority in this order and name in the output which one you used: the resolved artifact recorded in A0, then the pinned source tree, then the published spec or manual, then a generated listing (schema dump, route table, migration directory). Whichever it is, the enumerating command must print the population **and** its size, so the number that reaches the finding is the command's output and not your count of what you happened to notice.

```bash
grep -rln '<정의 표지>' <impl-src>/<pkg>/ | wc -l                  # 모집단 열거 + 크기
grep -rnE '^\s*(public )?class .*(extends|implements) <Base>' <impl-src>
javap -p -classpath <resolved.jar> <FQCN> | grep '<멤버명>'        # 아티팩트에 실재하는지
grep -oE '"[a-z_]+"[[:space:]]*:' <schema>.json | sort -u | wc -l  # 설정 키가 모집단인 경우
ls <migrations>/ | wc -l                                           # 디렉터리 자체가 모집단인 경우
```

Rules:

- Any symbol the change references that this repo does not define is verified against **the resolved artifact recorded in A0**, never against a locally newer checkout and never against the IDE. Then count all references, including ones already on the base branch, and say whether this change introduced the premise or only widened it.
- Code copied from upstream is diffed line by line against the named upstream version, and you enumerate what you compared (overload count, return value, message text, private helpers).
- For product behaviour, use the **cubrid-manual** or **cmt-manual** skill rather than memory.
- If the source tree or jar is not on disk, you are in the A0 미확보 case: ask once, carry the A0 limit line into the output, and mark every 개수 and 집합·범주 clause that depended on it 검증 불가. Do not guess the set.

## A5. Sibling conventions (only when A1 to A4 are silent)

Read 3 to 5 files nearest to the change: same directory first, then the module. `assets/review_context.sh` already prints an indentation table for the changed files and samples one untouched sibling.

```bash
ls <dir>
grep -c $'^\t' <sibling>.java ; grep -cE '^ {2,}' <sibling>.java
grep -hE '^import' <dir>/*.java | sort | uniq -c | sort -rn | head
```

Derive the de facto rule for indentation, imports (wildcard vs explicit, static-import habit), naming, assertion style, and file placement (what lives at a package root vs a subdirectory). Compare at two levels of locality: the new code against its neighbours, **and** the new block against the rest of its own file. Internal inconsistency inside one file is a real finding that formatter-style complaints miss.

Everything derived here is optional by construction. Say so in the output: "저장소에 문서화된 표준은 없고, 인접 코드 관례 기준입니다."

## Output of Step 1: the SUT record and the contract table

Step 1 has two outputs, and both gate the passes: nothing is run and nothing is dispatched until each exists. Produce them before reading the diff line by line, and pass both verbatim to every subagent in the fan-out, so all of them cite the same clause IDs and measure against the same build.

The SUT record (A0), three rows, no row left blank; an unresolved row is filled with the 리뷰 한계 line, which counts as filled:

```
| 항목 | 값 | 확인 방법 |
|---|---|---|
| 구현 저장소 | ~/src/<impl-repo> (main, 9f31c02) | git -C <path> rev-parse --short HEAD |
| 해소 아티팩트 | libs/<impl>.jar, sha 3c9d1a..., MANIFEST 4.2.0.118 | shasum, unzip -p META-INF/MANIFEST.MF |
| 소스-아티팩트 일치 | 아티팩트가 소스 tip 보다 이전 빌드, 전제 검증은 아티팩트 기준 | javap -p -classpath <jar> <FQCN> |
```

The contract table. One row per clause, and one row per silent source too: a source that yielded nothing gets a row saying so (`A1 없음`, `A4 미확보`), because a source that produced no clause and a source you never opened read identically once the table is the only record. 출처 pins the source so someone else can reopen it (issue key plus section, commit SHA, `[추정 기준]`, sibling path), 원문 is copied character for character and never paraphrased, 유형 comes from the clause-type table above, and 검증 방법 is written before it is run so an uncheckable clause is exposed here. The rows below show the shape, one per clause type; the subject matter is arbitrary.

```
| ID | 출처 | 원문 (그대로) | 유형 | 검증 방법 |
|----|------|--------------|------|-----------|
| C1 | PROJ-4210 AC | 재시도 가능한 상태 코드 전부에 백오프를 적용한다 | 집합·범주 | 스펙에서 재시도 대상 코드 전수 열거 후 변경분과 차집합 |
| C2 | commit 9d4e1a7 | 타임아웃 값은 설정에서 읽고 상수로 두지 않는다 | 규칙 | 변경된 전 지점에 술어 적용, 불성립 지점 목록화 |
| C3 | [추정 기준] diff 형태 | 동일 관용구를 전부 변환 | 개수 | 변경 전 패턴을 파일/모듈 grep, 제외 규칙 차감 후 잔여 보고 |
| C4 | 인접 파일 관례 | 들여쓰기 탭 | 산문 | 선택 사항으로 표기 |
```

Then mint the tag vocabulary: one tag per clause, phrased in that clause's own words, naming the failure mode against it (미적용 = declared but not applied, 누락 = in scope but not done, 갭 = required but not verified). Findings that match no clause get an invariant tag and must be labelled as your own addition (`[컴파일 전제 확인]`, `[실패 경로 자원 누수]`, `[중복 - 판단 사항]`); keep that set small. See `references/output.md` for the full minting rules.

**If the table contains no A1 and no A2 rows, that is finding #0**, reported first: 리뷰 기준이 없습니다. With no issue clause and no declared rule, the only available authorities are the inferred claims and taste, so ask the user for the AC or one sentence stating the rule the change follows, and state in the output that the review ran without a spec.
