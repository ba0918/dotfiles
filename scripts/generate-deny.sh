#!/usr/bin/env bash
#
# Pure transformer: deny-patterns.yaml → tool-specific deny JSON.
# This script holds ZERO deny patterns of its own. All patterns live in
# ai/shared/deny-patterns.yaml.
#
# Usage:
#   generate-deny.sh claude         # Output Claude Code deny JSON fragment
#   generate-deny.sh opencode       # Output OpenCode deny JSON fragment
#   generate-deny.sh opencode-apply # Patch ~/.opencode/opencode.json in place
#
# Overrides (testing):
#   DENY_PATTERNS_FILE   YAML source in place of ai/shared/deny-patterns.yaml
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DENY_FILE="${DENY_PATTERNS_FILE:-$REPO_ROOT/ai/shared/deny-patterns.yaml}"

if [ ! -f "$DENY_FILE" ]; then
  echo "error: deny-patterns.yaml not found at $DENY_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not found" >&2
  exit 1
fi

# Every category the transformer knows how to consume. The coverage check below
# compares the sum of these against every pattern line in the YAML, so a category
# added to deny-patterns.yaml without being registered here fails loudly instead
# of being silently dropped from the generated deny set.
ALL_CATEGORIES="
credentials
keys
ssh
environment
package_manager
database
network
directories
history
personal_directories
write_deny
read_shortform
bash_destructive
"

# Extract patterns from a specific YAML category
# Usage: extract_category "category_name"
#
# NOTE: the regexes below must stay POSIX. `\s` is a GNU awk extension and does
# NOT match under mawk, which is the default awk on Debian/Ubuntu — using it here
# silently yielded an empty deny set on a stock machine.
extract_category() {
  local cat="$1"
  awk -v cat="$cat" '
    $0 ~ "^"cat":" { found=1; next }
    found && /^[a-zA-Z_]+:/ { exit }
    found && /^[[:space:]]+-[[:space:]]+"/ { gsub(/^[[:space:]]*-[[:space:]]*"/, ""); gsub(/"$/, ""); print }
  ' "$DENY_FILE"
}

# Fail unless every pattern line in the YAML was claimed by exactly one known
# category. Guards against a broken parser (extracting nothing) and against
# unregistered categories (extracting only part of the file). Without this, both
# failure modes produce a valid-looking but empty/partial deny set.
verify_coverage() {
  local total extracted cat
  total=$(grep -c '^[[:space:]]*-[[:space:]]*"' "$DENY_FILE" || true)
  extracted=0
  for cat in $ALL_CATEGORIES; do
    extracted=$((extracted + $(extract_category "$cat" | grep -c . || true)))
  done

  if [ "$total" -eq 0 ]; then
    echo "error: no patterns found in $DENY_FILE" >&2
    exit 1
  fi

  if [ "$extracted" -ne "$total" ]; then
    echo "error: deny pattern extraction is incomplete: parsed ${extracted} of ${total} patterns in $DENY_FILE" >&2
    echo "error: either a category is missing from ALL_CATEGORIES in $0, or the YAML parser failed" >&2
    exit 1
  fi
}

verify_coverage

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
  opencode-apply)
    # Patch ~/.opencode/opencode.json in place with deny patterns from yaml.
    # Runs after mise template rendering to inject the canonical deny set.
    OC_TARGET="$HOME/.opencode/opencode.json"
    if [ ! -f "$OC_TARGET" ]; then
      echo "error: $OC_TARGET not found (run mise bootstrap dotfiles apply first)" >&2
      exit 1
    fi

    DENY_OBJ=$("$0" opencode)

    # Merge deny patterns into permission.read (preserve existing allows)
    # and permission.external_directory (preserve existing non-deny entries)
    jq --argjson deny "$DENY_OBJ" '
      .permission.read = (
        (.permission.read | to_entries | map(select(.value != "deny"))) +
        ($deny | to_entries)
        | from_entries
      ) |
      .permission.external_directory = (
        (.permission.external_directory | to_entries | map(select(.value != "deny"))) +
        ($deny | to_entries)
        | from_entries
      )
    ' "$OC_TARGET" > "${OC_TARGET}.tmp" && mv "${OC_TARGET}.tmp" "$OC_TARGET"
    echo "opencode deny patterns updated in $OC_TARGET"
    ;;
  *)
    echo "usage: generate-deny.sh {claude|opencode|opencode-apply}" >&2
    exit 1
    ;;
esac
