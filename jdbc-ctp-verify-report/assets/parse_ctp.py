#!/usr/bin/env python3
"""Parse CUBRID CTP JDBC results and diff two runs — for jdbc-ctp-verify.

  parse_ctp.py parse <result-dir|test-jdbc.xml> [out.json]   # counts + failing-case set (+ family); optionally save
  parse_ctp.py diff  <baseline.json> <after.json>            # +N recovered / -N regressed + per-family

Reads CTP's `test-jdbc.xml` (JUnit format) from result/jdbc/current_runtime_logs/.
A "failure" = a <testcase> with a <failure> or <error> child. Case identity = <TestFile.java>::<method>.
Stdlib only (python3).
"""
import sys
import os
import glob
import json
import re
from collections import Counter
import xml.etree.ElementTree as ET

FAMILY = [
    ("verify-error",     r"VerifyError"),
    ("conversion",       r"Type conversion error|conversion error|[Cc]annot coerce"),
    ("broker/env",       r"broker|Cannot communicate|Connection refused|Communication error|shared memory|Failed to connect"),
    ("classpath/compat", r"NoClassDefFound|ClassNotFound|NoSuchMethod|UnsupportedClassVersion|IncompatibleClassChange"),
    ("NPE",              r"NullPointerException"),
    ("syntax/semantic",  r"Syntax|semantic error|Unknown class"),
    ("assertion",        r"AssertionError|ComparisonFailure|expected:.*but was|assertEquals"),
    ("timeout",          r"timeout|timed out"),
]


def classify(text):
    for name, pat in FAMILY:
        if re.search(pat, text, re.I):
            return name
    return "other"


def sig(text):
    m = re.search(r"([\w.$]+(?:Error|Exception|Failure)[^\n]*)", text)
    line = m.group(1) if m else (text.strip().split("\n", 1)[0] if text.strip() else "")
    return re.sub(r"\s+", " ", line).strip()[:120]


def find_xml(p):
    if os.path.isfile(p):
        return p
    if os.path.isdir(p):
        direct = os.path.join(p, "test-jdbc.xml")
        if os.path.exists(direct):
            return direct
        hits = glob.glob(os.path.join(p, "**", "test-jdbc.xml"), recursive=True)
        return hits[0] if hits else None
    return None


def case_id(tc):
    f = tc.get("file")
    base = os.path.basename(f) if f else (tc.get("classname") or "?").rsplit("/", 1)[-1]
    return "%s::%s" % (base, tc.get("name"))


def parse(p):
    xml = find_xml(p)
    if not xml or not os.path.exists(xml):
        return {"total": 0, "passed": 0, "failed": 0, "skipped": 0, "failures": [],
                "_note": "no test-jdbc.xml under %s" % p}
    root = ET.parse(xml).getroot()
    seen, skipped, passed = {}, set(), set()
    for tc in root.iter("testcase"):
        i = case_id(tc)
        el = tc.find("failure")
        if el is None:
            el = tc.find("error")
        if el is not None:
            body = (el.text or "") + " " + (el.get("message") or "") + " " + (el.get("type") or "")
            seen[i] = {"test": i, "type": el.get("type") or "", "sig": sig(body), "family": classify(body)}
        elif tc.find("skipped") is not None:
            skipped.add(i)
        else:
            passed.add(i)
    return {"xml": xml, "total": len(seen) + len(skipped) + len(passed),
            "passed": len(passed), "failed": len(seen), "skipped": len(skipped),
            "failures": list(seen.values())}


def cmd_parse():
    p = sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else None
    r = parse(p)
    if "_note" in r:
        print(r["_note"], file=sys.stderr)
    print("total=%d  passed=%d  failed=%d  skipped=%d" % (r["total"], r["passed"], r["failed"], r["skipped"]))
    for k, v in Counter(x["family"] for x in r["failures"]).most_common():
        print("  %-18s %d" % (k, v))
    if out:
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(r, fh, ensure_ascii=False, indent=1)
        print("saved: %s" % out)


def cmd_diff():
    base = json.load(open(sys.argv[2], encoding="utf-8"))
    after = json.load(open(sys.argv[3], encoding="utf-8"))
    bset = {x["test"] for x in base["failures"]}
    amap = {x["test"]: x for x in after["failures"]}
    recovered = bset - set(amap)
    regressed = set(amap) - bset
    print("baseline failed=%d  after failed=%d  net=%+d" % (base["failed"], after["failed"], base["failed"] - after["failed"]))
    print("recovered (+%d)   regressed (-%d)" % (len(recovered), len(regressed)))
    print("recovered by family:")
    for k, v in Counter(x["family"] for x in base["failures"] if x["test"] in recovered).most_common():
        print("  +%-5d %s" % (v, k))
    if regressed:
        print("regressed by family:")
        for k, v in Counter(amap[t]["family"] for t in regressed).most_common():
            print("  -%-5d %s" % (v, k))
        print("regressed cases (first 25):")
        for t in list(regressed)[:25]:
            x = amap[t]
            print("  %s  [%s] %s" % (x["test"], x["family"], x["sig"][:60]))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "parse":
        cmd_parse()
    elif cmd == "diff":
        cmd_diff()
    else:
        print(__doc__)
        sys.exit(1)
