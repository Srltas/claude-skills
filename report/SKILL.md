---
name: report
description: "Generate a CUBRID-house-style Korean analysis report as a Word (.docx) — error analyses, code analyses, issue write-ups, before/after comparisons, and status/investigation reports. Builds the .docx with docx-js (the engine behind Anthropic's docx skill) from a JSON spec, embedding matplotlib charts, reproducing the exact design: centered cover (navy 23pt title), auto table of contents, navy/blue numbered headings, and bordered tables with row-level color coding (sky-blue header, green pass rows, red fail rows). Use when the user wants a Word report or structured document summarizing analysis, findings, comparisons, or current status of Hibernate/JDBC/CUBRID work. Triggers on phrases like 'write a report', '보고서 만들어', 'Word 문서로 정리', 'docx로 작성', 'analysis report', '검증 보고서', '비교 분석 문서'."
argument-hint: "[report type] <topic / what to report on>"
---

# Analysis report → Word (.docx)

Generate a CUBRID-house-style Korean Word report by writing a JSON spec and running the bundled generator (`assets/build_report.js`), which assembles the .docx with **docx-js** (the engine behind Anthropic's docx skill) and embeds matplotlib charts. The exact house design is reproduced:

- **Centered cover**: title (bold 23pt navy #1F3864), subtitle (12pt gray), meta line (9pt gray), bold conclusion abstract (10pt)
- **Auto table of contents** generated from the `h1` sections
- **Numbered headings**: Heading 1 = navy 15pt bold, Heading 2 = blue 12pt
- **Bordered tables with row-level color coding**: sky-blue (#D5E8F0) header row, green (#E2EFDA) pass rows, red (#F8D7DA) fail rows, gray (#F2F2F2) neutral-emphasis
- **Running header** set to the report title; footer page numbers

## Step 0 — Ensure dependencies (one-time)

```bash
# docx-js — document assembly
npm list -g docx >/dev/null 2>&1 || npm install -g docx
# Python venv — chart rendering (matplotlib)
VENV="$HOME/.cache/claude-skills/report-venv"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/python" -c "import matplotlib" 2>/dev/null || "$VENV/bin/pip" -q install matplotlib
```
The document is assembled with **docx-js**; `chart`/`diagram` blocks are rendered by `assets/figures.py` (matplotlib) and embedded as images.

## Step 1 — Identify the report type and gather inputs

| Type | Body skeleton |
|------|---------------|
| 에러 분석 | 증상 → 재현 → 원인 → 영향 → 해결 |
| 코드 분석 | 대상 → 구조/흐름 → 발견사항 → 개선안 |
| 이슈 분석 | 배경 → 현황 → 원인 → 해결방향 → 계획 |
| 비교 분석 | 기준/대상 → 항목별 비교표 → 권고 |
| 조사/현황 | 개요 → 방법 → 결과(표) → 해석 → 다음 단계 |

Collect (ask only for what is missing): title, subtitle (scope/version), meta (author/team · date — **author defaults to `CUBRID Dev1`**; do not ask for it unless the user names a different author), the headline conclusion, body content, and table data.

## 작성 원칙 — write less, show more

Optimize for a reader who skims. Keep prose minimal and let structure carry the detail:

- **Lead with the conclusion** — the cover `conclusion` states the answer first; `1. 개요` is one short paragraph.
- **Core points only** — short sentences, one idea per bullet; cut background the reader can infer.
- **Prefer tables / charts / figures over paragraphs** — turn comparisons, metrics, and status into a color-coded `table`; turn trends or distributions into a chart embedded via an `image`; use a `note` box for the single most important caveat. Reserve `p` paragraphs for the few sentences that truly need prose.
- **Emphasize only the few key terms** with `**…**` so the eye lands on them.
- **No em-dash**: never use the `—` character in the document; use commas, colons, parentheses, or periods instead.

## Step 2 — Write the JSON spec

Write `<topic>.json`. See `assets/example.json` for a complete example. Schema:

- `title`, `subtitle`, `meta` (`작성자/팀 · 작성일 YYYY-MM-DD` — author/team + date **only**; **author defaults to `CUBRID Dev1`** unless the user specifies another; no org name, scope, or version on this line — those go in the subtitle or 부록), `conclusion` (bold cover abstract), `header` (optional; defaults to title), `auto_number` (optional: `true` → h1 sections auto-numbered `1.`, `2.`, … and TOC stays in sync; then give h1 bare titles without numbers).
- `blocks`: an ordered list of:
  - `{"t":"h1","text":"1. 개요"}` — numbered section (TOC auto-built from these; number them `1.`, `2.`, …)
  - `{"t":"h2","text":"6.1 …"}` — subsection
  - `{"t":"p","text":"…","bold":false}` — paragraph (1.15 line spacing). Use `**핵심어**` anywhere to emphasize a phrase in navy bold.
  - `{"t":"ul","items":["…","…"]}` — bullet list ('•')
  - `{"t":"table","header":[…],"aligns":["left","center", …],"rows":[{"cells":[…],"status":"good"}, …]}` — default alignment: col0 left, other columns centered
  - `{"t":"note","text":"강조할 핵심/주의","kind":"info|warn|bad"}` — shaded callout box (참고/주의/경고)
  - `{"t":"image","path":"figure.png","caption":"그림 1","width_in":6.0}` — embed any existing image, centered + caption
  - `{"t":"chart","kind":"bar","title":"…","subtitle":"…","note":"하단 주석","signed":false,"bars":[{"label":"…","value":N,"color":"base|blue|good|lightgreen|warn|bad","badge":"강조\n둘째 줄","note":"바 위 메모"}]}` — vertical bars: bold-navy value labels, optional pill `badge` / colored `note` above a bar, subtle baseline (house style, no axes/grid)
  - `{"t":"chart","kind":"hbar","title":"…","subtitle":"…","note":"…","bars":[{"label":"…","value":N,"color":"…","tag":"유지","tag_color":"good"}]}` — horizontal ranked bars: label left (+ optional colored `tag`), proportional bar, bold-navy value at the end. Best for ranking magnitudes (`signed` defaults true)
  - For trends or share: `{"t":"chart","kind":"line|pie","labels":[…],"series":[{"name":"…","data":[…]}]}`
  - `{"t":"svg","code":"<svg …>…</svg>","caption":"그림 2","width_in":6.4}` — **hand-authored SVG diagram — PREFER THIS for every 도식/그림 (flow, architecture, state, sequence).** Authored like a visualize widget, embedded as a native vector image in Word (crisp, zero glyph/shape overlap) with an auto-generated PNG fallback. Follow the **SVG 도식 작성 규칙** below. (Needs LibreOffice for the fallback.)
  - `{"t":"diagram","direction":"LR|TB","nodes":[…],"edges":[…],"caption":"그림 2"}` — *(legacy)* matplotlib auto-layout flow; prone to text/shape overlap and stiff shapes. **Do not use for new reports — author an `svg` block instead.**
  - `{"t":"code","text":"..."}` — monospace block (Consolas on light-gray)
  - `{"t":"pagebreak"}` — force a page break (cover→목차→본문 breaks are automatic)
- Table `status` per row: `good` = green (pass), `bad` = red (fail), `warn` = gray, omitted = neutral. The header row is auto sky-blue and repeats across page breaks.

Follow the type skeleton from Step 1 and the 작성 원칙 above. Language: Korean, plain and direct.

### SVG 도식 작성 규칙 (the `svg` block)

Author the SVG yourself, the way the `visualize` tool would — deliberate layout, not auto-placed. These rules keep it on-brand and prevent the overlap/distortion that the old matplotlib `diagram` produced:

- **Canvas**: set `viewBox="0 0 W H"` (this fixes the aspect ratio; `width_in` sizes it in the doc). No pixel `width`/`height` needed.
- **Font**: put `font-family="'맑은 고딕','Malgun Gothic','Apple SD Gothic Neo',sans-serif"` on every `<text>`; titles `font-weight="bold"`.
- **Palette (match the report)**: text/heading navy `#1F3864`; strokes & arrows blue `#2E6DA4`, good `#2EA84F`, bad `#C0392B`, warn `#E8862E`; light box fills `#EAF1F8` (blue) / `#E2EFDA` (good) / `#F8D7DA` (bad) / `#FFF2CC` (warn); plain boxes on white.
- **Boxes**: rounded `rx="9"`, `stroke-width="2"`. Size each box to its text — roughly `width ≈ 9px × 글자수 + 32`, `height ≥ 48`. Center the label with `text-anchor="middle"` and baseline ≈ box-center-y + 5.
- **Arrows**: draw **edge-to-edge** (start on the source box border, end on the target border — never center-to-center), `stroke-width="2"`, end with a `<marker>` arrowhead colored like the line. Put an edge label at the segment midpoint in the matching color.
- **Spacing**: leave ≥ 24px between boxes; never let text touch or overlap a border or another shape.
- **Scope**: use SVG for schematic diagrams (boxes + arrows + short labels). For quantitative comparison/trend/share, use a `chart` block, not SVG.

## Step 3 — Generate the .docx

```bash
NODE_PATH="$(npm root -g)" REPORT_PY="$HOME/.cache/claude-skills/report-venv/bin/python" \
  node "<skill-base-dir>/assets/build_report.js" <topic>.json <output>.docx
```

`<skill-base-dir>` is this skill's own directory (shown as its base directory when the skill runs). `build_report.js` calls `figures.py` for `chart`/`diagram` blocks (matplotlib), and rasterizes each `svg` block's PNG fallback via LibreOffice (`soffice`, resolved on PATH → macOS app bundle). Filename convention: `CUBRID_<주제>_<유형>_YYYYMMDD.docx`.

## Step 4 — Validate, visually verify, hand off

**1) OOXML schema validation** — catches a malformed .docx before the user opens it (via Anthropic's docx skill):

```bash
# one-time: "$VENV/bin/pip" install defusedxml lxml
"$VENV/bin/python" <docx-skill>/scripts/office/validate.py <output>.docx   # expect "All validations PASSED!"
```

**2) Visual verification** — render every page to an image and read them, to catch layout issues the schema can't (clipped chart labels, overlapping text, a `note` box merging into a table, broken page breaks, color/table problems). This is the PRIMARY defect-catcher; schema validation cannot see any of these. **Do not skip it whenever `soffice` resolves** — only skip if LibreOffice is genuinely absent (and then say so explicitly).

```bash
# Resolve LibreOffice robustly: PATH first (brew/linux), then the macOS .app bundle.
SOFFICE="$(command -v soffice || command -v libreoffice || true)"
[ -z "$SOFFICE" ] && [ -x "/Applications/LibreOffice.app/Contents/MacOS/soffice" ] && SOFFICE="/Applications/LibreOffice.app/Contents/MacOS/soffice"
# if still empty -> install once: brew install --cask libreoffice  (mac) | sudo apt-get install -y libreoffice  (linux)
"$SOFFICE" --headless -env:UserInstallation=file:///tmp/loprofile --convert-to pdf --outdir /tmp/render <output>.docx
pdftoppm -png -r 120 "/tmp/render/$(basename <output>.docx .docx).pdf" /tmp/render/page
# then Read /tmp/render/page-*.png and check cover, TOC, tables, charts, page breaks
```

Note: LibreOffice substitutes 맑은 고딕 if it is not installed locally — the user's Word (with the font) renders correctly; chart text uses AppleGothic baked into the PNGs.

Then `ls -la <output>.docx`, tell the user the path, and keep the `.json` (editable source).
