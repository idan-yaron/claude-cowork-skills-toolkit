#!/usr/bin/env bash
# discover-skills.sh - Find SKILL.md files in a repo and extract metadata
# Usage: discover-skills.sh <repo-path>
# Outputs JSON array of discovered skills to stdout

set -euo pipefail

REPO_PATH="$1"

# Collect all SKILL.md paths based on repo type
SKILL_FILES=()

# Type 1: Full plugin with .claude-plugin/
if [ -f "$REPO_PATH/.claude-plugin/plugin.json" ]; then
  if [ -d "$REPO_PATH/skills" ]; then
    while IFS= read -r f; do
      SKILL_FILES+=("$f")
    done < <(find "$REPO_PATH/skills" -name "SKILL.md" -type f 2>/dev/null)
  fi
  if [ -d "$REPO_PATH/commands" ]; then
    while IFS= read -r f; do
      SKILL_FILES+=("$f")
    done < <(find "$REPO_PATH/commands" -name "*.md" -type f 2>/dev/null)
  fi

# Type 2: Skills-only repo
elif [ -d "$REPO_PATH/skills" ]; then
  while IFS= read -r f; do
    SKILL_FILES+=("$f")
  done < <(find "$REPO_PATH/skills" -name "SKILL.md" -type f 2>/dev/null)

# Type 3: Loose SKILL.md files
else
  while IFS= read -r f; do
    SKILL_FILES+=("$f")
  done < <(find "$REPO_PATH" -name "SKILL.md" -type f -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null)
fi

# Use Python to parse frontmatter and produce JSON (handles all special chars safely)
python3 -c "
import json, sys, os, re

MAX_FILE_SIZE = 512 * 1024  # 512 KB per SKILL.md

repo_path = sys.argv[1]
skill_files = sys.argv[2:]
results = []

for skill_md in skill_files:
    skill_dir = os.path.dirname(skill_md)
    rel_path = os.path.relpath(skill_dir, repo_path)

    # Skip oversized files
    if os.path.getsize(skill_md) > MAX_FILE_SIZE:
        continue

    # Read the file
    with open(skill_md, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    # Extract YAML frontmatter between --- markers
    name = ''
    description = ''
    fm_match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
    if fm_match:
        frontmatter = fm_match.group(1)
        lines = frontmatter.split('\n')
        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            if stripped.startswith('name:'):
                name = stripped[5:].strip().strip('\"').strip(\"'\")
            elif stripped.startswith('description:'):
                val = stripped[12:].strip().strip('\"').strip(\"'\")
                if val in ('>', '|', '>-', '|-', ''):
                    # Multi-line YAML: collect indented continuation lines
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

    # Fallbacks
    if not name:
        name = os.path.basename(skill_dir)
    if not description:
        # First non-empty line after frontmatter
        body = content
        if fm_match:
            body = content[fm_match.end():]
        for line in body.split('\n'):
            line = line.strip()
            if line and not line.startswith('#'):
                description = line[:200]
                break

    # Sanitize name: only allow alphanumeric, hyphens, underscores
    safe_name = re.sub(r'[^a-zA-Z0-9_-]', '-', name).strip('-')
    if safe_name:
        name = safe_name

    results.append({
        'name': name,
        'description': description[:500],
        'path': rel_path.replace(os.sep, '/'),
        'fullPath': skill_dir.replace(os.sep, '/')
    })

print(json.dumps(results))
" "$REPO_PATH" "${SKILL_FILES[@]}"
