# Review passes and scope discipline

Reference for the `pr-review` skill. This file is the review method itself: how to work a stranger's pull request so that every finding survives the author's triage.

This skill **never posts**. Everything below produces a report for the user, who decides what, if anything, is worth sending.

## Before the passes: the working copy and the ground rules

**Working copy.** Never mutate the user's repository state beyond fetching a ref and adding a worktree. Never `gh pr checkout`, never `git checkout` / `git switch` / `git stash` in a tree the user is working in.

```bash
PR=<number>; REPO=<abs path to local clone or "">; WT=$SCRATCH/pr-$PR
gh pr view "$PR" --json number,title,body,baseRefName,headRefName,headRefOid,files,commits,url,state

# repo already cloned locally: fetch the PR ref, then expand it as a detached worktree
git -C "$REPO" fetch origin "pull/$PR/head:refs/pr/$PR" "$(gh pr view "$PR" --json baseRefName -q .baseRefName)"
git -C "$REPO" worktree add --detach "$WT" "refs/pr/$PR"

# not cloned: clone into the scratch cache instead (full tree, not --depth 1: the history passes need it)
git clone https://github.com/<owner>/<repo> "$SCRATCH/cache/<repo>" && cd "$SCRATCH/cache/<repo>" && git fetch origin "pull/$PR/head:refs/pr/$PR"

BASE=$(git -C "$WT" merge-base origin/<baseRefName> refs/pr/$PR)
HEAD=$(git -C "$WT" rev-parse refs/pr/$PR)

# clean up when the review is done
git -C "$REPO" worktree remove "$WT"
```

Fetching the whole repository is deliberate. The passes below derive populations, siblings, and history from the tree, and a partial checkout silently turns "nothing else matches" into a false negative.

**No sampling.** Read every changed file **in full** at `$HEAD`, not just the hunks:

```bash
git -C "$WT" diff --name-status "$BASE...$HEAD"
git -C "$WT" diff "$BASE...$HEAD" -- <file>          # the change
sed -n '1,$p' "$WT/<file>"                            # the file as it now stands
git -C "$WT" show "$BASE:<file>"                      # the file as it stood before
```

A hunk shows what moved. It does not show the method three lines below the hunk that now contradicts it. Accuracy is the priority over cost: if the diff is large, spend the tokens, or tell the user which files you could not finish rather than guessing about them.

**The grounding bar.** A finding may be filed as a defect only when it carries all three:

1. a checkable reference: `file:line` at `$HEAD`, a quoted clause from the contract, or the output of a command you actually ran;
2. a concrete consequence: the input or state that produces the wrong result, or the declared rule that the change violates; and
3. a failed refutation: the existing guard, the test that already covers it, the caller that cannot reach that state, or the type that rules the value out, each searched for and not found. review-triage rules '이미 처리됨' as 부당, and only this step catches it.

Requirements 1 and 2 point in one direction only: they ask whether the finding can be argued for. Requirement 3 points the other way, and it is the one reviewers skip. **A finding that was never attacked is not grounded, it is merely unchallenged.** Go looking for the thing that would kill it:

```bash
rg -n -B3 -A3 '<the value or state you claim is unhandled>' "$WT/<file>"        # a guard already above it?
rg -n '<symbol>' "$WT" -g '**/test*/**' -g '**/*Test*'                          # a test already covering it?
rg -n '<symbol>\s*\(' "$WT" --type <lang>                                       # can any caller actually reach that state?
```

Then record the result on the finding's **반증** line (Pass 13, anatomy item 5). "찾아봤지만 없습니다" plus the search you ran is a result; silence is not, and silence is what triage reads as carelessness.

Anything missing any of the three goes out as a **질문** addressed to the author, never as a defect. This is the single most important rule in the file. Reviewing your own work fails by going easy; reviewing someone else's fails by asserting a defect you have misread, because you do not know why the code is the way it is.

**Tone, in every pass.** Address a colleague. Acknowledge what is legal or deliberate before pointing at it. Say what a fix costs. Where the author plausibly had a reason, grant the exception yourself in the finding rather than making them argue for it.

---

## (a) The passes

Run them in order. Passes 1 and 2 produce the yardstick and the veto; the rest hunt against them. A pass with no input available is skipped explicitly in the report ("계약 문서 없음: 선언 규칙 대조 생략"), never silently.

### Pass 1: Contract extraction and conformance

