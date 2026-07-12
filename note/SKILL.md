---
name: note
description: "Record an exploration note (PoC, review, code analysis, or any work without a JIRA issue) as a Markdown file in your public work-docs repo. Give it a free-form category and a slug and it scaffolds <category>/<YYYY-MM-DD>-<slug>.md from an exploration template (목적/배경/범위·방법/발견/결론/다음 단계/참고), fills it from the session, and commits it. While researching, actively use the collection's lookup/analysis skills (cubrid-manual, cmt-manual, and Understand-Anything if installed) so findings are verified, not asserted from memory. Complements the worklog skill, which is for issue-keyed work. The repo is PUBLIC, so keep internal-only detail in the master DOCX. Triggers on phrases like 'PoC 노트 남겨', '검토 노트 작성', '코드 분석 기록', 'record an exploration note', 'note this analysis'."
argument-hint: "<category> <slug>"
---

# Record an exploration note (work-docs)

For work that has **no JIRA issue**: PoC, 검토(review), 코드 분석, and the like. Issue-keyed work goes through the **worklog** skill instead. Both write to the same public `work-docs` repo, side by side (issue records in uppercase-key folders, notes in lowercase category folders).

## Step 0 — Prereqs

- The public docs repo cloned at `${WORK_DOCS_REPO:-$HOME/Devel/work-docs}` (shared with worklog; the legacy `WORKLOG_DOCS_REPO` also works), with its `origin` set to your public repo.

## Step 1 — Category and slug

Pick a free-form **lowercase category** (e.g. `poc`, `review`, `analysis`, or anything that fits) and a short **slug**. **Write the note in Korean.** The date is added automatically (`YYYY-MM-DD`).

## Step 2 — Scaffold the file

```bash
bash <skill-base-dir>/assets/new_note.sh <category> <slug>
```

Creates `<category>/<YYYY-MM-DD>-<slug>.md` from the template (refuses to overwrite) and prints the local path plus the public GitHub URL. Category and slug are lowercased and sanitized.

## Step 3 — Investigate (use the lookup / analysis skills)

Before writing conclusions, actively ground the note with the collection's investigation skills. Do not assert a fact from memory when a lookup can verify it:

- **cubrid-manual** — CUBRID engine SQL syntax, functions, data types, reserved words, and config parameters (for engine-behavior review or code analysis).
- **cmt-manual** — CUBRID Migration Toolkit behavior, source-type mapping, and options (for migration-related notes).
- **Understand-Anything** (if installed) — `/understand`, `/understand-explain`, `/understand-diff` for codebase structure, a specific file/function, or change impact (for 코드 분석).
- **jira-fetch** — if the exploration relates to an existing CUBRID Jira issue, pull it for context.

Record what you consulted (manual URLs, graph, issue keys) in the 참고 section.

## Step 4 — Fill it in

Complete each section: 요약 / 목적 / 배경 / 범위·방법 / 발견·관찰 / 결론 / 다음 단계(이슈화 여부) / 참고. Detailed but **easy to skim**:

- **`## 요약` first, in one line** (핵심 결론/발견).
- 목적·배경·결론은 2~3문장 짧은 서술, 방법·발견·다음 단계의 나열은 **개조식 불릿**.
- 데이터·비교·수치는 **표**로, 코드·SQL·로그는 **코드블록**으로 (문장으로 풀지 않기).
- 흐름·구조·관계·시퀀스는 **Mermaid 다이어그램**(GitHub가 자동 렌더하는 `mermaid` 코드블록)으로 적극 표현: `flowchart`(처리·분기 흐름), `sequenceDiagram`(호출/상호작용), `erDiagram`(스키마·테이블 관계), `classDiagram`/`stateDiagram`(구조·상태 전이). 이해를 돕는 곳에만, 노드는 간결하게(대략 10개 이하).

**The repo is PUBLIC**: no credentials, internal hostnames, local absolute paths, or internal-only analysis. Keep sensitive detail in the master DOCX and link out.

## Step 5 — Commit (never push)

```bash
REPO="${WORK_DOCS_REPO:-$HOME/Devel/work-docs}"
git -C "$REPO" add "<category>/<YYYY-MM-DD>-<slug>.md"
git -C "$REPO" commit -m "note(<category>): <short summary>"
```

Give the user the local path and the public URL. Pushing is the user's responsibility.
