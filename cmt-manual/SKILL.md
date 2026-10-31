---
name: cmt-manual
description: "Look up CUBRID Migration Toolkit (CMT) behavior in its official manual and return a citable URL: supported source databases, type mapping to CUBRID, wizard steps, console mode, and settings. Use when you need to verify what CMT supports or how it handles a case. For CUBRID engine SQL or JDBC questions, use cubrid-manual. Triggers on phrases like 'CMT 매뉴얼 확인', 'CMT 타입 매핑', 'how does CMT handle'."
argument-hint: "<CMT topic to look up>"
allowed-tools:
  - Read
  - Grep
  - Glob
  - WebFetch
  - WebSearch
  - ToolSearch
---

# CMT (CUBRID Migration Toolkit) manual lookup (online)

Answer CMT questions from the official online manual at <https://www.cubrid.org/cmt_manual/> (currently CUBRID Migration Toolkit 12.0), and return a citable URL. Unlike the engine manual, the CMT manual is a single current version: there is no version segment in the URL.

## Step 1: Map the topic to a page

Sub-pages live directly under `https://www.cubrid.org/cmt_manual/` with numbered names:

- `01_intro.html`: introduction
- `02_install.html`: installation
- `03_quickstart.html`: quick start scenarios
- `04_ui.html`: GUI walkthrough
- `05_wizard.html`: migration wizard steps
- `06_objects.html`: object mapping
- `07_sourcedb.html`: **source database support** (CUBRID, Oracle, MySQL, MariaDB, MSSQL, Informix, Tibero, MySQL XML)
- `08_target.html`: **target type guidance**
- `09_console.html`: console / CLI mode
- `10_report.html`: reports and output files
- `11_config.html`: configuration settings
- `12_advanced.html`: advanced usage
- `appendix_typemap.html`: **data type mapping reference**

Chapter numbers/slugs are as of CMT 12.0. If unsure of the exact page, or if a page 404s, fetch the index `https://www.cubrid.org/cmt_manual/` (full table of contents) and follow the right link, or `WebSearch query="<term> site:cubrid.org/cmt_manual"`.

## Step 2: Fetch the page

WebFetch `https://www.cubrid.org/cmt_manual/<page>.html` with a focused prompt. For type-mapping questions prefer `appendix_typemap.html` and `08_target.html`; for "which source DBs / how to connect" prefer `07_sourcedb.html`.

## Step 3: Answer and cite

Give the documented answer concisely, then cite the `cmt_manual` URL. If the manual is silent on the point, say so rather than guessing.
