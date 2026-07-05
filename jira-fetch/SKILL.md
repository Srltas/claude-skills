---
name: jira-fetch
description: "Download a JIRA issue to a local Markdown file to use as working context, via the Srltas/jira-to-md-downloader tool. Give it one or more issue keys (e.g. CBRD-1234) and it fetches each issue's summary + description as <KEY>.md, then loads it into the session so you can work against the ticket. Built for Jira Server/Data Center (REST API v2 + HTTP Basic auth); the verified target is CUBRID's CBRD JIRA at jira.cubrid.org, and any other Jira Server instance works by setting JIRA_URL. Atlassian Cloud (e.g. Hibernate HHH at hibernate.atlassian.net) is NOT supported as-is. It is the reverse of writing an issue up to JIRA. Triggers on phrases like 'CBRD-1234 내용 가져와', '이 이슈 md로 내려받아', 'jira 이슈 다운로드해서 참고', 'fetch jira issue as markdown'."
argument-hint: "<ISSUE-KEY> [ISSUE-KEY...] [-o out-dir]"
---

# Fetch a JIRA issue to local Markdown

Turn a JIRA issue key into a local `<KEY>.md` (issue summary + description as GitHub-flavored Markdown) and load it as working context. Wraps **[Srltas/jira-to-md-downloader](https://github.com/Srltas/jira-to-md-downloader)** (Python + `uv`, converts the description with `pandoc`).

## Step 0 — Prereqs (the helper does the setup)

- `uv` and `pandoc` on PATH (`brew install uv pandoc`).
- The tool is auto-cloned to `~/.cache/claude-skills/jira-to-md-downloader` and `uv sync`'d on first run (override the location with `JIRA_MD_TOOL_DIR`).
- **Credentials** come from env vars (or the tool's `.envrc`): `JIRA_URL`, `JIRA_USER`, `JIRA_PASSWORD` (password or a personal access token). The tool calls the **Jira Server/Data Center REST API v2** (`GET /rest/api/2/issue/<KEY>`) with HTTP Basic auth:
  - **Verified — CUBRID (CBRD-…)**: `JIRA_URL=https://jira.cubrid.org`, your CUBRID account + password/PAT.
  - Any other **Jira Server / Data Center** instance works by changing `JIRA_URL`.
  - **NOT supported as-is — Atlassian Cloud** (e.g. Hibernate `hibernate.atlassian.net`, HHH-…): Cloud requires email + API-token auth and returns the description as ADF JSON, which this v2 + pandoc path does not convert. Supporting it would require a change in the downloader tool itself (Cloud auth + `renderedFields`/ADF handling).

Never hardcode or echo the credentials; the helper reads them from the environment.

## Step 1 — Fetch the issue(s)

```bash
bash <skill-base-dir>/assets/fetch_jira.sh -o ./jira CBRD-1234 [CBRD-1250 …]
```

`<skill-base-dir>` is this skill's own directory. The helper clones/syncs the tool if needed, resolves credentials (env → the tool's `.envrc`), downloads each issue to `<out-dir>/<KEY>.md`, and prints the file paths. If credentials or `pandoc` are missing it stops with instructions rather than guessing.

**Output directory**: defaults to `./jira` (relative to the current working directory). If the user names a different location (e.g. "docs/tickets 에 받아줘", "save to ~/jira-issues"), pass it with `-o <dir>` — relative paths resolve against the current directory, absolute paths are used as-is.

## Step 2 — Load as context and work against it

Read each downloaded `<KEY>.md`, then give the user a short summary: 제목, 유형(버그/개선/작업), 핵심 요구사항, 제약. From then on, treat that file as the source of truth for the ticket while doing the actual work, and reference it (`jira/<KEY>.md`) in commits / PR / report as needed. Do not re-fetch an issue whose `.md` already exists unless the user asks to refresh it.
