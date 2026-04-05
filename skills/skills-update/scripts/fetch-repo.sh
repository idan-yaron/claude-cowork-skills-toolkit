#!/usr/bin/env bash
# fetch-repo.sh - Clone or download a GitHub repo to a temp directory
# Usage: fetch-repo.sh <github-url> [branch]
# Outputs JSON on stdout: {"path": "...", "branch": "...", "subpath": "...", "sha": "..."}
#   - path: filesystem path to the cloned/extracted directory (narrowed to subpath if any)
#   - branch: the branch actually checked out (or tarball-downloaded)
#   - subpath: subpath within the repo (empty if repo root)
#   - sha: commit SHA from git rev-parse HEAD (empty if tarball fallback was used)
#
# DUPLICATED from skills/skills-load/scripts/fetch-repo.sh — keep in sync.
# Each skill is self-contained with its own scripts (convention in this plugin).

set -euo pipefail

URL="$1"
BRANCH="${2:-}"

# Normalize URL: strip trailing slashes, .git suffix for parsing
CLEAN_URL="${URL%.git}"
CLEAN_URL="${CLEAN_URL%/}"

# Remove protocol prefix for parsing
PARSED="${CLEAN_URL#https://}"
PARSED="${PARSED#http://}"
PARSED="${PARSED#github.com/}"

# Handle SSH format: git@github.com:owner/repo
if [[ "$PARSED" == git@github.com:* ]]; then
  PARSED="${PARSED#git@github.com:}"
fi

# Extract owner/repo (first two path segments)
OWNER=$(echo "$PARSED" | cut -d'/' -f1)
REPO=$(echo "$PARSED" | cut -d'/' -f2)

# Extract branch and subpath from /tree/branch/path URLs
SUBPATH=""
if echo "$PARSED" | grep -q '/tree/'; then
  TREE_PART=$(echo "$PARSED" | sed 's|^[^/]*/[^/]*/tree/||')
  if [ -z "$BRANCH" ]; then
    BRANCH=$(echo "$TREE_PART" | cut -d'/' -f1)
  fi
  REMAINING=$(echo "$TREE_PART" | cut -d'/' -f2-)
  if [ "$REMAINING" != "$BRANCH" ] && [ -n "$REMAINING" ]; then
    SUBPATH="$REMAINING"
  fi
fi

# Create temp directory
TMPDIR=$(mktemp -d)

# Try git clone first
CLONE_URL="https://github.com/${OWNER}/${REPO}.git"
CLONE_ARGS=(clone --depth 1)
if [ -n "$BRANCH" ]; then
  CLONE_ARGS+=(--branch "$BRANCH")
fi

EFFECTIVE_BRANCH=""
SHA=""
if git "${CLONE_ARGS[@]}" "$CLONE_URL" "$TMPDIR/repo" 2>/dev/null; then
  RESULT="$TMPDIR/repo"
  # Record the branch that was actually checked out
  if [ -n "$BRANCH" ]; then
    EFFECTIVE_BRANCH="$BRANCH"
  else
    EFFECTIVE_BRANCH=$(cd "$RESULT" && git branch --show-current 2>/dev/null || echo "")
  fi
  # Capture commit SHA (best-effort)
  SHA=$(cd "$RESULT" && git rev-parse HEAD 2>/dev/null || echo "")
else
  # Fallback: download tarball
  TAR_BRANCH="${BRANCH:-main}"
  TAR_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${TAR_BRANCH}.tar.gz"

  if curl -sL --fail "$TAR_URL" | tar -xz -C "$TMPDIR" 2>/dev/null; then
    # Tarball extracts to repo-branch/ directory
    RESULT=$(find "$TMPDIR" -maxdepth 1 -mindepth 1 -type d | head -1)
    EFFECTIVE_BRANCH="$TAR_BRANCH"
  else
    # Try "master" branch as last resort
    TAR_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/master.tar.gz"
    if curl -sL --fail "$TAR_URL" | tar -xz -C "$TMPDIR" 2>/dev/null; then
      RESULT=$(find "$TMPDIR" -maxdepth 1 -mindepth 1 -type d | head -1)
      EFFECTIVE_BRANCH="master"
    else
      echo "ERROR: Could not clone or download ${OWNER}/${REPO}." >&2
      echo "If this is a private repo, authentication is required." >&2
      echo "Try: set a GITHUB_TOKEN env var, or run 'gh auth login' on your host." >&2
      rm -rf "$TMPDIR"
      exit 1
    fi
  fi
fi

# If there's a subpath, narrow the output path
if [ -n "$SUBPATH" ] && [ -d "$RESULT/$SUBPATH" ]; then
  OUTPUT_PATH="$RESULT/$SUBPATH"
else
  OUTPUT_PATH="$RESULT"
fi

# Output JSON with path + provenance
python3 -c "
import json, sys
print(json.dumps({
    'path': sys.argv[1],
    'branch': sys.argv[2],
    'subpath': sys.argv[3],
    'sha': sys.argv[4]
}))
" "$OUTPUT_PATH" "$EFFECTIVE_BRANCH" "$SUBPATH" "$SHA"
