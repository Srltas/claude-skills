# The nine review passes, in full

Each pass names what it hunts, the input it needs, and the moves to perform. **Run every pass.** A pass that finds nothing still produces output: the list of what it verified as passing, which is what makes the findings that do land credible.

Two standing rules for all passes:

- **Read whole files, not hunks.** The diff view actively hides the most common defect in this kind of work: a site that should have changed and did not is simply absent from the diff.
- **Read the minus side.** Deleted lines are executable code that a reviewer skimming the `+` side never evaluates.

## Pass 1: Contract conformance

- **Hunts**: clauses of the declared contract that the change does not actually satisfy, and clauses it satisfies only halfway.
- **Input**: the contract table from Step 1 (Jira Acceptance Criteria / Specification Changes / Implementation notes, verbatim), the commit subjects on this branch, the author's own stated rule for this work, and the implementation source the change exercises. There is usually no PR body at this stage, so the commit subjects and the issue are the whole contract.
- **Move**:
  1. For every clause that names a **set**, enumerate the real set from the source and diff it against what the change covers. Two clause shapes name a set: one carries a **number**, whether a single figure, a sum, or a range ("핸들러 4개", "호출 지점 24곳"), the other carries a **plural or a category noun that states no size** ("상속 클래스", "모든 구현체", "각 서브클래스", "관련 테스트", "the affected call sites"). A declared number is itself a claim to re-derive, not a target to match: derive the population first and compare afterwards, or you will stop enumerating the moment your count reaches the declared one. The unsized form is the more dangerous of the two, because there is no digit to reconcile and the clause reads as satisfied the moment one member is handled. Build the set the same way for both, from the source and never from the diff or from memory: `git grep -l <symbol>`, `git grep -n "class .* extends <Base>"`, `git grep -n "implements <Interface>"`, the enum's own constants, the type hierarchy in the resolved artifact (`javap`), the file listing of the parallel module. Write the members out one per line, mark each covered or not, and state the size you derived. Never accept a declared number at face value, never read "모든"/"전부"/"각" as evidence that the set was walked, and never accept the change's own claim to satisfy the clause.
  2. **Resolve the concrete type of every fixture the change tests.** For each member that came out uncovered in move 1, and for each object the change exercises, find in the implementation source the factory method, constructor, or accessor that produces that type (`git grep -n "<Type> [a-zA-Z]*(" <impl path>`, the return type of the setup method, the runtime type behind a declared interface), then check whether the change **already holds such an instance**: an existing field, a local in the changed method, a fixture the setup already builds, or an object reachable in one call from one it holds. A declared type is not the runtime type, so resolve it instead of reading it off the variable declaration. The answer decides the finding's action, and only the action makes the finding usable: "이미 인스턴스를 들고 있으므로 한 줄만 추가하면 됩니다" is a different request from "새 테스트와 픽스처가 필요합니다". Filing the second when the first is true hands back a correct finding the author still has to re-analyse before acting on it.
  3. For every clause that is a **table row or a conjunction**, split it into atoms and check that each atom is separately asserted. The atoms are whatever the clause joins with "and", a comma, or a parenthesis: type and code and message, status and body and header, row written and index updated and audit line emitted. Write them out one per line before checking, because a conjunction read as one sentence reads as satisfied the moment its first atom is, and the atom that goes unasserted is almost always the last one (the human-readable part: the message, the log line, the reason field). One unasserted atom is a half-satisfied row and it is a finding at the same severity as the whole row. Illustration: "400 응답 + 오류 코드 INVALID_RANGE + 메시지에 필드명 포함" is three atoms, not one.
  4. For every clause implying a **matrix** (open/closed x class, each type x each state), draw the matrix and name the empty cells.
  5. **Recount the declared numbers yourself** and reconcile against every count source you have: `git diff --stat`, `git diff -U0 | grep -c '^+.*<pattern>'`. An unsized clause has no declared number to reconcile, so report the size you built in move 1 and the covered/uncovered split in its place. Report the matches as well as the mismatches; saying "이슈 수치와 정확히 일치합니다" for the parts that are right is what makes the one mismatch believable.
  6. **Rule drift back-propagation**: when the change follows a rule the issue does not contain, the finding is "update the issue", not "revert the code".
  7. **No contract at all** (no issue, no stated rule, commit subjects that say only "fix") is itself finding #0, because there is then nothing to review against except taste.

