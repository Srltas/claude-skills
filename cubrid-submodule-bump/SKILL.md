---
name: cubrid-submodule-bump
description: "Pin a CUBRID submodule to a specific commit by dispatching the parent repo's 'Submodule bump (receiver)' GitHub Action, which opens or updates the bump PR on CUBRID/cubrid. Takes a submodule (cubrid-jdbc, cubrid-cci, cubridmanager: the short forms jdbc, cci, cms and the repo name cubrid-manager-server also work) and a commit SHA (or 'latest' for that submodule's develop head). Validates the submodule, the SHA, and the direction of the move before anything is dispatched, and shows the exact command for confirmation first. Use when the automatic bump is stuck, when several submodule commits piled up and you want to catch up in one go, or when you need to pin one specific commit. Triggers on phrases like '서브모듈 SHA 반영', 'jdbc 최신으로 올려줘', 'cci SHA 반영해줘', 'submodule bump 실행', 'cubridmanager SHA 바꿔줘'."
argument-hint: "<jdbc|cci|cms> <sha|latest> [--reanchor]"
---

# Bump a CUBRID submodule to a commit

Dispatch `submodule-bump-receiver.yml` on `CUBRID/cubrid` so the parent repo pins a submodule to the commit you name. The Action opens a bump PR (or updates the open one). Normally the bump is automatic, one commit per PR; run this only when you need to catch up, pin a specific commit, or restart a stalled bump.

**This triggers a real Action and touches a PR on the main repo.** Never dispatch without showing the user what will happen and getting a yes.

## Step 1: Resolve the target

| 사용자가 말하는 것 | 워크플로 입력 `submodule_path` | 서브모듈 저장소 |
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

| 거부 사유 | 뜻 |
|---|---|
| not a bumpable submodule | 허용된 세 개가 아니다 |
| not a commit SHA / not found | SHA 형식이 아니거나 그 저장소에 없는 커밋 |
| not merged into develop | 아직 서브모듈 develop에 머지되지 않았다 |
| already pins … | 이미 그 커밋이 반영되어 있다 |
| BEHIND the pinned one | 과거 커밋이다. 되돌리려면 서브모듈에서 revert 커밋을 만들고 그것을 지정한다 |
| history looks rewritten | 강제 푸시로 이력이 재작성됐다. `--reanchor`가 필요하다 |

## Step 3: Show it and get confirmation

Show the user the summary from Step 2 (pinned -> target, how many commits, the compare link) and ask whether to dispatch. Do not run it on your own initiative.

**지정한 SHA까지의 커밋이 모두 반영된다**: 중간 커밋만 골라 넣을 수 없다. 3번 커밋을 지정하면 1, 2번도 함께 들어간다.

## Step 4: Dispatch

```bash
bash <skill-base-dir>/assets/bump_submodule.sh <submodule> <sha|latest> --run
```

Then report the run:

```bash
gh run list --repo CUBRID/cubrid --workflow submodule-bump-receiver.yml --limit 3
```

## `--reanchor` (평소에는 쓰지 않는다)

부모 저장소는 어디까지 반영했는지 기준 커밋 하나를 기록해 둔다. 서브모듈에서 **강제 푸시로 이력이 재작성되면** 그 기준 커밋이 사라져 워크플로가 멈춘다. `--reanchor`는 그때만 쓴다: 새 이력에서 대응하는 커밋의 SHA를 지정해 기록을 그 위치로 다시 붙인다.

이력이 정상일 때는 붙여도 소용이 없고, **반영 위치를 과거로 되돌리는 데는 쓸 수 없다.** 사용자가 명시적으로 요청할 때만 붙인다: 스스로 판단해서 추가하지 않는다.

## Guardrails

- 이 스킬은 **`CUBRID/cubrid`의 `submodule-bump-receiver.yml` 하나만** 실행한다. 다른 워크플로나 저장소를 대상으로 `gh workflow run`을 쓰지 않는다.
- 허용된 세 서브모듈 밖의 입력은 **gh를 실행하지 않고** 거부한다.
- 검증(Step 2) 없이 바로 `--run`을 쓰지 않는다.
- 실패해도 부모 저장소는 바뀌지 않는다. 잘못된 입력은 반영 전에 거부된다.
