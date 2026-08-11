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

# Every category the transformer knows, paired with how its patterns are emitted
# to each tool. This single table drives BOTH the coverage check below and the
# per-tool output, so a category cannot be registered for extraction but forgotten
# in an emitter branch — the two can no longer drift apart.
#
# Emitters:
#   file         → claude `Read(**/p)`, opencode `**/p`          (global)
#   directory    → claude `Read(~/$p)` + `Read(//$HOME/$p)`, opencode `~/p` (home-scoped)
#   read         → claude `Read(p)` (Claude only, already-prefixed / short-form)
#   write        → claude `Write(p)` (Claude only)
#   bash         → claude `Bash(p)` (Claude only)
#
# A category added to deny-patterns.yaml MUST be added here (with an emitter).
# The coverage check below compares every pattern line in the YAML against the
# sum of these categories, so an unregistered category fails loudly instead of
# being silently dropped from the generated deny set.
CATEGORIES="
credentials:file
keys:file
ssh:file
environment:file
package_manager:file
database:file
network:file
history:file
directories:directory
personal_directories:read
read_shortform:read
write_deny:write
bash_destructive:bash
"

# Emit every category's patterns as claude deny forms.
emit_claude() {
  local entry cat emitter
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    cat="${entry%%:*}"
    emitter="${entry##*:}"
    case "$emitter" in
      file)
        extract_category "$cat" | while IFS= read -r p; do echo "Read(**/$p)"; done
        ;;
      directory)
        extract_category "$cat" | while IFS= read -r p; do
          echo "Read(~/$p)"
          echo 'Read(//$HOME/'"$p"')'
        done
        ;;
      read)
        extract_category "$cat" | while IFS= read -r p; do echo "Read($p)"; done
        ;;
      write)
        extract_category "$cat" | while IFS= read -r p; do echo "Write($p)"; done
        ;;
      bash)
        extract_category "$cat" | while IFS= read -r p; do echo "Bash($p)"; done
        ;;
      *)
        echo "error: unknown emitter '$emitter' for category '$cat' in $0" >&2
        exit 1
        ;;
    esac
  done <<EOF
$CATEGORIES
EOF
}

# Emit every category's patterns as opencode deny patterns.
emit_opencode() {
  local entry cat emitter
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    cat="${entry%%:*}"
    emitter="${entry##*:}"
    case "$emitter" in
      file)
        extract_category "$cat"
        ;;
      directory)
        extract_category "$cat" | awk '{ print "~/" $0 }'
        ;;
      read|write|bash)
        # Claude-only emitters are deliberately not emitted for opencode
        ;;
      *)
        echo "error: unknown emitter '$emitter' for category '$cat' in $0" >&2
        exit 1
        ;;
    esac
  done <<EOF
$CATEGORIES
EOF
}

# Extract patterns from a specific YAML category
# Usage: extract_category "category_name"
#
# NOTE: the regexes below must stay POSIX. `\s` is a GNU awk extension and does
# NOT match under mawk, which is the default awk on Debian/Ubuntu — using it here
# silently yielded an empty deny set on a stock machine.
#
# The coverage check counts the same `- "..."` lines that extract_category
# reads, so a single-quoted pattern (`- 'x'`) would pass both counts and still
# be silently dropped from the generated deny set. Patterns in deny-patterns.yaml
# MUST use double quotes (stated in the yaml header).
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
  local total extracted cat entry
  total=$(grep -c '^[[:space:]]*-[[:space:]]*"' "$DENY_FILE" || true)
  extracted=0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    cat="${entry%%:*}"
    extracted=$((extracted + $(extract_category "$cat" | grep -c . || true)))
  done <<EOF
$CATEGORIES
EOF

  if [ "$total" -eq 0 ]; then
    echo "error: no patterns found in $DENY_FILE" >&2
    exit 1
  fi

  if [ "$extracted" -ne "$total" ]; then
    echo "error: deny pattern extraction is incomplete: parsed ${extracted} of ${total} patterns in $DENY_FILE" >&2
    echo "error: either a category is missing from CATEGORIES in $0, or the YAML parser failed" >&2
    exit 1
  fi
}

verify_coverage

case "${1:-}" in
  claude)
    {
      emit_claude
    } | jq -R -s '
      split("\n") | map(select(length > 0)) | unique |
      { "permissions": { "deny": . } }
    '
    ;;
  opencode)
    # OpenCode: file + directory patterns only (no Bash/Write deny concept).
    # File patterns are global (**/prefix); directory patterns are $HOME-scoped
    # (deny-patterns.yaml declares .dir/** as $HOME-relative). An unscoped
    # `**/.config/**` would also match the repo's own fish/.config, git/.config,
    # etc., blocking the agent from reading the files it maintains. opencode
    # expands a leading ~ in patterns (permission docs), so prefix with ~/.
    {
      emit_opencode
    } | jq -R -s '
      split("\n") | map(select(length > 0)) |
      map(if startswith("~/") then { (.): "deny" } else { ("**/" + .): "deny" } end) | add
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
