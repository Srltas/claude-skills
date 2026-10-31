---
name: pr-review
description: "Review someone else's pull request in depth from its URL or number: reads every changed file in a separate worktree, learns why the code is the way it is before calling a defect, and returns a ranked Korean report of defects, judgment calls, and questions. Posts nothing. For your own work use self-review; for comments on your PR use review-triage. Triggers on phrases like '이 PR 리뷰해줘', '남의 PR 검토해줘'."
argument-hint: "[PR URL or number] [optional JIRA key]"
allowed-tools:
  - "Bash(bash ${CLAUDE_SKILL_DIR}/assets/fetch_pr.sh *)"
  - "Bash(${CLAUDE_SKILL_DIR}/assets/fetch_pr.sh *)"
---

# Review someone else's pull request

Input: a PR URL or number, optionally a Jira key. Output: one ranked Korean report handed to the user, who decides whether any line of it is worth posting. **This skill posts nothing and edits nothing.**

## The stance

Reviewing someone else's code fails in the opposite direction from reviewing your own. On your own work you go easy. On someone else's you assert a defect you have misread, because you do not know why the code is the way it is.

- **Ground it before you call it.** A defect needs `git log` and `git blame` on the touched lines, the PR body, the linked issue, or a prior PR on the same file. No grounding, no defect.
- **Ungrounded observations go out as 질문**, addressed to the author, never as assertions.
- **It has to survive review-triage.** This report is the exact input to the sibling `review-triage` skill, which rules each comment 타당 / 부분 / 부당 / 범위 밖 / 취향 / 확인필요. A finding ruled 부당 is worse than no finding: it costs the author time and costs you the credibility that carries the next twenty findings.
- **Apply 범위 밖 to yourself.** A correct observation about something this PR never set out to do is a follow-up suggestion, marked as one, never mixed into the defect list.
- **Tone: a colleague, not an auditor.** Acknowledge that something is legal or intentional before pointing at it, say what the fix costs, and grant the exception yourself when the author plausibly had a reason.

## Step 1: Put the PR on this machine

```bash
${CLAUDE_SKILL_DIR}/assets/fetch_pr.sh https://github.com/OWNER/REPO/pull/1629 CBRD-12345
```