**Hunts:** the change failing a rule that the work itself declared.

**Input:** the PR body, the linked issue (a Jira key given by the user, or one parsed from the body or branch name), the commit messages, and the PR title.

**Move.** Extract the contract before reading the diff, so the diff cannot talk you into a different yardstick:

```bash
gh pr view "$PR" --json title,body -q '.title, .body'
git -C "$WT" log --format='%H%n%s%n%b%n--' "$BASE..$HEAD"
```

Collect, verbatim, every clause of these shapes and give each an identifier:

- numbered or bulleted rules the body declares it applied ("rule 1: ... rule 7: ...");
- an exclusion list ("not converting X, Y");
- a counts table or any number ("7 classes", "all 12 endpoints");
- acceptance criteria in the linked issue;
- a promise in a commit message ("also removes the deprecated overload").

Then check the change against each clause one at a time, and record the verdict per clause, including the ones that pass. A clause that passes is worth one line in the report: it tells the author you actually checked.

**Tag construction.** Output tags are **invented from the contract's own vocabulary**, not drawn from a fixed taxonomy. Build the tag from the words the author used, so they can find it in their own text:

- body declares numbered rules of some name → `[<그 명칭> N 미적용]`. For a PR whose body says "converts every cron expression to an ISO-8601 duration, rules 1 to 5", an unapplied rule 4 files as `[변환 규칙 4 미적용]`.
- issue declares acceptance criteria → `[스펙 갭]`.
- body declares counts → `[카운트 불일치]`.
- body declares exclusions and an item is excluded silently → `[제외 사유 누락]`.
- contract declares nothing relevant → fall back to the pass name (`[잔여 지점]`, `[의미 변화]`, ...).

Never invent a tag whose vocabulary appears nowhere in the contract, other than the fallbacks. A tag the author does not recognize reads as a taxonomy imposed on them.

**Files as:** a defect when a declared clause is violated (the clause is the consequence: the PR says it did this and it did not). A 질문 when the clause is ambiguous about the case you found.

### Pass 2: History and intent (this pass exists only because it is someone else's code)

**Hunts:** your own about-to-be-filed defect that is actually a deliberate decision. Its output is mostly vetoes, not findings.

**Input:** every line the diff touches or sits next to, plus the file's own history and the PRs that shaped it.

**Move.** For each candidate finding from any pass, before writing it down:

```bash
# what these exact lines were, and why they changed last
git -C "$WT" log -L <start>,<end>:<file> "$BASE" | head -100
git -C "$WT" blame -w -C -C -L <start>,<end> "$BASE" -- <file>

# the file's recent history, and the PR each commit arrived in
git -C "$WT" log --oneline -20 "$BASE" -- <file>
gh api "repos/<owner>/<repo>/commits/<sha>/pulls" -q '.[] | "\(.number) \(.title)"'

# discussion on the same file before this PR
gh pr list --state merged --limit 20 --search "<distinctive filename or symbol>"
```

Read the result for these signals, each of which vetoes the defect:

- the line you object to was **introduced by a fix**, with an issue key or a "revert of" in the message: the shape is load-bearing, and your suggestion probably reintroduces the old bug;
- the pattern was **already reviewed** in a prior PR on the same file and settled there;
- the surrounding code has a comment or a test naming the constraint;
- the odd construct is **the local dialect**: it appears in the sibling files too (this overlaps Pass 9, which is where you check it).

When a veto applies, do one of three things and nothing else: drop the finding; or restate it as a 질문 that names what you found ("blame says this guard came in with the fix for issue N; is the new path still covered by that reason?"); or, if you still believe the defect holds against the historical reason, file it **with the history quoted and answered**, so the author does not have to re-derive it.

**Do not** file a finding whose whole content is "why is this like this". Answer that yourself first; ask only what the history genuinely does not answer.

**Files as:** normally nothing of its own. Its work leaves three visible traces, and the third is the one that proves it ran: findings that other passes did **not** file; 질문 that already contain the historical context; and the **반증** line that every surviving finding carries (Pass 13, anatomy item 5), where the history you checked and answered is written down. A finding whose 반증 line is empty did not go through this pass.

### Pass 3: Population enumeration and coverage diff

**Hunts:** an incomplete set, where the change covers some members of a group and the contract or the code implies all of them.

**Input:** every clause naming a set, whether or not it states a size. "7 classes" names a set; so do "상속 클래스", "all implementations", "each endpoint", "the affected callers", and a plural in a commit message.

