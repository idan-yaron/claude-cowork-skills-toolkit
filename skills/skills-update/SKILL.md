---
name: skills-update
description: >
  Refresh plugins previously installed by skills-toolkit by re-fetching
  their GitHub sources and presenting updated .plugin files to Cowork. Use
  when the user says "update my loaded skills", "refresh skills from github",
  "pull latest skills", "sync skills-toolkit plugins", "check for skill
  updates", or runs /skills-update. Identifies target plugins via the
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
content. Cowork's "Save plugin" flow replaces each installed plugin in-place.

## How it works

Every `.plugin` that `/skills-load` builds embeds its source URL in
`plugin.json.repository` and tags itself with `"skills-toolkit"` in
`keywords`. This command scans all installed plugins for that marker, reads
the repository URL, re-clones, diffs each `SKILL.md` by SHA256, and rebuilds
the plugin with the same name — so Save plugin replaces the installed version.

Because the source URL lives inside the installed plugin itself, updates work
across session restarts, VM reboots, and conversation compaction. No
`/skills-load` rerun needed.

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
> Run `/skills-load <github-url>` to install skills first, then come back
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

## Step 4: Re-fetch each unique source

Collect unique `(repository, source.branch)` pairs across all plugins —
different branches of the same repo need separate fetches. For each unique
pair, clone once and cache by that pair:

```bash
FETCH_JSON=$(bash "${CLAUDE_SKILL_DIR}/scripts/fetch-repo.sh" "<repository>" "<source.branch>")
REPO_PATH=$(echo "$FETCH_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['path'])")
FRESH_SHA=$(echo "$FETCH_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")
```

If `source.branch` is empty (plugin installed before the provenance feature),
call `fetch-repo.sh` with an empty second arg so it defaults to the repo's
default branch — backward compatibility with older installs.

If a repo fails to fetch (404, private, network error), skip that plugin with
a warning like: "Could not fetch `{owner}/{repo}@{branch}` — skipping
`{plugin-name}`." Continue with the other plugins.

If more than 10 unique source pairs, warn about GitHub's 60/hour
unauthenticated rate limit and mention `GITHUB_TOKEN`.

## Step 4.5: SHA fast-path check

For each plugin, compare `source.sha` from Step 1 (install-time SHA) against
`FRESH_SHA` from Step 4 (current upstream HEAD):

- **Both non-empty AND equal** → mark all skills in the plugin as
  `unchanged`. Skip Step 5–6 for this plugin; jump to Step 7 for
  presentation.
- **Both non-empty AND different** → upstream has commits; proceed to Step 5
  for per-file diff.
- **`source.sha` empty** (older plugin without provenance) → no short-circuit
  available; proceed to Step 5.
- **`FRESH_SHA` empty** (tarball fallback, no `.git/`) → no short-circuit;
  proceed to Step 5.

This saves a full file-by-file diff when nothing has actually shipped
upstream — a common case on repeat refresh runs.

## Step 5: Re-discover skills in each fresh clone

For each source pair that did NOT pass the Step 4.5 fast-path, run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/discover-skills.sh" "<fresh-repo-path>"
```

Build a lookup keyed by `(repo_url, branch, skill_name)` — including branch
in the key so that two plugins loaded from the same repo but different
branches stay separate.

## Step 6: Diff via SHA256

For each installed skill whose plugin did NOT fast-path in Step 4.5:

- Look up `(repository, source.branch, skill.name)` in the fresh catalog.
- **Not found** → status `removed_upstream`.
- **Found** → compute SHA256 of the fresh `SKILL.md`, compare to
  `skill.currentSha` from step 1.
  - Equal → `unchanged`.
  - Differ → `updated`. Optionally compute a brief line diff (added/removed
    counts) by reading both files for display.

Skills from fast-pathed plugins (Step 4.5) retain their `unchanged` status
set in that step.

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
skills (Cowork's Save plugin REPLACES the entire plugin — omitting unchanged
skills would silently remove them):

- `updated` skills → use fresh `SKILL.md` (+ any fresh supporting files) from
  the clone
- `unchanged` skills → copy from the installed plugin's mount path
- `removed_upstream` skills → include only if user said `keep`

Preserve the original `plugin.json` metadata (name, repository, keywords,
description, version) so the marker and source URL survive.

```bash
python3 << 'PYEOF'
import zipfile, json, os, re, tempfile

