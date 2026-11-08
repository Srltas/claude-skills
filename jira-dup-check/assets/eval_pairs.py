#!/usr/bin/env python3
"""Measure how often search_jira.py finds the original of a known duplicate.

  pairs  Collect the issues closed as Duplicate whose Duplicate link points to an
         earlier issue of the same project (the original existed when the
         duplicate was filed). Writes gold.json and one draft per duplicate
         (title and description, issue keys masked) to write phrases from.
  score  Search for each duplicate as of its creation time and report how often
         an original is in the top k. Phrases come from a JSON file
         {"CBRD-1": ["phrase", ...]} written by following SKILL.md Step 2, or
         from a baseline: --baseline title (the title as one query, what a person
         pastes into Jira) or --baseline title-or (the title words joined by OR,
         ranked by Jira's own relevance).

Anonymous by default so anyone can reproduce the numbers. score searches the
summary and description only: comments added after the duplicate was filed
often name it, which would leak the answer.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import search_jira as sj  # noqa: E402

# no \b: a Korean particle right after a key (CBRD-1234의) leaves no word boundary
KEYS = re.compile(r'(?<![A-Za-z0-9])(?:CBRD|CUBRIDQA|APIS|TOOLS|CUBRIDMAN|CUBRIDSUS|HHH)-\d+(?!\d)')
TOP_K = (1, 5, 10, 20)


def fetch_all(jira, jql, fields):
    issues, start = [], 0
    while True:
        data = jira.search(jql, 1000, fields, start)
        issues += data['issues']
        start += len(data['issues'])
        if not data['issues'] or start >= data['total']:
            return issues


def jql_time(created):
    """'2026-10-28T14:03:12.000+0900' -> '2026-10-28 14:03' (the server's local time)."""
    return created[:16].replace('T', ' ')


def has_hangul(text):
    return bool(sj.HANGUL.search(text or ''))


def pairs(args):
    jira = sj.Jira(anonymous=not args.login)
    project = args.project
    dups = fetch_all(jira, f'project = {project} AND resolution = Duplicate ORDER BY key ASC',
                     'summary,description,created,issuelinks')
    linked = {}
    for d in dups:
        keys = set()
        for link in d['fields'].get('issuelinks') or []:
            other = link.get('outwardIssue') or link.get('inwardIssue')
            if link['type']['name'] == 'Duplicate' and other and other['key'].startswith(project + '-'):
                keys.add(other['key'])
        linked[d['key']] = keys
    wanted = sorted(set().union(*linked.values())) if linked else []
    info = {}
    for i in range(0, len(wanted), 100):
        for issue in fetch_all(jira, f'key in ({", ".join(wanted[i:i + 100])})', 'created,summary'):
            info[issue['key']] = issue['fields']
    os.makedirs(os.path.join(args.out, 'drafts'), exist_ok=True)
    gold = []
    for d in dups:
        f = d['fields']
        originals = sorted(k for k in linked[d['key']] if k in info and info[k]['created'] < f['created'])
        if not originals:
            continue
        mixed = has_hangul(f['summary']) != has_hangul(info[originals[0]]['summary'])
        gold.append({'key': d['key'], 'created': f['created'], 'summary': f['summary'],
                     'originals': originals, 'languages': 'mixed' if mixed else 'same'})
        draft = KEYS.sub('<KEY>', f"{f['summary']}\n\n{f.get('description') or ''}")[:args.max_chars]
        with open(os.path.join(args.out, 'drafts', d['key'] + '.md'), 'w', encoding='utf-8') as out:
            out.write(draft)
    with open(os.path.join(args.out, 'gold.json'), 'w', encoding='utf-8') as out:
        json.dump(gold, out, ensure_ascii=False, indent=1)
    with_link = sum(1 for k in linked.values() if k)
    mixed = sum(1 for g in gold if g['languages'] == 'mixed')
    print(f'{len(dups)} closed as Duplicate, {with_link} with a visible Duplicate link, '
          f'{len(gold)} pairs whose original came first ({mixed} written in different languages)')
    print(f'wrote {args.out}/gold.json and {len(gold)} drafts in {args.out}/drafts/')


def score(args):
    with open(args.gold, encoding='utf-8') as f:
        gold = json.load(f)
    queries = {}
    if not args.baseline:
        with open(args.queries, encoding='utf-8') as f:
            queries = json.load(f)
    jira = sj.Jira(anonymous=not args.login)
    results = []
    for g in gold:
        raw = False
        if args.baseline == 'title':
            phrases = [sj.clean(g['summary'], wildcard=False)]
        elif args.baseline == 'title-or':
            phrases, raw = [' OR '.join(sj.clean(g['summary'], wildcard=False).split())], True
        else:
            phrases = queries.get(g['key'], [])
        ranked, log = sj.find(jira, phrases, args.project, args.per_phrase, jql_time(g['created']), {g['key']},
                              args.search_fields, wildcard=not args.baseline, raw=raw,
                              title=g['summary'] if args.with_title else None)
        keys = [k for k, _, _ in ranked]
        rank = min((keys.index(o) + 1 for o in g['originals'] if o in keys), default=None)
        results.append({'key': g['key'], 'languages': g['languages'], 'rank': rank,
                        'originals': g['originals'], 'queries': log})
        print(f"{g['key']:12} rank {rank or '-':>3}  {g['languages']}", file=sys.stderr)
    label = (args.baseline or os.path.basename(args.queries)) + (' + title' if args.with_title else '')
    print(f'\n{label}: {len(results)} pairs, search fields {args.search_fields}')
    for group in ('all', 'same', 'mixed'):
        rows = [r for r in results if group == 'all' or r['languages'] == group]
        if not rows:
            continue
        cells = [f"top{k} {sum(1 for r in rows if r['rank'] and r['rank'] <= k)}/{len(rows)}" for k in TOP_K]
        print(f'  {group:5} ' + '  '.join(cells))
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='command', required=True)
    p = sub.add_parser('pairs', help='collect the known duplicate pairs and write drafts')
    p.add_argument('--out', required=True, help='directory for gold.json and drafts/')
    p.add_argument('--max-chars', type=int, default=6000, help='cut each draft to this length (default 6000)')
    s = sub.add_parser('score', help='measure how often an original is found')
    s.add_argument('--gold', required=True, help='gold.json written by pairs')
    group = s.add_mutually_exclusive_group(required=True)
    group.add_argument('--queries', help='JSON file {"KEY": ["phrase", ...]}')
    group.add_argument('--baseline', choices=['title', 'title-or'])
    s.add_argument('--with-title', action='store_true', help='also run the title query, as SKILL.md Step 3 does')
    s.add_argument('--search-fields', choices=['summary-description', 'text'], default='summary-description')
    s.add_argument('--per-phrase', type=int, default=20)
    s.add_argument('--out', help='write per-pair results (rank, queries) to this JSON file')
    for x in (p, s):
        x.add_argument('--project', default='CBRD')
        x.add_argument('--login', action='store_true', help='use JIRA_USER / JIRA_PASSWORD (default anonymous)')
    args = ap.parse_args()
    pairs(args) if args.command == 'pairs' else score(args)


if __name__ == '__main__':
    main()