**Move.** Derive the population **from the source first**, then compare it with the change and only then with any declared count:

```bash
# subclasses / implementations
rg -n 'class \w+ (extends|implements) \b<Base>\b' --type <lang> "$WT"
# annotation, decorator, or registration based membership
rg -n '@<Marker>' "$WT" -l | sort > /tmp/pop.txt
# what the change touches
git -C "$WT" diff --name-only "$BASE...$HEAD" | sort > /tmp/covered.txt
comm -23 /tmp/pop.txt /tmp/covered.txt     # population members the change never touches
```

**The ordering is the rule, not a preference.** Reading the declared count first makes you stop enumerating the moment you reach it, so a set of nine with a declared "7" is confirmed as seven. Derive, then diff, then compare with the declaration. If the derived population and the declared count disagree, that disagreement is itself the finding (`[카운트 불일치]`), and it is worth filing even when the extra members turn out to be intentionally excluded, because the exclusion is unstated.

**Open the member before you count it.** `comm` prints filenames, not gaps. Every supposedly-missing member is opened and confirmed **runnable** before it enters the count:

```bash
sed -n '1,80p' "$WT/<member>"                                     # read it, do not infer from the name
rg -n 'abstract class|interface |@Disabled|@Ignore|@Generated|DO NOT EDIT|generated by' "$WT/<member>"
rg -n -F '<member basename>' "$WT" -g '*.{gradle,gradle.kts,pom.xml,xml,json,yml,yaml,cfg,mk}'   # in the build at all?
rg -n -F '<member basename>' "$WT" -g '**/*suite*' -g '**/*Suite*'                                # in the suite at all?
```

A member counts as a gap only when all four hold: not abstract, not generated, not disabled or skipped, and not excluded from the build or the test suite. Anything else is dropped **before** the number is written, and the drops are worth one line in the finding ("8건 중 2건은 abstract, 1건은 생성 코드라 제외하고 셌습니다"), because that line is what shows the author you counted the way they did.

**State the blind spot, always.** Every enumeration has one, including the ones that look mechanical. Name it in the finding next to the number: transitive subclasses your pattern's depth never reached, dynamic or runtime registration, reflection, and configuration-driven membership. For sets the tree cannot enumerate mechanically at all (behaviour-defined membership), give the enumeration you did manage with its boundary: "직접 상속 9개는 셌고, 2단계 이상 상속과 런타임 등록분은 못 봤습니다". A bare number with no stated boundary is a completeness claim you cannot back, and triage rules it 확인필요 at best.

**Files as:** **질문, or a "사유 한 줄" request, by default.** An uncovered member is normally the author knowing something you do not (it is excluded on purpose, it is covered elsewhere, it cannot run here), so the default output is "이 3건은 왜 빠졌는지 한 줄만 본문에 적어주실 수 있을까요"; the author answers in one line and the point closes either way. File it as a **defect** only when both hold: a member you **opened and confirmed runnable** is uncovered, **and** a contract clause actually names that set (quote the clause). Set implied by the code but never promised: 후속 제안 (see section (b)).

### Pass 4: Instance resolution and the real cost of the ask

**Hunts:** the difference between "you already have this, one line" and "this needs new scaffolding". Every uncovered item from Pass 3 goes through here before it is written up.

**Input:** the uncovered member, and the fixtures, factories, builders, or providers available at the call site the change already added.

**Move.** Resolve the member's **concrete type** and find who produces one:

```bash
rg -n 'fun <name>|<Type> \w+\(|new <Type>\(|@Bean|@Fixture|factory|Provider' "$WT/<fixture dir>"
rg -n '\b<ConcreteType>\b' "$WT" --type <lang> | head -40
```

Then answer, in the finding itself:

- does the change **already hold an instance** of that type (a field, a parameter, a fixture it constructs)? Then the ask is one line, and you say which line and which variable.
- does the type require setup the change has none of (a running service, a schema, a licensed component, a fixture that does not exist)? Then the ask is expensive, and you say so and offer the alternative: exclude it and write the reason.

A finding that says "also cover Z" without resolving this is where triage rules 부당 most often: the author knows the cost, you did not, and the request reads as careless.

**Files as:** part of the Pass 3 finding, as its 비용 line. Never as a separate finding.

### Pass 5: Residual sites

