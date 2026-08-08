#!/usr/bin/env bash
#
# Pure transformer: deny-patterns.yaml → tool-specific deny JSON.
# This script holds ZERO deny patterns of its own. All patterns live in
# ai/shared/deny-patterns.yaml.
#
# Usage:
#   generate-deny.sh claude   # Output Claude Code deny JSON fragment
#   generate-deny.sh opencode # Output OpenCode deny JSON fragment
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DENY_FILE="$REPO_ROOT/ai/shared/deny-patterns.yaml"

if [ ! -f "$DENY_FILE" ]; then
  echo "error: deny-patterns.yaml not found at $DENY_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not found" >&2
  exit 1
fi

# Extract patterns from a specific YAML category
# Usage: extract_category "category_name"
extract_category() {
  local cat="$1"
  sed -n "/^${cat}:/,/^[a-z_]*:/{ /^${cat}:/d; /^[a-z_]*:/d; p; }" "$DENY_FILE" \
    | grep -E '^\s+-\s+"' \
    | sed 's/^[[:space:]]*-[[:space:]]*"\(.*\)"/\1/'
}

# Extract all file/directory patterns (categories that produce Read(**/) patterns)
file_categories() {
  extract_category credentials
  extract_category keys
  extract_category ssh
  extract_category environment
  extract_category package_manager
  extract_category database
  extract_category network
  extract_category history
}

case "${1:-}" in
  claude)
    {
      # File patterns → Read(**/pattern)
      file_categories | while IFS= read -r p; do echo "Read(**/$p)"; done

      # Directory patterns → Read(~/dir) + Read(//$HOME/dir)
      extract_category directories | while IFS= read -r p; do
        echo "Read(~/$p)"
        echo 'Read(//$HOME/'"$p"')'
      done

      # Personal directory denials (already prefixed with //$HOME/)
      extract_category personal_directories | while IFS= read -r p; do
        echo "Read($p)"
      done

      # Short-form Read denials
      extract_category read_shortform | while IFS= read -r p; do
        echo "Read($p)"
      done

      # Write denials
      extract_category write_deny | while IFS= read -r p; do
        echo "Write($p)"
      done

      # Bash destructive command denials
      extract_category bash_destructive | while IFS= read -r p; do
        echo "Bash($p)"
      done

    } | jq -R -s '
      split("\n") | map(select(length > 0)) | unique |
      { "permissions": { "deny": . } }
    '
    ;;
  opencode)
    # OpenCode: file + directory patterns only (no Bash/Write deny concept)
    {
      file_categories
      extract_category directories
    } | jq -R -s '
      split("\n") | map(select(length > 0)) |
      map({ ("**/" + .): "deny" }) | add
    '
    ;;
  *)
    echo "usage: generate-deny.sh {claude|opencode}" >&2
    exit 1
    ;;
esac