## Pass 2: Completeness and residual sites

- **Hunts**: the sites that match the change's own pattern and were left untouched. Partial mechanical conversion is the default failure mode of sweep work.
- **Input**: the pre-change idiom read off the minus side, the whole changed file, the module, the declared exclusion wording, and section 4b of `assets/review_context.sh`.
- **Move**:
  1. Grep the pre-change shape in the changed file first, then the module, then the tree. Subtract the declared exclusion set. Report the residue with exact line numbers and a count. **When the shape or the exclusion spans more than one line, a single-line grep cannot separate them**: an exclusion defined by a code shape rather than by a token (the same call inside an empty catch, inside a try, inside a loop, under an annotation on the line above) never appears on the line the token is on, so a one-line grep either returns the union or returns nothing. Pull each set with a context-carrying or multi-line search, `grep -n -A3 '<old form>'` and `grep -n -A3 '<exclusion form>'` (or `grep -Pzo` with the shape written across lines), then subtract the second set from the first on the `파일:행` key rather than by eye. Put both commands and the size of each set in the output: a wrong exclusion pattern then shows up as a wrong count instead of silently swallowing the residue.
  2. **Prove the residue is not excluded** by re-reading the exclusion literally, word by word, and testing each residual site against those words rather than against the intent you infer from them. An exclusion names a shape, and a site one nesting level away from that shape is not the shape: "이미 재시도 래퍼 안에 있는 호출은 제외" does not cover a call whose *caller* is wrapped, and "생성 파일 제외" does not cover a file a generator once produced and a human has since edited. Quote the exclusion and the residual site side by side in the finding. This proof step is what makes the finding stick, and skipping it is how a review reports residue the author deliberately excluded.
  3. Count what was **correctly left alone** and report that number too.
  4. **Mixed idiom inside one file**: when the old and new forms of the same idiom both survive in one file, raise it even when the omission is defensible, using the maintainer argument (a file with two conventions leaves the next editor no rule to follow). Offer both resolutions: convert all, or defer all and record the deferral.
  5. Check the same completeness question one level up: sibling test classes, the parallel module, the other direction of a read/write pair.

## Pass 3: Premise verification

- **Hunts**: symbols, fields, versions, options, and behaviors the new code assumes exist but that the environment the tree actually builds and runs against does not provide. This is the only finding class where the whole change fails to compile in a real environment, and it is invisible to any reviewer whose local setup is newer.
- **Input**: the resolved dependency artifacts (not the source you can browse), the base branch, the official manual, the build command.
- **Move**:
  1. For every symbol the new code references that is not defined in this tree, verify it exists **in the artifact the build resolves**: `javap -p -cp <bundled.jar> <Class> | grep <field>`, `unzip -l`, the dependency lock or the checked-in jar. Do not trust the IDE, a locally newer driver, or a newer branch of the dependency.
  2. **Count all references including ones already on the base branch** (`git grep -n <symbol> <base>` versus the working tree) and state clearly whether this change introduced the premise or merely widened it. Attributing blame correctly is what makes the finding land as a request for one documentation line rather than a rewrite.
  3. Verify version claims: which build introduced the symbol, and whether the pinned dependency includes it.
  4. If code was copied from an upstream project, diff it line by line against the named upstream version and **enumerate what you compared** (overload count, return value, message text, private helpers).
  5. Verify every product-behavior claim against the manual (**cubrid-manual**, **cmt-manual**, or the JDBC/JPA spec), never against memory.
  6. **Compile against the bundled classpath first, then `javap` only what the compiler rejected.** Fire this whenever either trigger holds: (a) the change class can break compilation (lambda capture, effectively-final, type inference, generics, an added or changed signature, a widened `throws`), or (b) the change references a symbol that resolves only through a checked-in binary or a pinned dependency rather than through source in this tree (a jar in the repo, a driver artifact, a generated class, a shaded package). The order is what bounds the cost: one compile against the classpath the build actually resolves settles every referenced symbol at once, and `javap -p` from move 1 is then run only on the symbols the compiler rejected, to establish whether the artifact has the member under a different name, signature, or visibility. Symbol-by-symbol `javap` before compiling costs one command per symbol and still misses the failures only the compiler sees (inference, ambiguity, checked exceptions). Run the directly related tests when they are cheap. Report the exact command and its result, pass or fail.
  7. Where a stated future path exists ("later this is just an import swap"), verify it **by absence**: grep for the symbols that would break it and report the count, ideally zero.
  8. A premise you cannot check locally goes out as 확인필요 with the command that would settle it.

