---
name: skill-create
description: "Create a new skill in this claude-skills collection, from scaffolding through a lightweight trigger/dry-run test before commit. Use when the user wants to turn a workflow they just did into a reusable skill, capture a repeated process, or add a new skill to their toolbox. Applies this collection's conventions (domain prefixes, description-with-triggers, just install) plus skill-authoring practices from Anthropic's skill-creator (progressive disclosure, trigger-tested descriptions, bundled scripts/references/assets). Triggers on phrases like 'make this a skill', 'create a skill for this', 'save this as a skill', 'add a new skill', 'turn this workflow into a skill'."
argument-hint: "<skill-name-or-description>"
---

# Create a new skill in claude-skills

Scaffold a new skill and write a complete, trigger-tested `SKILL.md` (plus `scripts/`, `references/`, `assets/` when the skill needs them) from the surrounding context. This layers Anthropic skill-creator practices onto the collection's own conventions.

## Step 1: Find the collection root

Walk up from the current directory looking for a `justfile` that contains `npx skills add`. That directory is the collection root. If none is found, ask the user for the collection path.

## Step 2: Derive the skill name

From `$ARGUMENTS` (or, if empty, from the workflow gathered in Step 4):

- Drop filler words: `a`, `the`, `this`, `that`, `skill`, `make`, `save`, `as`, `create`.
- Convert to an imperative verb + object, lowercase and hyphenated: e.g. "a skill that checks migration parity" → `check-parity`.
- Apply the domain prefix from the collection's convention:
  - `hhh-`: Hibernate ORM / dialect work
  - `cmt-`: CUBRID Migration Toolkit (runs, schema/data parity)
  - `jdbc-`: CUBRID JDBC driver
  - `cubrid-`: general CUBRID (manual, containers)
  - no prefix: truly general-purpose

Propose the candidate name and wait for confirmation before continuing.

## Step 3: Check for conflicts

Confirm `<collection-root>/<skill-name>/` does not already exist. If it does, ask whether to update the existing skill or pick a new name.

## Step 4: Gather context

From the current conversation, collect:

- **Workflow**: the exact sequence of commands, tools, and actions the skill automates.
- **Inputs & output**: the arguments the skill takes and what it produces (file, report, summary).
- **Tools**: CLI tools, APIs, or other skills it depends on (note install hints).
- **Edge cases**: failure modes or conditions the user mentioned.
- **Trigger prompts**: 2-3 realistic user phrasings that SHOULD invoke this skill, and one nearby phrasing it must NOT hijack. Used to test the description in Step 7.

If the name was deferred in Step 2, derive it now from the workflow's verb + object, confirm, then run the Step 3 conflict check.

## Step 5: Choose the structure (progressive disclosure)

Keep in `SKILL.md` only what the model needs every time it runs; push the rest into bundled files it loads on demand. Create only the directories the skill actually needs (a pure-guidance skill is `SKILL.md` alone):

- **SKILL.md**: metadata + the workflow steps. Keep it under ~500 lines. If a section grows past ~300 lines, move it to `references/` and link it.
- **scripts/**: deterministic code the skill runs (parsers, builders, runners) instead of re-deriving logic in prose. Invoke via `<skill-base-dir>/scripts/…`.
- **references/**: long docs, tables, or per-variant guides the skill reads only when relevant (organize by variant, e.g. `references/oracle.md`; add a table of contents to any file over ~300 lines).
- **assets/**: templates, example specs, fonts, or icons the skill copies or embeds.

## Step 6: Write the SKILL.md (and any scripts / references / assets)

Frontmatter: `name` (kebab-case, matching the directory) and `description`.

**`description`: invest here; it is the ONLY signal that makes the skill fire:**
- One imperative line on what it does and what it produces, then the concrete "use when …" situations, ending with `Triggers on phrases like 'X', 'Y', 'Z'.`
- Put ALL the "when to use" in the description, not in the body.
- Be specific and a little assertive so it fires when it should, but keep the triggers tied to THIS workflow so it does not fire on unrelated tasks.

**Body:** a `# Title` heading and numbered, executable steps with exact commands. Reference bundled files with `<skill-base-dir>/…`. No placeholders, no leftover `<!-- … -->` comments. Match the collection's language and house style. Then write any `scripts/`, `references/`, `assets/` decided in Step 5.

## Step 7: Test the skill (lightweight eval)

Before installing, sanity-check that it will actually fire and run:

- **Trigger fit**: check the description against the 2-3 SHOULD-fire prompts and the one must-NOT-fire prompt from Step 4. Adjust the description if it under- or over-triggers.
- **Dry run**: walk the steps against one realistic prompt. Every command must be runnable exactly as written; run the read-only steps to confirm the paths and tools exist. Fix any step that is vague or broken.

For a high-stakes or to-be-distributed skill, use Anthropic's official `skill-creator` for a full eval/benchmark loop and `.skill` packaging: this step is the lightweight local equivalent.

## Step 8: Self-review (required)

- [ ] `description` is imperative, names *when* to use it, and ends with concrete `Triggers on phrases like '…'`; triggers are specific, not generic verbs.
- [ ] `SKILL.md` holds the essentials only; long content is split into `references/` (with a TOC), deterministic logic lives in `scripts/`, templates in `assets/`.
- [ ] Every step is executable with an exact command; bundled files are referenced via `<skill-base-dir>/…`.
- [ ] No placeholders and no leftover `<!-- … -->` comments; correct domain prefix.
- [ ] Passed the Step 7 trigger + dry-run test.

Skills are matched by their description and trigger phrases, so vague writing here means the skill never fires. Fix anything that fails before continuing.

## Step 9: Install, verify, commit

```bash
just install
just list | grep <frontmatter-name>
```

`just list` prints frontmatter `name:` values, so grep the name set in the SKILL.md. If it appears, propose committing (match the style of `git log --oneline -10`):

```bash
git add <skill-name>/ && git commit -m "feat: add <skill-name> skill"
```

Skills are **copy-installed**, so re-run `just install` after any later edit to the skill.
