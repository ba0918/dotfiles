#!/usr/bin/env bash
#
# Sync claude-skills shared documents into ai/shared/vendor/.
#
# Fetches the four claude-skills documents that the LLM wrappers reference
# (design-principles, tdd-contract, testing-anti-patterns, information-placement)
# from the ba0918/claude-skills repository (GitHub raw) and writes them under
# ai/shared/vendor/. The ref (branch/tag) defaults to "main"; override with the
# CLAUDE_SKILLS_VERSION environment variable.
#
# The script is idempotent: re-running it refreshes the vendored files with the
# current upstream content and exits 0. Any failed fetch exits non-zero.
#
# Output is neutral English.
#
# Overrides (testing / mirroring):
#   CLAUDE_SKILLS_RAW_BASE   base URL in place of raw.githubusercontent.com
#   CLAUDE_SKILLS_VENDOR_DIR output dir in place of <repo>/ai/shared/vendor

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW_BASE="${CLAUDE_SKILLS_RAW_BASE:-https://raw.githubusercontent.com/ba0918/claude-skills}"
REF="${CLAUDE_SKILLS_VERSION:-main}"
VENDOR_DIR="${CLAUDE_SKILLS_VENDOR_DIR:-${REPO_ROOT}/ai/shared/vendor}"

FILES=(
	"skills/shared/references/design-principles.md"
	"skills/shared/references/tdd-contract.md"
	"skills/shared/references/testing-anti-patterns.md"
	"rules/information-placement.md"
)

mkdir -p "${VENDOR_DIR}"

for rel in "${FILES[@]}"; do
	url="${RAW_BASE}/${REF}/${rel}"
	dest="${VENDOR_DIR}/$(basename "${rel}")"
	if ! curl -fsSL "${url}" -o "${dest}"; then
		echo "error: failed to fetch ${url}" >&2
		exit 1
	fi
done

echo "synced ${#FILES[@]} claude-skills documents (ref: ${REF}) to ${VENDOR_DIR}"
