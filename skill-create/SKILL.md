---
name: skill-create
description: "Create a new skill in this claude-skills collection. Use when the user wants to turn a workflow they just did into a reusable skill, capture a repeated process as a skill, or add a new skill to their toolbox. Triggers on phrases like 'make this a skill', 'create a skill for this', 'save this as a skill', 'add a new skill'."
argument-hint: "<skill-name-or-description>"
---

# Create a new skill in claude-skills

Scaffold a new skill directory and write a complete `SKILL.md` from the surrounding context.

## Step 1 — Find the collection root

Walk up from the current directory looking for a `justfile` that contains `npx skills add`. That directory is the collection root. If none is found, ask the user for the collection path.

## Step 2 — Derive the skill name

From `$ARGUMENTS` (or, if empty, from the workflow gathered in Step 4):

- Drop filler words: `a`, `the`, `this`, `that`, `skill`, `make`, `save`, `as`, `create`.
- Convert to an imperative verb + object, lowercase and hyphenated — e.g. "a skill that checks migration parity" → `check-parity`.
- Apply the domain prefix from the collection's convention:
  - `hhh-` — Hibernate ORM / dialect work
  - `cmt-` — CUBRID Migration Toolkit (runs, schema/data parity)
  - `jdbc-` — CUBRID JDBC driver
  - `cubrid-` — general CUBRID (manual, containers)
  - no prefix — truly general-purpose

Propose the candidate name and wait for confirmation before continuing.

## Step 3 — Check for conflicts

Confirm `<collection-root>/<skill-name>/` does not already exist. If it does, ask whether to update the existing skill or pick a new name.

## Step 4 — Gather context

From the current conversation, collect:

- **Workflow** — the exact sequence of commands, tools, and actions the skill automates.
- **Tools** — CLI tools, APIs, or other skills it depends on (note install hints).
- **Edge cases** — failure modes or conditions the user mentioned.

If the name was deferred in Step 2, derive it now from the workflow's verb + object, confirm with the user, then run the Step 3 conflict check.

## Step 5 — Write the SKILL.md

Create `<collection-root>/<skill-name>/SKILL.md`:

- Frontmatter: `name` (kebab-case, matching the directory) and `description`.
- `description`: an imperative phrase, then "Use when …", ending with `Triggers on phrases like 'X', 'Y', 'Z'.`
- Body: a `# Title` heading and numbered, executable steps with exact CLI commands. No placeholders, no `<!-- ... -->` comments.

## Step 6 — Self-review (required)

Before installing, re-read the SKILL.md and confirm each item:

- [ ] `description` is imperative, names *when* to use it, and ends with concrete `Triggers on phrases like '...'`.
- [ ] Trigger phrases are specific to this workflow — not generic verbs that would fire on unrelated tasks.
- [ ] Every step is executable; tool steps give the exact command, not just "run the tests".
- [ ] No placeholders and no leftover `<!-- ... -->` comments.
- [ ] The correct domain prefix is applied.

Skills are loaded and matched by their description and trigger phrases, so vague writing here means the skill never fires. Fix anything that fails before continuing.

## Step 7 — Install, verify, commit

```bash
just install
just list | grep <frontmatter-name>
```

`just list` prints frontmatter `name:` values, so grep the name set in the SKILL.md. If it appears, propose committing:

```bash
git add <skill-name>/ && git commit -m "feat: add <skill-name> skill"
```

Match the commit message style to `git log --oneline -10`.
