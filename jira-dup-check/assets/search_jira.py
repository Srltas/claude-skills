#!/usr/bin/env python3
"""Search CUBRID Jira with several phrases and print the merged candidates.

Each phrase becomes one `text ~ "..."` query, where every word must match. The
result lists are merged by reciprocal rank fusion, so an issue that several
phrases find ranks first. Korean words get a prefix wildcard, because Jira does
not strip Korean particles (`병합` misses `병합하면`, `병합*` finds it).

Logs in with JIRA_USER / JIRA_PASSWORD when both are set (restricted comments and
internal projects become visible) and falls back to anonymous access. Uses
https directly: http:// redirects there and double-encodes the query string.
Python 3 standard library only.
"""
import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = 'https://jira.cubrid.org'
FIELDS = 'summary,status,resolution,issuetype,created,fixVersions,description'
# Lucene query syntax that would change or break a text search
SPECIAL = re.compile(r'[+\-&|!(){}\[\]^"~?:\\]')
HANGUL = re.compile('[가-힣]')


def clean(phrase, wildcard=True):
    words = []
    for w in SPECIAL.sub(' ', phrase).split():
        w = w.strip('*')
        if not w:
            continue
        if w in ('AND', 'OR', 'NOT'):
            w = w.lower()
        if wildcard and HANGUL.search(w) and len(w) > 1:
            w += '*'
        words.append(w)
    return ' '.join(words)


class Jira:
    def __init__(self, anonymous=False):
        user, password = os.environ.get('JIRA_USER'), os.environ.get('JIRA_PASSWORD')
        self.auth = None
        if user and password and not anonymous:
            self.auth = 'Basic ' + base64.b64encode(f'{user}:{password}'.encode()).decode()

    def search(self, jql, max_results, fields=FIELDS, start=0):
        query = urllib.parse.urlencode({'jql': jql, 'fields': fields, 'maxResults': max_results, 'startAt': start})
        headers = {'Accept': 'application/json'}
        if self.auth:
            headers['Authorization'] = self.auth
        request = urllib.request.Request(f'{BASE}/rest/api/2/search?{query}', headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as e:
            if e.code == 401 and self.auth:
                print('warning: login rejected, continuing anonymously', file=sys.stderr)
                self.auth = None
                return self.search(jql, max_results, fields, start)
            try:
                messages = json.load(e).get('errorMessages')
            except ValueError:
                messages = None
            raise RuntimeError(f'HTTP {e.code}: {messages or e.reason}') from None


def project_clause(projects):
    names = [p.strip() for p in projects.split(',') if p.strip()]
    return f'project = {names[0]}' if len(names) == 1 else f'project in ({", ".join(names)})'


def title_query(title):
    """The title's words joined by OR, so Jira ranks issues by how many of them they share."""
    return ' OR '.join(clean(title, wildcard=False).split())


def find(jira, phrases, projects='CBRD', per_phrase=20, before=None, exclude=(),
         search_fields='text', wildcard=True, raw=False, title=None):
    """Run one query per phrase (plus the title query) and merge them.

    Returns (ranked candidates, per-query log). raw=True passes each phrase through unchanged.
    """
    scores, issues, hits, queries = {}, {}, {}, []
    jobs = [(p, p if raw else clean(p, wildcard)) for p in phrases]
    if title:
        jobs.append(('title', title_query(title)))
    for phrase, terms in jobs:
        if not terms:
            continue
        if search_fields == 'text':
            match = f'text ~ "{terms}"'
        else:
            match = f'(summary ~ "{terms}" OR description ~ "{terms}")'
        jql = f'{project_clause(projects)} AND {match}'
        if before:
            jql += f' AND created < "{before}"'
        try:
            data = jira.search(jql, per_phrase)
        except RuntimeError as e:
            queries.append((match, str(e)))
            continue
        queries.append((match, data.get('total', 0)))
        for rank, issue in enumerate(data.get('issues', [])):
            key = issue['key']
            if key in exclude:
                continue
            scores[key] = scores.get(key, 0) + 1 / (60 + rank)
            issues[key] = issue
            hits.setdefault(key, []).append(phrase)
        time.sleep(0.2)
    ranked = sorted(scores, key=lambda k: (-scores[k], k))
    return [(key, issues[key], hits[key]) for key in ranked], queries


def describe(issue, excerpt):
    f = issue['fields']
    resolution = (f.get('resolution') or {}).get('name') or '-'
    fixes = ', '.join(v['name'] for v in f.get('fixVersions') or []) or '-'
    text = ' '.join((f.get('description') or '').split())
    if excerpt and len(text) > excerpt:
        text = text[:excerpt] + '...'
    return {
        'summary': f.get('summary', ''),
        'type': f['issuetype']['name'],
        'status': f['status']['name'],
        'resolution': resolution,
        'fix_versions': fixes,
        'created': f['created'][:10],
        'excerpt': text if excerpt else '',
    }


def main():
    ap = argparse.ArgumentParser(description='Find existing CUBRID Jira issues that match several phrases.')
    ap.add_argument('phrases', nargs='+', help='short phrases; every word of a phrase must match')
    ap.add_argument('--project', default='CBRD', help='project key, or several separated by commas (default CBRD)')
    ap.add_argument('--top', type=int, default=15, help='candidates to print (default 15)')
    ap.add_argument('--per-phrase', type=int, default=20, help='results taken from each query (default 20)')
    ap.add_argument('--excerpt', type=int, default=300, help='description characters to show, 0 for none (default 300)')
    ap.add_argument('--title', help='the draft title: adds one query that ranks issues by the title words they share')
    ap.add_argument('--exclude', nargs='*', default=[], help='keys to leave out, e.g. the issue being checked')
    ap.add_argument('--before', help='only issues created before this time, e.g. "2026-10-28 14:00"')
    ap.add_argument('--anonymous', action='store_true', help='do not log in even when credentials are set')
    ap.add_argument('--json', action='store_true', help='print JSON instead of text')
    args = ap.parse_args()

    jira = Jira(args.anonymous)
    ranked, queries = find(jira, args.phrases, args.project, args.per_phrase, args.before, set(args.exclude),
                           title=args.title)
    top = [dict(key=k, phrases=len(p), **describe(i, args.excerpt)) for k, i, p in ranked[:args.top]]
    if args.json:
        print(json.dumps({'queries': queries, 'candidates': top, 'found': len(ranked)}, ensure_ascii=False, indent=1))
        return
    print(f'access: {"logged in" if jira.auth else "anonymous"}, project: {args.project}')
    for match, total in queries:
        print(f'  {total!s:>6}  {match}')
    print(f'{len(ranked)} distinct issues, top {len(top)}:\n')
    for n, c in enumerate(top, 1):
        print(f'{n:2}. {c["key"]}  [{c["phrases"]}/{len(queries)} queries]  {c["type"]} / {c["status"]} / '
              f'{c["resolution"]}  created {c["created"]}  fix {c["fix_versions"]}')
        print(f'    {c["summary"]}')
        print(f'    {BASE}/browse/{c["key"]}')
        if c['excerpt']:
            print(f'    {c["excerpt"]}')
    if not top:
        print('no candidates; try shorter phrases or other words')


if __name__ == '__main__':
    main()
