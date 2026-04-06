# Contributing

Thanks for your interest in improving the Claude Cowork Skills Toolkit.

## Setup

```bash
git clone https://github.com/idan-yaron/claude-cowork-skills-toolkit.git
cd claude-cowork-skills-toolkit
python3 build.py          # produces dist/skills-toolkit.zip
```

Upload `dist/skills-toolkit.zip` to Cowork via **Customize > Personal Plugin (+) > Create plugin > Upload plugin** to test your changes.

## Project structure

```
.claude-plugin/plugin.json   # plugin manifest
skills/
  skills-load/SKILL.md       # /skills-load command
  skills-save/SKILL.md       # /skills-save command
  skills-share/SKILL.md      # /skills-share command
  skills-update/SKILL.md     # /skills-update command
  detect-github-url/SKILL.md # passive URL auto-detection
build.py                     # packages everything into .zip
```

Each skill is a single `SKILL.md` file with YAML frontmatter (`name`, `description`, `allowed-tools`, etc.) followed by the skill's prompt body. Reference scripts live in sibling directories (e.g., `skills-load/scripts/`).

## Adding a skill

1. Create `skills/<skill-name>/SKILL.md` with the standard frontmatter
2. Use the `/skills-*` namespace prefix if it extends the toolkit's core commands
3. Test in Cowork by building and uploading the plugin
4. Update the README if the skill is user-invocable

## Branches and commits

- Branch names are type-prefixed: `feature/`, `fix/`, `refactor/`, `docs/`
- Commits need a concise subject line + a short body (4-6 lines) explaining _why_
- Keep PRs focused on a single change

## Reporting issues

Use [GitHub Issues](https://github.com/idan-yaron/claude-cowork-skills-toolkit/issues). Bug reports and skill requests are both welcome. Check the issue templates for guidance.
