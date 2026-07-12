---
name: worklog
description: "Record a piece of issue work as a Markdown note in your public work-docs repo, for a shareable, PR-linkable trail (the GitHub-visible record that complements the internal master DOCX). Give it a CUBRID Jira key (CBRD, TOOLS, APIS, CUBRIDQA, ...) or a Hibernate HHH key (or a topic slug) and it scaffolds <KEY>/<KEY>-<slug>.md from a consistent template (배경/원인/변경/검증/결과/링크), fills it from the session's work, and commits it. Pairs with jira-fetch for issue context. The repo is PUBLIC — keep internal-only detail in the master DOCX. Triggers on phrases like '작업 기록 남겨', 'worklog 작성', '이 이슈 문서로 정리해서 커밋', 'record this work as a markdown note', 'publish a work note for CBRD-1234'."
argument-hint: "<ISSUE-KEY|topic> [slug]"
---

# Record work as a Markdown note (work-docs)

Publish a per-issue work record to your **public** `work-docs` repo, so the reasoning behind a change is shareable and linkable from PRs. This complements (does not replace) the internal master DOCX: deep internal analysis stays in the DOCX; a clear, public-safe summary goes here.

## Step 0 — Prereqs

- The docs repo cloned locally at `${WORK_DOCS_REPO:-$HOME/Devel/work-docs}`, with its `origin` set to your public repo (e.g. `github.com/Srltas/work-docs`). Override the path with `WORK_DOCS_REPO` (the legacy `WORKLOG_DOCS_REPO` also works). Shared with the `note` skill.
- Optional: the **jira-fetch** skill, to pull issue context (CBRD only; Hibernate HHH is Atlassian Cloud, not supported by that tool).

## Step 1 — Identify the record

From `$ARGUMENTS`: an issue key (`<PROJECT>-<N>`, e.g. `CBRD-1234`, `TOOLS-4888`, `APIS-1079`, `CUBRIDQA-123`, `HHH-20527`) or a topic slug, plus an optional short slug. **Write the note in Korean** regardless of the project. The project prefix only decides the folder/file name (see Step 3).

## Step 2 — Gather context (optional)

For a CUBRID Jira Server issue (CBRD, TOOLS, APIS, CUBRIDQA), pull its summary/description with jira-fetch to seed the note:

```bash
bash ~/.claude/skills/jira-fetch/assets/fetch_jira.sh -o /tmp/jira <KEY>
```

(HHH is Atlassian Cloud, which jira-fetch does not support, so write its context from the session instead.) Also use the current session's work (the change, the verification numbers) as the substance.

## Step 3 — Scaffold the file

```bash
bash <skill-base-dir>/assets/new_worklog.sh <ISSUE-KEY|topic> [slug]
```

Creates `<KEY>/<KEY>-<slug>.md` from the template (refuses to overwrite an existing one) and prints the local path plus the public GitHub URL it will have.

## Step 4 — Fill it in

Edit the created file, completing each section (요약, 배경/이슈, 원인 분석 AS-IS, 변경/해결 TO-BE, 검증 with real numbers, 결과/영향, 참고 links). Detailed but **easy to skim**:

- **`## 요약` first, in one line** (무엇을 했고 결과가 뭔지).
- 배경·결론은 2~3문장 짧은 서술, 원인·변경·검증·결과의 나열은 **개조식 불릿**.
- before/after·수치는 **표**로, 코드·SQL·로그는 **코드블록**으로 (문장으로 풀지 않기).
- 흐름·구조·관계·시퀀스는 **Mermaid 다이어그램**(GitHub가 자동 렌더하는 `mermaid` 코드블록)으로 적극 표현: `flowchart`(처리·분기 흐름), `sequenceDiagram`(호출/상호작용), `erDiagram`(스키마·테이블 관계), `classDiagram`/`stateDiagram`(구조·상태 전이). 이해를 돕는 곳에만, 노드는 간결하게(대략 10개 이하).
- em-dash(`—`)는 쓰지 않는다. 쉼표·콜론·괄호·마침표로 대체.

**This repo is PUBLIC**: do not include credentials, internal hostnames, local absolute paths, or internal-only analysis. Anything sensitive stays in the master DOCX; link to the JIRA/PR instead.

## Step 5 — Commit (never push)

```bash
REPO="${WORK_DOCS_REPO:-$HOME/Devel/work-docs}"
git -C "$REPO" add "<folder>/<name>.md"
git -C "$REPO" commit -m "docs(<key>): <short summary>"
```

Give the user the local path and the public URL. Pushing is the user's responsibility.
