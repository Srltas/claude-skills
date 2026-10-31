---
name: ci-check
description: "Check a CUBRID PR's CI and, when a test job failed, work out whether it is your change, a project-wide failure, a stale base, or a flaky test. Reads the PR's checks and pulls the failing tests from whichever system ran them: CircleCI, classified against recent runs of the same job on other PRs, or the self-hosted GitHub Actions gha-ci workflow (started by `/run` PR comments), classified against develop's own nightly verdicts at the PR's base and newest develop, then other PRs' recent runs. Labels each one 공통 (fails elsewhere or on develop too, not yours), flaky (result flips between runs), 고유 (fails only here). Also reports how far the PR's base is behind, and shows the failure output for the PR-specific ones. Answers 're-run, update the base, or actually investigate?'. Analysis only: it does not re-run CI, comment on the PR, or push anything. Triggers on phrases like 'CI 왜 깨졌어', 'CI 실패 원인 확인', '이 PR CI 확인해줘', 'gha-ci 왜 실패했어', 'flaky인지 봐줘', '재실행하면 되는지 확인', 'why did CI fail on this PR'."
argument-hint: "[PR number or URL, or a gha-ci run URL]"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Triage a CUBRID PR's CI failure

Decide what to do about a red PR: re-run it, update its base, or dig in. Built for submodule bump PRs on `CUBRID/cubrid`, but it works on any PR of that repo. **Analysis only**: it never re-runs CI, never comments on the PR, and never pushes.

## Step 0: How CUBRID's CI is laid out (why this skill works the way it does)

A PR's tests report from **one of two systems**; the script reads whichever one the PR's checks name.

| | CircleCI | gha-ci (self-hosted GitHub Actions) |
|---|---|---|
| Checks on the PR | `ci/circleci: build`, `test_medium`, `test_sql`, `test_shell` | commit statuses `gha-ci: build (debug)`, `gha-ci: build (release)`, `gha-ci: test_sql`, `test_shell`, `test_medium`, each linking to its run |
| Which PRs (today) | release-branch backports | `develop` and `feature/*` bases (its gate skips other bases) |
| Started by | every push | a PR comment: `/run all` (or `shell`, `sql`, `medium`), `/run rerun <run-id>` |
| Failing tests come from | the v1.1 tests API, readable without a token | the logs of the **failed** shards (`shard <suite> NN`): `[NOK]` case lines and a verdict line `assigned N / run N / failed F / skipped S` |
| Baseline for 공통 | none on develop, which runs only `build` and `build_debug`: **recent runs on other PRs** stand in, an approximation | **develop itself**: the nightly batch runs `dispatch all <sha>` on each new develop commit and posts the same statuses there. Compared at the PR's base and at the newest develop commit with a verdict |
| Evidence of flaky | the result flipping across those runs, or a pass on an earlier run of the same commit | a pass on another run of the same build. Then, for a case develop does not explain, **other PRs' recent failed runs** that failed it too |

GitHub Actions' other checks (`code-style`, `cppcheck`, `license`, `pr-style`, the TC Merge Gate, ...) are lint, style, or merge gates, not test results.

gha-ci details that change the answer:

- A comment-started run's own `headSha` is the develop tip, not the PR head. The tested SHA is in the `gate` job's `resolved:` line, which the script reads.
- `/run rerun <run-id>` re-runs that run's failures (plus TCs changed since) and **reuses the build of the same SHA**, so it cannot clear a failure caused by a stale base. Only a base update (a new SHA, a new build) followed by `/run all` can.
- The nightly runs each develop commit once, so a case that fails only now and then can pass there and look 고유. For a case develop does not explain (it passes at the base, or develop has no verdict), the script reads other PRs' failed runs of the last 3 days, at most 40, newest first, and stops once every such case has turned up. A run that failed more than 3 of the suite's shards is left out: that PR broke something, which says nothing about flakiness. A case newer develop passes is not looked up, because PRs on older bases fail it too: that is a stale base, not flakiness.
- The failure diff exists only in the `collect` job's step summary (the API does not expose it) and in each shard's JUnit XML on the internal artifact server `http://192.168.1.48:30080`. For 고유 cases the script tries that server; when it is unreachable, it prints the link, and the diff is on the run page's Summary.

Re-running anything needs a token (CircleCI) or a PR comment (gha-ci), which is why this skill only reports.

## Step 1: Run it

```bash
python3 <skill-base-dir>/assets/ci_check.py [PR]
python3 <skill-base-dir>/assets/ci_check.py https://github.com/CUBRID/cubrid/actions/runs/<run-id>
```

