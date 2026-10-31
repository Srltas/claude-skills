#!/usr/bin/env python3
"""Check every skill in this collection against the collection's conventions.

Fails on: a name that does not match its directory; a description that is missing, not one
double-quoted line, longer than MAX_DESC, or contains '<', '>' or an em-dash; trigger phrases
on a manual-only skill or none on an auto-invoked one; a leftover <skill-base-dir> placeholder
or a hardcoded ~/.claude/skills path in SKILL.md; a README skill table that does not match the
skills. Warns when a skill is not linked into ~/.claude/skills.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILLS_DIR = os.path.expanduser('~/.claude/skills')
MAX_DESC = 450
HARDCODED = re.compile(r'(~|\$HOME|\$\{HOME\})/\.claude/skills/[A-Za-z0-9_-]+/(assets|scripts|references)/')
MANUAL_MARK = '(`/{}` only, manual)'

errors, warnings = [], []
skills = sorted(d for d in os.listdir(ROOT) if os.path.isfile(os.path.join(ROOT, d, 'SKILL.md')))
manual = set()

for d in skills:
    where = f'{d}/SKILL.md'
    text = open(os.path.join(ROOT, where), encoding='utf-8').read()
    m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
    if not m:
        errors.append(f'{where}: no frontmatter')
        continue
    fm = m.group(1)
    name = re.search(r'^name:\s*(.+)$', fm, re.M)
    if not name or name.group(1).strip().strip('"\'') != d:
        errors.append(f'{where}: name does not match the directory')
    if re.search(r'^disable-model-invocation:\s*true\s*$', fm, re.M):
        manual.add(d)
    desc = re.search(r'^description:\s*"(.*)"$', fm, re.M)
    if not desc:
        errors.append(f'{where}: description must be one double-quoted line')
    else:
        desc = desc.group(1)
        if len(desc) > MAX_DESC:
            errors.append(f'{where}: description is {len(desc)} chars (max {MAX_DESC})')
        bad = sorted({c for c in desc if c in '<>—'})
        if bad:
            errors.append(f'{where}: description contains {" ".join(bad)}')
        triggers = 'Triggers on phrases like' in desc
        if d in manual and triggers:
            errors.append(f'{where}: manual-only skill lists trigger phrases (its description never reaches Claude)')
        if d not in manual and not triggers:
            errors.append(f'{where}: auto-invoked skill has no "Triggers on phrases like ..."')
    if '<skill-base-dir>' in text:
        errors.append(f'{where}: <skill-base-dir> placeholder left (use the CLAUDE_SKILL_DIR variable)')
    if HARDCODED.search(text):
        errors.append(f'{where}: hardcoded ~/.claude/skills path (use the CLAUDE_SKILL_DIR variable)')
    if os.path.realpath(os.path.join(SKILLS_DIR, d)) != os.path.realpath(os.path.join(ROOT, d)):
        warnings.append(f'{d}: not linked into {SKILLS_DIR} (run just install)')

readme = open(os.path.join(ROOT, 'README.md'), encoding='utf-8').read()
section = re.search(r'^## Skills\n(.*?)(?=^## )', readme, re.S | re.M)
rows = dict(re.findall(r'^\| `([a-z0-9-]+)` \| (.*) \|$', section.group(1) if section else '', re.M))
for d in skills:
    if d not in rows:
        errors.append(f'README.md: no row for {d}')
    elif (MANUAL_MARK.format(d) in rows[d]) != (d in manual):
        errors.append(f'README.md: the manual marker on {d} does not match its frontmatter')
for d in rows:
    if d not in skills:
        errors.append(f'README.md: row for {d}, which is not a skill here')

for w in warnings:
    print(f'warn: {w}')
for e in errors:
    print(f'FAIL: {e}')
print(f'{len(skills)} skills ({len(manual)} manual-only): {len(errors)} errors, {len(warnings)} warnings')
sys.exit(1 if errors else 0)
