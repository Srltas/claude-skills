# claude-skills

My personal collection of [Claude Code](https://www.claude.com/product/claude-code) skills, focused on CUBRID migration, JDBC, and Hibernate work.

## Skills

| Skill | Description |
|-------|-------------|
| `skill-create` | Scaffold a new skill in this collection from a workflow you just did |
| `commit` | Commit staged changes with a clean Conventional Commit subject |
| `cubrid-manual` | Look up CUBRID engine behavior in the version-pinned online manual |
| `cmt-manual` | Look up CUBRID Migration Toolkit (CMT) behavior in the online manual |
| `report` | Generate a CUBRID-house-style Korean analysis report as a Word (.docx) — docx-js + matplotlib charts, OOXML-validated |
| `hhh-dialect-verify` | Run the hibernate-core suite against CUBRID, diff pass/fail vs a baseline, classify failures by family |
| `hhh-dialect-verify-report` | One-shot: run the suite (one/all CUBRID versions) → diff vs a baseline → always write the .docx report |
| `jdbc-ctp-verify-report` | One-shot: build the CUBRID JDBC driver → run the CTP suite → diff vs a baseline → classify → always write the .docx report |
| `jira-fetch` | Download a Jira Server issue (e.g. CUBRID CBRD) to a local Markdown file and load it as working context (wraps `Srltas/jira-to-md-downloader`; Atlassian Cloud not supported as-is) |
| `jira-draft` | Draft a CUBRID JIRA issue (bug/task) as copy-paste text: concise English title, Korean 개조식 body under English section headers. The reverse of jira-fetch |
| `tutor` | (`/tutor` only, manual) Patient expert teacher for the current work or a topic: defines every term first, then teaches step by step, grounded in real code/manuals, with comprehension checks. Korean, chat-only |
| `blog` | Draft a Korean tech blog post for velog (minimal text, visuals-first): scaffolds `work-docs/blog/<date>-<slug>/`, renders diagrams to images via Kroki (velog can't render Mermaid) + matplotlib charts |
| `java-format` | Apply google-java-format (AOSP, in place) to changed / staged / all / specific Java files; asks the version, resolves `~/Driver` or auto-downloads the jar |
| `pr-draft` | Draft a PR title (`[XXX-0000]` + easy English) and Korean body (Purpose / Implementation / Remarks) from the current branch's commits and diff; draft only |
| `worklog` | Record issue work as a Markdown note in your public `work-docs` repo (`<KEY>/<KEY>-<slug>.md`), a shareable PR-linkable trail that complements the internal master DOCX |
| `note` | Record a non-issue exploration note (PoC, review, code analysis) in the public `work-docs` repo (`<category>/<YYYY-MM-DD>-<slug>.md`) |

## Naming convention

Skills are grouped by domain prefix:

| Prefix | Domain |
|--------|--------|
| `hhh-` | Hibernate ORM upstream / dialect work |
| `cmt-` | CUBRID Migration Toolkit (runs, schema/data parity) |
| `jdbc-` | CUBRID JDBC driver |
| `cubrid-` | General CUBRID (manual, containers) |
| _(none)_ | Truly general-purpose skills |

## Install

Using the [`skills`](https://github.com/vercel-labs/skills) CLI (installs globally to `~/.claude/skills/`):

```bash
npx skills add Srltas/claude-skills -y -g
```

Or clone and use the justfile:

```bash
git clone https://github.com/Srltas/claude-skills.git
cd claude-skills
just install      # install all skills globally
just list         # list installed skills
just remove NAME  # remove one skill
```

## License

MIT — add a `LICENSE` file before publishing.