`PR` is a number or URL; with no argument it uses the current branch's PR. Pass a **gha-ci run URL** instead when the user names a run, or when a later push or base update left the failing run off the PR head: the PR's checks show only the current head's statuses. Needs `gh` (authenticated), `curl`, and `python3`.

**A green PR costs nothing**: the script prints the check summary and stops, so this is also the right command for a plain "is CI ok?" question. Test results are downloaded only when a test job actually failed. A gha-ci triage reads a few runs' logs (an sql shard's out of its run's log zip, which `gh` caches; any other job's on its own) and takes about half a minute. Reading other PRs' runs, done only for a case still 고유 or 판정 불가 after develop, adds up to about a minute.

If neither system has reported on the PR head, the script says so: a gha-ci PR needs a `/run all` comment.

## Step 2: Read the classification

For each failing test job or suite the script prints:

| Section | Meaning |
|---|---|
| `N failing test(s), M skipped by bug` (CircleCI), `N failing case(s)` and each failed shard's verdict line (gha-ci) | `skipped` is a deliberate exclusion, never counted as a failure |
| `compared against:` (gha-ci) | the develop verdicts used, at the PR's base and at the newest develop commit with one, this PR's other runs of the same build, and, when looked up, how many of other PRs' recent failed runs were read |
| **공통** | CircleCI: also fails on other PRs' recent runs. gha-ci: also fails on develop. Either way, not caused by this PR |
| **flaky** | CircleCI: the result flips between runs (shown as 실패/성공 counts). gha-ci: passed in another run of the same build |
| **flaky 추정** | gha-ci: develop does not explain it, and other PRs' recent runs failed it too (each PR and run shown). `** 확정 flaky **` when one of those PRs also passed it on the same build and the same testcases |
| **고유** | fails only here (gha-ci: passes on develop at the PR's base, and no recent run of another PR failed it), with an excerpt of the failure output |
| **판정 불가** | no comparison evidence either way |
| `base: <sha>, <branch> is N commit(s) ahead` | how stale the PR's base is, against the branch the PR targets |

A gha-ci 공통 line also shows what newer develop does. `(base 4f1a68c 실패 · develop 5cd1de8 통과)` means the PR's base fails the case and develop has since fixed it: a stale base. The 판단 then names the develop commit whose issue key matches the TC path (`cbrd_27381` → `[CBRD-27381]`), when there is one.

## Step 3: Decide

| What you see | What it means | Do |
|---|---|---|
| 고유 failures | this PR's change is implicated | Compare against the submodule commits in the bump. Read the excerpt: a `core file` line means the server crashed, which is an engine problem, not a TC problem |
| flaky only | intermittent | Re-run: the CircleCI job, or comment `/run rerun <run-id>` for gha-ci |
| gha-ci flaky 추정 | intermittent, most likely, and not this PR | Comment `/run rerun <run-id>`. If it fails again on the same build, compare it against this PR's change |
| 공통 that newer develop also fails | project-wide breakage | Re-running changes nothing, and updating the base does not fix it either. Raise the TC separately or ask its owner |
| gha-ci 공통 that the base fails and newer develop passes | stale base | Update the base, then comment `/run all`. `/run rerun` reuses the same build and cannot fix it |
| mixed | several of the above | Handle each group as above |
| CircleCI: base far behind **and** newer PRs pass the same tests | stale base | Update the base, then re-run |

**Do not report a verdict the data does not support.** On CircleCI, when the comparison sample turns up nothing for a test, the script counts it as 고유; say that it is unproven rather than asserting the bump broke it. On gha-ci, a develop pass is inferred only when the case was in that run's testcases (a TC added after the base's nightly snapshot never ran there), so such a case is 판정 불가, not 고유. When newer develop passes it, the honest answer is "update the base and `/run all` to find out"; when develop says nothing (a `feature/*` base, which the nightly does not test), a same-build `/run rerun <run-id>` at least shows whether it is flaky. A gha-ci flaky 추정 is a strong hint, not proof: another PR can fail the same case for its own reason (a change in the same area, or an older base that lacks a fix). Call it settled only when the script marks it 확정.

## Step 4: Hand off

Report the classification and the recommendation. To act, the user does it: re-running a CircleCI job needs a token, a gha-ci re-run is a PR comment (`/run all`, `/run rerun <run-id>`), and updating the base means pushing. Show the relevant link (the script prints each failed check's URL) so they can act from there.

If the base needs updating on a bump PR, point the user to `/submodule-bump --status` (a manual-only skill), which shows whether an open bump PR already covers the submodule head.
