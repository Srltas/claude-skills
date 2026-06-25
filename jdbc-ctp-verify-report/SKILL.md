---
name: jdbc-ctp-verify-report
description: "One-shot CUBRID JDBC driver verification + report. Builds the CUBRID JDBC driver, runs the CTP JDBC test suite against CUBRID, diffs pass/fail vs a baseline (a prior run's JSON, CTP result dir, or test-jdbc.xml), classifies broken cases (VerifyError, conversion, broker/env, …), and ALWAYS produces a Korean Word (.docx) 비교 분석 report. Use to verify a JDBC driver change or a Java-version/build-target change (e.g. v50 1.6 vs v52 1.8) end to end. Composes parse_ctp.py + the report skill. Triggers on phrases like 'JDBC 드라이버 검증', 'CTP 돌려', 'ctp jdbc 실행하고 리포트', 'verify the JDBC driver with CTP', 'build driver and run CTP'."
argument-hint: "--baseline <json|result-dir|test-jdbc.xml> [--no-build] [--cubrid <path>]"
---

# CUBRID JDBC driver verify (CTP) → report (one-shot)

Build the CUBRID JDBC driver, run the **CTP** JDBC suite against CUBRID, diff vs a baseline, classify broken cases, and **always** generate the Word 비교 분석 report. Mirrors `hhh-dialect-verify-report` for the JDBC side. Needs the JDBC repo, CTP, a CUBRID install (`$CUBRID`), Docker/server running, `python3`, and (for the report) `node`+`docx`.

## Step 0 — Prereqs
- JDBC driver source: `~/Devel/JDBC/devel` (ant `build.xml` via `./build.sh`).
- CTP: `~/Devel/JDBC/jdbc-verification/cubrid-testtools/CTP` (`bin/ctp.sh jdbc -c conf/jdbc.conf`); test cases under `cubrid-testcases-private/interface/JDBC/test_jdbc`.
- A CUBRID install at `$CUBRID` (the built jar deploys to `$CUBRID/jdbc/cubrid_jdbc.jar`) with the server/broker reachable.
- Installed `report` skill + its deps (see report Step 0).

## Step 1 — Run the orchestrator (build + CTP + diff)

```bash
bash <skill-base-dir>/assets/run_ctp.sh \
  --baseline ~/Devel/JDBC/jdbc-verification/cubrid-testtools/CTP/result/jdbc/current_runtime_logs \
  --cubrid "$CUBRID"            # add --no-build to reuse the deployed jar
```

It builds the driver (`./build.sh`), deploys `cubrid_jdbc.jar` to `$CUBRID/jdbc/`, runs `ctp.sh jdbc`, parses `result/jdbc/current_runtime_logs/test-jdbc.xml`, and diffs vs the baseline. Writes `ctp-out/after.json`, `baseline.json`, `diff.txt`.

The **change under test** is in the working tree — a driver code change, or a build-target change (the javac `source`/`target` in `JDBC/devel/build.xml`, e.g. 1.6→1.8 for the "Java 8 build impact" case). For a before/after diff, capture the baseline build first, then apply the change and re-run.

(Baseline may be a `.json` from a prior `parse`, a CTP `current_runtime_logs` dir, or a `test-jdbc.xml`. CTP also writes `test_status.data` with `total_*_case_count` for a quick sanity count.)

On exit the script **prunes orphaned anonymous CUBRID test-DB volumes** (those attached to no container; named volumes like `jenkins_jenkins-data` are preserved) so leftover test databases don't accumulate. Pass `--no-cleanup` to skip.

## Step 2 — Read the diff/summary
From `ctp-out/diff.txt` + `after.json`: total/passed/failed, **+N recovered / −N regressed**, and the regressed cases by family (verify-error, conversion, broker/env, classpath/compat, NPE, …).

## Step 3 — Author the report spec (MANDATORY — always reports)
Turn the numbers into a `report` JSON spec (비교 분석):
- **conclusion**: build target/driver under test + net pass/fail change, `**…**` on key numbers.
- **결과** section: a `table` (총 케이스 · 성공 · 실패 · +recovered · −regressed) with `status` colors + a `bar` chart (failed before→after, `-N` badge).
- **깨진 케이스 분류** section: an `hbar` of failures-by-family (e.g. verify-error N).
- **회귀** section: if regressed, a `note` (warn) + the case list; else "회귀 ~0".
Follow the report skill's schema + 작성 원칙. Default `meta` = `작성자/팀 · 작성일`.

## Step 4 — Generate, validate, verify (MANDATORY)
```bash
NODE_PATH="$(npm root -g)" REPORT_PY="$HOME/.cache/claude-skills/report-venv/bin/python" \
  node ~/.claude/skills/report/assets/build_report.js <spec>.json <out>.docx
```
Then validate (OOXML) + visually verify (LibreOffice render) per the report skill's Step 4. Hand the user the `.docx` path + `ctp-out/`.
