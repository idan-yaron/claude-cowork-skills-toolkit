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
`### LOADED SKILL: {name}` blocks. This skill gathers skills from two sources:
(A) those conversation markers — which preserve any iterations you made — and
(B) already-installed `skills-toolkit` plugins on disk, as a fallback when
markers were lost to conversation compaction. It then synthesizes each skill's
current state (Source A only, incorporating iterations) and packages into a
new `.plugin` file presented for install via Cowork's "Save plugin" button.

## Step 1: Discover loaded skills (two sources)

Skills can come from two sources. Gather from BOTH, then decide which to use.

### Source A: Conversation markers (primary — captures iterations)

Find all `### LOADED SKILL: {name}` markers in this conversation. For each
marker, extract:
- The skill name (from the header)
- The description (from the `**Description:**` line)
- The body content (everything until the next `---` separator or next
  `### LOADED SKILL:` block)

This source preserves any iterations you made during the conversation. It's
the happy path when conversation context is intact.

### Source B: Installed plugins on disk (fallback — survives compaction)

Run the discovery script to find skills-toolkit plugins already installed in
this Cowork session:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/discover-installed-plugins.sh"
```

Returns a JSON array of `{pluginName, pluginRoot, manifestPath, skills: [{name, path, currentSha}]}`.
The script already filters for the `skills-toolkit` keyword and excludes plugins
tagged `iterated` (those are already saved).

This source saves ORIGINALS, not iterations — the installed plugin is the
pre-iteration snapshot from when you clicked Save plugin. Use it when markers
are gone because Cowork compacted the conversation.

### Pick the source

- **If Source A has results** → use markers. Go to Step 2 (synthesize iterations).
- **Else if Source B has results** → warn the user and confirm before
  proceeding:

  > **Conversation markers not found — likely compacted.** Falling back to
  > `{N}` skills-toolkit plugins installed on disk. This saves the **originals**
  > as an `iterated-*` plugin; any iterations from this conversation are NOT
  > captured (the edit history was in the compacted span).
  >
  > Found:
  > - `{pluginName-1}` ({M1} skills)
  > - `{pluginName-2}` ({M2} skills)
  >
  > Save originals as `iterated-*` plugins? Reply `yes`, pick plugin names,
  > or `cancel`.

  If the user confirms, for each chosen plugin read every `{skill.path}/SKILL.md`
  from disk — that content is the skill body. Skip the Step 2 synthesis pass
  (originals don't need it). Go to Step 3.

- **Else (neither source has results)** →

  > **No skills to save.** No conversation markers AND no skills-toolkit
  > plugins installed on disk.
  >
  > Run `/skills-load <github-url>` first to load skills from GitHub, then
  > come back here.

  Then stop.

## Step 2: Synthesize current state (Source A only)

**Skip this step entirely if Step 1 chose Source B** — those are originals
read from disk. They don't need synthesis.

For each Source A skill (from conversation markers), examine the conversation
holistically to determine its CURRENT state:

- If the skill was discussed/modified/iterated on after the initial injection
  (e.g., user said "add a step for X", "reword the intro", "make it more
  concise"), produce the updated version that reflects those changes
- If the skill was not modified, use the original injected content verbatim

Track which skills were iterated and summarize what changed (high level —
not a full diff, just enough for the user to confirm).

## Step 3: Show the summary

Display a compact table with a Source column so the user can tell which
skills came from conversation markers vs. the installed-plugin fallback:

> **Found {N} skills to save:**
>
> | # | Skill | Source | Status | Notes |
> |---|-------|--------|--------|-------|
> | 1 | roadmap-planning | conversation | iterated | Added stakeholder-review step |
> | 2 | discovery-process | conversation | unchanged | — |
> | 3 | competitive-analysis | conversation | iterated | Reworded intro, added 2 criteria |
> | 4 | positioning-workshop | conversation | unchanged | — |
>
> Save all {N} as a new plugin? Reply with a plugin name, `all`, or pick
> by number (`1, 3`).

When all skills come from Source B, the Source column shows `installed plugin`
and the Status column shows `original` for every row (no iterations to display).

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

Build the `.plugin` ZIP via Python inside the VM. Pass skill content as JSON
(the content came from conversation markers in Source A, or from disk reads
in Source B — the build step doesn't care which):

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

If all skills came from Source B (installed-plugin fallback), add this note:

> **Heads-up:** This plugin was built from the originals on disk because
> conversation markers were lost to compaction. To capture iterations next
> time, run `/skills-save` before the conversation gets long enough to
> compact — or redo your edits in a fresh conversation after reloading with
> `/skills-load`.

## Edge cases

- **No `### LOADED SKILL:` markers in conversation**: Fall back to Source B
  (installed plugins on disk). If Source B is also empty, exit with a pointer
  to `/skills-load`. No plugin is built.
- **Markers AND installed plugins both exist for the same skills**: Source A
  wins (iterations are more valuable than originals). Mention in the summary
  that disk copies exist but aren't being used.
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
