# Fan-out: the agent packet, the return shape, and merging

The passes are dispatched to independent subagents with the **Agent tool** so each angle is judged without seeing the others' conclusions. Independence is the point: an agent that has read another agent's verdict will anchor on it, which reproduces exactly the tunnel vision the skill exists to break.

## When not to fan out

Fan-out costs a lot of tokens and buys nothing on a small change. Run the passes yourself, in order, in one sequence when any of these hold:

- the change set is a single file, or under roughly 150 changed lines across at most 3 files
- the work is one narrow commit with a single obvious purpose
- the tree does not compile, or the change set is empty: report that first and stop

For a mid-size change, dispatch agents A through D and run group E (관례·이름) yourself, since it is the cheapest group and needs no isolation.

## Grouping

Five groups, related passes together, dispatched in **one message** so they run in parallel.

| Agent | Passes | Angle |
|---|---|---|
| A 계약·완전성 | 1, 2 | contract conformance, enumerated-set diffs, residual sites, counts |
| B 전제·파급 | 3, 7 | premise verification, build artifacts, blast radius, scope containment |
| C 의미·실패경로 | 4, 5 | old-versus-new semantics, strengthening risk, cleanup and failure paths |
| D 사각지대 | 6 | the cases the author never considered (runs alone, it is the deepest pass) |
| E 관례·이름 | 8, 9 | sibling conventions, internal consistency, name versus behaviour |

## Context packet handed to every agent

Identical for all five, plus that agent's own pass text from `references/passes.md`:

1. **The change set**: the exact commands that reproduce it, covering **uncommitted and untracked work** (`git status --porcelain`, `git diff`, `git diff --cached`, plus untracked files by path), because this skill runs before a PR exists. Hand over the `assets/review_context.sh` output as well. Instruct the agent to read whole files, not hunks.
2. **The contract table** from Step 1, verbatim: the issue's AC / Specification Changes / Implementation notes, the commit subjects, the author's stated rule, and an explicit statement of what is missing ("PR 본문 없음", "이슈 없음"). Verbatim matters: findings cite the clause in its own words.
3. **Repo facts**: build and test commands, where dependency artifacts resolve from, module layout, and pointers to **cubrid-manual** / **cmt-manual** for product-behavior questions.
4. **The evidence bar** from `references/output.md`, quoted in full.
5. **The return shape** below, as the only accepted output format.
6. **Persona**: you are a hostile, meticulous reviewer of code you did not write. Your job is to find what the author did not think about. Do not summarize, do not praise, do not say the change looks good overall. Do not soften a finding, and do not invent one.
7. **Prohibitions**: read-only. Do not edit, format, stage, commit, push, or post anything. Never run `git checkout`, `git restore`, `git stash`, or `git clean`: the tree holds the user's uncommitted work. Do not fix what you find, report it.
8. **Anti-contamination**: judge only from the sources handed to you. Do not consult other agents, and never assume another pass covers something. If you see it, report it. Deduplication is the orchestrator's job, not yours.
9. **Calibration**: before returning a finding, try to refute it yourself (an existing guard, a test that already covers it, a call site that cannot reach that state, a fix already made elsewhere in this same change set). A finding survives only if you failed to refute it. A reviewer is judged by hit rate, not by volume. Anything you cannot evidence goes in `unverified`, not in `findings`.

## Fixed return shape

Every agent returns exactly this, and nothing else:

````
### findings
```yaml
- id: A1
  pass: 1
  file: path/to/File.java
  line: "69-72"
  claim: <one sentence, the defect stated as a claim>
  authority: <the clause in its own words, or "reviewer invariant">
  evidence: <file:line quote, command + output, or manual/spec sentence>
  sites: <other occurrences of the same root cause, with line numbers>
  severity: high | medium | low
  cost: <how expensive the fix is>
  fix: <paste-ready line(s), or "none">
  fix_verified: compiled | not compiled
  alternative: <recording the decision, if that closes it>
  confidence: confirmed | plausible
```

### verified_passing
- <what you checked and found correct, with the specific evidence>

### unverified
- <what you could not establish> | question: <the exact question> | command: <what would settle it>

### commands_run
- <every command you actually executed>
````

`commands_run` is mandatory: it is how the orchestrator detects fabricated line numbers and invented counts.

## Merging

1. **Drop anything failing the evidence bar.** No `file:line`, no citation, no run means it does not ship. Do not repair a weak finding by inventing evidence for it.
2. **Deduplicate by root cause, not by text.** Key on (file, overlapping line range, defect). Two agents describing the same defect merge into one finding: keep the strongest evidence, and keep the tag from the higher-authority pass (contract > premise > semantics and failure paths > blast radius > blind spots > name > convention).
3. **Collapse repeats, unless the sites ask the author different questions.** One root cause across many lines is one finding with a counted site list, not N findings. The author fixes it in one pass, so report it in one entry.

   **Exception: split when the question the author must answer differs by site, even when the root cause is single.** The test is mechanical, and it is run before merging, not after: write out, per site, the one question the author has to answer to close that site. Merge only if one decision, taken once, closes all of them. Split if the answers can diverge, which they do whenever a site needs its own value, name, boundary, type, or message; whenever the keep-or-drop judgement is made per site; whenever the patch shape differs site to site; or whenever a different clause of the contract decides it. Interchangeable sites merge. Sites that share a cause but need individual answers do not. What does *not* count as a different question: a different line number, a different file, or the same identical patch restated. Volume is still not the goal.

   Merging across differing questions is worse than the extra entries it saves, because the counted site list carries the cause but drops the per-site decision, and the author is left with one entry they cannot answer. When you split, name the shared cause identically in every entry and append the counted modifier (`, 같은 원인 3곳 중 1번째`) so the author reads it as one cause with three decisions, not as three unrelated defects. Illustration only: several inline comments wrong for one reason, each describing a different constant, each needing a different replacement text, are separate findings under one shared tag.
4. **Never resolve a conflict by vote.** When one agent says a site is fine and another says it is broken, re-verify it yourself by running the check. If it is still open, output 확인필요 carrying both positions.
5. **Re-check against the whole change set.** Drop findings the author already handled in a file no agent looked at.
6. **Merge `verified_passing`** into one list, minus anything another agent contradicted, and keep the specifics.
7. **Merge `unverified`** into the 확인필요 bucket, each with its settling command.
8. **Cap noise.** If a bucket exceeds roughly ten entries after step 3, merge further by root cause. The deliverable is a ranked list a person can act on in one sitting. Entries split under rule 3's exception are exempt from this further merge, since merging is what would destroy the answer: group them under one shared root-cause heading and count the whole group as one entry against the cap.
