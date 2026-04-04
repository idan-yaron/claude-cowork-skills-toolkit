#!/usr/bin/env bash
# discover-installed-plugins.sh - Find installed plugins tagged with skills-toolkit keyword
# Outputs JSON array of tracked plugins to stdout.
#
# Usage: discover-installed-plugins.sh
# Returns: [
#   {
#     "pluginName": "product-manager-skills",
#     "repository": "https://github.com/deanpeters/Product-Manager-Skills",
#     "pluginRoot": "/sessions/.../mnt/.local-plugins/cache/.../.../0.1.0",
#     "manifestPath": "/sessions/.../mnt/.local-plugins/cache/.../.claude-plugin/plugin.json",
#     "keywords": ["skills", "skills-toolkit", "product-manager-skills"],
#     "skills": [
#       {"name": "roadmap-planning", "path": "/.../skills/roadmap-planning", "currentSha": "abc123..."}
#     ]
#   }
# ]

set -euo pipefail

python3 -c "
import json, os, re, glob, hashlib, subprocess

MAX_FILE_SIZE = 512 * 1024  # 512 KB per SKILL.md

def sha256_of(path):
    h = hashlib.sha256()
    try:
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b''):
                h.update(chunk)
        return h.hexdigest()
    except IOError:
        return ''

def enumerate_skills(plugin_root):
    '''Return list of {name, path, currentSha} for all SKILL.md files under plugin_root/skills/.'''
    skills_dir = os.path.join(plugin_root, 'skills')
    if not os.path.isdir(skills_dir):
        return []
    results = []
    try:
        for entry in sorted(os.listdir(skills_dir)):
            skill_dir = os.path.join(skills_dir, entry)
            skill_md = os.path.join(skill_dir, 'SKILL.md')
            if not os.path.isfile(skill_md):
                continue
            if os.path.getsize(skill_md) > MAX_FILE_SIZE:
                continue
            results.append({
                'name': entry,
                'path': skill_dir,
                'currentSha': sha256_of(skill_md),
            })
    except OSError:
        pass
    return results

# Candidate glob patterns where Accept-installed .plugin files may land.
# The architecture doc says uploaded plugins go to cowork_plugins/cache/ (host)
# which is mounted at .local-plugins/cache/ (VM). Exact subdirectory structure
# for user-installed (vs marketplace) plugins is not 100% documented, so we
# check several depth variants and fall back to a broader find.
patterns = [
    '/sessions/*/mnt/.local-plugins/cache/*/*/*/.claude-plugin/plugin.json',  # marketplace/plugin/version
    '/sessions/*/mnt/.local-plugins/cache/*/*/.claude-plugin/plugin.json',    # alt depth
    '/sessions/*/mnt/.local-plugins/cache/*/.claude-plugin/plugin.json',      # alt depth
    '/sessions/*/mnt/.local-plugins/*/.claude-plugin/plugin.json',            # no cache/
    '/sessions/*/mnt/.remote-plugins/*/.claude-plugin/plugin.json',
    '/sessions/*/mnt/.skills/.claude-plugin/plugin.json',
]

candidates = set()
for pat in patterns:
    for p in glob.glob(pat):
        candidates.add(p)

# Broad fallback: find any plugin.json under /sessions/*/mnt (bounded depth).
# This catches Accept-installed plugins wherever Cowork actually puts them.
try:
    sessions_roots = glob.glob('/sessions/*/mnt')
    for root in sessions_roots:
        res = subprocess.run(
            ['find', root, '-maxdepth', '8', '-name', 'plugin.json', '-type', 'f'],
            capture_output=True, text=True, timeout=10,
        )
        for line in res.stdout.strip().split('\n'):
            line = line.strip()
            if line and line.endswith('.claude-plugin/plugin.json'):
                candidates.add(line)
except (subprocess.SubprocessError, FileNotFoundError, OSError):
    pass

results = []
seen_roots = set()

for manifest_path in sorted(candidates):
    # plugin.json is at {plugin-root}/.claude-plugin/plugin.json
    plugin_claude = os.path.dirname(manifest_path)
    plugin_root = os.path.dirname(plugin_claude)
    if plugin_root in seen_roots:
        continue
    seen_roots.add(plugin_root)

    try:
        if os.path.getsize(manifest_path) > MAX_FILE_SIZE:
            continue
        with open(manifest_path, 'r', encoding='utf-8', errors='replace') as f:
            data = json.load(f)
    except (IOError, json.JSONDecodeError):
        continue

    keywords = data.get('keywords', []) or []
    if not isinstance(keywords, list):
        continue
    if 'skills-toolkit' not in keywords:
        continue

    plugin_name = data.get('name', os.path.basename(plugin_root))
    repository = data.get('repository', '')
    if isinstance(repository, dict):
        repository = repository.get('url', '')

    skills = enumerate_skills(plugin_root)

    results.append({
        'pluginName': plugin_name,
        'repository': repository,
        'pluginRoot': plugin_root,
        'manifestPath': manifest_path,
        'keywords': keywords,
        'skills': skills,
    })

# Stable sort
results.sort(key=lambda r: r['pluginName'])
print(json.dumps(results))
"
