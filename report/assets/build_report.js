/* Build a CUBRID-house-style .docx from a JSON spec, using docx-js (the base of
 * Anthropic's docx skill). Charts/diagrams are rendered by figures.py (matplotlib)
 * to PNG and embedded. Same spec schema as the Python generator.
 *
 *   NODE_PATH=$(npm root -g) node build_report.js <spec.json> <out.docx>
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, PageNumber, BorderStyle, WidthType, ShadingType,
  VerticalAlign, PageBreak, LevelFormat,
} = require("docx");

const ASSETS = __dirname;
const PY = process.env.REPORT_PY || path.join(os.homedir(), ".cache/claude-skills/report-venv/bin/python");
const [, , SPEC_PATH, OUT_PATH] = process.argv;
const spec = JSON.parse(fs.readFileSync(SPEC_PATH, "utf-8"));

const FONT = "맑은 고딕";
const NAVY = "1F3864", BLUE = "2E5496", GRAY = "595959", BODY = "262626";
const HEADER_FILL = "D5E8F0";
const ROW_FILL = { good: "E2EFDA", bad: "F8D7DA", warn: "F2F2F2" };
const NOTE_FILL = { info: "D5E8F0", warn: "FFF2CC", bad: "F8D7DA" };
const NOTE_LABEL = { info: "참고", warn: "주의", bad: "경고" };
const tmpFiles = [];

/* **bold** → navy-bold runs; rest → base run (carries bold/color/size). */
function runs(text, { bold = false, size, color } = {}) {
  const out = [];
  for (const part of String(text).split(/(\*\*[^*]+\*\*)/)) {
    if (!part) continue;
    if (part.startsWith("**") && part.endsWith("**")) {
      out.push(new TextRun({ text: part.slice(2, -2), bold: true, color: NAVY, size, font: FONT }));
    } else {
      out.push(new TextRun({ text: part, bold, color, size, font: FONT }));
    }
  }
  return out.length ? out : [new TextRun({ text: String(text), bold, color, size, font: FONT })];
}

/* Render a chart/diagram block to PNG via figures.py; return ImageRun + caption paragraphs. */
function figure(block) {
  const base = path.join(os.tmpdir(), `rep_${process.pid}_${tmpFiles.length}`);
  const j = base + ".json", p = base + ".png";
  fs.writeFileSync(j, JSON.stringify(block));
  execFileSync(PY, [path.join(ASSETS, "figures.py"), j, p]);
  tmpFiles.push(j, p);
  const buf = fs.readFileSync(p);
  const imgW = buf.readUInt32BE(16), imgH = buf.readUInt32BE(20);
  const wPx = Math.round((block.width_in || 6.4) * 96);
  const hPx = Math.round(wPx * imgH / imgW);
  const out = [new Paragraph({
    alignment: AlignmentType.CENTER, spacing: { before: 60, after: 60 },
    children: [new ImageRun({ type: "png", data: buf, transformation: { width: wPx, height: hPx } })],
  })];
  if (block.caption) {
    out.push(new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { after: 120 },
      children: [new TextRun({ text: block.caption, italics: true, size: 18, color: GRAY, font: FONT })],
    }));
  }
  return out;
}

function heading(text, level) {
  return new Paragraph({
    spacing: level === 1 ? { before: 320, after: 160 } : { before: 220, after: 120 },
    children: [new TextRun({ text, bold: true, size: level === 1 ? 30 : 24, color: level === 1 ? NAVY : BLUE, font: FONT })],
  });
}

function bodyPara(text, bold) {
  return new Paragraph({ spacing: { after: 120, line: 276 }, children: runs(text, { bold, color: BODY }) });
}

function bullet(text) {
  return new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 60 }, children: runs(text, { color: BODY }) });
}

function codeBlock(text) {
  // preserve line breaks (docx-js does NOT turn \n into breaks); subtle box + navy left accent bar
  const children = String(text).split("\n").map((ln, i) =>
    new TextRun({ text: ln, font: "Consolas", size: 17, color: "2B2B2B", break: i > 0 ? 1 : undefined }));
  return new Paragraph({
    shading: { type: ShadingType.CLEAR, fill: "F2F4F7" },
    border: { left: { style: BorderStyle.SINGLE, size: 24, color: NAVY, space: 8 } },
    indent: { left: 130 },
    spacing: { before: 80, after: 140, line: 252 },
    children,
  });
}

function cellPara(text, { bold = false, align = AlignmentType.LEFT } = {}) {
  return new Paragraph({ alignment: align, children: runs(text, { bold, color: BODY }) });
}

