#!/usr/bin/env python3
"""Triage a CUBRID PR's CI result.

  ci_check.py [PR]        PR = number or URL; default = the current branch's PR

Green PRs cost nothing: the CircleCI test payloads (1-2 MB each) are downloaded only when a
test job actually failed. Each failing test is then classified against other recent runs of the
same job, because CUBRID's develop branch runs only build/build_debug: there is no develop
baseline to compare against, so recent builds on OTHER PRs stand in for one.
"""
import json, re, subprocess, sys

REPO_DEFAULT = "CUBRID/cubrid"
SAMPLE = 5           # comparison builds (other PRs' runs of the same job)
TIMEOUT = 30


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


def main():
    arg = None
    for a in sys.argv[1:]:
        if a.startswith("-"):
            die(f"unknown option '{a}'")
        arg = a
    repo, pr = resolve_pr(arg)

    roll = sh("gh", "pr", "view", str(pr), "--repo", repo, "--json", "statusCheckRollup,baseRefOid",
              "-q", "{r: .statusCheckRollup, b: .baseRefOid}")
    if not roll:
        die(f"cannot read PR #{pr} of {repo} (gh authenticated?)")
    data = json.loads(roll)
    checks = data["r"] or []

    failed, pending = [], []
    for c in checks:
        name = c.get("context") or c.get("name") or "?"
        state = (c.get("state") or c.get("conclusion") or "").upper()
        url = c.get("targetUrl") or c.get("detailsUrl") or ""
        if state in ("FAILURE", "ERROR"):
            failed.append((name, url))
        elif state in ("PENDING", "IN_PROGRESS", "QUEUED", ""):
            pending.append(name)

    print(f"# PR #{pr}  ({repo})")
    print(f"checks: {len(checks)} total, {len(failed)} failed"
          + (f", {len(pending)} still running" if pending else ""))

    # base staleness: a bump PR branched off develop at some point
    base = data.get("b") or ""
    dev = sh("gh", "api", f"repos/{repo}/commits/develop", "--jq", ".sha")
    if base and dev:
        if base == dev:
            print("base: up to date with develop")
        else:
            n = sh("gh", "api", f"repos/{repo}/compare/{base}...{dev}", "--jq", ".ahead_by")
            print(f"base: {base[:7]}, develop is {n or '?'} commit(s) ahead")

    if not failed:
        print("\nAll checks green (or still running). Nothing to triage.")
        return 0

    print("\nfailed checks:")
    for n, u in failed:
        print(f"  {n}  {u}")

    # Only CircleCI test jobs carry test results worth diffing.
    jobs = []
    for name, url in failed:
        m = re.search(r"circleci\.com/gh/[^/]+/[^/]+/(\d+)", url)
        if m and "circleci" in name:
            jobs.append((name.split(":")[-1].strip(), int(m.group(1))))
    if not jobs:
        print("\nNo CircleCI test job failed: the failures above are lint/style checks, "
              "so read them directly (nothing to compare).")
        return 1

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

        def show(title, rows, fmt):
            print(f"\n  [{title}] {len(rows)}")
            for r in rows[:12]:
                print("    " + fmt(r))
            if len(rows) > 12:
                print(f"    ... and {len(rows)-12} more")

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
    return 1


if __name__ == "__main__":
    sys.exit(main())
