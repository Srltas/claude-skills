---
name: submodule-bump
description: "Pin a CUBRID submodule to a specific commit by dispatching the parent repo's 'Submodule bump (receiver)' GitHub Action, which opens or updates the bump PR on CUBRID/cubrid. Takes a submodule (cubrid-jdbc, cubrid-cci, cubridmanager: the short forms jdbc, cci, cms and the repo name cubrid-manager-server also work) and a commit SHA (or 'latest' for that submodule's develop head). Validates the submodule, the SHA, and the direction of the move before anything is dispatched, and shows the exact command for confirmation first. `--status` is a read-only overview: with no submodule it reports all three (pinned, head, how many commits behind, the open bump PR), and with one it lists that submodule's pending commits so you can pick how far to bump. Use when the automatic bump is stuck, when several submodule commits piled up and you want to catch up in one go, or when you need to pin one specific commit. Triggers on phrases like '서브모듈 상태 확인', '밀린 서브모듈 있나', '서브모듈 SHA 반영', 'jdbc 최신으로 올려줘', 'cci SHA 반영해줘', 'submodule bump 실행', 'cubridmanager SHA 바꿔줘'."
argument-hint: "[jdbc|cci|cms] <sha|latest|--status> [--reanchor]"
---

# Bump a CUBRID submodule to a commit

Dispatch `submodule-bump-receiver.yml` on `CUBRID/cubrid` so the parent repo pins a submodule to the commit you name. The Action opens a bump PR (or updates the open one). Normally the bump is automatic, one commit per PR; run this only when you need to catch up, pin a specific commit, or restart a stalled bump.

**This triggers a real Action and touches a PR on the main repo.** Never dispatch without showing the user what will happen and getting a yes.

## Step 0: Check the state first (read-only)

```bash
bash <skill-base-dir>/assets/bump_submodule.sh --status             # all three, at a glance
bash <skill-base-dir>/assets/bump_submodule.sh <submodule> --status # that one's pending commits
```

Read-only, so run it without asking first. One call reports, for all three submodules, the pinned SHA, the submodule head, how many commits are pending, and the open bump PR.

**When the open PR already pins the head there is nothing to dispatch**: merging that PR is the whole job. The script says `just merge it` in that case, so guide the user to merge rather than suggesting a run.

The per-submodule view lists only the commits added **after** the pinned one, oldest first and numbered (up to 20; beyond that it states how many remain). That number is exactly "how far to bump", so pick the SHA here when the user wants to stop at a specific commit.

## Step 1: Resolve the target

| What the user says | workflow input `submodule_path` | submodule repo |
|---|---|---|
| `jdbc`, `cubrid-jdbc` | `cubrid-jdbc` | `cubrid/cubrid-jdbc` |
| `cci`, `cubrid-cci` | `cubrid-cci` | `CUBRID/cubrid-cci` |
| `cms`, `manager`, `cubridmanager`, `cubrid-manager-server` | `cubridmanager` | `CUBRID/cubrid-manager-server` |

`cubrid-manager-server` is the repository name; `cubridmanager` is the submodule path the workflow expects. The helper accepts either.

The SHA can be a full 40-char SHA, a short SHA (it is expanded), or `latest` for that submodule's `develop` head. Anything else is rejected.

## Step 2: Validate (dry run, dispatches nothing)

```bash
bash <skill-base-dir>/assets/bump_submodule.sh <submodule> <sha|latest>
```

It prints the currently pinned SHA, the target, the direction of the move, and a compare link, then shows the exact `gh` command **without running it**. It refuses, and dispatches nothing, when:

| Refusal | Meaning |
|---|---|
| not a bumpable submodule | not one of the three allowed |
| not a commit SHA / not found | not a SHA, or no such commit in that repo |
| not merged into develop | the commit is not on the submodule's develop yet |
| already pins … | that commit is already pinned |
| BEHIND the pinned one | it is an older commit. To roll back, make a revert commit in the submodule and pin that |
| history looks rewritten | a force-push rewrote history. `--reanchor` is required |

## Step 3: Show it and get confirmation

Show the user the summary from Step 2 (pinned -> target, how many commits, the compare link) and ask whether to dispatch. Do not run it on your own initiative.

**Everything up to the chosen SHA comes in**: you cannot cherry-pick a middle commit. Naming commit 3 brings 1 and 2 with it.

## Step 4: Dispatch

```bash
bash <skill-base-dir>/assets/bump_submodule.sh <submodule> <sha|latest> --run
```

Then report the run:

```bash
gh run list --repo CUBRID/cubrid --workflow submodule-bump-receiver.yml --limit 3
```

## `--reanchor` (normally never)

The parent records one anchor commit to mark how far it has bumped. If a **force-push rewrites the submodule's history**, that anchor disappears from develop and the workflow stops. `--reanchor` is only for that: name the corresponding commit in the new history and it re-attaches the anchor there.

On healthy history it does nothing, and it **cannot move the pin backward.** Add it only when the user explicitly asks: never on your own judgement.

## Guardrails

- This skill runs **only `submodule-bump-receiver.yml` on `CUBRID/cubrid`**. Never point `gh workflow run` at another workflow or repo.
- Anything outside the three allowed submodules is refused **without running gh at all**.
- Never jump to `--run` without the Step 2 validation.
- A failure leaves the parent repo untouched: bad input is refused before anything is pinned.
