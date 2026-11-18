---
name: worklog
description: "Record issue work (a CUBRID Jira or Hibernate HHH key) as a Markdown note in the public work-docs repo, filled from the session (background, cause, change, verification, result) and committed. For work without an issue, use note. Triggers on phrases like '작업 기록 남겨줘', 'worklog 작성', '이 이슈 문서로 정리해서 커밋'."
argument-hint: "<ISSUE-KEY|topic> [slug] [--explainer]"
allowed-tools:
  - "Bash(bash ${CLAUDE_SKILL_DIR}/../jira-fetch/assets/fetch_jira.sh *)"
  - "Bash(bash ${CLAUDE_SKILL_DIR}/assets/new_worklog.sh *)"
  - "Bash(bash ${CLAUDE_SKILL_DIR}/assets/render_check.sh *)"
---

# Record work as a Markdown note (work-docs)

Publish a per-issue work record to your **public** `work-docs` repo, so the reasoning behind a change is shareable and linkable from PRs. This complements (does not replace) the internal master DOCX: deep internal analysis stays in the DOCX; a clear, public-safe summary goes here.

## Step 0: Prereqs

- The docs repo cloned locally at `${WORK_DOCS_REPO:-$HOME/Devel/work-docs}`, with its `origin` set to your public repo (e.g. `github.com/Srltas/work-docs`). Override the path with `WORK_DOCS_REPO` (the legacy `WORKLOG_DOCS_REPO` also works). Shared with the `note` skill.
- Optional: the **jira-fetch** skill, to pull issue context (CBRD only; Hibernate HHH is Atlassian Cloud, not supported by that tool).

## Step 1: Identify the record

From `$ARGUMENTS`: an issue key (`<PROJECT>-<N>`, e.g. `CBRD-1234`, `TOOLS-4888`, `APIS-1079`, `CUBRIDQA-123`, `HHH-20527`) or a topic slug, plus an optional short slug. **Write the note in Korean** regardless of the project. The project prefix only decides the folder/file name (see Step 3).

## Step 2: Gather context (optional)

For a CUBRID Jira Server issue (CBRD, TOOLS, APIS, CUBRIDQA), pull its summary/description with jira-fetch to seed the note:

```bash
bash ${CLAUDE_SKILL_DIR}/../jira-fetch/assets/fetch_jira.sh -o /tmp/jira <KEY>
```

(HHH is Atlassian Cloud, which jira-fetch does not support, so write its context from the session instead.) Also use the current session's work (the change, the verification numbers) as the substance.

## Step 3: Scaffold the file

```bash
bash ${CLAUDE_SKILL_DIR}/assets/new_worklog.sh <ISSUE-KEY|topic> [slug] [--explainer]
```

Creates `<KEY>/<KEY>-<slug>.md` from the work-record template (refuses to overwrite an existing one) and prints the local path plus the public GitHub URL it will have.

Add `--explainer` when the note is meant to explain a change in an API, protocol or data format to other people (a team meeting, reviewers): a second note next to the work record that covers only what changes, one figure per section, from the explainer template. The model is `${CLAUDE_SKILL_DIR}/references/example-protocol-explainer/`.

## Step 4: Fill it in

Edit the created file, completing each section (for a work record: 요약, 배경/이슈, 원인 분석 AS-IS, 변경/해결 TO-BE, 검증 with real numbers, 결과/영향, 참고 links; for an explainer, the sections of its template). Detailed but **easy to skim**:

- **`## 요약` first, in one line** (무엇을 했고 결과가 뭔지).
- 배경·결론은 2~3문장 짧은 서술, 원인·변경·검증·결과의 나열은 **개조식 불릿**.
- before/after·수치는 **표**로, 코드·SQL·로그는 **코드블록**으로 (문장으로 풀지 않기).
- **한 불릿에는 한 사실만**: `현재 → 목표`를 한 문장에 욱여넣지 말고 표의 두 열로. 클래스·파일 이름을 넷 넘게 쉼표로 잇지 말고, 표로 분리하거나 **기준 + 개수**로 압축한다 (예: "`Wrapper`를 구현하는 7개 클래스").
- **Use figures generously**: every layout, before/after change, version combination, flow or decision the reader has to picture gets a figure, and the bullets under it read the figure. Follow `${CLAUDE_SKILL_DIR}/references/figures.md` for which kind of figure, the colors, and the packet conventions.
  - Packet and field layouts, byte tables, before/after grids and version matrices are SVG files drawn with `${CLAUDE_SKILL_DIR}/assets/svgfig.py` from a short script, saved as `<folder>/img/<topic>-<figure>.svg`, and linked as `![what it shows](img/<topic>-<figure>.svg)`.
  - Flows, sequences and decisions are `mermaid` blocks (`sequenceDiagram`, `flowchart TB` past four nodes), which GitHub renders.
  - Bytes, sizes and values come from a real run, never from reading code: capture protocol traffic with `${CLAUDE_SKILL_DIR}/assets/tcp_log_proxy.py` and say under the figure how it was measured. Never commit the capture file (its connect packets carry credentials).
- **Check every figure before the commit**: `bash ${CLAUDE_SKILL_DIR}/assets/render_check.sh <note.md>` renders each linked SVG at its natural size (headless Chrome) and each mermaid block (Kroki) and prints the PNG paths. Read every PNG, fix clipped or overlapping text, and render again until all are clean.
- em-dash(`—`)는 쓰지 않는다. 쉼표·콜론·괄호·마침표로 대체.

**This repo is PUBLIC**: do not include credentials, internal hostnames, local absolute paths, or internal-only analysis. Anything sensitive stays in the master DOCX; link to the JIRA/PR instead.

## Step 5: Commit (never push)

```bash
REPO="${WORK_DOCS_REPO:-$HOME/Devel/work-docs}"
git -C "$REPO" add "<folder>/<name>.md" "<folder>/img/<topic>-"*.svg
git -C "$REPO" commit -m "docs(<key>): <short summary>"
```

Add only this note's figures (drop the `img` path when it has none), never the figure script or a capture file. Give the user the local path and the public URL. Pushing is the user's responsibility.
