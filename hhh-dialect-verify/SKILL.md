---
name: hhh-dialect-verify
description: "Run the Hibernate ORM test suite against CUBRID and measure a dialect change's impact — total failures, +N recovered / −N regressed vs a baseline, and failures grouped by signature/family. Use when verifying a CUBRIDDialect change, an auto_quote or capability-flag toggle, or any Hibernate-vs-CUBRID compatibility measurement. Pairs with the report skill (verify → numbers → 비교 분석 보고서). Triggers on phrases like 'dialect 검증', 'CUBRID 테스트 돌려', 'hibernate 스위트 실행', 'pass/fail 델타 측정', 'run the hibernate suite against CUBRID', 'measure dialect change'."
argument-hint: "[CUBRID version: 10.2|11.4] [--tests <filter>]"
---

# Hibernate ORM × CUBRID dialect verification

Run the `hibernate-core` suite against CUBRID, then quantify a dialect change: total failures, **recovered/regressed vs a baseline**, and **failure families**. Requires the Hibernate repo (default `~/Devel/hibernate`), Docker, and `python3` (stdlib). The full suite is ~16,900 tests and takes ~30 min — use `--tests` for fast iteration.

## Step 1 — Decide version, scope, baseline

- **Version:** `10.2` (dialect minimum) or `11.4` (current). Read from `$ARGUMENTS`; ask if unset (semantics differ).
- **Scope:** full suite (default) or a `--tests` filter (e.g. `--tests 'org.hibernate.orm.test.manytomany.*'`) for a quick check.
- **Baseline:** the failing-test set to diff against — either a saved `baseline.json` from a prior run, or capture one now by running Step 4–5 on the **un-changed** dialect first.

## Step 2 — Start CUBRID

```bash
cd ~/Devel/hibernate
CUBRID_IMAGE=docker.io/cubrid/cubrid:<version> ./db.sh cubrid   # waits for the csql healthcheck
```

## Step 3 — Apply the change under test

The change lives in the working tree — e.g. `hibernate-community-dialects/.../CUBRIDDialect.java`, or a config toggle like `hibernate.auto_quote_keyword`. For a **before/after** diff, capture the baseline (Steps 4–5) with the change reverted first, then re-apply it.

## Step 4 — Run the suite

```bash
./gradlew :hibernate-core:test -Pdb=cubrid -Plog-test-progress=true --stacktrace --no-daemon 2>&1 | tee <run>.log
# fast iteration: add  --tests '<filter>' ;  slow deps:  prefix  MAVEN_MIRROR="https://maven-central.storage-download.googleapis.com/maven2/"
```

The Gradle task **exits non-zero when tests fail — that is expected**; continue to Step 5. Profile `-Pdb=cubrid` selects the CUBRID dialect/JDBC from `local-build-plugins/.../local.databases.gradle`. Results: `hibernate-core/target/test-results/test/TEST-*.xml`.

## Step 5 — Parse results → failure set

```bash
python3 <skill-base-dir>/assets/parse_results.py parse \
  ~/Devel/hibernate/hibernate-core/target/test-results/test  <run>.json
```

Prints `total / passed / failed / skipped` and a per-family failure breakdown, and saves the failing-test set (with each failure's exception signature + family) to `<run>.json`.

## Step 6 — Diff vs baseline → recovered / regressed

```bash
python3 <skill-base-dir>/assets/parse_results.py diff  baseline.json  <run>.json
```

Prints `net` (baseline − after), **+N recovered** (failed in baseline, not now), **−N regressed** (new failures), each broken down by family, and lists the regressed tests.

## Step 7 — (optional) separate flaky failures

Load-dependent driver NPEs often pass in isolation. Re-run a suspect/regressed subset alone:

```bash
./gradlew :hibernate-core:test -Pdb=cubrid --tests '<Class or pattern>' --stacktrace --no-daemon
```

Failures that pass on isolated rerun = **flaky** → exclude from the regression count and note them.

## Step 8 — Summarize / hand to the report skill

State: total OFF→ON, **+N recovered / −N regressed**, net, and the top failure families. To produce the Word report, feed these to the **report** skill as a 비교 분석 — a 전/후 comparison table + a bar chart (failures before→after) + an `hbar` of recovered-by-family.
