---
name: skill-create
description: "Turn a workflow you just did into a new skill in the claude-skills collection: pick a name with the collection's prefixes, write a trigger-tested SKILL.md plus any scripts, test it, install it, and propose a commit. Triggers on phrases like '이 작업 스킬로 만들어줘', '스킬 새로 만들어줘', 'make this a skill'."
argument-hint: "<skill-name-or-description>"
---

# Create a new skill in claude-skills

Scaffold a new skill and write a complete, trigger-tested `SKILL.md` (plus `scripts/`, `references/`, `assets/` when the skill needs them) from the surrounding context. This layers Anthropic skill-creator practices onto the collection's own conventions.

## Step 1: Find the collection root

The collection root is where this skill's directory really lives, since `just install` links the skills from the repo:

```bash
(cd -P "${CLAUDE_SKILL_DIR}/.." && pwd)
```

If that directory has no `tools/check_skills.py` (for example, a machine with copied skills), ask the user for the collection path.

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
- **scripts/**: deterministic code the skill runs (parsers, builders, runners) instead of re-deriving logic in prose. Invoke them through the skill-directory variable (Step 6).
- **references/**: long docs, tables, or per-variant guides the skill reads only when relevant (organize by variant, e.g. `references/oracle.md`; add a table of contents to any file over ~300 lines).
- **assets/**: templates, example specs, fonts, or icons the skill copies or embeds.

## Step 6: Write the SKILL.md (and any scripts / references / assets)

Frontmatter: `name` (kebab-case, matching the directory) and `description`, one double-quoted line.

**`description`: invest here; it is the ONLY signal that makes the skill fire.** Every auto-invoked skill's description rides along on every turn inside a shared budget (about 1% of the context window), and when the list overflows the least-used skills lose their descriptions first, so keep it tight:
- Key use first: one imperative line on what it does and what it produces, then the situation that calls for it. Put ALL the "when to use" here, not in the body.
- One boundary line when a neighbor skill could be mistaken for it: `For X, use Y.`
- End with `Triggers on phrases like 'X', 'Y'.`: two or three phrases the user actually types, Korean included, tied to THIS workflow so it does not fire on unrelated tasks.
- Leave implementation detail (tools, flags, file layouts) to the body.
- About 250 to 450 characters (`just check` fails above 450). No `<` or `>` (the listing shows them as `&lt;` `&gt;`) and no em-dash.

**Manual-only skills**: a workflow with external side effects (dispatching an Action, posting) or one the user always types gets `disable-model-invocation: true`, so only `/<name>` runs it. Its description then never reaches Claude: drop the trigger phrases and keep one short line for the `/` menu.

**Script permissions**: when the body runs the skill's own scripts, pre-approve exactly those command shapes in `allowed-tools`, written the way `pr-draft/SKILL.md` writes its rule. Leave out any script with external side effects so it still asks first.

**Body:** a `# Title` heading and numbered, executable steps with exact commands. Reference bundled files through Claude Code's skill-directory variable: a dollar sign followed by `{CLAUDE_SKILL_DIR}` and the path, exactly as `pr-draft/SKILL.md` writes it (this file cannot spell it in one piece, because Claude Code would expand it to skill-create's own path). Reach a sibling skill's file with `/../<sibling>/…` after it. It expands only in SKILL.md and in `allowed-tools`, so inside `references/` write the installed path, `~/.claude/skills/<skill>/…`, instead. No placeholders, no leftover `<!-- … -->` comments. Match the collection's house style.

**Write the instructions in English.** SKILL.md is read by the model on every invocation, and Korean costs roughly twice the tokens for the same content. Keep Korean only where it is carrying meaning that English would lose:

- **output templates** for Korean deliverables (the placeholder text inside the fenced block: it doubles as the spec for the result),
- **Korean style terms** with no clean English equivalent (`개조식`, `서술체`),
- **quoted Korean phrases** that the rule is about (e.g. a banned opener). Then write any `scripts/`, `references/`, `assets/` decided in Step 5.

## Step 7: Test the skill (lightweight eval)

Before installing, sanity-check that it will actually fire and run:

- **Trigger fit**: check the description against the 2-3 SHOULD-fire prompts and the one must-NOT-fire prompt from Step 4. Adjust the description if it under- or over-triggers.
- **Dry run**: walk the steps against one realistic prompt. Every command must be runnable exactly as written; run the read-only steps to confirm the paths and tools exist. Fix any step that is vague or broken.

For a high-stakes skill, measure triggering with `claude plugin eval` (should-fire and must-not-fire prompts, each run with and without the skill; see `claude plugin eval --help`) rather than skill-creator's description optimizer, which tests a slash command instead of the skill: this step is the lightweight local equivalent.

## Step 8: Self-review (required)

- [ ] `description` puts the key use first, draws the boundary with any neighbor skill, and ends with two or three real `Triggers on phrases like '…'` (none on a manual-only skill); at most 450 characters, no `<`, `>`, or em-dash.
- [ ] `SKILL.md` holds the essentials only; long content is split into `references/` (with a TOC), deterministic logic lives in `scripts/`, templates in `assets/`.
- [ ] Every step is executable with an exact command; bundled files go through the skill-directory variable (as in `pr-draft/SKILL.md`), never a hardcoded install path.
- [ ] No placeholders and no leftover `<!-- … -->` comments; correct domain prefix.
- [ ] Passed the Step 7 trigger + dry-run test.

Skills are matched by their description and trigger phrases, so vague writing here means the skill never fires. Fix anything that fails before continuing.

## Step 9: Install, verify, commit

```bash
just install && just list | grep <frontmatter-name>
```

`just list` prints frontmatter `name:` values, so grep the name set in the SKILL.md. Add the skill's row to the README `Skills` table (a manual-only row starts with ``(`/<name>` only, manual)``), then run `just check` and fix every `FAIL`. Once it passes, propose committing (match the style of `git log --oneline -10`):

```bash
git add <skill-name>/ && git commit -m "feat: add <skill-name> skill"
```

Skills are **linked** from the repo, so later edits are live; `just install` is needed only once per new skill.
