# claude-skills justfile
# Manage this collection of Claude Code skills via the `npx skills` CLI.

# Install all skills globally to ~/.claude/skills (symlinked)
install:
    npx skills add . -y -g --agent claude-code

# Reinstall all skills globally
reinstall: install

# Pull latest, update globally-installed skills, then reinstall this collection
update:
    git pull --ff-only
    npx skills update -g -y
    just install

# List globally-installed skills
list:
    npx skills list -g --agent claude-code

# Remove one skill globally (e.g. `just remove skill-create`)
remove skill:
    npx skills remove -g --agent claude-code --yes {{ skill }}
