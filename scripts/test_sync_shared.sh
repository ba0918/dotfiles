#!/usr/bin/env bash
#
# Test harness for scripts/sync-shared.sh
#
# Runs the sync script against a local fixture tree served via file:// URLs
# (CLAUDE_SKILLS_RAW_BASE override) and writes to a temp vendor dir
# (CLAUDE_SKILLS_VENDOR_DIR override), so the test is hermetic and offline.
#
# Usage: bash scripts/test_sync_shared.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/sync-shared.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0

check() {
	local desc="$1"
	local cond="$2"
	if eval "${cond}"; then
		pass=$((pass + 1))
		printf 'PASS: %s\n' "${desc}"
	else
		fail=$((fail + 1))
		printf 'FAIL: %s\n' "${desc}" >&2
	fi
}

# --- fixture tree -----------------------------------------------------------
# Mirrors the raw.githubusercontent.com path layout under two refs.
FX="${TMP}/fx"
for ref in main v1.76.0; do
	mkdir -p "${FX}/${ref}/skills/shared/references" "${FX}/${ref}/rules"
done

echo "MAIN-DESIGN" > "${FX}/main/skills/shared/references/design-principles.md"
echo "MAIN-TDD" > "${FX}/main/skills/shared/references/tdd-contract.md"
echo "MAIN-ATP" > "${FX}/main/skills/shared/references/testing-anti-patterns.md"
echo "MAIN-IP" > "${FX}/main/rules/information-placement.md"

echo "V176-DESIGN" > "${FX}/v1.76.0/skills/shared/references/design-principles.md"
echo "V176-TDD" > "${FX}/v1.76.0/skills/shared/references/tdd-contract.md"
echo "V176-ATP" > "${FX}/v1.76.0/skills/shared/references/testing-anti-patterns.md"
echo "V176-IP" > "${FX}/v1.76.0/rules/information-placement.md"

OUT="${TMP}/out"

run_sync() {
	CLAUDE_SKILLS_RAW_BASE="file://${FX}" \
	CLAUDE_SKILLS_VENDOR_DIR="${OUT}" \
		"${SCRIPT}"
}

# --- RED: script must exist and run ----------------------------------------
if [ ! -x "${SCRIPT}" ]; then
	printf 'FAIL: %s does not exist or is not executable\n' "${SCRIPT}" >&2
	exit 1
fi

# --- 1. creates 4 files (default ref = main) --------------------------------
if run_sync >/dev/null 2>&1; then
	check "creates 4 files under vendor dir" \
		'[ -f "${OUT}/design-principles.md" ] && [ -f "${OUT}/tdd-contract.md" ] && [ -f "${OUT}/testing-anti-patterns.md" ] && [ -f "${OUT}/information-placement.md" ]'
	check "default ref fetches main content" \
		'[ "$(cat "${OUT}/design-principles.md")" = "MAIN-DESIGN" ]'
else
	fail=$((fail + 1))
	printf 'FAIL: sync failed on first run\n' >&2
fi

# --- 2. idempotent re-run (no diff, no error) --------------------------------
sha_before="$(cat "${OUT}"/*.md | sha256sum)"
if run_sync >/dev/null 2>&1; then
	sha_after="$(cat "${OUT}"/*.md | sha256sum)"
	check "re-run is idempotent (same content, exit 0)" \
		'[ "${sha_before}" = "${sha_after}" ]'
else
	fail=$((fail + 1))
	printf 'FAIL: re-run failed\n' >&2
fi

# --- 3. version override fetches that tag -----------------------------------
OUT2="${TMP}/out2"
if CLAUDE_SKILLS_RAW_BASE="file://${FX}" CLAUDE_SKILLS_VERSION=v1.76.0 \
	CLAUDE_SKILLS_VENDOR_DIR="${OUT2}" "${SCRIPT}" >/dev/null 2>&1; then
	check "CLAUDE_SKILLS_VERSION=v1.76.0 fetches that tag content" \
		'[ "$(cat "${OUT2}/design-principles.md")" = "V176-DESIGN" ]'
else
	fail=$((fail + 1))
	printf 'FAIL: version override run failed\n' >&2
fi

# --- 4. fetch failure is a non-zero exit -------------------------------------
OUT3="${TMP}/out3"
if CLAUDE_SKILLS_RAW_BASE="file://${FX}" CLAUDE_SKILLS_VERSION=nonexistent-ref \
	CLAUDE_SKILLS_VENDOR_DIR="${OUT3}" "${SCRIPT}" >/dev/null 2>&1; then
	fail=$((fail + 1))
	printf 'FAIL: missing ref should fail with non-zero exit\n' >&2
else
	pass=$((pass + 1))
	printf 'PASS: missing ref fails with non-zero exit\n'
fi

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