# ── Substitute these values from the /skills-update context ──
plugin_name = "<PLUGIN_NAME>"     # e.g., "product-manager-skills"
manifest_json = '<MANIFEST_JSON>' # original plugin.json content as string
sources_json = '<SOURCES_JSON>'   # JSON: [{"skillName":"...", "sourceDir":"/path/to/dir"}, ...]

out_dir = tempfile.mkdtemp(dir='/outputs', prefix='skill-outputs-')
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
                if f == 'SKILL.md':
                    with open(fp, 'r', encoding='utf-8') as fh:
                        content = fh.read()
                    if len(content.encode('utf-8')) > 12800:
                        lines = content.split('\n')
                        fm_end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), -1)
                        if fm_end > 0:
                            ds = next((i for i in range(1, fm_end) if lines[i].startswith('description')), -1)
                            if ds >= 0:
                                de = next((i for i in range(ds+1, fm_end) if lines[i] and not lines[i][0].isspace()), fm_end)
                                desc = '\n'.join(lines[ds:de])
                                trim = len(content.encode('utf-8')) - 12800 + 100
                                if len(desc) > trim + 80:
                                    short = desc[:len(desc)-trim]
                                    cut = short.rfind(' ')
                                    if cut > 50: short = short[:cut]
                                    lines = lines[:ds] + [short] + lines[de:]
                                    content = '\n'.join(lines)
                                    print(f'  [!] Truncated {skill_name}/SKILL.md description to fit 12.8KB limit', flush=True)
                    zf.writestr(arc, content)
                else:
                    zf.write(fp, arc)

print(out)
PYEOF
```

Substitute actual values into the `<PLACEHOLDER>` slots above. `manifest_json`
is the original plugin.json string (preserves repository URL and keywords for
future `/skills-update` runs). `sources_json` is a JSON-encoded array.

## Step 9: Present each .plugin to Cowork

Load and call `mcp__cowork__present_files` with each rebuilt `.plugin` path:

```
Use ToolSearch to load: mcp__cowork__present_files
Then call it with the output path printed by the Python script above.
```

Tell the user what to click:

> **Plugin `{plugin-name}` refreshed** — {N} skills updated. Click
> **"Save plugin"** on the preview above. Cowork will prompt to replace the
> existing version.

If multiple plugins were rebuilt, present them in separate messages so each
preview is visible.

If `mcp__cowork__present_files` isn't available, try
`mcp__cowork__create_artifact`, or fall back to writing the `.plugin` to the
host via the Write tool and telling the user to upload via
Customize > Personal Plugin.

## Step 10: Inject updated content

For each refreshed skill, output the fresh `SKILL.md` body inline so it's
usable immediately, even before the user clicks Save plugin:

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
> | product-manager-skills | roadmap-planning | competitive-analysis | Save plugin preview above |
> | retros-toolkit | team-retro | — | Save plugin preview above |
>
> Skills are active in this conversation immediately. Run `/skills-update`
> again anytime to re-check.

## Edge cases

- **No skills-toolkit plugins installed**: Friendly exit with a pointer
  to `/skills-load`.
- **Source repo deleted (404)**: Per-plugin warning, skip, continue with
  others.
- **GitHub rate limit**: In-run caching already dedupes repo fetches. If
  still hitting the limit, suggest setting `GITHUB_TOKEN`.
- **Plugin.json missing `repository` field** (older version, pre-marker):
  Warn: "Plugin `{name}` has no repository URL — cannot refresh. Re-run
  `/skills-load <url>` to re-register it."
- **Skill renamed upstream**: Treated as `removed_upstream` plus a "new"
  skill the user didn't ask for. For now, just surface as `removed_upstream`
  — the user can re-run `/skills-load` to pick up renames.
- **Dependencies auto-added in original load now dropped upstream**:
  Surfaces as `removed_upstream`, user decides.
- **User declines in step 7**: Exit without rebuilding. No Cowork state
  touched.
- **`mcp__cowork__present_files` unavailable**: Inline context injection
  still runs (updated skills usable immediately). Mention manual install
  path via Customize > Personal Plugin.
- **Multiple plugins, some fail to fetch**: Finish the ones that worked,
  report failures in the summary table.
