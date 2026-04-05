#!/usr/bin/env bash
# list-installed-skills.sh - Enumerate skills already installed in this Cowork session
# Outputs JSON array of {name, description, path, source} objects to stdout.
#
# Sources checked (all mounted into the VM):
#   - /sessions/*/mnt/.skills/manifest.json       (SkillsPlugin registry)
#   - /sessions/*/mnt/.skills/skills/*/SKILL.md   (SkillsPlugin files)
#   - /sessions/*/mnt/.local-plugins/cache/*/*/*/skills/*/SKILL.md  (domain plugins)
#   - /sessions/*/mnt/.remote-plugins/*/skills/*/SKILL.md           (remote plugins)

set -euo pipefail

python3 -c "
import json, os, re, glob

MAX_FILE_SIZE = 512 * 1024  # 512 KB per SKILL.md

def parse_frontmatter(path):
    '''Extract name and description from YAML frontmatter. Returns (name, description).'''
    try:
        if os.path.getsize(path) > MAX_FILE_SIZE:
            return '', ''
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except IOError:
        return '', ''

    name = ''
    description = ''
    fm_match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
    if not fm_match:
        return '', ''

    lines = fm_match.group(1).split('\n')
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith('name:'):
            name = stripped[5:].strip().strip('\"').strip(\"'\")
        elif stripped.startswith('description:'):
            val = stripped[12:].strip().strip('\"').strip(\"'\")
            if val in ('>', '|', '>-', '|-', ''):
                parts = []
                i += 1
                while i < len(lines) and (lines[i].startswith(' ') or lines[i].startswith('\t')):
                    parts.append(lines[i].strip())
                    i += 1
                description = ' '.join(parts)
                continue
            else:
                description = val
        i += 1

    return name, description[:500]

results = []
seen_paths = set()

# Source 1: SkillsPlugin registry manifest (authoritative — includes skillId, enabled state)
manifest_skills = {}  # name -> description
for manifest_path in glob.glob('/sessions/*/mnt/.skills/manifest.json'):
    try:
        with open(manifest_path) as f:
            data = json.load(f)
        for s in data.get('skills', []):
            if s.get('enabled', True):
                manifest_skills[s.get('name', '')] = s.get('description', '')
    except (json.JSONDecodeError, IOError):
        pass

# Source 2: SkillsPlugin skill directories
for skill_md in glob.glob('/sessions/*/mnt/.skills/skills/*/SKILL.md'):
    skill_dir = os.path.dirname(skill_md)
    if skill_dir in seen_paths:
        continue
    seen_paths.add(skill_dir)
    name = os.path.basename(skill_dir)
    # Prefer description from manifest, fall back to frontmatter
    description = manifest_skills.get(name, '')
    if not description:
        _, description = parse_frontmatter(skill_md)
    results.append({
        'name': name,
        'description': description,
        'path': skill_dir,
        'source': 'skills-plugin'
    })

# Source 3: Local domain plugin skills
for skill_md in glob.glob('/sessions/*/mnt/.local-plugins/cache/*/*/*/skills/*/SKILL.md'):
    skill_dir = os.path.dirname(skill_md)
    if skill_dir in seen_paths:
        continue
    seen_paths.add(skill_dir)
    name, description = parse_frontmatter(skill_md)
    if not name:
        name = os.path.basename(skill_dir)
    results.append({
        'name': name,
        'description': description,
        'path': skill_dir,
        'source': 'domain-plugin'
    })

# Source 4: Remote plugin skills
for skill_md in glob.glob('/sessions/*/mnt/.remote-plugins/*/skills/*/SKILL.md'):
    skill_dir = os.path.dirname(skill_md)
    if skill_dir in seen_paths:
        continue
    seen_paths.add(skill_dir)
    name, description = parse_frontmatter(skill_md)
    if not name:
        name = os.path.basename(skill_dir)
    results.append({
        'name': name,
        'description': description,
        'path': skill_dir,
        'source': 'remote-plugin'
    })

results.sort(key=lambda r: (r['source'], r['name']))
print(json.dumps(results))
"
