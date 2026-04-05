---
name: skills-save
description: >
  Save the current in-conversation version of loaded skills as a new plugin.
  Use when the user says "save these skills", "save my iterated skills", "save
  loaded", "package what I've been working on", "save this as a plugin", or
  runs /skills-save. Captures the CURRENT state from this conversation
  (including any iterations the user and assistant made), not the original
  GitHub version. For fetching from GitHub, use /skills-load instead.
argument-hint: "[plugin-name]"
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
---

# Save Loaded Skills as a New Plugin

Package skills that have been loaded and iterated on in THIS conversation as
a fresh `.plugin` file. The saved plugin contains the CURRENT in-context
version of each skill — incorporating any edits, additions, or refinements
made during the conversation.

**This is for saving iterations.** To fetch skills from GitHub, use
`/skills-load`. To refresh installed plugins from their GitHub sources, use
`/skills-update`. To package already-installed skills for sharing, use
`/skills-share`.

## When to use this

- You ran `/skills-load <github-url>` earlier this conversation
- You then iterated on one or more of those skills (modified steps, reworded,
  added examples, etc.)
- You want to save those ITERATED versions as a new plugin — separate from
  the original GitHub versions

## How it works

Skills loaded via `/skills-load` are injected into the conversation as
`### LOADED SKILL: {name}` blocks. This skill scans the conversation for
those markers, synthesizes each skill's current state (incorporating
iterations), and packages them into a new `.plugin` file presented for
install via Cowork's "Save plugin" button.

## Step 1: Scan conversation for loaded skills

Find all `### LOADED SKILL: {name}` markers in this conversation. For each
marker, extract:
- The skill name (from the header)
- The description (from the `**Description:**` line)
- The body content (everything until the next `---` separator or next
  `### LOADED SKILL:` block)

If no markers are found:

> **No loaded skills found in this conversation.**
>
> Run `/skills-load <github-url>` first to load skills from GitHub, then
> come back here to save iterated versions.

Then stop.

## Step 2: Synthesize current state

For each loaded skill, examine the conversation holistically to determine
its CURRENT state:

- If the skill was discussed/modified/iterated on after the initial injection
  (e.g., user said "add a step for X", "reword the intro", "make it more
  concise"), produce the updated version that reflects those changes
- If the skill was not modified, use the original injected content verbatim

Track which skills were iterated and summarize what changed (high level —
not a full diff, just enough for the user to confirm).

## Step 3: Show the summary

Display a compact table:

> **Found {N} loaded skills in this conversation:**
>
> | # | Skill | Status | Notes |
> |---|-------|--------|-------|
> | 1 | roadmap-planning | iterated | Added stakeholder-review step |
> | 2 | discovery-process | unchanged | — |
> | 3 | competitive-analysis | iterated | Reworded intro, added 2 criteria |
> | 4 | positioning-workshop | unchanged | — |
>
> Save all {N} as a new plugin? Reply with a plugin name, `all`, or pick
> by number (`1, 3`).

## Step 4: Parse user response and plugin name

- Empty / `all` / `yes` → include all loaded skills
- Comma-separated numbers → include only selected
- Plugin name string → include all, use this as plugin name

**Plugin name default:** if the original `/skills-load` referenced a repo
named `X` (check the conversation for the source repo), suggest
`iterated-X` (e.g., `iterated-product-manager-skills`). Otherwise prompt:
"Plugin name? (default: `iterated-skills`)".

Sanitize the plugin name: kebab-case, `[a-z0-9-]` only. Reject empty names
and re-ask.

## Step 5: Build the .plugin file

Build the `.plugin` ZIP via Python inside the VM. Since skill content lives
in conversation (not on disk), pass it as JSON:

```bash
python3 << 'PYEOF'
import zipfile, json, sys, os

plugin_name = sys.argv[1]          # e.g., "iterated-product-manager-skills"
skills_json = sys.argv[2]          # JSON: [{"name": "...", "body": "..."}, ...]

out_dir = '/tmp/skill-outputs'
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, plugin_name + '.plugin')

skills = json.loads(skills_json)

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
    # Plugin manifest — 'iterated' marker tells /skills-update to skip
    manifest = json.dumps({
        "name": plugin_name,
        "description": "Skills iterated from Cowork session",
        "version": "1.0.0",
        "author": {"name": "skills-toolkit"},
        "keywords": ["skills", "skills-toolkit", "iterated", plugin_name]
    }, indent=2)
    zf.writestr(".claude-plugin/plugin.json", manifest)

    # Write each skill's SKILL.md from conversation content
    for skill in skills:
        skill_name = skill['name']
        body = skill['body']
        zf.writestr(f"skills/{skill_name}/SKILL.md", body)

print(out)
PYEOF
```

Pass the plugin name + JSON array of `{name, body}` objects containing the
synthesized current state of each skill.

**Manifest keywords include `"iterated"`** — this tells `/skills-update`
these plugins have no upstream to refresh against, so it skips them.

**No `repository` field** — iterated plugins have no GitHub source.

## Step 6: Present the .plugin file to Cowork

Use `ToolSearch` to load `mcp__cowork__present_files`, then call it with
the output path from Step 5:

```
Use ToolSearch to load: mcp__cowork__present_files
Then call it with /tmp/skill-outputs/{plugin-name}.plugin
```

Cowork renders a rich preview with a **"Save plugin"** button. Clicking it
installs the iterated plugin — distinct from the original GitHub-sourced
plugin (they have different names if you used the default `iterated-*`
prefix).

If `present_files` is unavailable, fall back to `mcp__cowork__create_artifact`
or write the `.plugin` to the host via the Write tool for manual upload
via Customize > Plugins.

## Step 7: Re-inject into conversation

Output the saved skills back into conversation so they remain accessible
by name:

```
### LOADED SKILL: {skill-name}

**Description:** {description}

{Full synthesized body — do NOT truncate}

---
```

This keeps them usable immediately, even before the user clicks Save plugin.

## Step 8: Report

> **Plugin `{plugin-name}` ready** — {N} skills saved:
>
> | Skill | Status |
> |-------|--------|
> | roadmap-planning | iterated |
> | discovery-process | unchanged (kept original) |
> | competitive-analysis | iterated |
>
> **Click "Save plugin"** on the preview above to install the iterated
> versions. They'll appear in your `/` menu immediately.
>
> The original `/skills-load` plugin (if still installed) is untouched —
> this saves AS A SEPARATE PLUGIN with name `{plugin-name}`.

## Edge cases

- **No `### LOADED SKILL:` markers in conversation**: Exit with a pointer
  to `/skills-load`. No plugin is built.
- **Multiple `/skills-load` runs from different repos**: Show a single
  table listing ALL found skills across sources. Let the user pick which
  to save. Offer "iterated-mixed" as a default name if sources differ.
- **Name collision with existing plugin**: If `{plugin-name}` matches an
  installed plugin, warn the user — Save plugin will replace it. Suggest
  a unique name or confirm the replace.
- **Iteration detection unclear**: Default to the most recent version
  discussed. If unsure, use the original injected content and flag as
  "unchanged (could not detect iteration)" in the table.
- **`present_files` unavailable**: Still re-inject into context (Step 7).
  Tell the user the `.plugin` file is at `/tmp/skill-outputs/{name}.plugin`
  in the VM, or write it to the host via the Write tool for manual upload.
- **Single loaded skill**: Still package as a `.plugin` for consistency.
  The Save plugin flow works the same way.