**Hunts:** the same pattern the change converted, left unconverted elsewhere.

**Input:** the before/after shape of the conversion, taken from the diff itself, plus the touched files and their siblings (same directory, then same module).

**Move.** Characterize the **old** shape precisely, then search for it with context, at two radii:

```bash
# single-line shapes
rg -n '<old pattern>' "$WT/<dir of touched file>"
rg -n '<old pattern>' "$WT" -g '!**/build/**' -g '!**/node_modules/**'

# multi-line shapes: one-line grep will miss them
rg -n -U --multiline --multiline-dotall '<line A>[\s\S]{0,200}?<line B>' "$WT/<dir>"
# structural search where available, which survives formatting differences
ast-grep --pattern '<old shape with $VARS>' "$WT/<dir>"
```

Count what remains and report the count, not a vague "there are others". Distinguish two radii in the finding, because they have different dispositions: residuals **in the files this PR already touches** are normally in scope; residuals in files it never opened are usually 후속 제안.

Beware two false positives: the remaining occurrence may be in generated code, or in a test that deliberately asserts the old shape. Open each occurrence you cite. Cite at most three concrete `file:line` plus the total count.

**Files as:** defect for in-file residuals (the PR promised the conversion for this file and left some), 후속 제안 for the wider radius.

### Pass 6: Premise verification

**Hunts:** your own claim resting on a symbol, flag, API, or version that does not exist in the artifact this build actually resolves. Also the author's, when the change references something the build cannot see.

**Input:** the build's real dependency resolution, and the compiler.

**Move.** Compile in the worktree with the project's own build, against the artifact it resolves, not against documentation or memory:

```bash
cd "$WT" && ./gradlew :<module>:compileTestJava --offline || ./gradlew :<module>:compileTestJava
cd "$WT" && mvn -q -pl <module> -am test-compile
cd "$WT" && npm ci && npx tsc --noEmit

# which artifact is actually on the classpath
./gradlew :<module>:dependencies --configuration testRuntimeClasspath | rg '<artifact>'
```

**The control compile is mandatory before any compile-based defect is filed.** A red build only implicates the PR if the same build is green without it. Compile the merge base the identical way, in its own worktree, with the same command and the same flags:

```bash
git -C "$REPO" worktree add --detach "$WT-base" "$BASE"
cd "$WT-base" && <the exact command you ran at $HEAD>
git -C "$REPO" worktree remove "$WT-base"     # with the head worktree, at cleanup
```

Read the two results together:

- **base fails the same way** → the failure is the environment (missing toolchain, unresolvable dependency, stale or offline cache, wrong JDK), not the change. **The finding is dropped**, not downgraded, and the report says so in one line: "베이스도 같은 오류로 실패해서 환경 문제로 봅니다. 이 PR 결함으로 올리지 않았습니다."
- **base is green, head is red** → now it is a finding, and both outputs are quoted in the 근거 (the base command succeeding is half the evidence).

**Where the project has no compiler or type checker at all** (an untyped or interpreted tree with no type-check step, or a build you cannot run here for any reason), **premise verification has no substitute.** Reading the upstream source, the changelog, the docs, or the package registry verifies nothing about what this build resolves. Every premise-dependent finding then goes out as a **질문** rather than as a defect, carrying the command the author can run themselves, and the report states the gap once: "이 저장소엔 타입 체크 단계가 없어서 심볼 존재 여부를 검증하지 못했습니다. 아래는 단정이 아니라 질문입니다."

Only when the compiler rejects a symbol do you go looking for why:

```bash
javap -p -cp <resolved jar> <fqcn> | rg '<member>'
unzip -l <resolved jar> | rg '<Class>'
```

The rule this encodes: **a symbol may exist in the project's newest source and be absent from the checked-in or pinned artifact the build resolves.** Reading the upstream source, the changelog, or the docs proves nothing about what compiles here. Run the compiler first and let it decide what needs investigating; javap on everything is wasted time.

When the build cannot run (no network, no toolchain, missing credentials), say so explicitly in the report and downgrade every finding that depended on compiling to 확인필요, with the command the author can run.

**Files as:** a defect against the PR when the change itself does not compile or resolve **and the control compile at `$BASE` was green**. Never on a head-only run. Otherwise it is a gate on your other findings: an unverified premise turns its finding into a 질문, and an absent verifier (no compiler, no type checker) turns every premise-dependent finding into a 질문.

