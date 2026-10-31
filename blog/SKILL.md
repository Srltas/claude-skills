---
name: blog
description: "Draft a Korean tech blog post for velog in the public work-docs repo: short text, with every diagram and chart rendered as an image because velog does not render Mermaid. You publish it on velog yourself."
argument-hint: "<slug> [topic]"
disable-model-invocation: true
---

# Draft a tech blog post (velog, work-docs)

Write a tight, visuals-first Korean tech blog post for **velog**, saved as a draft in the public work-docs repo. **velog does not render Mermaid**, so every diagram becomes an image here (you upload those images to velog when publishing).

## Step 0: Prereqs

- work-docs cloned at `${WORK_DOCS_REPO:-$HOME/Devel/work-docs}` (shared with note/worklog).
- `curl` (for Kroki diagram rendering). For data charts, the report skill's venv + `figures.py`. Optional: an Excalidraw skill for hand-drawn diagrams.

## Step 1: Scaffold the post folder

```bash
bash ${CLAUDE_SKILL_DIR}/assets/new_blog.sh <slug>
```

Creates `blog/<YYYY-MM-DD>-<slug>/index.md` + an `assets/` folder, and prints the draft's GitHub URL.

## Step 2: Ground it (do not write from memory)

Verify facts before writing: **cubrid-manual**, **cmt-manual**, **Understand-Anything** (if installed), and the real code. A tech post must be correct. Cite sources in 참고.

## Step 3: Write the post (minimal text, visuals-first)

Korean. Structure: 제목 → 요약(1~2줄) → 들어가며(왜 읽나, 무슨 문제) → 핵심 섹션들 → 정리 → 참고.

- 핵심 텍스트만: 짧은 문단, 개조식.
- 개념 설명은 **글보다 그림**으로 (다음 단계에서 이미지로).
- 표는 비교·수치, 코드블록은 코드·로그.
- em-dash(`—`)는 쓰지 않는다: 쉼표·콜론·괄호·마침표로 대체.

## Step 4: Make visuals as IMAGES (velog cannot render Mermaid)

Put each source in `assets/`, render it to an image, and embed with `![설명](assets/…)`.

- **Diagram-as-code** (Mermaid / Graphviz / D2 / PlantUML): write `assets/diagram-N.mmd`, then render to PNG for velog:
  ```bash
  bash ${CLAUDE_SKILL_DIR}/assets/render.sh assets/diagram-N.mmd assets/diagram-N.png
  ```
  Keep the `.mmd` source so the diagram stays editable and reproducible. (velog accepts PNG uploads; SVG upload is often blocked, so render PNG for velog.)
- **Data charts**: build a chart JSON and render it with the report skill's `figures.py` to `assets/chart-N.png` (see the report skill for the `figures.py <block.json> <out.png>` command).
- **Hand-drawn / architecture**: if an Excalidraw skill is installed, use it to produce `assets/*.png`.
- Keep diagrams simple (roughly 10-15 nodes); dense graphs render poorly.
- **Prefer Mermaid** for structured visuals (flow/sequence/state/ER/class): nodes auto-size to their text, so labels never clip.

**Verify every image (render → look → fix → repeat)**: after rendering, **Read the PNG** and check it: is every label fully inside its node, nothing clipped or overlapping, the whole figure readable at blog width? If a diagram is wrong, fix the `.mmd` (switch `LR`↔`TB`, shorten labels, or split it) and re-render, then look again. Repeat until each image is clean. Never embed a diagram you have not looked at.

Note: Kroki (`https://kroki.io`) is a public service, so the diagram source is sent there. That is fine for public blog content. Point `KROKI_URL` at a self-hosted instance if you prefer.

## Step 5: Commit (never push)

```bash
REPO="${WORK_DOCS_REPO:-$HOME/Devel/work-docs}"
git -C "$REPO" add "blog/<YYYY-MM-DD>-<slug>/"
git -C "$REPO" commit -m "blog: <제목>"
```

Give the user the draft path and GitHub URL. Pushing is the user's responsibility.

## Step 6: Publish on velog (manual)

velog 에디터에 `index.md` 본문을 붙이고, `assets/`의 이미지를 드래그해 업로드하면 velog가 CDN URL로 바꿔 삽입합니다. 다이어그램이 이미지라 velog에서 정상 표시됩니다.
