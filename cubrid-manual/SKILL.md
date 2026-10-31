---
name: cubrid-manual
description: "Look up CUBRID engine behavior in the official version-pinned manual and return a citable URL: SQL syntax, functions, data types, reserved words, config parameters, driver APIs. Use it before writing dialect or driver code, or when an answer about CUBRID behavior needs a source rather than memory. For CMT questions, use cmt-manual. Triggers on phrases like 'CUBRID 매뉴얼 확인', 'CUBRID에서 X는 어떻게 동작해', 'is X reserved in CUBRID'."
argument-hint: "[version e.g. 10.2 or 11.4] <topic to look up>"
allowed-tools:
  - Read
  - Grep
  - Glob
  - WebFetch
  - WebSearch
  - ToolSearch
---

# CUBRID manual lookup (online)

Answer CUBRID engine questions from the official version-pinned online manual, and return a citable URL ready to paste into a PR description or verification report.

## Step 1: Determine the version

CUBRID semantics differ by version, so never guess. Read the version from `$ARGUMENTS` (e.g. `10.2`, `11.4`). If none is given, ask the user: typically `10.2` (the dialect's minimum supported version) or `11.4` (current). Use it in every URL below.

## Step 2: Determine the language

Default to English (`en`). Use Korean (`ko`) if the user writes in Korean or asks for the Korean manual. Only the `en`/`ko` segment of the URL changes.

## Step 3: Map the topic to a manual page

- `sql/syntax.html` · `sql/datatype.html` · `sql/identifier.html` · `sql/keyword.html` · `sql/literal.html` · `sql/transaction.html` · `sql/partition.html`: core SQL, types, identifiers, reserved words
- `sql/function/`: built-in functions (string, numeric, datetime, JSON, aggregate; `analysis_fn.html` for window/analytic)
- `sql/query/`: DML: `select.html`, `insert.html`, `update.html`, `delete.html`, `merge.html`, `cte.html`
- `sql/schema/`: DDL: `table_stmt.html` (CREATE TABLE), etc.
- `api/`: drivers: `jdbc.html`, `cci.html`, and others
- `admin/`: server admin, utilities, configuration parameters
- `pl/`: stored procedures (PL/CSQL, Java SP)
- top-level: `csql.html`, `ha.html`, `shard.html`, `security.html`, `install.html`

## Step 4: Fetch the version-pinned page

Build the URL:

```
https://www.cubrid.org/manual/<lang>/<version>/<path>.html[#anchor]
```

Example: `https://www.cubrid.org/manual/en/10.2/sql/query/select.html#for-update`.

- If you know the page path from Step 3, WebFetch it directly with a focused prompt.
- If unsure which page covers the topic, WebSearch first, then WebFetch the best hit:

  ```
  WebSearch query="<term> site:cubrid.org/manual/<lang>/<version>"
  ```

## Step 5: Answer and cite

Give the documented answer concisely, then cite the version-pinned URL (with `#anchor` when applicable) so the result is ready to paste into a PR description or verification report. If the manual is silent or contradicts observed behavior, say so explicitly rather than guessing.