## Pass 4: Semantic delta

- **Hunts**: assertions and behaviors that got quietly stronger, weaker, or retyped inside a change advertised as mechanical.
- **Input**: the minus side read as executable code, plus knowledge of whether a pinned constant is stable.
- **Move**:
  1. Per site, write **old semantics and new semantics as a pair**, then classify the delta: 강화 / 약화 / 타입 변경 / 동등.
  2. Flag every site where the **old code could pass without the condition holding**. The test is mechanical: name the input that would have made the old site fail. If you cannot name one, the old site was decorative, and saying so plainly is the justification for the change, which belongs in the review. The recurring shapes are the swallowed error (caught and only logged, a non-zero exit status ignored, a `|| true` in the script), the absent assertion, the assertion whose expected value is computed from the actual value, a condition evaluated and then discarded, and a branch no fixture reaches. Illustration: a config-parser test that runs the parser inside a try, logs whatever it catches, and never inspects the parsed result passes on a valid file, on a malformed file, and on a file that does not exist.
  3. Flag every **weakening** and every case where a change sold as a strengthening is actually equivalent.
  4. Risk-test every **strengthening that pins a new constant**: an error code, a message string, a generated id, a row count, a timestamp format, an ordering. For each one, name what makes the value vary (server or library version, code path, batch position, locale, timezone, platform, build id, whether another fixture ran first), and say whether anything in the tree guarantees it. Then count them with a command, because every newly pinned constant is one new way for CI to go red and the count is the number of new failure modes this change buys: `git diff -U0 | grep -cE '^\+.*<상수 패턴>'`. Report that number and the riskiest class inside it; a general worry about brittleness with no count attached is not a finding.
  5. Hunt the **outlier**: in a change advertised as mechanical, find the one site where the expected type or contract changed rather than the syntax, and establish whether it is the only one. The uniqueness claim requires having classified all of them, so classify all of them.
  6. Ask of each new assertion: what input makes this fail while the production code is still correct.

## Pass 5: Failure paths and resources

- **Hunts**: what happens on the path nobody exercises, and what cleanup the new shape dropped.
- **Input**: the minus side again, this time reading the cleanup rather than the assertion.
- **Move**:
  1. Diff the **cleanup behavior** across the refactor: `close()`, `finally`, rollback, temp table drop, restored config, reset system property. Refactors into lambdas silently orphan resources on the unexpected-success path.
  2. Walk the branch where the expected exception does **not** occur, and the branch where setup itself fails.
  3. Check test isolation: does a failing case leave state that breaks the next test, and does the change introduce an order dependence.
  4. Check resource ownership in the new shape: try-with-resources coverage, connections and statements created inside a lambda, streams, temp files.
  5. **Check whether the changed or added test actually runs**, and fold the answer into severity: look for `@Ignore` / `@Disabled` / `@SkipForDialect` / an `assumeTrue` style guard on the method **and on its class**, and for the method being excluded by the build's own test filters. A defect inside a test that never executes is a documentation defect rather than a runtime one; a test this change silently disabled is a finding of its own, at high severity, even when the body reads correctly.
  6. Set severity honestly. A leak confined to the already-failing path is real and low severity, and saying so is what buys credibility for the high-severity findings.

## Pass 6: Blind spots (the anti-tunnel-vision pass)

