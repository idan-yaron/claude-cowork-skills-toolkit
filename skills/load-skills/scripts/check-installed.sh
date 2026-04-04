#!/usr/bin/env bash
# check-installed.sh - List skill names already installed in this Cowork session
# Checks VM mount points for skills present in the SkillsPlugin registry and
# domain plugins. Outputs a JSON array of installed skill names to stdout.
#
# Usage: check-installed.sh
# Returns: ["skill-name-1", "skill-name-2", ...]

set -euo pipefail

python3 -c "
import json, os, glob

installed = set()

# Source 1: SkillsPlugin registry manifest (the authoritative skill list)
# Mounted at /sessions/{session-name}/mnt/.skills/manifest.json
for manifest in glob.glob('/sessions/*/mnt/.skills/manifest.json'):
    try:
        with open(manifest) as f:
            data = json.load(f)
        for s in data.get('skills', []):
            if s.get('enabled', True):
                name = s.get('name', '')
                if name:
                    installed.add(name)
    except (json.JSONDecodeError, IOError):
        pass

# Source 2: SkillsPlugin skill directories (backup if manifest is stale)
for skill_md in glob.glob('/sessions/*/mnt/.skills/skills/*/SKILL.md'):
    installed.add(os.path.basename(os.path.dirname(skill_md)))

# Source 3: Local domain plugin skills (engineering, data, design, etc.)
for skill_md in glob.glob('/sessions/*/mnt/.local-plugins/cache/*/*/*/skills/*/SKILL.md'):
    installed.add(os.path.basename(os.path.dirname(skill_md)))

# Source 4: Remote plugin skills
for skill_md in glob.glob('/sessions/*/mnt/.remote-plugins/*/skills/*/SKILL.md'):
    installed.add(os.path.basename(os.path.dirname(skill_md)))

installed.discard('')
print(json.dumps(sorted(installed)))
"
