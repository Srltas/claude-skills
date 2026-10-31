---
name: jdbc-ctp-verify-report
description: "Build the CUBRID JDBC driver, run the CTP JDBC suite, compare pass/fail with a baseline, classify the broken cases, and always write a Korean Word comparison report. The JDBC counterpart of hhh-dialect-verify-report."
argument-hint: "--baseline <json|result-dir|test-jdbc.xml> [--no-build] [--cubrid <path>]"
disable-model-invocation: true
---

# CUBRID JDBC driver verify (CTP) → report (one-shot)

Build the CUBRID JDBC driver, run the **CTP** JDBC suite against CUBRID, diff vs a baseline, classify broken cases, and **always** generate the Word 비교 분석 report. Mirrors `hhh-dialect-verify-report` for the JDBC side. Needs the JDBC repo, CTP, a CUBRID install (`$CUBRID`), Docker/server running, `python3`, and (for the report) `node`+`docx`.

## Step 0: Prereqs
- JDBC driver source: `~/Devel/JDBC/devel` (ant `build.xml` via `./build.sh`).
- CTP: `~/Devel/JDBC/jdbc-verification/cubrid-testtools/CTP` (`bin/ctp.sh jdbc -c conf/jdbc.conf`); test cases under `cubrid-testcases-private/interface/JDBC/test_jdbc`.
- A CUBRID install at `$CUBRID` (the built jar deploys to `$CUBRID/jdbc/cubrid_jdbc.jar`) with the server/broker reachable.
- Installed `report` skill + its deps (see report Step 0).

## Step 1: Run the orchestrator (build + CTP + diff)

```bash
bash ${CLAUDE_SKILL_DIR}/assets/run_ctp.sh \
  --baseline ctp-out/baseline.json \
  --cubrid "$CUBRID"            # add --no-build to reuse the deployed jar
```

It builds the driver (`./build.sh`), deploys `cubrid_jdbc.jar` to `$CUBRID/jdbc/`, runs `ctp.sh jdbc`, parses `result/jdbc/current_runtime_logs/test-jdbc.xml`, and diffs vs the baseline. Writes `ctp-out/after.json`, `baseline.json`, `diff.txt`.

**The baseline must come from before this run.** The CTP run overwrites `$CTP_HOME/result`, so a `--baseline` pointing inside it would be re-parsed from the same post-run XML and every diff would read `+0 / -0`. The script resolves the baseline **before** running CTP and hard-errors on that path. Keep a saved `baseline.json` from the previous run (`ctp-out/baseline.json` or a copy taken beforehand). If the run parses zero cases, it exits non-zero instead of producing a report from an empty result.

The **change under test** is in the working tree: a driver code change, or a build-target change (the javac `source`/`target` in `JDBC/devel/build.xml`, e.g. 1.6→1.8 for the "Java 8 build impact" case). For a before/after diff, capture the baseline build first, then apply the change and re-run.

(Baseline may be a `.json` from a prior `parse`, a CTP `current_runtime_logs` dir, or a `test-jdbc.xml`. CTP also writes `test_status.data` with `total_*_case_count` for a quick sanity count.)

On exit the script prunes anonymous volumes **that this run created** and that are attached to no container, so leftover test databases do not accumulate. It snapshots the volume list at start and removes only ids that appeared afterwards: volumes that already existed, and named volumes, are never touched. Pass `--no-cleanup` to skip.

## Step 2: Read the diff/summary
From `ctp-out/diff.txt` + `after.json`: total/passed/failed, **+N recovered / −N regressed**, and the regressed cases by family (verify-error, conversion, broker/env, classpath/compat, NPE, …).

## Step 3: Author the report spec (MANDATORY: always reports)
Turn the numbers into a `report` JSON spec (비교 분석):
- **conclusion**: build target/driver under test + net pass/fail change, `**…**` on key numbers.
- **결과** section: a `table` (총 케이스 · 성공 · 실패 · +recovered · −regressed) with `status` colors + a `bar` chart (failed before→after, `-N` badge).
- **깨진 케이스 분류** section: an `hbar` of failures-by-family (e.g. verify-error N).
- **회귀** section: if regressed, a `note` (warn) + the case list; else "회귀 ~0".
Follow the report skill's schema + 작성 원칙. Default `meta` = `CUBRID Dev1 · 작성일 <date>` (author = `CUBRID Dev1` unless the user names another).

## Step 4: Generate, validate, verify (MANDATORY)
```bash
bash ${CLAUDE_SKILL_DIR}/../report/assets/build.sh   <spec>.json <out>.docx
bash ${CLAUDE_SKILL_DIR}/../report/assets/preview.sh <out>.docx
```
`build.sh` handles the toolchain; `preview.sh` checks the structure and renders every page to PNG. **Read those page images** before handing off (report skill Step 4). Hand the user the `.docx` path + `ctp-out/`.
