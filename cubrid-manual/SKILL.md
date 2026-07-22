---
name: cubrid-manual
description: "Look up CUBRID engine behavior in the official online manual: SQL syntax, built-in functions, data types, identifiers and reserved keywords, configuration parameters, and JDBC/driver APIs. Fetches the version-pinned manual at www.cubrid.org/manual. Use when you need to verify CUBRID SQL semantics, a function signature, a data type's range, whether a word is reserved, or a config parameter before writing dialect or JDBC code. For CUBRID Migration Toolkit (CMT) questions, use the cmt-manual skill instead. Triggers on phrases like 'how does X work in CUBRID', 'CUBRID syntax for', 'is X a reserved word in CUBRID', 'what functions does CUBRID have', 'check the CUBRID manual'."
argument-hint: "[version e.g. 10.2 or 11.4] <topic to look up>"
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
