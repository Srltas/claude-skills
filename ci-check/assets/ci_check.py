#!/usr/bin/env python3
"""Triage a CUBRID PR's CI result.

  ci_check.py [PR]        PR = number or URL; default = the current branch's PR
  ci_check.py RUN_URL     a gha-ci run (.../actions/runs/<id>): triage that run of its PR

A PR's tests report from one of two systems, and a green PR costs nothing on either:
- CircleCI (`ci/circleci: test_*`). The test payloads (1-2 MB each) are downloaded only when a
  test job actually failed. Each failing test is then classified against other recent runs of
  the same job, because develop runs only build/build_debug there: there is no develop baseline
  to compare against, so recent builds on OTHER PRs stand in for one.
- gha-ci, a self-hosted GitHub Actions workflow (`gha-ci: test_*`) that `/run ...` PR comments
  start. Its nightly batch tests every develop commit (`dispatch all <sha>`) and posts the same
  statuses there, so each failing case is checked against develop itself: at the PR's base and
  at the newest develop commit with a verdict. That nightly runs each commit once, so a case that
  fails now and then can pass there: a case develop does not explain is then looked up in other
  PRs' recent failed runs. Only failed shards' logs are read.
"""
import json, re, subprocess, sys
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from functools import lru_cache

REPO_DEFAULT = "CUBRID/cubrid"
SAMPLE = 5           # comparison builds (other PRs' runs of the same job)
TIMEOUT = 30
SAME_BUILD = 3       # gha-ci: other runs of one build read for flakiness, and other PRs' failing runs checked so
DEVELOP_WALK = 15    # gha-ci: newest develop commits searched for a verdict
OTHER_DAYS = 3       # gha-ci: how far back other PRs' failed runs are searched for the same case
OTHER_RUNS = 40      # gha-ci: at most this many of those runs, newest first
OTHER_SHARDS = 3     # gha-ci: one of those runs that failed more of the suite's shards is broken, not flaky
ARTIFACTS = "http://192.168.1.48:30080"   # gha-ci's JUnit XML: internal, often unreachable

# A case line in a gha-ci shard's CTP output, sql/medium and shell:
#   Testing /home/cubrid-testcases/sql/_36_guava/.../x.sql (132/228 57.89%) [NOK]
#   [TESTCASE] cubrid-testcases-private-ex/shell/_06_issues/.../x.sh EnvId=local [NOK]
CASE = re.compile(r"(?:Testing /home/([^/\s]+)/|\[TESTCASE\] ([^/\s]+)/)(\S+).*\[(N?OK)\]\s*$")
VERDICT = re.compile(r"assigned (\d+) / run (\d+) / failed (\d+) / skipped (\d+)")
KO = {"fail": "실패", "pass": "통과"}


