# Figures in work-docs notes

The note that set this style is [example-protocol-explainer/](example-protocol-explainer/) (CBRD-28170, the PARAMETER_INFO change): its text, six SVG figures, three mermaid blocks, and `make_figs.py`, the script that drew the SVG files. Read it before drawing.

## Contents

1. When to draw
2. Which kind of figure
3. Measure what you draw
4. SVG figures with svgfig
5. Packet and byte figures
6. Mermaid figures
7. Check every figure before the commit

## 1. When to draw

- Draw every structure the reader has to picture: a message or record layout, a change before and after, the combinations of client and server versions, a flow, a decision. If the reader would sketch it on paper to follow the text, it is a figure.
- Put the figure first, then short bullets that read it (what each part means, what changed). The bullets do not explain the same thing again in prose.
- One idea per figure. A figure that needs a paragraph to explain is two figures.
- A note about a change in an API, protocol or format goes section by section, each with its figure: where it is used, the whole layout, one unit before and after, real bytes, the rules for the values, versions, client API. `assets/explainer-template.md` has this order.

## 2. Which kind of figure

| Content | Figure |
|---|---|
| Packet, header, record or struct layout (fields, sizes) | SVG: one box per field, name, size and hex inside |
| Real bytes of a message, unit by unit | SVG: byte table (header row, column grid, one row per unit, a meaning column) |
| One unit before and after | SVG: two rows on the same grid, new fields in green |
| Values before and after | SVG: a header row of what each slot is, a red row before, a green row after |
| Client and server version combinations | SVG: matrix, one cell per combination with what happens there |
| Message exchange, call sequence | mermaid `sequenceDiagram` |
| Processing order, decisions | mermaid `flowchart TB` |
| Sizes or counts to compare | Markdown table under the figure |

## 3. Measure what you draw

- Bytes, sizes and values in a figure come from a real run. To capture a conversation, put `tcp_log_proxy.py` between the client and the server and point the client at the proxy:

  ```bash
  python3 ~/.claude/skills/worklog/assets/tcp_log_proxy.py run --listen 127.0.0.1:33099 --target 127.0.0.1:33000 --log capture.jsonl --conns 2 &
  # run the client against port 33099, once per connection
  python3 ~/.claude/skills/worklog/assets/tcp_log_proxy.py dump capture.jsonl --cas-function 27
  ```

  It runs on Python 3.6, so it also runs inside a CUBRID build container (`docker cp` it in). A CUBRID broker hands the socket to a CAS, so one connection carries every request. `--cas-function N` keeps the CAS requests with function code N and the reply that follows each.
- Capture with each client version you compare (for example a new CCI and an 11.4 CCI) and draw both.
- The connect packets of a capture carry the database user name and password. Dump only the requests you show, and never commit a capture file.
- Under the figure, say in one line how it was measured: the tool and the build.
- When a value cannot be measured, say that it was read from the code.

## 4. SVG figures with svgfig

- Write a short Python script per note that imports `~/.claude/skills/worklog/assets/svgfig.py`, as `example-protocol-explainer/make_figs.py` does. Keep the script out of the work-docs repo (the session scratchpad is fine); commit only the SVG files.
- Save each figure as `<folder>/img/<topic>-<figure>.svg` and link it as `![what the figure shows](img/<topic>-<figure>.svg)`.
- Colors carry a fixed meaning: gray unchanged, coral a value that changes, green something new, red a wrong or old value or a warning, blue a repeated unit, white a header. A figure that uses more than one meaning gets a legend (`Figure.legend`).
- Box text: the field name bold (`B`), its size or a short note (`S`), bytes in monospace hex (`M`).
- Keep a figure at most 1000 px wide; GitHub scales wider images down.
- `Figure.report()` must print `no text overflow`. It estimates widths, so the render check (section 7) is the real test.
- svgfig draws a white card behind every figure, so it stays readable in GitHub dark mode.

## 5. Packet and byte figures

- Show each field as a box: its name, its size in bytes and, when you have it, the real hex.
- In a byte table, put the header (length, info, result code) in its own row, then one row per repeated unit on a shared column grid (`Figure.column_heads`, `Figure.field_row`), then a meaning column that decodes the row, such as `IN · INT(8) · Num`.
- Under the new layout, draw the same unit in the old layout, so the difference shows without reading the text.
- Footnote the encoding rules a reader needs to decode the bytes (flag bits, type numbers).
- Put the size arithmetic in a table under the figure, such as "75 bytes against 40, the difference 35 = 4 name lengths × 4 + names with NUL 19".

## 6. Mermaid figures

- `flowchart TB` once there are more than four nodes; keep labels short.
- No semicolons in sequence messages (mermaid reads them as statement ends).
- Highlight the message that changes with `rect rgba(46, 160, 67, 0.15)` … `end`. A solid light color hides the text in GitHub dark mode.
- Keep the `mermaid` block in the note; GitHub renders it.

## 7. Check every figure before the commit

```bash
bash ~/.claude/skills/worklog/assets/render_check.sh <note.md>
```

It renders each SVG the note links at its natural size with headless Chrome, and each mermaid block through Kroki, then prints the PNG paths. Read every PNG. Look for text cut off at a box or card edge, text that overlaps, a legend that does not match the colors, and mermaid blocks that failed. Fix the script or the block and render again until every figure is clean.
