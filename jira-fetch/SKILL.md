---
name: jira-fetch
description: "Fetch CUBRID Jira issues as Markdown and load them as working context. Use it whenever a key like CBRD-1234 or a jira.cubrid.org link comes up and the issue content matters. Reads every project the CUBRID account can open, CUBRIDQA included; Atlassian Cloud (HHH) cannot be fetched. To write a new issue, use jira-draft. Triggers on phrases like 'CBRD-1234 내용 가져와', '이 이슈 참고해서 작업하자'."
argument-hint: "<ISSUE-KEY> [ISSUE-KEY...] [-o out-dir]"
allowed-tools:
  - "Bash(bash ${CLAUDE_SKILL_DIR}/assets/fetch_jira.sh *)"
---

# Fetch a JIRA issue to local Markdown

Turn a JIRA issue key into a local `<KEY>.md` (issue summary + description as GitHub-flavored Markdown) and load it as working context. Wraps **[Srltas/jira-to-md-downloader](https://github.com/Srltas/jira-to-md-downloader)** (Python + `uv`, converts the description with `pandoc`).

## Step 0: Prereqs (the helper does the setup)

- `uv` and `pandoc` on PATH (`brew install uv pandoc`).
- The tool is auto-cloned to `~/.cache/claude-skills/jira-to-md-downloader` and `uv sync`'d on first run (override the location with `JIRA_MD_TOOL_DIR`).
- **Credentials** come from env vars (or the tool's `.envrc`): `JIRA_URL`, `JIRA_USER`, `JIRA_PASSWORD` (password or a personal access token). The tool calls the **Jira Server/Data Center REST API v2** (`GET /rest/api/2/issue/<KEY>`) with HTTP Basic auth:
  - **CUBRID Jira Server (CBRD, TOOLS, APIS, CUBRIDQA, ...)**: `JIRA_URL=https://jira.cubrid.org`, your CUBRID account + password/PAT.
  - Any other **Jira Server / Data Center** instance works by changing `JIRA_URL`.
  - **NOT supported as-is: Atlassian Cloud** (e.g. Hibernate `hibernate.atlassian.net`, HHH-…): Cloud requires email + API-token auth and returns the description as ADF JSON, which this v2 + pandoc path does not convert. Supporting it would require a change in the downloader tool itself (Cloud auth + `renderedFields`/ADF handling).

Never hardcode or echo the credentials; the helper reads them from the environment.

## Step 1: Fetch the issue(s)

```bash
bash ${CLAUDE_SKILL_DIR}/assets/fetch_jira.sh -o ./jira CBRD-1234 [TOOLS-4888 APIS-1079 …]
```

The helper clones/syncs the tool if needed, resolves credentials (env → the tool's `.envrc`), downloads each issue to `<out-dir>/<KEY>.md`, and prints the file paths. If credentials or `pandoc` are missing it stops with instructions rather than guessing.

**Issue URLs work too**: a pasted `http://jira.cubrid.org/browse/CBRD-1234` (or `.../issues/...`, with or without a query string) is reduced to its key, and lower-case keys are upper-cased. Anything with no readable key is rejected with a clear error.

**Output directory**: defaults to `./jira` (relative to the current working directory). If the user names a different location (e.g. "docs/tickets 에 받아줘", "save to ~/jira-issues"), pass it with `-o <dir>`: relative paths resolve against the current directory, absolute paths are used as-is.

### Access (measured 2026-11-09)

`jira.cubrid.org` now serves https directly and redirects http to https, so the login in `JIRA_USER` / `JIRA_PASSWORD` reaches the server: every project the account can open downloads, internal ones such as CUBRIDQA included. Before 2026-11 the server redirected https to http, `requests` dropped the login on that redirect, and only public projects (CBRD, TOOLS, APIS) could be read; notes written then may still say so.

- Keep `JIRA_URL=https://jira.cubrid.org`. The helper upgrades an `http://jira.cubrid.org` value, because the http-to-https redirect double-encodes query strings.
- The `# TODO: paste a Personal Access Token …` comment in `.envrc` is a template note, not a credential status. This Jira version has no Personal Access Tokens; the account's username and password work.
- Read failures by code: `401` = the account cannot open that issue; `404` = a wrong key, or a URL passed where a key was expected.

## Step 2: Load as context and work against it

Read each downloaded `<KEY>.md`, then give the user a short summary: 제목, 유형(버그/개선/작업), 핵심 요구사항, 제약. From then on, treat that file as the source of truth for the ticket while doing the actual work, and reference it (`jira/<KEY>.md`) in commits / PR / report as needed. Do not re-fetch an issue whose `.md` already exists unless the user asks to refresh it.