### Pass 7: Semantic delta

**Hunts:** behaviour that changed strength or reachability without the PR saying so.

**Input:** the diff with wide context, and the before-file for anything heavily edited.

```bash
git -C "$WT" diff -U15 "$BASE...$HEAD" -- <file>
```

**Move.** For each changed statement, ask which direction it moved, and whether the PR body claims that move:

- **assertion strengthened** (a looser check replaced by an exact one, a subset check by an equality, a warning by an error): who else runs through this? A strengthened assertion can make previously passing inputs fail, which is often the point but is sometimes collateral.
- **assertion weakened** (equality relaxed to "contains", a specific exception widened, a case removed): the test still passes but proves less. This is the most under-reported defect in test-touching PRs, because nothing goes red.
- **previously swallowed, now mandatory**: an empty catch, a logged-and-continued error, or a printed stack trace replaced by a throw or a failed assertion. Anything that was quietly tolerated becomes a hard failure for every caller.
- **previously mandatory, now swallowed**: the reverse, which hides regressions.
- **default changed**: a parameter default, a config fallback, a null-handling branch. Enumerate the callers that relied on the old default (Pass 12).
- **ordering, timing, or transactionality** changed around the same lines.

Say the direction plainly in the finding, and name the population affected. For example, for a change that replaces "response contains the field" with "response equals the fixture", the finding names the fixtures now required to match exactly and what happens to the ones that do not.

**Files as:** defect when the delta is unintended or unstated and something concrete breaks. 질문 when the delta is plausibly intentional but nothing declares it ("this makes the check exact; was that the intent, or a side effect of the rewrite?").

### Pass 8: Failure paths and resources

**Hunts:** what happens on the unhappy path that the change introduced or moved.

**Input:** every new or moved acquisition, branch, and boundary in the diff.

**Move.** For each changed block, trace the non-happy exits explicitly:

- **acquisition without release**: file handles, sockets, connections, locks, temp files, subscriptions, timers, child processes. Is release in a `finally` / `defer` / `using` / context manager, or on the happy path only? Does an early return skip it?
- **partial state on failure**: if the operation fails midway, what is left behind (a half-written file, a row inserted without its child rows, a cache entry pointing at nothing)? Is the cleanup ordered so it works when the failure happens in the middle?
- **error translation**: is the original cause preserved, or replaced by a generic message that erases the diagnosis?
- **empty catch, catch-and-log, catch-and-continue** introduced by the change: which caller now proceeds with invalid state?
- **new external call**: timeout, retry, and what the caller sees when it never returns.
- **concurrency**, when the change touches shared state: what two callers do at once.

```bash
rg -n 'catch\s*\([^)]*\)\s*\{\s*\}|except\s*:\s*pass|catch\s*\{\s*\}' "$WT/<dir>"
git -C "$WT" diff "$BASE...$HEAD" | rg -n '^\+.*(open|connect|acquire|lock|new FileInputStream|setTimeout)'
```

**Files as:** defect with the concrete failure scenario ("if the write throws after line N, the temp file stays and the next run reads it as complete"). Without a concrete scenario it is a 질문, not a defect.

### Pass 9: Local convention, at two localities

**Hunts:** a block that is legal and works but does not look like its neighbours, and where the mismatch has a cost.

**Input:** two populations of neighbour, checked separately because they disagree more often than people expect.

