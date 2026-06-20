# claude-skills

A git-managed collection of Claude Code skills, focused on CUBRID migration, JDBC, and Hibernate work. Skills are installed globally to `~/.claude/skills/` via `npx skills`.

## Directory structure

Each top-level directory containing a `SKILL.md` is one skill. Skills are grouped by domain prefix:

- `hhh-*` — Hibernate ORM upstream / dialect work
- `cmt-*` — CUBRID Migration Toolkit (runs, schema/data parity)
- `jdbc-*` — CUBRID JDBC driver
- `cubrid-*` — General CUBRID (manual, containers)
- _(no prefix)_ — truly general-purpose skills

## Adding / updating a skill

Prefer the `skill-create` skill, which scaffolds and self-reviews a new `SKILL.md`. Manually:

1. Create `<prefix>-<name>/SKILL.md` with frontmatter (`name`, `description`) and numbered steps.
2. `just install` to install globally.
3. `just list` to verify it appears.
4. Commit the new directory.

## Reference material (read-only)

`vimkim/my-cubrid-skills` (cloned locally at `../my-cubrid-skills`) is a separate collection by another engineer, focused on CUBRID *engine* (C/C++) development. Use it as **read-only inspiration only** — never modify, fork, install from, or push to it. Every skill here is written fresh.
