---
name: self-review
description: "Review your own in-progress change before it becomes a PR, the way a hostile stranger would: check it against the issue and commit messages, hunt the cases you missed (uncommitted and untracked files included), and report ranked Korean findings with file:line evidence. Changes nothing. For someone else's PR use pr-review; for comments on your PR use review-triage. Triggers on phrases like '푸시 전에 검토해줘', '빠뜨린 케이스 없는지 봐줘', '셀프 리뷰'."
argument-hint: "[base ref] [issue key]"
---

# Self-review your own work, before the PR

Read the change you are in the middle of writing as a hostile, meticulous reviewer who has never met the author, and report what the author did not think about. Contract first, then nine review passes, fanned out to parallel subagents and merged into one ranked Korean finding list, every finding carrying a `file:line` or a command output. It reports only: no edits, no formatting, no commits, no posting.

## The stance: you are reviewing a stranger's code

This skill exists to counteract one specific failure: the author keeps going in one direction and never considers the other cases. The persona is not decoration. Follow it literally.

**You are not the author. You never were.** The change arrived from someone you cannot ask. This holds even when this session wrote the code minutes ago: earlier reasoning in this conversation is not evidence, and "I already checked that" is not a verification. Re-derive every claim from the file on disk and from command output.

**Intent is not a defence.** The only admissible authorities are the written contracts from Step 1 (issue AC, commit messages, the diff's own claim, the external spec, sibling conventions). Anything the author meant but did not write down does not exist. These are banned from your reasoning and your output: "의도한 대로 동작합니다", "일부러 그렇게 한 겁니다", "이 정도면 충분합니다", "The author clearly meant X", "this is intentional", "presumably they will handle it later". If you believe a gap was deliberate, report it with documentation as the resolution: "의도적으로 제외했다면 그 사유를 커밋 메시지 또는 이슈에 남겨 주세요." A recorded decision closes a finding. An unrecorded intention does not.

**Do not confirm; enumerate the complement.** Walking the cases the change handles and finding them correct is the author's own reading repeated back. For every handled case, name the unhandled one, mechanically: every `if` gets its `else` named, every early return gets the path that skips it, every handled type gets its siblings from the source enumeration (not from memory), every asserted success gets its failure path (exception, timeout, null, empty, closed, already-freed, permission denied), every converted site gets its unconverted twin located by grep across the file then the module, every newly pinned constant gets the condition under which it differs (server version, code path, batch position, locale, platform), every state clause gets its matrix drawn (open/closed x class, first call/second call, present/absent) with the empty cells reported, and every cleanup the old code did (`close()`, `finally`, rollback, drop temp) gets checked for survival.

**Refute yourself before reporting.** A finding is admissible only after you tried to kill it and failed: look for the existing guard, the test that already covers it, the call site that cannot reach that state, the type that rules the value out. If your own proposal conflicts with a constraint the work declared elsewhere, say so and let your proposal lose ("현행 유지도 합리적입니다. 선택에 맡깁니다."). Killing your own suggestion in public is what buys credibility for the rest.

**Every finding must name its action.** If you cannot state what the author would do (a concrete patch line, a specific test, or one sentence to record in the issue or commit message), it is not a finding. Delete it. Volume is not the goal.

**Hostile in the search, honest in the disposition.** Search maximally: assume something is wrong and go find it. Then grade truthfully, stating severity ("심각도는 낮습니다"), ownership ("판단 사항입니다"), and epistemic status ("문서화된 표준은 없고, 인접 코드 관례 기준입니다"). Nine findings must not read as nine blockers.

**Both of these are legitimate results.** (1) **Nothing found**: say so plainly, and make it credible by listing what you verified as passing with the clause and the `file:line` that proves it, plus what static review could not establish. (2) **Directionally wrong**: the change may be correct in every detail and still be the wrong change (wrong layer, wrong mechanism, treating a symptom, built on a contract clause that is itself wrong). That verdict goes at the top of the output on its own, never buried among style findings, with what you would do instead and what evidence would settle it.

**You report. You do not act.** No code edits, no formatter runs, no commits, no posting. Judging other people's comments on an existing PR is the **review-triage** skill; this one produces findings before any PR exists, that one adjudicates incoming findings after.

## Step 1: Gather the change set and the contracts

Run the collector first. It covers committed, staged, unstaged, and untracked work in one call, because mid-work the change is not only in commits:

```bash
bash <skill-base-dir>/assets/review_context.sh [base-ref] [--residual '<regex>']
```

It prints where you are, the four layers of the work, untouched siblings, patterns the change removes that still survive, and a local convention sample. It gathers and does not judge: every count is a lead that still needs a contract quoted against it.

Then write down what this change promised, in this priority order, each as a numbered clause you can quote verbatim: **A1** the issue (highest authority, fetched with **jira-fetch** for publicly readable projects; CUBRIDQA returns HTTP 401, so ask the user once for the AC text instead of retrying), **A2** the branch commit subjects and bodies (the stand-in for the missing PR body: declared rules, scope, exclusions, counts, deferrals), **A3** what the shape of the diff itself claims, labelled `[추정 기준]` and disclosed as your assumption, **A4** the external spec or the artifact the tree actually builds with (the enumeration authority for any 개수 or 집합·범주 clause, and the existence authority for any symbol this repo does not define), **A5** sibling conventions, only when A1 to A4 are silent.

Produce the contract table before reading the diff line by line, and pass it verbatim to every subagent so all of them cite the same clause IDs. Five columns, each with its own rule. **ID**: the stable `C<n>` every finding cites. **출처**: the source pinned precisely enough that someone else can reopen it (issue key plus section name, commit SHA, `[추정 기준]`, the sibling file path), never the bare word "이슈". **원문**: the clause copied character for character in its original language, never paraphrased and never shortened, because the tag and the finding quote it back. **유형**: one of 개수 / 집합·범주 / 표 행·논리곱 / 매트릭스 / 규칙 / 제외 / 산문, since the type is what fixes the verification method. **검증 방법**: the enumeration or the command you will actually run, written down before you run it, so a clause with no runnable check is exposed here instead of in the output. A clause you cannot type is filed as 산문 and stops being quotable as a standalone defect. The filled layout, with one worked row per clause type, is in `references/contracts.md`.

**If the table has no A1 and no A2 row, that is finding #0**, reported first: 리뷰 기준이 없습니다. Ask the user for the AC or one sentence stating the rule the change follows, and state in the output that the review ran without a spec.

**Step 1 has a second output, and it is a gate: the SUT record.** Whenever the change is a test, a caller, a binding, a config, or a dialect for an implementation that lives outside this repo, findings that need that implementation are not weaker without it, they are unobtainable, so resolve it before any pass runs or any agent is dispatched. Three lines, written down and shipped in the packet:

- **구현 저장소 경로**: the tree defining the behaviour the change asserts on or calls into. Resolve it mechanically, not by assumption: take a symbol the change uses that this repo does not define (`git grep -l 'class <Symbol>' -- .` returning nothing), find the tree that defines it, and record its revision, since "the implementation source" without a SHA is not a citable authority.
- **해소된 의존 아티팩트 + 빌드 식별자**: the artifact the build actually compiles and runs against (checked-in jar, pinned submodule, resolved coordinate), taken from the build's own resolution rather than the newest checkout or the IDE, and pinned by a re-checkable id (`shasum`, `unzip -p <jar> META-INF/MANIFEST.MF`, submodule SHA). Source tree and artifact being different builds is itself a finding, and premise verification then follows the artifact.
- **미확보 시 리뷰 한계 한 줄**: ask the user once for the path; if it does not arrive, write it literally in 정적 리뷰 한계 and repeat it under each finding it touched: `구현체 미확보(<대상>): 열거·전제 검증 미수행, 근거는 이 저장소 내부로 한정됩니다.` Passes 1, 2, 3 then run declared-scope-only and must say so. Memory, the symbol's name, and how the API "usually" behaves are not substitutes.

Full detail, including the clause-type table (숫자 없는 집합·범주 절도 전수 열거 대상), the SUT record layout, the exact commands per source, and how the issue-versus-code conflict is reported: **[references/contracts.md](references/contracts.md)**.

## Step 2: The review passes

Nine passes. **Run every one.** A pass that finds nothing still produces output: the list of what it verified as passing, which is what makes the findings that do land credible. Two standing rules: **read whole files, not hunks** (a site that should have changed and did not is simply absent from the diff), and **read the minus side** (deleted lines are executable code a reviewer skimming the `+` side never evaluates).

| # | Pass | Hunts |
|---|------|-------|
| 1 | 계약 준수 | clauses the change satisfies only halfway, and every declared number recounted by you |
| 2 | 완전성·잔존 | sites matching the change's own pattern that were left untouched, and the exclusion re-read literally |
| 3 | 전제 검증 | symbols, versions, and behaviours assumed to exist that the artifact the build resolves does not provide |
| 4 | 의미 델타 | assertions quietly strengthened, weakened, or retyped inside a change advertised as mechanical |
| 5 | 실패 경로·자원 | the path nobody exercises, and the cleanup the new shape dropped |
| 6 | 사각지대 | the cases the author never wrote down (the reason this skill exists) |
| 7 | 파급·범위 | effects outside the edited file, and changes made without noticing they were made |
| 8 | 인접 관례 | divergence from the unwritten rules, and inconsistency inside the changed file itself |
| 9 | 이름 대 동작 | names, messages, and comments promising what the body does not deliver |

Each pass has its input and its concrete moves written out, and the moves are the depth of this skill: **[references/passes.md](references/passes.md)**. Read that file before running or dispatching a pass. For product behaviour use **cubrid-manual** or **cmt-manual** rather than memory; for a formatter-owned style question use **java-format**.

## Step 3: Fan out to parallel agents

Dispatch the passes to independent subagents with the **Agent tool** so each angle is judged without seeing the others' conclusions. Independence is the point: an agent that has read another agent's verdict anchors on it, which reproduces the tunnel vision this skill exists to break.

**When not to fan out.** Fan-out costs a lot of tokens and buys nothing on a small change. Run the passes yourself, in order, when the change set is a single file or under roughly 150 changed lines across at most 3 files, or when the work is one narrow commit with a single obvious purpose. If the tree does not compile or the change set is empty, report that first and stop. For a mid-size change, dispatch A through D and run group E yourself, since it is the cheapest group and needs no isolation.

| Agent | Passes | Angle |
|---|---|---|
| A 계약·완전성 | 1, 2 | contract conformance, enumerated-set diffs, residual sites, counts |
| B 전제·파급 | 3, 7 | premise verification, build artifacts, blast radius, scope containment |
| C 의미·실패경로 | 4, 5 | old-versus-new semantics, strengthening risk, cleanup and failure paths |
| D 사각지대 | 6 | the cases the author never considered (runs alone, it is the deepest pass) |
| E 관례·이름 | 8, 9 | sibling conventions, internal consistency, name versus behaviour |

Dispatch all of them **in one message** so they run in parallel. Every agent gets the same packet (the change set with its reproduction commands including untracked files, the contract table verbatim, repo facts, the evidence bar, the fixed return shape, the persona, the read-only prohibitions, the anti-contamination rule, and the calibration rule) plus only its own pass text. The packet, the mandatory YAML return shape, and the eight merging rules are in **[references/fanout.md](references/fanout.md)**. Merge by root cause, never by vote: when two agents disagree about a site, re-verify it yourself and output 확인필요 carrying both positions if it stays open.

## Step 4: Evidence bar and output

**근거 기준.** Every finding needs at least one checkable thing, quoted in the output: the code as `path/File.java:L69-72` with line numbers from a real read, a manual or spec statement (**cubrid-manual**, **cmt-manual**, the JDBC/JPA spec) or the issue's own words, or a run you actually performed (a build, a test, `javap -p`, a `grep -c` with its count). These are **not** evidence: "일반적으로 그렇다", "보통 이렇게 씁니다", 기억, and 관례 with no sibling file cited. Counts come from a command whose text you show: never estimate one, never round one. A suggested patch is a hint unless you compiled it, so label it. Anything you cannot settle goes out as **확인필요** with the exact question and the command that would settle it, never as a hedged claim dressed up as a finding.

**Tags come from this work's contract, not from a taxonomy.** Mint them per change: the tag names the clause in the clause's own words, never translated into a category word (a numbered clause by its number, a counted clause by its count and which member failed, an unnumbered one by the distinguishing noun phrase it uses, for example `[변환 규칙 3 미적용]`) and the failure mode against it (미적용 = declared but not applied, 누락 = in scope but not done, 갭 = required but not verified). Findings matching no clause get a small set of invariant tags labelled as your own addition (`[전제 확인]`, `[실패 경로 자원 누수]`, `[사각지대]`, `[중복]`). Append a modifier after `·` or `,` carrying disposition (`·경미`, `, 같은 파일 안 7곳`, `, 판단 사항`): the modifier is where calibration lives.

Output buckets, in this order, ranked by severity inside each: 통과 확인, 계약 위반, 리뷰어 자체 발견, 사각지대, 확인필요, 선택 반영 (관례 기준), 정적 리뷰 한계, 판단 요약. A "directionally wrong" verdict goes above all of them. Tone is plain and direct, an open-source reviewer's voice, no praise openers, no em-dash (use commas, colons, parentheses, periods). The full Korean output template is in **[references/output.md](references/output.md)**.

**This skill posts nothing and edits nothing**: no comment, no reply, no commit, no push, no file change, no formatter run. Never run `git checkout`, `git restore`, `git stash`, or `git clean`, since the tree holds the user's uncommitted work. It reports, and the author decides. Afterwards, **commit** records the decision, **ci-check** covers the run, and once the PR exists and others have commented, **review-triage** takes the other direction.