1. **The tree**: how does the rest of the project do this (naming, test structure, assertion library, logging, error type, module layout)?
2. **The file itself**: does the new block match the file it lives in (indentation, brace style, ordering of members, the file's own naming of the same concept, the section it was inserted into)?

**Move.**

```bash
# tree-wide: how the same job is done elsewhere
rg -n '<the construct>' "$WT" --type <lang> | head -30
# file-local: is the new block indented like its own file
awk 'NR>=<start> && NR<=<end>' "$WT/<file>" | cat -A | head -20
git -C "$WT" diff --check "$BASE...$HEAD"     # whitespace errors introduced by the change
```

A file-local mismatch is worth reporting even when the project has no global rule, because it is visible on every future read of that file. A tree-wide mismatch is only worth reporting when you can point at the prevailing form and its count ("the other 14 call sites use the helper").

Do not report style that a formatter or linter owns; run the project's formatter check instead and report the command's verdict:

```bash
cd "$WT" && ./gradlew spotlessCheck || npx prettier --check . || <project's own check>
```

**Files as:** 취향 unless it either violates a documented convention or a configured tool, or it is a file-local inconsistency (which is not taste: it is noise the author can remove in one edit). Say which of the two it is, so triage does not have to guess.

### Pass 10: Name versus behaviour

**Hunts:** an identifier that makes a claim the body does not keep.

**Input:** every name the change introduces or renames: methods, tests, variables, flags, config keys, error messages, log lines, and the PR title itself.

**Move.** Read the name as a claim, then read the body as the evidence for it, in that order (reading the body first makes you accept the name):

- a test named for a condition that it never asserts, or that asserts something narrower or wider;
- a boolean whose `true` means the opposite of what its name suggests, or a `disableX` that is checked as if it were `enableX`;
- a method named for one job that also performs a second, unrelated one (the hidden side effect);
- a name that encodes a specific case ("retryOnTimeout") whose body handles the general one, or the reverse;
- an error or log message that says something the code does not do;
- a name kept from a previous meaning after the code around it changed (Pass 2 finds these: blame shows the name predates the behaviour).

For a synthetic example of the shape: a helper called `normalizeToUtc` that returns its input unchanged when the timezone is absent is not normalizing, and every future caller will assume it did.

**Files as:** defect when the mismatch can mislead a caller or hides an untested case. 취향 when it is only a better word for the same behaviour.

### Pass 11: Duplication

**Hunts:** the change re-implementing something the tree already has, or repeating itself inside its own diff.

**Input:** the new helpers, constants, regexes, and blocks in the diff.

**Move.** For each new helper or literal, search the tree for a prior art before assuming it is new:

```bash
rg -n 'fun <verb>|def <verb>|<Type> <verb>\w*\(' "$WT" --type <lang> | rg -i '<concept>'
rg -n -F '<the literal or regex>' "$WT"
# near-duplicate blocks inside the diff itself
git -C "$WT" diff "$BASE...$HEAD" | rg -n '^\+' | sort | uniq -c | sort -rn | head -20
```

Two cases with different dispositions:

- **duplicate of existing tree code**: name the existing symbol and its `file:line`, and check it is actually reachable from here (visibility, module boundary, dependency direction). A helper the new code cannot legally call is not a duplicate.
- **repetition inside the diff**: only worth a finding when the copies must change together, or when the copies already diverge (one has a fix the other lacks). Three similar-looking blocks that will never change together are not a defect.

**Files as:** defect when copies have already diverged. Otherwise 후속 제안 or 취향, and say which.

### Pass 12: Blast radius

**Hunts:** everything outside the diff that the diff can break.

**Input:** every symbol, key, format, and file the change alters or removes, and the whole tree (this is why the full clone matters).

**Move.** For each altered or removed public-facing thing, enumerate the dependents:

```bash
SYM=<changed symbol>
rg -n "\b$SYM\b" "$WT" -g '!**/build/**' | wc -l
rg -n "\b$SYM\b" "$WT" -g '!**/build/**' | head -40
# non-code dependents, which code search misses
rg -n -F "$SYM" "$WT" -g '*.{json,yaml,yml,xml,properties,toml,md,sql,sh}'
git -C "$WT" log --oneline -5 "$BASE" -- <config or CI dir>
```

**A grep count is not a dependency count.** `rg | wc -l` counts text, and text matches a comment, a string literal, a docstring, a same-named symbol in a different package, a vendored or shaded copy, and a test fixture that shadows the type. **Every hit you cite and every hit you count is opened and confirmed to resolve to the changed symbol:**

```bash
rg -n "\b$SYM\b" "$WT" -g '!**/build/**' -l | while read -r f; do
  echo "== $f"; rg -n '^(package|import|use |require|from )' "$f" | rg -i '<owning package>'
done
sed -n '<hit line minus 15>,<hit line plus 5>p' "$WT/<file>"   # what is the receiver's actual type here
```

Three things per hit, all three or it does not count: the file imports (or lives in) the package that owns the changed symbol; the receiver resolves to the changed type, not a same-named one; and the hit is code, not a comment, a literal, or a doc line. **Non-resolving hits are dropped from the citation and from the count**, and the finding reports the resolved number, naming the raw one only when the gap is the point: "문자열 매치는 40건이지만 실제로 이 심볼로 해석되는 건 6건입니다". If the tree is too large to resolve every hit, cite the ones you resolved and state the remainder as an unresolved boundary rather than folding it into the number. An inflated dependent count is the fastest way to have the whole finding ruled 부당: the author opens your third citation, sees an unrelated class, and stops reading.

Cover, one by one:

- **callers** of changed signatures, defaults, nullability, or thrown types;
- **subclasses and overrides** when a base changed;
- **serialized or persisted shapes**: on-disk formats, wire payloads, database columns, cached values written by an older version and read by this one;
- **configuration and CI**: a renamed key, a moved file path, a build script referencing a deleted target;
- **public API surface** for a library: is the change source-compatible, binary-compatible, both, neither, and does the project promise either?
- **tests that the change makes vacuous**: a test that still passes but no longer exercises the path.

**Files as:** defect with the specific dependent quoted (`file:line`), confirmed to resolve to the changed symbol, and what it now does. Every number in the finding is a resolved count, never a raw match count. A radius you could not fully enumerate is stated as a boundary, not implied as clean.

### Pass 13: Disposition, cost, and patch labelling

**Hunts:** findings that are correct but written in a way triage will rule 부당.

**Input:** the surviving findings from passes 1 to 12.

**Move.** Rewrite each finding to carry, in this order:

1. the tag from Pass 1;
2. `file:line` at `$HEAD`;
3. what is wrong, in one sentence, in the author's own vocabulary;
4. the evidence: the quoted contract clause, the command output, or the dependent site;
5. **반증**: what you went looking for that would have killed this finding, and did not find. The guard, the covering test, the caller that cannot reach the state, the type that rules the value out (grounding bar item 3), plus the history answer from Pass 2 where one applies. Name the search, not just the conclusion. **A finding with an empty 반증 line is not a defect yet, it is a 질문**, and it moves sections before it ships.
6. the concrete consequence: the input or state that produces it;
7. **비용**: what fixing it takes, honestly. "한 줄" when Pass 4 resolved an instance you already hold; "새 픽스처 필요" when it does not exist; "설계 논의" when the fix is not local.
8. the disposition, one of: fix here, exclude and write the reason in the PR body, follow-up issue, or leave it.

**반증 renders as its own line in the report**, directly under `- 근거:`, in the author's language:

```
- 근거: BazIT.java:41에서 같은 커넥션을 이미 들고 있습니다.
- 반증: 상위 setUp()에 널 가드가 있는지(rg로 3개 상위 클래스 확인), 이 경로를 덮는
  테스트가 있는지(rg로 test 디렉터리 확인) 찾아봤지만 없었습니다. blame 기준 이
  블록은 abc1234 이후 바뀐 적이 없습니다.
```

**Cost-aware disposition is a rule, not a nicety.** For each missing item, separate the cheap from the expensive and say which is which. The expensive ones get the alternative offered in the same breath: "if you exclude it, write the reason in the PR body" costs the author a sentence and closes the point.

**Patches are 힌트, not fixes.** Any code you suggest is labelled as a hint unless you compiled it in the worktree (Pass 6). Say which: "compiled in the worktree" or "미검증 힌트". A suggested line can fail for reasons invisible in the diff, most commonly visibility (the type is package-private), a module boundary, or a generic bound. The finding can be right while the patch is wrong, and an unlabelled wrong patch is what makes an author distrust the rest of the report.

**Final self-check, per finding.** Ask what `review-triage` would rule:

- does it carry a **반증** line, naming a search you actually ran? If not, it has been argued for and never attacked, which is not grounded. Attack it now (grounding bar item 3), or send it out as a 질문.
- would it rule **이미 처리됨** (a 부당 verdict), because a guard, a test, an unreachable caller, or the type already handles it? That is exactly what the 반증 search is for, and it is cheaper to find it yourself than to have the author find it for you.
- for an enumeration finding: was every counted member opened and confirmed runnable, and is the blind spot stated (Pass 3)? If not, it is a "사유 한 줄" 질문, not a defect.
- for a compile-based finding: did the merge base compile clean with the same command (Pass 6)? If the base failed too, drop the finding.
- for a blast-radius finding: does every cited dependent resolve to the changed symbol, and is the count the resolved count (Pass 12)?
- would it rule **부당**, because the premise is unverified or the history explains it? Send it back to Pass 2 or Pass 6, or downgrade it to 질문.
- would it rule **범위 밖**? Move it to the 후속 제안 section (see (b)); do not delete it, do not leave it among the defects.
- would it rule **취향**? Keep it, but mark it 취향 yourself and put it last. Marking your own taste as taste is what earns the defects their credibility.
- is it 확인필요? Then it is a 질문. Write the question so the author can answer it in one line.

A finding that triage would rule 부당 is worse than no finding: it costs the author time and costs you the standing to be believed on the next one.

---

## (b) Scope discipline

Scope is not a courtesy. It is the difference between a review the author acts on and a review the author starts skimming. Apply 범위 밖 to yourself with the same rigour you would want applied to a comment on your own PR.

### The scope boundary, in order of authority

1. **The linked issue's acceptance criteria.** Highest authority: it is what the work was commissioned to do.
2. **The PR body's declarations**: its stated purpose, its rule list, and especially its **exclusion list**. An item the body explicitly excludes is 범위 밖 by declaration.
3. **The commit messages**, for anything the body forgot to mention.
4. **The implicit scope**: the invariants the change itself creates, and the files it touches.

When these conflict (the body promises more than the issue asks, or a commit does something neither mentions), the conflict itself is a finding for Pass 1, and you review against the **union** while naming which source you are using for each finding.

### The test for a single observation

Ask three questions, in order. The first "yes" decides it.

1. **Does the change introduce, reach, or worsen it?** If yes, it is **in scope** regardless of what the contract says. You broke it, you own it. This covers a pre-existing bug the change makes reachable for the first time, and a latent inefficiency the change turns into a hot path.
2. **Does a contract clause name it?** If yes, in scope, tagged with that clause (Pass 1).
3. **Does leaving it break something this PR itself promises?** For example, a residual site inside a file the PR claims to have fully converted. If yes, in scope.

If all three are "no", the observation is **범위 밖**, no matter how correct it is.

### The boundary cases, decided

- **Pre-existing defect on a line the change touches.** 범위 밖 by default: the author moved the line, they did not write the bug. It becomes in scope when the change rewrites that logic anyway (fixing it is now nearly free) or when the change makes it reachable. Either way, say which of the two applies.
- **Pre-existing defect in a changed file but untouched lines.** 범위 밖, always. Offer it as a follow-up.
- **The change makes an existing bad pattern more numerous.** In scope for the new occurrences only. Do not ask the author to convert the old ones in this PR.
- **A better overall design.** 범위 밖 unless the chosen design cannot meet a declared acceptance criterion. "I would have done it differently" is not a finding. "This structure cannot satisfy AC 3, here is why" is a Pass 1 defect.
- **Missing tests.** In scope when the contract promises tests, when the change fixes a bug (the regression test is the proof of the fix), or when the change adds a branch nothing exercises. 범위 밖 when it is about pre-existing untested code.
- **Renames and formatting of untouched code.** 범위 밖, always, and usually not even worth a follow-up.
- **A dependency, tool, or CI upgrade the change would benefit from.** 범위 밖 unless the change actually fails without it.

### What to do with correct observations that are outside scope

Do not delete them, and do not mix them in. Put them in their own section, after the defects and after the 질문, under a heading that says what they are (`후속 제안 (이 PR 범위 밖)`), with:

- one or two lines each, with `file:line`;
- **the concrete risk it removes**, named. This is the admission ticket: if you cannot name what goes wrong by leaving it, drop the item entirely. It keeps the section from growing into a wish list that buries the real findings.
- a proposed home: a follow-up issue, a separate PR, or "the next time this file is touched";
- an explicit line that it does **not** block this PR.

Say it plainly in the report's opening summary too: how many defects, how many 질문, how many 후속 제안. An author who can see that the out-of-scope items are fenced off will read the in-scope ones properly.

### Scope discipline applied to the reviewer

Two failure modes to check yourself for before sending:

- **Volume creep.** A long list of small out-of-scope items, each individually reasonable, is a review the author cannot finish. If the 후속 제안 section is longer than the defect section, cut it to the ones with a named risk.
- **Redesign creep.** Asking for a different structure, a different library, a different naming scheme, or a test framework change, on a PR that set out to do one specific thing. Unless a declared criterion fails, this belongs in an issue, not in a review of someone else's finished work.

And one asymmetry worth holding on to: for a defect, the bar is evidence (Pass 13's grounding rule). For a 후속 제안, the bar is the named risk. For 취향, the bar is that you labelled it 취향 yourself. Nothing gets promoted upward because you feel strongly about it.