function table(block) {
  const header = block.header, rows = block.rows;
  const ncol = header.length;
  const aligns = block.aligns || ["left", ...Array(ncol - 1).fill("center")];
  const AL = { left: AlignmentType.LEFT, center: AlignmentType.CENTER, right: AlignmentType.RIGHT };
  const edge = { style: BorderStyle.SINGLE, size: 4, color: "auto" };
  const border = { top: edge, bottom: edge, left: edge, right: edge, insideHorizontal: edge, insideVertical: edge };
  const mk = (text, { fill, bold } = {}, j = 0) => new TableCell({
    shading: fill ? { type: ShadingType.CLEAR, fill } : undefined,
    verticalAlign: VerticalAlign.CENTER, margins: { left: 60, right: 60, top: 20, bottom: 20 },
    children: [cellPara(text, { bold, align: AL[aligns[j]] || AlignmentType.LEFT })],
  });
  const trs = [new TableRow({ tableHeader: true, children: header.map((h, j) => mk(h, { fill: HEADER_FILL, bold: true }, j)) })];
  for (const r of rows) {
    const fill = ROW_FILL[r.status];
    trs.push(new TableRow({ children: r.cells.map((c, j) => mk(c, { fill }, j)) }));
  }
  return new Table({ width: { size: 100, type: WidthType.PERCENTAGE }, borders: border, rows: trs });
}

function noteBox(text, kind) {
  const fill = NOTE_FILL[kind] || "F2F2F2";
  const label = NOTE_LABEL[kind] || "";
  const edge = { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF" };
  const children = label ? [new TextRun({ text: label + "  ", bold: true, color: NAVY, font: FONT }), ...runs(text, { color: BODY })] : runs(text, { color: BODY });
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    borders: { top: edge, bottom: edge, left: edge, right: edge, insideHorizontal: edge, insideVertical: edge },
    rows: [new TableRow({ children: [new TableCell({
      shading: { type: ShadingType.CLEAR, fill }, margins: { left: 120, right: 120, top: 60, bottom: 60 },
      children: [new Paragraph({ children })],
    })] })],
  });
}

/* ---- assemble ---- */
const children = [];
const autoNum = !!spec.auto_number;
let n = 0;
const h1Label = {};
spec.blocks.forEach((b, i) => { if (b.t === "h1") { n++; h1Label[i] = autoNum ? `${n}. ${b.text}` : b.text; } });

// cover
children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 1600, after: 120 },
  children: [new TextRun({ text: spec.title, bold: true, size: 46, color: NAVY, font: FONT })] }));
if (spec.subtitle) children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
  children: [new TextRun({ text: spec.subtitle, size: 24, color: GRAY, font: FONT })] }));
if (spec.meta) children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 1200 },
  children: [new TextRun({ text: spec.meta, size: 18, color: GRAY, font: FONT })] }));
if (spec.conclusion) {
  const b = { style: BorderStyle.SINGLE, size: 6, color: BLUE, space: 6 };
  children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 },
    border: { top: b, bottom: b }, children: runs(spec.conclusion, { bold: true, size: 20 }) }));
}
children.push(new Paragraph({ children: [new PageBreak()] }));

// TOC
children.push(new Paragraph({ spacing: { after: 160 }, children: [new TextRun({ text: "목차", bold: true, size: 28, color: NAVY, font: FONT })] }));
spec.blocks.forEach((b, i) => { if (b.t === "h1") children.push(new Paragraph({ indent: { left: 220 }, spacing: { after: 90 }, children: [new TextRun({ text: h1Label[i], size: 22, color: BODY, font: FONT })] })); });
children.push(new Paragraph({ children: [new PageBreak()] }));

// body
spec.blocks.forEach((b, i) => {
  switch (b.t) {
    case "h1": children.push(heading(h1Label[i], 1)); break;
    case "h2": children.push(heading(b.text, 2)); break;
    case "p": children.push(bodyPara(b.text, !!b.bold)); break;
    case "ul": for (const it of b.items) children.push(bullet(it)); break;
    case "code": children.push(codeBlock(b.text)); break;
    case "note": children.push(noteBox(b.text, b.kind || "info"), new Paragraph({})); break;
    case "chart": case "diagram": for (const p of figure(b)) children.push(p); break;
    case "pagebreak": children.push(new Paragraph({ children: [new PageBreak()] })); break;
    case "table": children.push(table(b), new Paragraph({})); break;   // spacer: keep tables from merging
  }
});

const headerEdge = { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF", space: 2 };
const doc = new Document({
  styles: { default: { document: { run: { font: FONT, size: 21, color: BODY } } } },
  numbering: { config: [{ reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 285, hanging: 185 } } } }] }] },
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440, header: 708, footer: 708 } } },
    headers: { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, border: { bottom: headerEdge }, children: [new TextRun({ text: spec.header || spec.title, size: 16, color: GRAY, font: FONT })] })] }) },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ children: ["- ", PageNumber.CURRENT, " -"], size: 16, color: GRAY, font: FONT })] })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(OUT_PATH, buf);
  for (const f of tmpFiles) { try { fs.unlinkSync(f); } catch (e) {} }
  console.log("saved: " + OUT_PATH);
});
