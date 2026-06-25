---
name: hhh-dialect-verify-report
description: "One-shot CUBRID dialect verification + report. Runs the hibernate-core test suite against one or ALL CUBRID versions, diffs pass/fail vs a baseline (a prior run's JSON, results dir, or .tgz), and ALWAYS produces a Korean Word (.docx) 비교 분석 report. Use when you want the full 'verify → measure → report' pipeline for a CUBRIDDialect change in one go, or to test across all CUBRID versions. Composes the hhh-dialect-verify and report skills. Triggers on phrases like 'dialect 검증하고 리포트까지', 'CUBRID 전체 버전 테스트 + 보고서', 'verify the dialect and write the report', 'run all CUBRID versions and report'."
argument-hint: "--baseline <json|tgz|dir> [--all-versions | --versions 10.2,11.4] [--tests <filter>]"
---

# CUBRID dialect verify → report (one-shot)

Run the hibernate-core suite against CUBRID (one version or the full matrix), diff vs a baseline, and **always** generate the Word 비교 분석 report. This orchestrates two installed skills: **hhh-dialect-verify** (`parse_results.py`, measurement) and **report** (`build_report.js`, document).

⚠️ Long-running: the full suite is ~30 min **per version** (≈2.5 h for `--all-versions`). Use `--tests '<filter>'` for a quick smoke check first.

## Step 0 — Prereqs

- Installed skills: **`hhh-dialect-verify`** and **`report`** (both under `~/.claude/skills/`).
- Hibernate repo (default `~/Devel/hibernate`), Docker, `python3`, and for the report: `node` + global `docx`, plus the report venv (matplotlib). See the report skill's Step 0.

## Step 1 — Run the orchestrator (verify across versions)

```bash
bash <skill-base-dir>/assets/run_verify.sh \
  --baseline ~/Devel/cubrid-fullsuite-10.2-2026-06-13.tgz \
  --all-versions                      # or: --versions 10.2,11.4   (add --tests '<filter>' for a fast run)
```

Per version it starts CUBRID (`CUBRID_IMAGE=...:<v> ./db.sh cubrid`), runs `:hibernate-core:test -Pdb=cubrid`, parses results, and diffs vs the baseline. Writes `verify-out/summary.json` (+ per-version `<v>.json`, `run-<v>.log`) and prints a table: `version · total · failed · +recovered · −regressed · net`.

The baseline may be a `.tgz`, a `test-results/test` dir, or a `*.json` from a prior `parse`. For accurate per-version deltas the baseline should correspond to the version(s) compared.

After each version the script **tears the CUBRID container down with its anonymous data volume** (`down -v`) before the next version, so the disk doesn't fill up across the matrix (each version's volume is ~2.7 GB). Pass `--no-cleanup` to keep the DB running for debugging.

## Step 2 — Read the summary

Read `verify-out/summary.json` → `{ baseline_failed, versions: [{version, total, passed, failed, skipped, recovered, regressed, net, families, recovered_by_family, regressed_by_family}] }`.

## Step 3 — Author the report spec (MANDATORY — the pipeline always reports)

Turn `summary.json` into a `report` JSON spec (a 비교 분석), using the real numbers — do not skip this:

- **conclusion**: headline net change + recovered/regressed, `**…**` on key numbers.
- **결과** section: a `table` of version × (failed, +recovered, −regressed, net) with row `status` colors, plus a `bar`/`hbar` chart (failed-per-version for `--all-versions`, or before→after with a `-N` badge for a single version).
- **실패 분류** section: an `hbar` of recovered-by-family (and/or top remaining families).
- **회귀** section: if any `regressed`, a `note` (warn) + the regressed test list; else state "회귀 ~0".

Follow the report skill's schema + 작성 원칙 (간결, 표/차트 우선). Default `meta` = `CUBRID Dev1 · 작성일 <date>` (author = `CUBRID Dev1` unless the user names another).

## Step 4 — Generate, validate, visually verify (MANDATORY)

```bash
NODE_PATH="$(npm root -g)" REPORT_PY="$HOME/.cache/claude-skills/report-venv/bin/python" \
  node ~/.claude/skills/report/assets/build_report.js <spec>.json <out>.docx
```

Then validate (OOXML) and visually verify (LibreOffice render → page images) as in the report skill's Step 4. Hand the user the `.docx` path and `verify-out/summary.json`.
