---
name: ci-check
description: "Check a CUBRID PR's CI and, when a test job failed, work out whether it is your change, a project-wide failure, or a flaky test. Reads the PR's checks, pulls the failing tests from CircleCI, and classifies each one against recent runs of the same job on other PRs: 공통 (fails elsewhere too, not yours), flaky (result flips between runs), 고유 (fails only here). Also reports how far the PR's base is behind develop, and shows the failure output for the PR-specific ones. Answers 're-run, update the base, or actually investigate?'. Analysis only: it does not re-run CI or push anything. Triggers on phrases like 'CI 왜 깨졌어', 'CI 실패 원인 확인', '이 PR CI 확인해줘', 'flaky인지 봐줘', '재실행하면 되는지 확인', 'why did CI fail on this PR'."
argument-hint: "[PR number or URL]"
---

# Triage a CUBRID PR's CI failure

Decide what to do about a red PR: re-run it, update its base, or dig in. Built for submodule bump PRs on `CUBRID/cubrid`, but it works on any PR of that repo. **Analysis only**: it never re-runs CI and never pushes.

## Step 0: How CUBRID's CI is laid out (why this skill works the way it does)

- The real tests run on **CircleCI** (`build`, `build_debug`, `test_medium`, `test_sql`, `test_shell`). GitHub Actions only carries lint and style checks (`code-style`, `cppcheck`, `license`, `pr-style`, ...).
- CircleCI's v1.1 API is readable **without a token** for this public project, so failing tests and their output can be pulled directly. Re-running a job, however, needs a token, which is why this skill only reports.
- **`develop` runs only `build` and `build_debug`.** There is no develop run of the test jobs, so there is no baseline saying "this test is already broken on develop". The skill uses **recent runs of the same job on other PRs** as a stand-in. That is an approximation: treat 공통 as strong evidence, not proof.

## Step 1: Run it

```bash
python3 <skill-base-dir>/assets/ci_check.py [PR]
```

`PR` is a number or URL; with no argument it uses the current branch's PR. Needs `gh` (authenticated), `curl`, and `python3`.

**A green PR costs nothing**: the script prints the check summary and stops. The 1-2 MB test payloads are downloaded only when a CircleCI test job actually failed, so this is also the right command for a plain "is CI ok?" question.

## Step 2: Read the classification

For each failing test job the script prints:

| Section | Meaning |
|---|---|
| `N failing test(s), M skipped by bug` | `skipped` is a deliberate exclusion, never counted as a failure |
| **공통** | the same test also fails on other PRs' recent runs: not caused by this PR |
| **flaky** | the result flips between runs (shown as 실패/성공 counts) |
| **고유** | fails only here, with an excerpt of the actual failure output |
| `base: <sha>, develop is N commit(s) ahead` | how stale the PR's base is |

## Step 3: Decide

| What you see | What it means | Do |
|---|---|---|
| 고유 failures | this PR's change is implicated | Compare against the submodule commits in the bump. Read the excerpt: a `core file` line means the server crashed, which is an engine problem, not a TC problem |
| flaky only | intermittent | Re-run the job |
| 공통 only | project-wide breakage | Re-running changes nothing, and updating the base does not fix it either. Raise the TC separately or ask its owner |
| mixed | both | Re-run for the flaky ones, handle 공통 separately |
| base far behind develop **and** newer PRs pass the same tests | stale base | Update the base, then re-run |

**Do not report a verdict the data does not support.** When the comparison sample turns up nothing for a test, the script counts it as 고유; say that it is unproven rather than asserting the bump broke it.

## Step 4: Hand off

Report the classification and the recommendation. To act, the user does it: re-running a CircleCI job needs a token, and updating the base means pushing. Show the relevant link (the script prints each failed check's URL) so they can re-run from the CircleCI UI.

If the base needs updating on a bump PR, the **submodule-bump** skill's `--status` shows whether an open bump PR already covers the submodule head.
