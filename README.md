# Claude Cowork Skills Toolkit

Four commands for moving skills between GitHub, your Cowork session, and your teammates.

Cowork is Anthropic's agentic AI system for knowledge work, with a built-in skill/plugin system. New Claude skills ship on GitHub all the time. This toolkit cuts the time between finding one and using it down to a single `/` command, even mid-session. Four commands: install from a GitHub URL, refresh against upstream, share installed skills with teammates as a `.zip` plugin, and auto-detect URLs pasted in chat.

## The toolkit

- **`/load-skills <github-url>`** — Browse any GitHub repo's skills, pick what you want, install as a one-click plugin.
- **Auto-detection** — Paste a GitHub URL in chat and the toolkit offers to browse its skills.
- **`/share-skill`** — Package already-installed skills as a `.zip` to share with teammates.
- **`/update-skills`** — Re-fetch each installed plugin's GitHub source, diff by SHA256, rebuild only what changed.

## Example: loading skills from a GitHub repo

```
You:    /load-skills https://github.com/deanpeters/Product-Manager-Skills

Claude: Found 47 skills in deanpeters/Product-Manager-Skills:

        | #  | Skill                | Description                              |
        |----|----------------------|------------------------------------------|
        | 1  | discovery-process    | Run structured product discovery...      |
        | 2  | roadmap-planning     | Build quarterly roadmaps with deps...    |
        | 3  | competitive-analysis | Framework for competitive assessment...  |
        | ...                                                                     |

        Pick by number, name, keyword search, or "all".

You:    2, 3

Claude: `roadmap-planning` references `discovery-process` — including it.

        Plugin `product-manager-skills` ready — 3 skills (including 1 dependency).
        Click "Accept" on the plugin preview above.
```

## Install

Upload `dist/skills-toolkit.plugin` to Cowork via **Customize > Plugins > Upload plugin**.

Or build from source:

```bash
python build.py
# Output: dist/skills-toolkit.plugin
```

## Commands

**`/load-skills <github-url>`** — Clones the repo, discovers all SKILL.md files, shows a numbered catalog. You pick; dependencies are resolved automatically (if skill A references skill B, both get included). Everything is packaged as a `.plugin` and presented with a one-click **"Accept"** button. Skills appear in your `/` menu immediately, mid-session. No restart.

**Auto-detection** — Paste a GitHub URL in chat and the toolkit recognizes it, offering to browse available skills.

**`/share-skill`** — Export skills already in your session as a downloadable `.zip`. Save it wherever you want (Desktop, Documents, Slack) and share. For skills you already have — use `/load-skills` for new skills from GitHub.

**`/update-skills`** — Refresh plugins previously installed by this toolkit from their GitHub sources. Discovers them via the `skills-toolkit` keyword marker embedded in each plugin's `plugin.json`, diffs each skill by SHA256, and rebuilds only the plugins with actual upstream changes. Accept replaces the installed version in place. Works across session restarts — no need to re-run `/load-skills`.

## How it works

Cowork runs a Linux VM. Bash commands execute inside the VM (isolated from the host). The `Write` tool bridges to the host filesystem. `mcp__cowork__present_files` bridges the VM to the desktop UI.

The load flow:

1. **Bash** clones the GitHub repo inside the VM
2. **discover-skills.sh** finds all SKILL.md files, extracts name/description from YAML frontmatter, outputs JSON
3. User picks skills from the catalog
4. Dependency scanner reads each selected skill's body, finds references to other skills, auto-includes them
5. **Python** (via Bash) builds a `.plugin` ZIP with `.claude-plugin/plugin.json` + `skills/*/SKILL.md`
6. **`mcp__cowork__present_files`** presents the ZIP to the Cowork desktop UI
7. Cowork renders a rich preview with an **"Accept"** button
8. Click → skills install through Anthropic's backend → appear in `/` menu immediately
9. Skills are also injected into the conversation context as a parallel fallback

Every plugin this toolkit builds embeds `"skills-toolkit"` in its keywords array. That marker is how `/update-skills` later finds them for refreshing.

## Tradeoffs

**Unified `.plugin` vs individual `.skill` files.** A single `.plugin` gives one "Accept" button that installs everything as a named package. Downside: uninstalling removes the whole plugin, not individual skills. We chose this because the common case is loading a set of related skills, and one click beats five.

**Auto-resolving dependencies.** Skills often reference each other — a roadmap skill may depend on a discovery-process skill. We auto-include dependencies and tell the user why. This sometimes pulls in skills you didn't ask for, but a broken skill is worse than an extra one.

## License

MIT
