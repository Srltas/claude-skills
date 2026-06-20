# claude-skills

My personal collection of [Claude Code](https://www.claude.com/product/claude-code) skills, focused on CUBRID migration, JDBC, and Hibernate work.

## Skills

| Skill | Description |
|-------|-------------|
| `skill-create` | Scaffold a new skill in this collection from a workflow you just did |
| `commit` | Commit staged changes with a clean Conventional Commit subject |
| `cubrid-manual` | Look up CUBRID engine behavior in the version-pinned online manual |
| `cmt-manual` | Look up CUBRID Migration Toolkit (CMT) behavior in the online manual |

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
