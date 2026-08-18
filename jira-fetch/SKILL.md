---
name: jira-fetch
description: "Download a JIRA issue to a local Markdown file to use as working context, via the Srltas/jira-to-md-downloader tool. Give it one or more issue keys or issue URLs (e.g. CBRD-1234, TOOLS-4888, APIS-1079, or a pasted http://jira.cubrid.org/browse/CBRD-1234) and it fetches each issue's summary + description as <KEY>.md, then loads it into the session so you can work against the ticket. Built for Jira Server/Data Center (REST API v2 + HTTP Basic auth); the target is CUBRID's Jira Server at jira.cubrid.org, and it reaches the publicly readable projects (CBRD, TOOLS, APIS, ...) only: internal-only projects such as CUBRIDQA return HTTP 401 and are not supported, and any other Jira Server instance works by setting JIRA_URL. Atlassian Cloud (e.g. Hibernate HHH at hibernate.atlassian.net) is NOT supported as-is. It is the reverse of writing an issue up to JIRA. Triggers on phrases like 'CBRD-1234 내용 가져와', '이 이슈 md로 내려받아', 'jira 이슈 다운로드해서 참고', 'fetch jira issue as markdown'."
argument-hint: "<ISSUE-KEY> [ISSUE-KEY...] [-o out-dir]"
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
bash <skill-base-dir>/assets/fetch_jira.sh -o ./jira CBRD-1234 [TOOLS-4888 APIS-1079 …]
```

`<skill-base-dir>` is this skill's own directory. The helper clones/syncs the tool if needed, resolves credentials (env → the tool's `.envrc`), downloads each issue to `<out-dir>/<KEY>.md`, and prints the file paths. If credentials or `pandoc` are missing it stops with instructions rather than guessing.

**Issue URLs work too**: a pasted `http://jira.cubrid.org/browse/CBRD-1234` (or `.../issues/...`, with or without a query string) is reduced to its key, and lower-case keys are upper-cased. Anything with no readable key is rejected with a clear error.

**Output directory**: defaults to `./jira` (relative to the current working directory). If the user names a different location (e.g. "docs/tickets 에 받아줘", "save to ~/jira-issues"), pass it with `-o <dir>`: relative paths resolve against the current directory, absolute paths are used as-is.

### 접근 범위와 한계 (실측)

이 도구가 읽을 수 있는 것은 **공개(익명 열람 가능) 프로젝트**뿐이다: CBRD, TOOLS, APIS 등은 정상 다운로드된다.

**내부 전용 프로젝트(CUBRIDQA)는 지원하지 않는다.** `HTTP 401`로 실패하며, 그 이슈는 브라우저로 열어서 확인해야 한다. 사용자가 CUBRIDQA 키나 URL을 주면 받아오려 시도하지 말고 이 제약을 알려준다.

이유(2026-07-25 실측): `jira.cubrid.org`가 https 요청을 http로 302 리다이렉트하는데, `requests`는 스킴이 바뀌면 `Authorization` 헤더를 제거한다. 그래서 모든 요청이 익명으로 나가고, 익명에 공개된 프로젝트만 읽힌다. 리다이렉트를 피해 http로 직접 보내면 인증이 전달되지만 서버가 `X-Seraph-LoginReason: AUTHENTICATED_FAILED`로 자격증명을 거부한다 (구버전 Jira라 Personal Access Token도 없다).

따라서:

- **`JIRA_URL`을 `http://…`로 바꾸지 말 것.** 인증이 실제로 전달되면서 거부되어, 지금 되는 공개 프로젝트까지 401로 막힌다. `https://jira.cubrid.org` 유지가 유일하게 동작하는 조합이다.
- `.envrc`의 `# TODO: paste a Personal Access Token …` 주석은 파일 생성 시의 안내문이고 값과 무관하다. **주석만 보고 자격증명 상태를 단정하지 말 것.**
- 실패는 코드로 판단한다: `401` = 그 계정으로 읽을 수 없음(내부 전용 포함), `404` = 키 오타이거나 URL을 키로 잘못 넘긴 경우.

## Step 2: Load as context and work against it

Read each downloaded `<KEY>.md`, then give the user a short summary: 제목, 유형(버그/개선/작업), 핵심 요구사항, 제약. From then on, treat that file as the source of truth for the ticket while doing the actual work, and reference it (`jira/<KEY>.md`) in commits / PR / report as needed. Do not re-fetch an issue whose `.md` already exists unless the user asks to refresh it.
