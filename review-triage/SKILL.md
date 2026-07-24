---
name: review-triage
description: "Triage the review comments on your pull request. Fetches a PR's reviews (inline code comments, review summaries, and PR-level comments, from humans and bots) and, for each, gives an easy Korean summary, judges whether it is valid by checking the actual code, then either drafts a fix plan (if valid) or a reasoned reply explaining why not (if not). Analysis and drafts only: it does not post replies or change code. Use when your PR has review feedback you want to understand and respond to. Triggers on phrases like 'PR 리뷰 정리해줘', '리뷰 코멘트 타당한지 봐줘', '리뷰 대응', 'triage my PR reviews', 'help me respond to PR review'."
argument-hint: "[PR number or URL]"
---

# Triage PR review comments

Pull the review feedback on your PR and, comment by comment, summarize it plainly, judge whether it holds up against the real code, and draft either a fix plan or a reasoned reply. Analysis and drafts only: it does not post anything or change code.

## Step 1: Identify the PR

The current branch's PR by default, or a number/URL from `$ARGUMENTS`.

```bash
gh pr view --json number,url,headRefName,baseRefName   # current branch's PR
```

## Step 2: Fetch the reviews

```bash
bash <skill-base-dir>/assets/fetch_reviews.sh [PR]
```

Merges inline code comments, review summaries, and PR-level comments (humans and bots, shown as `(User)` / `(Bot)`) with thread/reply info. Needs `gh` (authenticated) and `jq`.

## Step 3: Judge each comment against the real code (grounding)

For every comment, open the referenced `file:line` and the PR diff and check whether the point is actually correct. Do not agree or dismiss from memory: read the code. Separate real issues from style opinions, misunderstandings, or already-handled cases. Use cubrid-manual / cmt-manual to confirm a fact when the comment hinges on one.

## Step 4: Summarize and draft, per comment

For each comment, output (요약/판정/계획 or 답변 in Korean for the user):

- **요약**: what the reviewer is asking, in plain Korean.
- **판정**: 타당(O) / 부당(X) / 부분(△), with a one-line 근거 grounded in the code.
- if 타당 → **수정 계획**: which file and approach, briefly.
- if 부당/부분 → **답변 초안**: a reasoned reply to post. Write the reply in the reviewer's language (English for upstream repos such as Hibernate, Korean for CUBRID internal repos); keep the user-facing 요약/판정 in Korean.

Tone: open-source developer voice, plain and direct, not academic or formal-document. No em-dash (`—`): use commas, colons, parentheses, periods.

## Step 5: Hand off (no posting, no fixing)

Give the user the per-comment triage. Do not post replies or edit code. If they want to reply, show the command only when they ask:

```bash
gh pr comment <N> --body "<reply>"    # PR-level reply
# inline thread reply:
# gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies -f body="<reply>"
```
