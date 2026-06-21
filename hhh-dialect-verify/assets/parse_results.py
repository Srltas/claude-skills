#!/usr/bin/env python3
"""Parse Hibernate JUnit XML results and diff two runs — for CUBRID dialect verification.

  parse_results.py parse <test-results-dir> [out.json]   # counts + failing-test set (+ family) ; optionally save
  parse_results.py diff  <baseline.json> <after.json>    # +N recovered / -N regressed + per-family

Stdlib only (python3). Reads per-class TEST-*.xml; skips the giant aggregate file.
A "failure" = a <testcase> with a <failure> or <error> child. Test identity = classname::name.
"""
import sys
import os
import glob
import json
import re
from collections import Counter
import xml.etree.ElementTree as ET

# failure families (order matters — first match wins); patterns from the CUBRID triage
FAMILY = [
    ("syntax/reserved",  r"Syntax: before|Unknown class|reserved word|syntax error"),
    ("bit/boolean",      r"coerce.*\bbit\b|to type bit|\bBOOLEAN\b|cannot .*boolean"),
    ("datetime/binding", r"java\.time|OffsetDateTime|Instant|getTimeZone|setTimestamp|UnsupportedOperationException"),
    ("LOB/binary",       r"\bLOB\b|blob|Type conversion error|byte\[\]|VARBINARY|bit varying"),
    ("scrollable",       r"Scrollable result sets"),
    ("lock/timeout",     r"\block\b|timeout|LockTimeout"),
    ("driver-NPE",       r"NullPointerException|CUBRIDConnection|createCUBRIDException"),
]


def classify(text):
    for name, pat in FAMILY:
        if re.search(pat, text, re.I):
            return name
    return "other"


def root_sig(text):
    """Condensed root-cause signature: prefer a CUBRID 'Caused by', else the deepest one."""
    causes = re.findall(r"Caused by:\s*([^\n]+)", text)
    line = next((c for c in causes if "cubrid" in c.lower()), None)
    if line is None and causes:
        line = causes[-1]
    if line is None:
        m = re.search(r"([\w.]+(?:Exception|Error|Failure)[^\n]*)", text)
        line = m.group(1) if m else (text.strip().split("\n", 1)[0] if text.strip() else "")
    return re.sub(r"\s+", " ", line).strip()[:120]


def parse_dir(d):
    files = [f for f in glob.glob(os.path.join(d, "TEST-*.xml"))
             if "Gradle-Test-Run" not in os.path.basename(f)]
    seen, skipped, passed = {}, set(), set()
    for f in files:
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        for tc in root.iter("testcase"):
            tid = "%s::%s" % (tc.get("classname"), tc.get("name"))
            el = tc.find("failure")
            if el is None:
                el = tc.find("error")
            if el is not None:
                body = (el.text or "") + " " + (el.get("message") or "") + " " + (el.get("type") or "")
                seen[tid] = {"test": tid, "type": el.get("type") or "",
                             "sig": root_sig(body), "family": classify(body)}
            elif tc.find("skipped") is not None:
                skipped.add(tid)
            else:
                passed.add(tid)
    failures = list(seen.values())
    return {"dir": d, "total": len(seen) + len(skipped) + len(passed),
            "passed": len(passed), "failed": len(failures), "skipped": len(skipped),
            "failures": failures}


def cmd_parse():
    d = sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else None
    r = parse_dir(d)
    print("total=%d  passed=%d  failed=%d  skipped=%d" % (r["total"], r["passed"], r["failed"], r["skipped"]))
    for k, v in Counter(x["family"] for x in r["failures"]).most_common():
        print("  %-18s %d" % (k, v))
    if out:
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(r, fh, ensure_ascii=False, indent=1)
        print("saved: %s" % out)


def _diff_counts(base, after):
    bset = {x["test"] for x in base["failures"]}
    amap = {x["test"]: x for x in after["failures"]}
    recovered = bset - set(amap)
    regressed = set(amap) - bset
    return {
        "total": after["total"], "passed": after["passed"], "failed": after["failed"], "skipped": after["skipped"],
        "baseline_failed": base["failed"], "net": base["failed"] - after["failed"],
        "recovered": len(recovered), "regressed": len(regressed),
        "families": dict(Counter(x["family"] for x in after["failures"])),
        "recovered_by_family": dict(Counter(x["family"] for x in base["failures"] if x["test"] in recovered)),
        "regressed_by_family": dict(Counter(amap[t]["family"] for t in regressed)),
    }


def cmd_summarize():
    """summarize <baseline.json> <out.json> <label1>=<after1.json> [<label2>=<after2.json> ...]"""
    base = json.load(open(sys.argv[2], encoding="utf-8"))
    out = sys.argv[3]
    versions = []
    for arg in sys.argv[4:]:
        label, _, path = arg.partition("=")
        d = _diff_counts(base, json.load(open(path, encoding="utf-8")))
        d["version"] = label
        versions.append(d)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"baseline_failed": base["failed"], "versions": versions}, fh, ensure_ascii=False, indent=1)
    print("%-9s %8s %8s %10s %10s %7s" % ("version", "total", "failed", "recovered", "regressed", "net"))
    for v in versions:
        print("%-9s %8d %8d %+10d %+10d %+7d" % (v["version"], v["total"], v["failed"], v["recovered"], -v["regressed"], v["net"]))
    print("saved: %s" % out)


def cmd_diff():
    base = json.load(open(sys.argv[2], encoding="utf-8"))
    after = json.load(open(sys.argv[3], encoding="utf-8"))
    bset = {x["test"]: x for x in base["failures"]}
    aset = {x["test"]: x for x in after["failures"]}
    recovered = [bset[t] for t in bset if t not in aset]
    regressed = [aset[t] for t in aset if t not in bset]
    print("baseline failed=%d  after failed=%d  net=%+d" % (base["failed"], after["failed"], base["failed"] - after["failed"]))
    print("recovered (+%d)   regressed (-%d)" % (len(recovered), len(regressed)))
    print("recovered by family:")
    for k, v in Counter(x["family"] for x in recovered).most_common():
        print("  +%-5d %s" % (v, k))
    if regressed:
        print("regressed by family:")
        for k, v in Counter(x["family"] for x in regressed).most_common():
            print("  -%-5d %s" % (v, k))
        print("regressed tests (first 25):")
        for x in regressed[:25]:
            print("  %s  [%s] %s" % (x["test"], x["family"], x["sig"][:60]))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "parse":
        cmd_parse()
    elif cmd == "diff":
        cmd_diff()
    elif cmd == "summarize":
        cmd_summarize()
    else:
        print(__doc__)
        sys.exit(1)
