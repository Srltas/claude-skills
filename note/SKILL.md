---
name: note
description: "Record an exploration note (PoC, review, code analysis, or other work without a Jira issue) as Markdown in the public work-docs repo, filled from the session and committed. For issue work, use worklog; for a Word report, use report. Triggers on phrases like '노트로 남겨줘', '분석 내용 기록해두자', 'PoC 노트 작성'."
argument-hint: "<category> <slug>"
allowed-tools:
  - "Bash(bash ${CLAUDE_SKILL_DIR}/assets/new_note.sh *)"
  - "Bash(bash ${CLAUDE_SKILL_DIR}/../worklog/assets/render_check.sh *)"
---

# Record an exploration note (work-docs)

For work that has **no JIRA issue**: PoC, 검토(review), 코드 분석, and the like. Issue-keyed work goes through the **worklog** skill instead. Both write to the same public `work-docs` repo, side by side (issue records in uppercase-key folders, notes in lowercase category folders).

## Step 0: Prereqs

- The public docs repo cloned at `${WORK_DOCS_REPO:-$HOME/Devel/work-docs}` (shared with worklog; the legacy `WORKLOG_DOCS_REPO` also works), with its `origin` set to your public repo.

## Step 1: Category and slug

The invocation is `<category> <slug>`. **A category the user names wins over inference:**

1. **If the user named a category, use it verbatim** (lowercased). A leading ASCII word (`/note bug …` → `bug`), or any word matching an existing folder, is the category, even when the rest of the request describes the content: `/note bug 분석한 내용...` still means category `bug`, not `analysis`.
2. **Reuse an existing category** rather than inventing a near-duplicate (`bug` vs `analysis`). List them first (uppercase folders are worklog issue keys: skip them):
   ```bash
   REPO="${WORK_DOCS_REPO:-$HOME/Devel/work-docs}"; ls -d "$REPO"/*/ 2>/dev/null | xargs -n1 basename | grep -vE '^[A-Z]'
   ```
3. **Only if the user named no category, infer one** that fits (`poc`, `review`, `analysis`, …).

Then pick a short **slug**. **Before scaffolding, state the resolved `<category>/<slug>`**; if you inferred the category (step 3) or it would create a brand-new folder, confirm with the user first (it creates a directory). **Write the note in Korean.** The date is added automatically (`YYYY-MM-DD`).

## Step 2: Scaffold the file

```bash
bash ${CLAUDE_SKILL_DIR}/assets/new_note.sh <category> <slug>
```

Creates `<category>/<YYYY-MM-DD>-<slug>.md` from the template (refuses to overwrite) and prints the local path plus the public GitHub URL. Category and slug are lowercased and sanitized.

## Step 3: Investigate (use the lookup / analysis skills)

Before writing conclusions, actively ground the note with the collection's investigation skills. Do not assert a fact from memory when a lookup can verify it:

- **cubrid-manual**: CUBRID engine SQL syntax, functions, data types, reserved words, and config parameters (for engine-behavior review or code analysis).
- **cmt-manual**: CUBRID Migration Toolkit behavior, source-type mapping, and options (for migration-related notes).
- **Understand-Anything** (if installed): `/understand`, `/understand-explain`, `/understand-diff` for codebase structure, a specific file/function, or change impact (for 코드 분석).
- **jira-fetch**: if the exploration relates to an existing CUBRID Jira issue, pull it for context.

Record what you consulted (manual URLs, graph, issue keys) in the 참고 section.

## Step 4: Fill it in

Complete each section: 요약 / 목적 / 배경 / 범위·방법 / 발견·관찰 / 결론 / 다음 단계(이슈화 여부) / 참고. Detailed but **easy to skim**:

- **`## 요약` first, in one line** (핵심 결론/발견).
- 목적·배경·결론은 2~3문장 짧은 서술, 방법·발견·다음 단계의 나열은 **개조식 불릿**.
- 데이터·비교·수치는 **표**로, 코드·SQL·로그는 **코드블록**으로 (문장으로 풀지 않기).
- **한 불릿에는 한 사실만**: `현재 → 목표`를 한 문장에 욱여넣지 말고 표의 두 열로. 클래스·파일 이름을 넷 넘게 쉼표로 잇지 말고, 표로 분리하거나 **기준 + 개수**로 압축한다 (예: "`Wrapper`를 구현하는 7개 클래스").
- **Use figures generously**, the same way the worklog skill does: follow `${CLAUDE_SKILL_DIR}/../worklog/references/figures.md`. Layouts, byte tables, before/after grids and version matrices are SVG files drawn with `${CLAUDE_SKILL_DIR}/../worklog/assets/svgfig.py` into `<category>/img/<slug>-<figure>.svg`; flows, sequences and decisions are `mermaid` blocks; bytes and values come from a real run (`${CLAUDE_SKILL_DIR}/../worklog/assets/tcp_log_proxy.py` for protocol traffic).
- **Check every figure before the commit**: `bash ${CLAUDE_SKILL_DIR}/../worklog/assets/render_check.sh <note.md>`, then read every PNG it prints and fix clipped or overlapping text.
- em-dash(`—`)는 쓰지 않는다. 쉼표·콜론·괄호·마침표로 대체.

**The repo is PUBLIC**: no credentials, internal hostnames, local absolute paths, or internal-only analysis. Keep sensitive detail in the master DOCX and link out.

## Step 5: Commit (never push)

```bash
REPO="${WORK_DOCS_REPO:-$HOME/Devel/work-docs}"
git -C "$REPO" add "<category>/<YYYY-MM-DD>-<slug>.md" "<category>/img/<slug>-"*.svg
git -C "$REPO" commit -m "note(<category>): <short summary>"
```

Add only this note's figures (drop the `img` path when it has none), never the figure script or a capture file. Give the user the local path and the public URL. Pushing is the user's responsibility.
