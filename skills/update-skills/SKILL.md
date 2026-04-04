---
name: update-skills
description: >
  Refresh plugins previously installed by skills-toolkit by re-fetching
  their GitHub sources and presenting updated .plugin files to Cowork. Use
  when the user says "update my loaded skills", "refresh skills from github",
  "pull latest skills", "sync skills-toolkit plugins", "check for skill
  updates", or runs /update-skills. Identifies target plugins via the
  skills-toolkit keyword marker embedded in plugin.json — does not touch
  domain plugins or unrelated SkillsPlugin entries.
argument-hint: "[skill-name... | --all]"
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
---

# Update Skills from GitHub

Re-fetch the GitHub sources for plugins previously installed by
skills-toolkit, detect what changed, and rebuild each plugin with fresh
content. Cowork's "Accept" flow replaces each installed plugin in-place.

## How it works

Every `.plugin` that `/load-skills` builds embeds its source URL in
`plugin.json.repository` and tags itself with `"skills-toolkit"` in
`keywords`. This command scans all installed plugins for that marker, reads
the repository URL, re-clones, diffs each `SKILL.md` by SHA256, and rebuilds
the plugin with the same name — so Accept replaces the installed version.

Because the source URL lives inside the installed plugin itself, updates work
across session restarts, VM reboots, and conversation compaction. No
`/load-skills` rerun needed.

## VM constraints

- **Bash** runs in an isolated Linux VM — use for discovery, cloning, and ZIP building.
- **Write tool** bridges to the HOST filesystem.
- Host paths like `~/AppData/...` don't exist inside the VM.

## Step 1: Discover installed skills-toolkit plugins

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/discover-installed-plugins.sh"
```

Returns JSON array of `{pluginName, repository, pluginRoot, manifestPath, keywords, skills: [{name, path, currentSha}]}`.

If empty:

> **No skills-toolkit plugins found.**
>
> Run `/load-skills <github-url>` to install skills first, then come back
> here to refresh them.

Then stop.

## Step 2: Filter by arguments

Parse `$ARGUMENTS`:
- Empty or `--all` → keep all discovered plugins and skills
- Skill names (space or comma separated) → filter each plugin's `skills[]` to
  entries where `name` matches. Drop plugins with no matching skills.

If filter matches nothing: "No skills matched `{args}`. Found: `{list of names}`."

## Step 3: Report the plan

> **Found {M} skills-toolkit plugins with {N} skills total.**
> Re-fetching GitHub sources to check for updates…

## Step 4: Re-fetch each unique repository

Collect the unique `repository` URLs across all plugins. For each, clone once
into a temp directory and cache the path by URL:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/fetch-repo.sh" "<repository>"
```

If a repo fails to fetch (404, private, network error), skip that plugin with
a warning like: "Could not fetch `{owner}/{repo}` — skipping `{plugin-name}`."
Continue with the other plugins.

If more than 10 unique repos, warn about GitHub's 60/hour unauthenticated
rate limit and mention `GITHUB_TOKEN`.

## Step 5: Re-discover skills in each fresh clone

For each successfully-fetched repo:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/discover-skills.sh" "<fresh-repo-path>"
```

Build a lookup: `{(repo_url, skill_name) → fresh_skill_record}`.

## Step 6: Diff via SHA256

For each installed skill across all plugins:

- Look up `(repository, skill.name)` in the fresh catalog.
- **Not found** → status `removed_upstream`.
- **Found** → compute SHA256 of the fresh `SKILL.md`, compare to
  `skill.currentSha` from step 1.
  - Equal → `unchanged`.
  - Differ → `updated`. Optionally compute a brief line diff (added/removed
    counts) by reading both files for display.

## Step 7: Present the plan and confirm

Show a table grouped by plugin:

> **Refresh plan:**
>
> | # | Plugin | Skill | Status | Δ lines |
> |---|--------|-------|--------|---------|
> | 1 | product-manager-skills | roadmap-planning | updated | +12 −3 |
> | 2 | product-manager-skills | discovery-process | unchanged | — |
> | 3 | product-manager-skills | competitive-analysis | removed_upstream | — |
> | 4 | retros-toolkit | team-retro | updated | +4 −1 |
>
> Refresh all updated? Reply `yes` / `all`, pick by number (`1, 4`),
> or `none` to cancel.

If every skill across every plugin is `unchanged` and none are
`removed_upstream`:

> **All plugins up to date.** Nothing to refresh.

Then stop.

For `removed_upstream` skills, ask a follow-up per-skill before building:

> `competitive-analysis` no longer exists upstream in
> `deanpeters/Product-Manager-Skills`. Drop from the rebuilt plugin or keep
> the currently-installed version? (`drop` / `keep`)

## Step 8: Rebuild per-plugin .plugin

For each plugin that needs a rebuild (has at least one refreshed or dropped
skill), build a new `.plugin` ZIP. Contents must include ALL of the plugin's
skills (Cowork's Accept REPLACES the entire plugin — omitting unchanged
skills would silently remove them):

- `updated` skills → use fresh `SKILL.md` (+ any fresh supporting files) from
  the clone
- `unchanged` skills → copy from the installed plugin's mount path
- `removed_upstream` skills → include only if user said `keep`

Preserve the original `plugin.json` metadata (name, repository, keywords,
description, version) so the marker and source URL survive.

```bash
python3 << 'PYEOF'
import zipfile, json, sys, os, re

