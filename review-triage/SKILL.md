---
name: review-triage
description: "Triage the review comments on your pull request. Fetches a PR's reviews (inline code comments, review summaries, and PR-level comments, from humans and bots) and, for each, gives an easy Korean summary, then judges it on the evidence (the actual code, the manual/spec, and this PR's own scope) instead of on the reviewer's authority, and either drafts a fix plan (valid) or a reasoned reply saying why not (wrong, already handled, out of scope, or style). Analysis and drafts only: it does not post replies or change code. Use when your PR has review feedback you want to understand and respond to. Triggers on phrases like 'PR 리뷰 정리해줘', '리뷰 코멘트 타당한지 봐줘', '리뷰 대응', 'triage my PR reviews', 'help me respond to PR review'."
argument-hint: "[PR number or URL]"
---

# Triage PR review comments

Pull the review feedback on your PR and, comment by comment, summarize it plainly, judge whether it holds up against the real code, and draft either a fix plan or a reasoned reply. Analysis and drafts only: it does not post anything or change code.

## Step 1: Identify the PR

The current branch's PR by default, or a number/URL from `$ARGUMENTS`.

```bash
gh pr view --json number,url,title,body,headRefName,baseRefName   # current branch's PR
```

Read the title and body: they state **what this PR set out to do**, which Step 3 judges scope against. If the body links an issue (CBRD, APIS, TOOLS, CUBRIDQA, HHH), pull it too (**jira-fetch** for CUBRID Jira Server keys) so the PR's intent comes from the issue, not from a guess.

## Step 2: Fetch the reviews

```bash
bash <skill-base-dir>/assets/fetch_reviews.sh [PR] [--include-resolved]
```

Merges inline code comments, review summaries, and PR-level comments (humans and bots, shown as `(User)` / `(Bot)`) with thread/reply info. Needs `gh` (authenticated) and `jq`.

**Comments in resolved review threads are skipped**: that discussion is already settled, so re-judging it wastes effort and reopens closed points. The script prints how many it skipped; pass `--include-resolved` when you do want to revisit them (say, to check that a resolved thread was actually addressed). Threads that are merely **outdated** (the diff moved) are still shown: outdated is not resolved. If `$ARGUMENTS` is a full PR URL, its owner/repo is used, so a URL from another repo is not read as the current directory's PR.

## Step 3: Judge each comment on evidence, not on authority

**Start neutral.** A reviewer being senior, confident, a maintainer, or a bot is not evidence: bots especially produce false positives. Agreeing when the reviewer is wrong costs a pointless change and a wrong precedent; dismissing when they are right ships a defect. Judge every comment on two axes:

1. **사실 (is the claim true here?)**: open the referenced `file:line` and the diff and trace the real path. Look for evidence **both ways**: what would make the reviewer right, and what would refute them (an existing guard, a test that already covers it, a call site that cannot reach that state, a value the type system rules out). A comment survives only if you failed to refute it.
2. **범위 (is it this PR's job?)**: check the claim against the PR/issue intent from Step 1. A correct point that is outside what this PR set out to do is a follow-up issue, not a change to make here.

**근거 기준**: every 판정 needs at least one checkable thing, quoted in the output: the code itself (`file:line`), a manual or spec statement (**cubrid-manual** / **cmt-manual**, or the JDBC/JPA spec), or a run you actually did (test, query, log). These are **not** evidence: "일반적으로 그렇다", "리뷰어가 그렇게 말했다", 기억, 관례.

If the comment claims a bug, **try to reproduce it** (run the test, follow the code path) instead of reasoning about it. If you cannot verify it either way, do not guess: mark it 확인필요 and draft the question to ask the reviewer.

## Step 4: Summarize and draft, per comment

For each comment, output (요약/판정/계획 or 답변 in Korean for the user):

- **요약**: what the reviewer is asking, in plain Korean.
- **판정**: one of the following, each with a one-line 근거 that **quotes** a `file:line`, a manual/spec statement, or a run result:
  - **타당(O)**: a real defect or a clear improvement, verified.
  - **부분(△)**: the observation holds but its premise, scope, or proposed fix is partly wrong. Say which part you take and which you push back on.
  - **부당(X)**: factually wrong, misread the code, or already handled. Name the refuting evidence.
  - **범위 밖(S)**: correct, but outside this PR's intent. Propose it as a follow-up issue instead.
  - **취향(P)**: a style preference with no correctness argument. Follow the project convention if one exists; otherwise mark it optional.
  - **확인필요(?)**: you could not verify it either way. Do not guess a verdict.
- **수정 계획** (타당·부분): which file and approach, briefly.
- **답변 초안** (부당·부분·범위 밖·확인필요): a reasoned reply to post. Write the reply in the reviewer's language (English for upstream repos such as Hibernate, Korean for CUBRID internal repos); keep the user-facing 요약/판정 in Korean.

If a reply needs to explain a non-trivial flow or relationship, an inline `mermaid` code block is an option (GitHub renders it in PR comments; nodes auto-size to text). Use it only when a diagram is clearer than a sentence.

Tone: open-source developer voice, plain and direct, not academic or formal-document. Lead a reply with the evidence, not with agreement: no "좋은 지적입니다" / "You're absolutely right" openers, and no conceding a point you just refuted to keep things pleasant. Disagreement is fine when it carries a reason; state it plainly and leave the decision to the reviewer. No em-dash (`—`): use commas, colons, parentheses, periods.

## Step 5: Hand off (no posting, no fixing)

Give the user the per-comment triage. Do not post replies or edit code. If they want to reply, show the command only when they ask:

```bash
gh pr comment <N> --body "<reply>"    # PR-level reply
# inline thread reply:
# gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies -f body="<reply>"
```