- **Hunts**: the cases the author never wrote down, because they were going in one direction. This pass is the reason the skill exists.
- **Input**: the change, and an explicit instruction to ignore the author's framing of what the change is about.
- **Move**:
  1. **Write the input that makes it wrong**, then check whether the code or a test rules that input out. If nothing does, that is the finding.
  2. Walk the axes the author did not mention, one at a time, and record a verdict for each: null / empty / zero / negative / maximum, boundary and off-by-one, multibyte and byte-versus-char length, timezone and DST, locale and collation, precision and rounding, overflow and truncation, duplicate execution, concurrent execution, ordering assumed without an explicit ORDER BY, empty result set, transaction and autocommit state, connection loss and retry, client/server version skew, platform differences (path separator, line endings), and 32-bit versus 64-bit.
  3. **State the assumption the change silently makes**, then find the call site or configuration where that assumption is not guaranteed.
  4. **Take the opposite direction of every choice**: if the author handled X, what breaks in the Y case they did not handle.
  5. Check the **reverse operation** exists and matches: write/read, encode/decode, set/get, migrate/rollback, open/close.
  6. Return the blind spots ranked by how easy they are to miss, each with the concrete input that triggers it. A blind spot with no concrete input is not a finding, it is a worry, and it goes to 확인필요 or gets dropped.

## Pass 7: Blast radius and scope

- **Hunts**: effects outside the file being edited, and changes the author made without noticing they made them.
- **Input**: the full change set including uncommitted and untracked files, the base branch, repo-wide grep.
- **Move**:
  1. `git grep -n` every changed symbol, constant, config key, and default value: do all existing call sites survive the new behavior.
  2. **Scope containment**: list files changed outside what the issue explains, and say so explicitly when there are none.
  3. **Unannounced side effects**: a widened `throws` clause (setup failures now propagate as test failures), a visibility change, a changed default, a new dependency, a regenerated file, formatting churn hiding a real edit. Each one is a finding of the form "this may be intended, but nothing records it".
  4. Compatibility surfaces: public API, serialized form, DB schema, config file format, log output others parse.
  5. If the branch will be reviewed commit by commit, check each commit stands on its own.

## Pass 8: Local convention from siblings

- **Hunts**: divergence from the unwritten rules of this tree, and inconsistency inside the changed file itself.
- **Input**: 3 to 5 adjacent files, the immediate subdirectory, any formatter config, and section 5 of `assets/review_context.sh`.
- **Move**:
  1. If a formatter or lint config exists (`.editorconfig`, spotless, google-java-format), **the config is the authority**: run it, diff, and do not opine. See the **java-format** skill.
  2. Otherwise derive the de facto rule from siblings, at **two levels of locality**: the whole tree (for example wildcard imports) and the immediate subdirectory (for example whether that package calls `Assert.assertTrue(...)` explicitly).
  3. Compare in **two directions**: external (this file versus its neighbours) and internal (this block versus the rest of the same file, with line numbers). The internal inconsistency is the part a formatter-style complaint usually misses.
  4. Cover imports (wildcard, static, unused), indentation, file placement in the directory layout, test method ordering, message and log phrasing, and in-file precedent for an idiom used two ways.
  5. **Count the repetition the change itself introduces.** This pass owns the `[중복]` tag; no other pass hunts it, so if you skip this move the tag is minted and never used. On the `+` side only, look for a block of 3 or more lines of identical shape (same statements and same call sequence, differing only in literals, names, or types) repeated N times inside one file. Report N, the line ranges, and what varies between the copies, then raise helper extraction (a private helper, a parameterized test, a table-driven loop) as 판단 사항 with the extracted signature written out. Two limits bound it: repetition already present on the base branch is not this change's finding, so say so and move on; and if the helper would conflict with a constraint this work declared elsewhere (the issue asks each case to stay independently readable, every sibling file repeats the same block, a parameterized form would lose the per-case assertion or the per-case name), write the conflict down and recommend 현행 유지. This one is measured inside the change rather than derived from the neighbours, so it goes out under the invariant tag and not under the optional label in move 6.
  6. **Label everything derived this way as optional and disclose it out loud**: there is no documented standard, this is the neighbouring code's habit.

## Pass 9: Name versus behaviour

- **Hunts**: names, messages, and comments that promise something the body does not deliver.
- **Input**: the diff alone, plus the commit subjects.
- **Move**:
  1. Read each test name as a claim and the body as the evidence, then compare. Propose a replacement name **derived from the body**, not from taste.
  2. Do the same for method names, variables, constants, exception and log message text.
  3. **Commit subject versus commit diff.** With no PR body, the commit subjects are the closest thing to a declared contract, so a subject that overstates or misdescribes its diff is a contract defect, not a style nit. Check the Conventional Commit type and scope too (see the **commit** skill).
  4. Comments and docs versus code: stale comments describing the old behavior, a TODO left behind, a README or changelog line the change invalidated.