plugin_name = sys.argv[1]          # e.g., "product-manager-skills"
manifest_json = sys.argv[2]        # original plugin.json content as string
sources_json = sys.argv[3]         # JSON: [{"skillName":"...", "sourceDir":"/path/to/dir"}, ...]

out_dir = '/tmp/skill-outputs'
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, plugin_name + '.plugin')

sources = json.loads(sources_json)

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('.claude-plugin/plugin.json', manifest_json)
    for entry in sources:
        skill_name = re.sub(r'[^a-zA-Z0-9_-]', '-', entry['skillName']).strip('-')
        src = entry['sourceDir']
        if not os.path.isdir(src):
            continue
        for root, dirs, files in os.walk(src):
            for f in files:
                fp = os.path.join(root, f)
                arc = 'skills/' + skill_name + '/' + os.path.relpath(fp, src).replace('\\', '/')
                zf.write(fp, arc)

print(out)
PYEOF
```

Pass the original plugin.json string (already includes the repository URL
and keywords) to preserve traceability for future `/update-skills` runs.

## Step 9: Present each .plugin to Cowork

Load and call `mcp__cowork__present_files` with each rebuilt `.plugin` path:

```
Use ToolSearch to load: mcp__cowork__present_files
Then call it with /tmp/skill-outputs/{plugin-name}.plugin
```

Tell the user what to click:

> **Plugin `{plugin-name}` refreshed** — {N} skills updated. Click
> **"Accept"** on the preview above. Cowork will prompt to replace the
> existing version.

If multiple plugins were rebuilt, present them in separate messages so each
preview is visible.

If `mcp__cowork__present_files` isn't available, try
`mcp__cowork__create_artifact`, or fall back to writing the `.plugin` to the
host via the Write tool and telling the user to upload via
Customize > Plugins.

## Step 10: Inject updated content

For each refreshed skill, output the fresh `SKILL.md` body inline so it's
usable immediately, even before the user clicks Accept:

```
### LOADED SKILL: {skill-name} (updated)

**Source:** {owner}/{repo}
**Description:** {description}

{Full fresh SKILL.md body — do NOT truncate}

---
```

Skip `unchanged` skills — they're already in context or in the installed
plugin.

## Step 11: Report

> **Update summary:**
>
> | Plugin | Refreshed | Dropped | Click to install |
> |--------|-----------|---------|------------------|
> | product-manager-skills | roadmap-planning | competitive-analysis | Accept preview above |
> | retros-toolkit | team-retro | — | Accept preview above |
>
> Skills are active in this conversation immediately. Run `/update-skills`
> again anytime to re-check.

## Edge cases

- **No skills-toolkit plugins installed**: Friendly exit with a pointer
  to `/load-skills`.
- **Source repo deleted (404)**: Per-plugin warning, skip, continue with
  others.
- **GitHub rate limit**: In-run caching already dedupes repo fetches. If
  still hitting the limit, suggest setting `GITHUB_TOKEN`.
- **Plugin.json missing `repository` field** (older version, pre-marker):
  Warn: "Plugin `{name}` has no repository URL — cannot refresh. Re-run
  `/load-skills <url>` to re-register it."
- **Skill renamed upstream**: Treated as `removed_upstream` plus a "new"
  skill the user didn't ask for. For now, just surface as `removed_upstream`
  — the user can re-run `/load-skills` to pick up renames.
- **Dependencies auto-added in original load now dropped upstream**:
  Surfaces as `removed_upstream`, user decides.
- **User declines in step 7**: Exit without rebuilding. No Cowork state
  touched.
- **`mcp__cowork__present_files` unavailable**: Inline context injection
  still runs (updated skills usable immediately). Mention manual install
  path via Customize > Plugins.
- **Multiple plugins, some fail to fetch**: Finish the ones that worked,
  report failures in the summary table.
