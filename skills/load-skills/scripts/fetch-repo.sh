#!/usr/bin/env bash
# fetch-repo.sh - Clone or download a GitHub repo to a temp directory
# Usage: fetch-repo.sh <github-url> [branch]
# Outputs the path to the cloned/extracted directory on stdout

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

if git "${CLONE_ARGS[@]}" "$CLONE_URL" "$TMPDIR/repo" 2>/dev/null; then
  RESULT="$TMPDIR/repo"
else
  # Fallback: download tarball
  TAR_BRANCH="${BRANCH:-main}"
  TAR_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${TAR_BRANCH}.tar.gz"

  if curl -sL --fail "$TAR_URL" | tar -xz -C "$TMPDIR" 2>/dev/null; then
    # Tarball extracts to repo-branch/ directory
    RESULT=$(find "$TMPDIR" -maxdepth 1 -mindepth 1 -type d | head -1)
  else
    # Try "master" branch as last resort
    TAR_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/master.tar.gz"
    if curl -sL --fail "$TAR_URL" | tar -xz -C "$TMPDIR" 2>/dev/null; then
      RESULT=$(find "$TMPDIR" -maxdepth 1 -mindepth 1 -type d | head -1)
    else
      echo "ERROR: Could not clone or download ${OWNER}/${REPO}." >&2
      echo "If this is a private repo, authentication is required." >&2
      echo "Try: set a GITHUB_TOKEN env var, or run 'gh auth login' on your host." >&2
      rm -rf "$TMPDIR"
      exit 1
    fi
  fi
fi

# If there's a subpath, verify it exists
if [ -n "$SUBPATH" ] && [ -d "$RESULT/$SUBPATH" ]; then
  echo "$RESULT/$SUBPATH"
else
  echo "$RESULT"
fi