It resolves the repository against **every** remote (`origin` is often the reviewer's own fork), fetches `refs/pull/N/head` into `refs/pr/N` and the base branch into `refs/pr-base/N`, expands a **detached worktree** under scratch, and prints repo, PR, title, author, base/head/merge-base, the worktree path, and every changed file with its +/- counts. If the repo is not on this machine it bare-clones into a scratch cache: the worktree holds the only checkout, so nothing is duplicated, and the next review of that repo is fast. The base is kept as a ref, not a branch, which is why cleanup removes two refs.

Take `$WT` (worktree), `$REPO_DIR`, `$MERGE_BASE` and `$HEAD_SHA` from its output. Never `gh pr checkout`, never `git checkout` / `switch` / `stash` anywhere the user works.

## Step 2: Freeze the contract before opening the diff

Follow `references/contract.md`. Gather the PR body, the Jira issue, the commit messages, linked PRs, the blame of the touched lines **at the base**, the dependency artifact the build actually resolves, and the conventions of neighbouring files. Write the contract ledger (ID / 출처 / 원문 인용 / 검증 방법 / 태그 후보) to a scratch file **before** reading the code: once the change is in your head, you read the contract as a description of what was done and every gap disappears. Output tags are generated from that ledger. If there is no contract, say so in the report and expect mostly 질문.

## Step 3: Read every changed file, in full

No sampling. Every file in the changed list is read whole at `$HEAD_SHA`, and its pre-image (`git show $MERGE_BASE:path`) whenever the hunks are not self-explanatory. Hunk context lies about surrounding code, and the coverage line in the report is a claim you must be able to back.

**Size gate, before you dispatch.** A full read has a cost, and on a big PR the no-sampling rule is what quietly breaks. Count first: the changed-file count printed by `fetch_pr.sh`, and `git -C "$WT" diff --shortstat "$MERGE_BASE...$HEAD_SHA"`. Above roughly **40 changed files or 3000 changed lines**, stop and go to the user *before* dispatching: report the size, say what reading all of it in full will cost (time, tokens, how many agents), and propose a scope (all of it, or a named subset, for example the production paths with generated and test data excluded). Wait for their answer. The agreed scope goes in the report header as the 합의 범위 line **instead of** a full-coverage claim, and everything outside it is named as unreviewed. Never sample silently to stay inside the budget.

## Step 4: Run the passes

`references/passes.md` holds all thirteen passes (hunt, input, commands, filing rule) plus the scope-discipline section. Two are special:

- **Pass 2 (history and intent) is every finder's duty**, not one agent's job, which is why it appears on every row of the fan-out table below. Whoever files a finding runs blame and log on those lines first and either drops it, restates it as a 질문, or files it with the history quoted and answered. Its output is the required `이력` and `반증 시도` lines of the return shape: a finding without both is not finished and does not ship.
- **Pass 13 (disposition) is the merge gate**, run by you in Step 6, not inside an agent.

## Step 5: Fan out to parallel subagents

Dispatch these in one batch with the Agent tool, and only once the size gate in Step 3 is settled. Each is independent, so they run in parallel.

| Agent | Passes | Angle |
|---|---|---|
| A 계약·커버리지 | 1, 2, 3, 4 | contract conformance, population enumeration vs the changed set, what the ask really costs |
| B 잔여·중복·이름 | 2, 5, 10, 11 | residual old-shape sites, name versus behaviour, duplication in tree and in diff |
| C 전제·의미 | 2, 6, 7 | premise verification against the resolved artifact, semantic delta in six directions |
| D 실패·파급 | 2, 8, 12 | failure paths and resources, blast radius across callers, config, CI, persisted shapes |
| E 관례 | 2, 9 | local convention at both localities (tree-wide prevailing form, file-local consistency) |

**Each agent receives:** `$WT`, `$REPO_DIR`, `$MERGE_BASE`, `$HEAD_SHA`, the changed-file list it must cover in full (all of it, or the agreed scope from the size gate, no sampling either way), the frozen contract ledger and issue text, its pass numbers with instruction to follow `references/passes.md`, **plus Pass 2, run against every candidate finding before it is written down**, the grounding bar, the return shape below, and the ban on posting, editing and touching the user's branches.

**Each agent returns exactly this, or `발견 없음`:**

```
분류: 결함 | 판단 사항 | 범위 밖 | 질문
태그: [계약 원문에서 파생]
위치: path/to/File.java:142
요약: 한 줄
근거: 검증 가능한 참조 (계약 조항 인용 / blame·commit sha / 컴파일 출력 / 트리 내 카운트)
이력: blame/log 결과 한 줄, 또는 "해당 없음(신규 코드)"
반증 시도: 무엇으로 이 지적을 죽여보려 했고 왜 안 죽었는지
결과: 구체적 실패 시나리오 또는 영향
비용: 고치는 데 드는 비용
확신도: 확실 | 확인필요
---
커버리지: 패스별로, 전문 확인한 파일 목록
확인 못 한 것: 항목과 이유
```

`이력` and `반증 시도` are Pass 2's output and are **required on every finding of every 분류**. An agent that returns a finding without both has not run Pass 2, and you send it back rather than merging it.

**Merging.** Deduplicate on (파일, 라인 범위, 근본 원인): keep the strongest 근거, union the affected sites, keep the highest severity. **Exception: findings that share a root cause stay separate when each asks the author a different question** (for example "이 규칙이 여기엔 왜 빠졌나" and "이 규칙 자체가 이 케이스엔 안 맞는 것 아닌가" are two answers, so two findings). When two agents disagree, the grounded one wins; if neither is grounded, it becomes a 질문. Carry every "확인 못 한 것" into the report as a stated boundary.

**Coverage is reported per pass**, not per agent. The denominator is the changed-file count printed by `fetch_pr.sh` (or, after a size gate, the agreed scope, with the rest named as unreviewed). A file that no agent carrying pass P read in full is not covered for pass P. Never union partial per-agent lists into a full-coverage claim: five agents that each read a different third of the tree do not add up to one full read, and the coverage line is the one claim the user cannot check for you.

## Step 6: Report

Follow `references/output.md`: the survival test against review-triage, the mandatory per-pass coverage line (or the 합의 범위 line from the size gate), four hard-separated sections (결함 / 판단 사항 / 범위 밖·후속 제안 / 질문), severity ranking within 결함 only, the nine-part finding anatomy including 이력 and 반증 시도, and the Korean templates. Patches are labelled `힌트(미검증):` unless actually compiled. Korean, colleague's voice, no em-dash.

Then clean up: `${CLAUDE_SKILL_DIR}/assets/fetch_pr.sh OWNER/REPO N --cleanup` removes the worktree and the two refs, and nothing else. Keep the worktree only if the user wants to keep digging, and say that you did.

## Hard rules

- **Never post.** No `gh pr review`, no `gh pr comment`, no `gh api ... /comments`. The user decides and posts.
- **Never edit the reviewed code**, not even in the scratch worktree.
- **Never touch the user's repository state** beyond a namespaced fetch and a scratch worktree: no branch switch, no `refs/heads/*` write, no stash, no push.
- **Clean up the worktree when the review is delivered**, and never leave it behind silently.