def sh(*args):
    p = subprocess.run(args, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def api(url):
    # curl, not urllib: CircleCI's project-list endpoint returns nothing to urllib.
    out = sh("curl", "-sf", "--max-time", str(TIMEOUT), url)
    if not out:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def die(msg, code=2):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def resolve_pr(arg):
    repo = REPO_DEFAULT
    if arg and "github.com/" in arg:
        m = re.search(r"github\.com/([^/]+/[^/]+)/pull/(\d+)", arg)
        if m:
            return m.group(1), int(m.group(2))
    if arg:
        m = re.search(r"\d+", arg)
        if not m:
            die(f"cannot read a PR number from '{arg}'")
        return repo, int(m.group(0))
    n = sh("gh", "pr", "view", "--json", "number", "-q", ".number")
    if not n:
        die("no PR for the current branch. Pass a PR number or URL.")
    r = sh("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
    return (r or repo), int(n)


def failing_tests(repo, build):
    """Tests that actually FAILED. `skipped` is a deliberate exclusion ("Skipped by bug"),
    not a failure, so counting it would inflate every report."""
    d = api(f"https://circleci.com/api/v1.1/project/github/{repo}/{build}/tests")
    if not d or "tests" not in d:
        return None, {}, 0, 0
    bad, msgs, skipped = set(), {}, 0
    for t in d["tests"]:
        r = t.get("result")
        if r == "skipped":
            skipped += 1
        elif r != "success":
            name = t.get("name") or t.get("classname") or "?"
            bad.add(name)
            msgs[name] = t.get("message") or ""
    return bad, msgs, skipped, len(d["tests"])


def builds_of_job(repo, job, limit=100):
    d = api(f"https://circleci.com/api/v1.1/project/github/{repo}?filter=completed&limit={limit}")
    return [b for b in (d or []) if (b.get("workflows") or {}).get("job_name") == job]


def builds_of_job_on_pr(repo, pr, job, limit=30):
    """This PR's own earlier runs. The project-wide list only reaches back about a day, so
    an earlier run of the same PR must be read from the PR branch itself: missing it makes a
    flaky test look PR-specific."""
    branch = f"pull%2F{pr}%2Fhead"
    d = api(f"https://circleci.com/api/v1.1/project/github/{repo}/tree/{branch}?filter=completed&limit={limit}")
    return [b for b in (d or []) if (b.get("workflows") or {}).get("job_name") == job]


def build_revision(repo, build):
    d = api(f"https://circleci.com/api/v1.1/project/github/{repo}/{build}")
    return (d or {}).get("vcs_revision") or ""


def excerpt(msg, lines=6):
    """The interesting part of a shell-TC failure: the NOK / diff lines."""
    keep = [ln for ln in msg.splitlines() if re.search(r"NOK|failed|Error|error:|diff ", ln)]
    return keep[:lines] or msg.splitlines()[:lines]


def show(title, rows, fmt):
    print(f"\n  [{title}] {len(rows)}")
    for r in rows[:12]:
        print("    " + fmt(r))
    if len(rows) > 12:
        print(f"    ... and {len(rows)-12} more")


def circleci_triage(repo, pr, jobs):
    for job, build in jobs:
        print(f"\n## {job}  (build {build})")
        mine, msgs, skipped, total = failing_tests(repo, build)
        if mine is None:
            print("  no structured test results for this build: open the CircleCI link.")
            continue
        if total == 0:
            print("  이 잡은 테스트 결과가 없다: 빌드/컴파일 단계에서 실패했다는 뜻이다.")
            print("  서브모듈 변경이 부모 빌드를 깨뜨렸을 가능성이 높다. 위 CircleCI 링크에서 컴파일 로그를 확인할 것.")
            print("  (테스트 단계까지 가지 못했으므로 flaky·공통 판별은 의미가 없다.)")
            continue
        print(f"  {len(mine)} failing test(s)" + (f", {skipped} skipped by bug (not a failure)" if skipped else ""))

        others = [b for b in builds_of_job(repo, job)
                  if b["build_num"] != build and f"pull/{pr}" not in (b.get("branch") or "")]
        same_pr = [b for b in builds_of_job_on_pr(repo, pr, job) if b["build_num"] != build]
        sample = others[:SAMPLE]
        print(f"  compared against {len(sample)} recent run(s) on other PRs"
              + (f" and {len(same_pr[:3])} earlier run(s) of this PR" if same_pr else " (no earlier run of this PR)"))

        # Evidence from an earlier run of the SAME commit outranks everything else: the code was
        # identical, so a differing result can only be flakiness.
        rev = build_revision(repo, build)
        ev = {t: {"same_ok": 0, "fail": 0, "ok": 0} for t in mine}
        for b in sample + same_pr[:3]:
            bad, _, _, _ = failing_tests(repo, b["build_num"])
            if bad is None:
                continue
            same_commit = bool(rev) and b.get("vcs_revision") == rev
            for t in mine:
                if t in bad:
                    ev[t]["fail"] += 1
                else:
                    ev[t]["ok"] += 1
                    if same_commit:
                        ev[t]["same_ok"] += 1

        common, unique, flaky, unknown = [], [], [], []
        for t in sorted(mine):
            e = ev[t]
            if e["same_ok"]:
                flaky.append((t, e["fail"], e["ok"], True))
            elif e["fail"] and e["ok"]:
                flaky.append((t, e["fail"], e["ok"], False))
            elif e["fail"]:
                common.append((t, e["fail"]))
            elif e["ok"]:
                unique.append(t)
            else:
                unknown.append(t)

        show("공통 (다른 PR에서도 실패, 이 PR 무관)", common, lambda r: f"{r[0]}  (다른 실행 {r[1]}건에서도 실패)")
        show("flaky (실행마다 결과가 갈림)", flaky,
             lambda r: f"{r[0]}  (실패 {r[1]} / 성공 {r[2]})" + ("  ** 동일 커밋에서 통과한 적 있음 **" if r[3] else ""))
        show("고유 (여기서만 실패)", unique, lambda t: t)
        if unknown:
            show("판정 불가 (비교 표본에 근거 없음)", unknown, lambda t: t)

        for t in unique[:5]:
            print(f"\n  --- {t}")
            for ln in excerpt(msgs.get(t, "")):
                print("      " + ln[:160])

        print("\n  판단:")
        confirmed = [f for f in flaky if f[3]]
        if not mine:
            print("    잡은 실패했는데 실패한 TC가 없다. 인프라·타임아웃 등 테스트 외 원인이므로 CircleCI 로그를 볼 것.")
        elif unique:
            print("    이 PR에서만 실패한 TC가 있다. 서브모듈 변경 내용과 대조해 실제 원인을 확인할 것.")
        elif confirmed:
            print(f"    {len(confirmed)}건이 동일 커밋({rev[:7]})에서 통과한 적이 있다: 확정 flaky.")
            print("    재실행이 유효하다. base 업데이트는 이 실패와 무관하다.")
        elif flaky and not common:
            print("    간헐적 실패로 보인다. 재실행이 유효하다.")
        elif common and not flaky:
            print("    전부 다른 PR에서도 실패한다. 이 PR 탓이 아니므로 재실행해도 같은 결과다.")
            print("    base 업데이트로도 안 고쳐진다. 해당 TC를 별도 이슈로 다루거나 담당자에게 확인할 것.")
        else:
            print("    공통 실패와 flaky가 섞여 있다. 공통 실패 쪽은 별도 이슈, flaky 쪽은 재실행.")


def gh_lines(*args):
    return [ln for ln in sh("gh", "api", *args).splitlines() if ln]


def merge_base(repo, branch, head):
    """Where `head` left `branch`, and how many commits `branch` has gained since."""
    out = sh("gh", "api", f"repos/{repo}/compare/{branch}...{head}",
             "--jq", "[.merge_base_commit.sha, .behind_by] | @tsv")
    return out.split("\t") if out else ("", "")


def print_base(base, behind, branch):
    if base:
        print(f"base: up to date with {branch}" if behind == "0"
              else f"base: {base[:7]}, {branch} is {behind} commit(s) ahead")


@lru_cache(maxsize=None)
def run_jobs(repo, run):
    """(job id, name, conclusion) of each job in a gha-ci run's latest attempt; [] if unreadable.
    50 per page: a page of 100 jobs, each listing its steps, can be too big and get an HTTP 502."""
    return [tuple(ln.split("\t")) for ln in gh_lines(
        "--paginate", f"repos/{repo}/actions/runs/{run}/jobs?per_page=50",
        "--jq", '.jobs[] | [.id, .name, (.conclusion // "")] | @tsv')]


def job_log(repo, job, name=""):
    # An sql shard's log is ~25 MB raw, so it comes out of the run's compressed log zip, which
    # `gh run view` downloads once and caches. Any other job's (gate, plan, a shell or medium
    # shard: ~100 KB) is fetched alone, since GitHub can take 30 s to build a run's zip.
    cmd = (["gh", "run", "view", "--job", str(job), "--log", "--repo", repo] if name.startswith("shard sql ")
           else ["gh", "api", f"repos/{repo}/actions/jobs/{job}/logs"])
    p = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    return p.stdout if p.returncode == 0 else None


@lru_cache(maxsize=None)
def gate_info(repo, run):
    """The engine SHA a gha-ci run tested and, for `/run rerun <id>`, the run it re-ran. The
    run's own head_sha is useless here: a comment-started run carries the develop tip."""
    for job, name, _ in run_jobs(repo, run):
        if name == "gate":
            m = re.search(r"resolved: event=\S+ sha=([0-9a-f]{40}).*", job_log(repo, job) or "")
            if m:
                r = re.search(r"rerun_from=(\d+)", m.group(0))
                return m.group(1), (r.group(1) if r else "")
    return "", ""


@lru_cache(maxsize=None)
def gha_verdicts(repo, sha):
    """{suite: [(run, state, description), ...]} gha-ci posted on a commit, newest first. `/run`
    posts on the PR head; the nightly batch (`dispatch all <sha>`) posts on each develop commit."""
    v = {}
    for ln in gh_lines("--paginate", f"repos/{repo}/commits/{sha}/statuses?per_page=100", "--jq",
                       '.[] | select(.context | startswith("gha-ci: test_"))'
                       ' | [.context, .state, .target_url, (.description // "")] | @tsv'):
        ctx, state, url, desc = (ln.split("\t") + [""] * 4)[:4]
        m = re.search(r"/actions/runs/(\d+)", url)
        suite = ctx[len("gha-ci: test_"):]
        if m and state != "pending" and m.group(1) not in [r for r, _, _ in v.get(suite, [])]:
            v.setdefault(suite, []).append((m.group(1), state, desc))
    return v


def verdict(repo, sha, suite):
    """(run, state) of the newest pass/fail verdict for a suite on a commit, or None."""
    return next(((r, st) for r, st, _ in gha_verdicts(repo, sha).get(suite, [])
                 if st in ("success", "failure")), None)


@lru_cache(maxsize=None)
def suite_result(repo, run, suite):
    """What a gha-ci run's FAILED shards of one suite say. Green shards are never read: one sql
    shard's log is ~25 MB. Returns the failed cases (-> shard index), the cases those shards
    passed, each case's testcase repo, each failed shard's verdict line, and whether every
    failed shard ran its whole share (if one died, a case absent from the logs may never have run)."""
    jobs = run_jobs(repo, run)
    r = {"nok": {}, "ok": set(), "repo": {}, "shards": [], "complete": bool(jobs)}
    for job, name, concl in jobs:
        if not name.startswith(f"shard {suite} ") or concl in ("success", "skipped"):
            continue
        if concl == "cancelled":
            r["complete"] = False
            r["shards"].append((name, "cancelled"))
            continue
        res, v, log = {}, None, job_log(repo, job, name)
        for ln in (log or "").splitlines():
            m = CASE.search(ln)
            if m:
                res[m.group(3)] = m.group(4)    # the last word on a case wins
                r["repo"][m.group(3)] = m.group(1) or m.group(2)
            elif VERDICT.search(ln):
                v = VERDICT.search(ln)
        for case, res_ in res.items():
            if res_ == "NOK":
                r["nok"][case] = name.split()[-1]
            else:
                r["ok"].add(case)
        if not v or int(v.group(2)) + int(v.group(4)) < int(v.group(1)):
            r["complete"] = False
        r["shards"].append((name, v.group(0) if v else "no verdict: it died before running its share"
                            if log is not None else "its log could not be read"))
    return r


@lru_cache(maxsize=None)
def tc_commits(repo, run):
    """{testcase repo: commit} a gha-ci run checked out, from its plan job."""
    for job, name, _ in run_jobs(repo, run):
        if name == "plan":
            return dict(re.findall(r"\[checkout\] (\S+) @ \S+ -> ([0-9a-f]{40})", job_log(repo, job) or ""))
    return {}


@lru_cache(maxsize=None)
def tc_files(owner, tc_repo, commit, top):
    """Every file under `top` (sql, shell, medium) of a testcase commit, or None if unreadable."""
    tree = sh("gh", "api", f"repos/{owner}/{tc_repo}/git/trees/{commit}",
              "--jq", f'.tree[] | select(.path == "{top}") | .sha')
    out = sh("gh", "api", f"repos/{owner}/{tc_repo}/git/trees/{tree}?recursive=1", "--jq",
             '.truncated, (.tree[] | select(.type == "blob") | .path)').splitlines() if tree else []
    return {f"{top}/{p}" for p in out[1:]} if out[:1] == ["false"] else None


def read_runs(repo, suite, runs):
    """Read several gha-ci runs at once. Each log takes seconds (an sql shard's costs the run's
    whole log zip), so runs go in parallel; one run's jobs go in sequence to share that zip."""
    def one(run):
        suite_result(repo, run, suite), gate_info(repo, run), tc_commits(repo, run)
    with ThreadPoolExecutor(max_workers=8) as ex:
        list(ex.map(one, dict.fromkeys(runs)))


def outcome(repo, run, suite, case, tc_repo):
    """'fail' or 'pass' for one case in a gha-ci run that reached a verdict, or None when the run
    does not show it. Only failed shards are read, so a pass is mostly inferred: a re-run took
    every failure of the run it names, and a full run took every case in its testcases."""
    r = suite_result(repo, run, suite)
    if case in r["nok"]:
        return "fail"
    if case in r["ok"]:
        return "pass"
    if not r["complete"]:
        return None
    src = gate_info(repo, run)[1]
    if src:
        return "pass" if case in suite_result(repo, src, suite)["nok"] else None
    # A case added to the testcases after this run's snapshot never ran here: no evidence.
    commit = tc_commits(repo, run).get(tc_repo)
    files = tc_files(repo.split("/")[0], tc_repo, commit, case.split("/")[0]) if commit else None
    return "pass" if files and case in files else None


def develop_newer(repo, branch, base):
    """develop commits newer than the PR's base, newest first (at most DEVELOP_WALK)."""
    if branch != "develop" or not base:
        return []
    shas = gh_lines(f"repos/{repo}/commits?sha=develop&per_page={DEVELOP_WALK}", "--jq", ".[].sha")
    return shas[:shas.index(base)] if base in shas else shas


def fixing_commits(repo, base, fixed, cases):
    """Commits from the base to the develop commit that passes whose issue key a failing case's
    path names (cbrd_27381 -> CBRD-27381): the likely fix the PR's base lacks."""
    rows = gh_lines(f"repos/{repo}/compare/{base}...{fixed}", "--jq",
                    r'.commits[] | [.sha[0:7], (.commit.message | split("\n")[0])] | @tsv')
    keys = {f"CBRD-{n}" for c in cases for n in re.findall(r"cbrd_(\d+)", c, re.I)}
    hits = [ln.replace("\t", " ") for ln in rows if any(re.search(rf"\b{k}\b", ln) for k in keys)]
    return hits, len(rows)


def other_pr_failures(repo, pr, suite, cases):
    """Which of `cases` other PRs' recent failed gha-ci runs failed too: {case: [(PR, run), ...]},
    then how many runs were read, how many were left out as broken (over OTHER_SHARDS of the
    suite's shards failed: that PR's own breakage, and dozens of logs), how many GitHub returned
    no job list for (it sometimes answers "Server Error"), and the cut-off date. Newest first,
    sixteen runs at a time, stopping once every case has one."""
    since = (datetime.now(timezone.utc) - timedelta(days=OTHER_DAYS)).strftime("%Y-%m-%d")
    runs = [(x, m.group(1)) for x, title in (ln.split("\t", 1) for ln in gh_lines(
                f"repos/{repo}/actions/workflows/gha-ci.yml/runs?status=failure&created=%3E%3D{since}&per_page=100",
                "--jq", ".workflow_runs[] | [.id, .display_title] | @tsv"))
            for m in [re.match(r"PR #(\d+) ", title)] if m and m.group(1) != str(pr)][:OTHER_RUNS]

    def failed_cases(run):
        shards = [n for _, n, concl in run_jobs(repo, run) if n.startswith(f"shard {suite} ") and concl == "failure"]
        return suite_result(repo, run, suite)["nok"] if len(shards) <= OTHER_SHARDS else None

    hits, read, broken = {}, [], 0
    for i in range(0, len(runs), 16):
        batch = runs[i:i + 16]
        with ThreadPoolExecutor(max_workers=16) as ex:
            noks = list(ex.map(lambda r: failed_cases(r[0]), batch))
        read += batch
        broken += noks.count(None)
        for (x, p), nok in zip(batch, noks):
            for case in cases & (nok or {}).keys():
                hits.setdefault(case, []).append((p, x))
        if cases <= hits.keys():
            break
    return hits, len(read), broken, sum(1 for x, _ in read if not run_jobs(repo, x)), since


def same_build_flip(repo, suite, run, case, tc):
    """Another run of the build `run` tested, on the same testcases commit, that passed `case`, or
    None. A case that failed and passed on one build and one testcase set is flaky: nothing else
    changed between the two runs."""
    sha, commit = gate_info(repo, run)[0], tc_commits(repo, run).get(tc)
    if not sha or not commit:
        return None
    others = [x for x, st, _ in gha_verdicts(repo, sha).get(suite, [])
              if x != run and st in ("success", "failure")][:SAME_BUILD]
    read_runs(repo, suite, others)
    return next((x for x in others if tc_commits(repo, x).get(tc) == commit
                 and outcome(repo, x, suite, case, tc) == "pass"), None)


@lru_cache(maxsize=None)
def artifacts_reachable():
    return sh("curl", "-s", "-o", "/dev/null", "-m", "3", "-w", "%{http_code}", ARTIFACTS + "/")[:1] in ("2", "3")


def junit_failure(run, suite, shard, case):
    """A failed case's <failure> text from its shard's JUnit XML on the artifact server: besides
    the collect job's step summary, which the API does not expose, the only place with the diff."""
    if not artifacts_reachable():
        return ""
    url = f"{ARTIFACTS}/runs/{run}/{suite}/shard/{shard}/test-results/"
    for name in re.findall(r'href="([^"/?]+\.xml)"', sh("curl", "-sf", "-m", str(TIMEOUT), url)):
        try:
            root = ET.fromstring(sh("curl", "-sf", "-m", str(TIMEOUT), url + name))
        except ET.ParseError:
            continue
        for tc in root.iter("testcase"):
            n, f = tc.get("name") or "", tc.find("failure")
            if f is None:
                f = tc.find("error")
            if f is not None and (n == case or n.endswith("/" + case)):
                return (f.get("message") or "") + "\n" + (f.text or "")
    return ""


def gha_build_failed(names):
    print(f"\n## {', '.join(names)}")
    print("  gha-ci 빌드가 실패했다: 테스트 단계까지 가지 못했다. 이 PR의 변경(bump PR이면 서브모듈 변경)이 빌드를 깨뜨렸을 가능성이 높다.")
    print("  run의 build 잡 로그를 확인할 것. (테스트를 못 돌렸으므로 flaky·공통 판별은 의미가 없다.)")


def gha_triage(repo, pr, head, base, branch, failing):
    """Classify each failing case of each failing gha-ci suite against develop, whose nightly
    batch leaves a verdict on (nearly) every commit, against this PR's other runs of the same
    build, and, for a case develop does not explain, against other PRs' recent runs. `failing`
    holds (suite, run, state, description)."""
    newer = develop_newer(repo, branch, base)
    word = {"success": "passed", "failure": "failed"}
    for suite, run, state, desc in failing:
        if state != "failure":
            print(f"\n## gha-ci: test_{suite}  (run {run})")
            print(f"  판정 없음: {desc or state}")
            print(f"  이 실행은 결과를 내지 못했다(취소·중복 요청·인프라). PR에 `/run {suite}` 코멘트로 다시 요청할 것.")
            continue
        # The evidence runs are known from commit statuses alone, so all logs download together.
        same = [(x, st) for x, st, _ in gha_verdicts(repo, head).get(suite, [])
                if x != run and st in ("success", "failure")][:SAME_BUILD]
        at_base = verdict(repo, base, suite) if branch == "develop" and base else None
        newest = next(((c, v) for c in newer for v in [verdict(repo, c, suite)] if v), None)
        read_runs(repo, suite, [run] + [x for x, _ in same] + [v[0] for v in (at_base, newest and newest[1]) if v])

        sha, src = gate_info(repo, run)
        sha = sha or head
        print(f"\n## gha-ci: test_{suite}  (run {run}" + (f", /run rerun {src})" if src else ")"))
        if not run_jobs(repo, run):
            print("  GitHub API에서 이 run의 잡 목록을 읽지 못했다: run 페이지를 직접 열어 볼 것.")
            continue
        r = suite_result(repo, run, suite)
        mine = r["nok"]
        print(f"  {len(mine)} failing case(s)")
        for name, v in r["shards"][:10]:
            print(f"    {name}: {v}")
        if len(r["shards"]) > 10:
            print(f"    ... and {len(r['shards'])-10} more failed shard(s)")
        if not mine:
            if r["shards"]:
                print("  shard가 실패했는데 실패한 케이스가 없다: 케이스 누락·파드 종료 같은 테스트 외 원인이다. 위 verdict 줄과 run 로그를 볼 것.")
                print(f"  못 돌린 케이스는 PR에 `/run rerun {run}` 코멘트로 다시 돌릴 수 있다.")
            else:
                print("  실패한 shard가 없다: collect 단계의 검증(빌드·TC provenance 일치, 케이스 누락)이 실패했다. run의 collect 잡 로그를 볼 것.")
            continue

        print("  compared against:")
        if branch != "develop":
            print(f"    {branch}: no nightly verdicts (the batch tests develop only)")
        else:
            print(f"    develop {base[:7]} (the PR's base): "
                  + (f"run {at_base[0]}, {suite} {word[at_base[1]]}" if at_base
                     else "no verdict (the nightly batch did not cover it)"))
            if newest:
                print(f"    develop {newest[0][:7]} (newest with a verdict): run {newest[1][0]}, {suite} {word[newest[1][1]]}")
            elif newer:
                print(f"    develop: no verdict on the {len(newer)} newer commit(s) searched")
        for x, st in same:
            print(f"    same build {sha[:7]} (this PR): run {x}, {suite} {word[st]}")

        common, flaky, unique, unknown = [], [], [], []
        for case in sorted(mine):
            tc = r["repo"][case]
            # The same build passing it once outranks everything else: only flakiness explains it.
            passed = next((x for x, _ in same if outcome(repo, x, suite, case, tc) == "pass"), None)
            if passed:
                flaky.append((case, passed))
                continue
            b = outcome(repo, at_base[0], suite, case, tc) if at_base else None
            n = outcome(repo, newest[1][0], suite, case, tc) if newest else None
            if "fail" in (b, n):
                common.append((case, b, n))
            elif b == "pass":
                unique.append(case)
            else:
                unknown.append((case, n))

        # The nightly runs each develop commit once, so a case that fails now and then can pass
        # there and look like this PR's. Other PRs' recent runs catch it. A case newer develop
        # passes is left alone: other PRs on old bases fail it too, and that is a stale base.
        ask = set(unique) | {c for c, n in unknown if n != "pass"}
        elsewhere = []
        if ask:
            hits, read, broken, unreadable, since = other_pr_failures(repo, pr, suite, ask)
            print(f"    other PRs: {read} failed gha-ci run(s) since {since} read, newest first"
                  + (f"; {broken} left out, over {OTHER_SHARDS} {suite} shards failed (broken, not flaky)" if broken else "")
                  + (f"; {unreadable} skipped, GitHub returned no job list" if unreadable else ""))
            for case in sorted(hits):
                tc = r["repo"][case]
                flip = next(((p, x, y) for p, x in hits[case][:SAME_BUILD]
                             for y in [same_build_flip(repo, suite, x, case, tc)] if y), None)
                elsewhere.append((case, hits[case], flip))
            unique = [c for c in unique if c not in hits]
            unknown = [c for c in unknown if c[0] not in hits]

        bs, ns = base[:7], (newest[0][:7] if newest else "")

        def note(b, n):
            return " · ".join(([f"base {bs} {KO[b]}"] if b else []) + ([f"develop {ns} {KO[n]}"] if n else []))

        def where(c):
            runs = ", ".join(f"PR #{p} run {x}" for p, x in c[1][:3]) + (f" 외 {len(c[1]) - 3}건" if len(c[1]) > 3 else "")
            return (f"{c[0]}  ({runs}에서도 실패)"
                    + (f"  ** 확정 flaky: PR #{c[2][0]}의 동일 빌드 run {c[2][2]}에서는 통과 **" if c[2] else ""))

        show("공통 (develop에서도 실패, 이 PR 무관)", common, lambda c: f"{c[0]}  ({note(c[1], c[2])})")
        show("flaky (실행마다 결과가 갈림)", flaky, lambda c: f"{c[0]}  (동일 빌드 run {c[1]}에서 통과)")
        if elsewhere:
            show("flaky 추정 (다른 PR에서도 실패, 이 PR 무관)", elsewhere, where)
        show("고유 (여기서만 실패)", unique, lambda c: c)
        if unknown:
            show("판정 불가 (develop과 비교할 근거 없음)", unknown,
                 lambda c: c[0] + (f"  ({note(None, c[1])})" if c[1] else ""))

        for case in unique[:5]:
            print(f"\n  --- {case}")
            text = junit_failure(run, suite, mine[case], case)
            for ln in (excerpt(text) if text else [f"{ARTIFACTS}/runs/{run}/{suite}/shard/{mine[case]}/test-results/"]):
                print("      " + ln[:160])
        if unique and not artifacts_reachable():
            print("\n  (아티팩트 서버에 접속할 수 없어 diff를 못 읽었다: run 페이지 Summary의 collect 항목에서 볼 것)")

        stale = [c for c in common if c[2] == "pass"]      # fails at the base, passes on newer develop
        broken = [c for c in common if c[2] == "fail"]     # newer develop fails it too
        unsure = [c for c in common if c[2] is None]       # fails at the base, nothing newer to say
        print("\n  판단:")
        if unique:
            print(f"    {len(unique)}건은 PR의 base({bs})에서 통과하는데 여기서만 실패한다. 이 PR의 변경과 대조해 원인을 확인할 것.")
        if stale:
            print(f"    {len(stale)}건은 PR의 base({bs})에서도 실패하고 develop {ns}에서는 통과한다: base가 낡아서 생긴 실패다.")
            hits, total = fixing_commits(repo, base, newest[0], [c[0] for c in stale])
            for h in hits:
                print(f"      base 이후 develop에 들어온 관련 커밋: {h}")
            if not hits and total:
                print(f"      base 이후 develop에 들어온 커밋 {total}개 중 하나가 고쳤다 ({bs}..{ns}).")
            print("    `/run rerun`은 같은 SHA의 빌드를 재사용하므로 이 실패를 지우지 못한다.")
            print(f"    base를 {branch} 최신으로 업데이트(merge/rebase)한 뒤 PR에 `/run all` 코멘트로 다시 요청할 것.")
        if broken:
            print(f"    {len(broken)}건은 develop 최신({ns})에서도 실패한다: 이 PR 탓이 아니다. 재실행해도 base를 업데이트해도 같은 결과이므로, 해당 TC를 별도 이슈로 다루거나 담당자에게 확인할 것.")
        if unsure:
            print(f"    {len(unsure)}건은 PR의 base({bs})에서도 실패한다: 이 PR 탓이 아니다. base 이후 develop의 판정이 아직 없어 base 업데이트로 고쳐지는지는 모른다.")
        if flaky:
            print(f"    {len(flaky)}건은 동일 빌드에서 통과한 적이 있다: 확정 flaky. PR에 `/run rerun {run}` 코멘트로 다시 돌리면 된다.")
        if elsewhere:
            sure = sum(1 for c in elsewhere if c[2])
            print(f"    {len(elsewhere)}건은 다른 PR의 최근 run에서도 실패했다: 이 PR 탓이 아닌 flaky로 보인다"
                  + (f"(그중 {sure}건은 그 PR의 동일 빌드에서 통과도 해 확정 flaky)" if sure else "") + ".")
            if not flaky:
                print(f"    PR에 `/run rerun {run}` 코멘트로 다시 돌리면 된다.")
            if sure < len(elsewhere):
                print("    확정이 아닌 건은 다시 돌려도 또 실패하면 이 PR의 변경과 대조할 것.")
        if unknown:
            print(f"    {len(unknown)}건은 develop과 비교할 근거가 없다: 고유로 단정하지 말 것.")
            later = [c[0] for c in unknown if c[1] == "pass"]
            if later:
                print(f"    그중 {len(later)}건은 develop {ns}에서 통과한다. base를 {branch} 최신으로 업데이트한 뒤 `/run all`로 확인할 것.")
                for h in fixing_commits(repo, base, newest[0], later)[0]:
                    print(f"      base 이후 develop에 들어온 관련 커밋: {h}")
            else:
                print(f"    같은 빌드로 다시 돌리면(PR에 `/run rerun {run}`) flaky인지는 가릴 수 있다.")


def gha_run_mode(repo, run):
    """Triage one gha-ci run, e.g. one that a later push or base update left off the PR head."""
    meta = sh("gh", "api", f"repos/{repo}/actions/runs/{run}", "--jq", "[.path, .display_title, .status] | @tsv")
    if not meta:
        die(f"cannot read run {run} of {repo} (gh authenticated?)")
    path, title, status = meta.split("\t")
    if not path.endswith("/gha-ci.yml"):
        die(f"run {run} is not a gha-ci run ({path})")
    m = re.match(r"PR #(\d+) ", title)
    if not m:
        die(f"run {run} tested no PR ('{title}'): only a PR's run can be triaged")
    pr = int(m.group(1))
    print(f"# PR #{pr}  ({repo})  gha-ci run {run}")
    if status != "completed":
        print(f"run {run} is still running. Nothing to triage yet.")
        return 0
    sha = gate_info(repo, run)[0]
    if not sha:
        die(f"run {run} resolved nothing to test (its gate never ran)")
    info = sh("gh", "pr", "view", str(pr), "--repo", repo, "--json", "baseRefName,headRefOid",
              "-q", "[.baseRefName, .headRefOid] | @tsv")
    branch, head = info.split("\t") if info else ("develop", "")
    print(f"tested {sha[:7]}" + (f", which is no longer the PR head ({head[:7]})" if head and head != sha else ""))
    base, behind = merge_base(repo, branch, sha)
    print_base(base, behind, branch)

    builds = [name for _, name, concl in run_jobs(repo, run) if name.startswith("build (") and concl == "failure"]
    failing = [(suite, run, st, desc) for suite, rows in gha_verdicts(repo, sha).items()
               for x, st, desc in rows if x == run and st in ("failure", "error")]
    if not builds and not failing:
        print(f"\nRun {run} failed no suite. Nothing to triage.")
        return 0
    if builds:
        gha_build_failed(builds)
    gha_triage(repo, pr, sha, base, branch, failing)
    return 1


def main():
    arg = None
    for a in sys.argv[1:]:
        if a.startswith("-"):
            die(f"unknown option '{a}'")
        arg = a
    m = re.search(r"github\.com/([^/]+/[^/]+)/actions/runs/(\d+)", arg or "")
    if m:
        return gha_run_mode(m.group(1), m.group(2))
    repo, pr = resolve_pr(arg)

    roll = sh("gh", "pr", "view", str(pr), "--repo", repo, "--json", "statusCheckRollup,baseRefName,headRefOid",
              "-q", "{r: .statusCheckRollup, b: .baseRefName, h: .headRefOid}")
    if not roll:
        die(f"cannot read PR #{pr} of {repo} (gh authenticated?)")
    data = json.loads(roll)
    checks = data["r"] or []

    failed, pending, gha, tested = [], [], [], False
    for c in checks:
        name = c.get("context") or c.get("name") or "?"
        state = (c.get("state") or c.get("conclusion") or "").upper()
        url = c.get("targetUrl") or c.get("detailsUrl") or ""
        tested = tested or name.startswith("gha-ci: ") or "circleci" in name
        if state in ("FAILURE", "ERROR"):
            failed.append((name, url))
            m = re.search(r"/actions/runs/(\d+)", url)
            if name.startswith("gha-ci: test_") and m:
                gha.append((name[len("gha-ci: test_"):], m.group(1), state.lower(), c.get("description") or ""))
        elif state in ("PENDING", "IN_PROGRESS", "QUEUED", ""):
            pending.append(name)

    print(f"# PR #{pr}  ({repo})")
    print(f"checks: {len(checks)} total, {len(failed)} failed"
          + (f", {len(pending)} still running" if pending else ""))

    # base staleness: where the PR left its base branch (a bump PR, develop at some point)
    head, branch = data.get("h") or "", data.get("b") or "develop"
    base, behind = merge_base(repo, branch, head) if head else ("", "")
    print_base(base, behind, branch)
    no_tests = f"Neither CircleCI nor gha-ci has reported on the head {head[:7]}" + (
        ": gha-ci runs only when someone comments `/run all` on the PR."
        if branch == "develop" or branch.startswith("feature/") else ".")

    if not failed:
        print("\nAll checks green (or still running). Nothing to triage.")
        if not tested:
            print(no_tests)
        return 0

    print("\nfailed checks:")
    for n, u in failed:
        print(f"  {n}  {u}")

    # Only CircleCI test jobs and gha-ci suites carry test results worth diffing.
    jobs = []
    for name, url in failed:
        m = re.search(r"circleci\.com/gh/[^/]+/[^/]+/(\d+)", url)
        if m and "circleci" in name:
            jobs.append((name.split(":")[-1].strip(), int(m.group(1))))
    builds = [n for n, _ in failed if n.startswith("gha-ci: build")]
    if not jobs and not gha and not builds:
        print("\nNo test job failed: the failures above are lint/style checks or merge gates, "
              "so read them directly (nothing to compare).")
        if not tested:
            print(no_tests)
        return 1

    circleci_triage(repo, pr, jobs)
    if builds:
        gha_build_failed(builds)
    if gha:
        gha_triage(repo, pr, head, base, branch, gha)
    return 1


if __name__ == "__main__":
    sys.exit(main())
