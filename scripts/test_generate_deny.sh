#!/usr/bin/env bash
#
# Test harness for scripts/generate-deny.sh
#
# Runs the generator against the real deny-patterns.yaml and against fixture
# YAML files (DENY_PATTERNS_FILE override), so the test is hermetic and offline.
#
# The regression this exists for: the extractor used the GNU-only `\s` escape,
# which does not match under mawk (the default awk on Debian/Ubuntu). Generation
# still exited 0 and produced well-formed JSON — with an empty deny list. Any
# assertion here must therefore check pattern COUNTS, not just exit status.
#
# Usage: bash scripts/test_generate_deny.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/generate-deny.sh"
REAL_YAML="${ROOT}/ai/shared/deny-patterns.yaml"

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

check_fails() {
	local desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		fail=$((fail + 1))
		printf 'FAIL: %s\n' "${desc}" >&2
	else
		pass=$((pass + 1))
		printf 'PASS: %s\n' "${desc}"
	fi
}

if [ ! -x "${SCRIPT}" ]; then
	printf 'FAIL: %s does not exist or is not executable\n' "${SCRIPT}" >&2
	exit 1
fi

# --- 1. real yaml: every pattern reaches the generated output ----------------
# The count guard inside the script already enforces this, but assert it from
# the outside too so a regression cannot hide behind a disabled guard.
yaml_total="$(grep -c '^[[:space:]]*-[[:space:]]*"' "${REAL_YAML}")"
claude_count="$("${SCRIPT}" claude | jq '.permissions.deny | length')"
opencode_count="$("${SCRIPT}" opencode | jq 'length')"

check "real yaml has patterns to convert" '[ "${yaml_total}" -gt 0 ]'
check "claude deny set is not empty" '[ "${claude_count}" -gt 0 ]'
check "opencode deny set is not empty" '[ "${opencode_count}" -gt 0 ]'
# Directory patterns emit both a ~/ and a //$HOME/ form, so claude always ends up
# with more entries than there are source patterns.
check "claude deny covers every yaml pattern" '[ "${claude_count}" -ge "${yaml_total}" ]'

# --- 2. known-secret patterns actually survive the conversion ----------------
claude_json="$("${SCRIPT}" claude)"
for want in 'Read(**/.env)' 'Read(**/id_rsa)' 'Read(**/*.pem)' 'Write(.env*)' 'Bash(sudo:*)'; do
	check "claude deny contains ${want}" \
		'[ "$(echo "${claude_json}" | jq --arg w "${want}" ".permissions.deny | index(\$w) != null")" = "true" ]'
done

# --- 3. indentation variants parse (POSIX regex, not GNU \s) ----------------
# Two spaces, four spaces, and a leading tab must all be recognized. Under the
# old GNU-only escape every one of these silently produced nothing.
FX_INDENT="${TMP}/indent.yaml"
printf 'credentials:\n  - "two-space.json"\n    - "four-space.json"\n\t- "tab.json"\n' > "${FX_INDENT}"
indent_out="$(DENY_PATTERNS_FILE="${FX_INDENT}" "${SCRIPT}" claude | jq -r '.permissions.deny[]' | sort | tr '\n' ' ')"
check "space- and tab-indented patterns are all extracted" \
	'[ "${indent_out}" = "Read(**/four-space.json) Read(**/tab.json) Read(**/two-space.json) " ]'

# --- 4. a category missing from ALL_CATEGORIES is a hard failure ------------
FX_UNKNOWN="${TMP}/unknown.yaml"
cat "${REAL_YAML}" > "${FX_UNKNOWN}"
printf '\nbrand_new_category:\n  - "unregistered.json"\n' >> "${FX_UNKNOWN}"
check_fails "unregistered category fails instead of dropping patterns" \
	env DENY_PATTERNS_FILE="${FX_UNKNOWN}" "${SCRIPT}" claude

# --- 5. a yaml with no patterns at all is a hard failure --------------------
FX_EMPTY="${TMP}/empty.yaml"
printf '# only comments here\ncredentials:\n' > "${FX_EMPTY}"
check_fails "pattern-less yaml fails" \
	env DENY_PATTERNS_FILE="${FX_EMPTY}" "${SCRIPT}" claude

# --- 6. missing yaml is a hard failure --------------------------------------
check_fails "missing yaml fails" \
	env DENY_PATTERNS_FILE="${TMP}/does-not-exist.yaml" "${SCRIPT}" claude

# --- 7. opencode-apply injects deny and preserves non-deny entries ----------
FAKE_HOME="${TMP}/home"
mkdir -p "${FAKE_HOME}/.opencode"
cat > "${FAKE_HOME}/.opencode/opencode.json" <<'JSON'
{
  "permission": {
    "read": { "*": "allow", "*.env.example": "allow", "**/stale-leftover": "deny" },
    "external_directory": { "*": "ask" },
    "edit": "allow"
  }
}
JSON

if HOME="${FAKE_HOME}" "${SCRIPT}" opencode-apply >/dev/null 2>&1; then
	applied="${FAKE_HOME}/.opencode/opencode.json"
	check "apply keeps non-deny read entries" \
		'[ "$(jq -r ".permission.read[\"*.env.example\"]" "${applied}")" = "allow" ]'
	check "apply drops stale deny entries not in the yaml" \
		'[ "$(jq -r ".permission.read | has(\"**/stale-leftover\")" "${applied}")" = "false" ]'
	check "apply injects the generated deny set into read" \
		'[ "$(jq -r ".permission.read[\"**/.netrc\"]" "${applied}")" = "deny" ]'
	check "apply injects the generated deny set into external_directory" \
		'[ "$(jq -r ".permission.external_directory[\"**/.netrc\"]" "${applied}")" = "deny" ]'
	check "apply leaves unrelated keys untouched" \
		'[ "$(jq -r ".permission.edit" "${applied}")" = "allow" ]'
else
	fail=$((fail + 1))
	printf 'FAIL: opencode-apply failed\n' >&2
fi

# --- 8. opencode-apply refuses to run without a target ----------------------
check_fails "opencode-apply fails when opencode.json is absent" \
	env HOME="${TMP}/no-such-home" "${SCRIPT}" opencode-apply

# --- 9. the shipped opencode.json holds no literal read deny entries --------
# deny-patterns.yaml is the single source of truth for file-read denials, and
# opencode-apply overwrites them on every bootstrap; a literal copy in the repo
# is dead weight that drifts from the yaml silently.
# permission.bash is NOT generated (the yaml's bash_destructive category is
# Claude-only), so its deny entries are hand-maintained and stay put.
check "shipped opencode.json declares no literal read/external_directory deny" \
	'[ "$(jq "[(.permission.read, .permission.external_directory) | values[] | select(. == \"deny\")] | length" "${ROOT}/ai/opencode/opencode.json")" -eq 0 ]'
check "shipped opencode.json keeps its hand-maintained bash denials" \
	'[ "$(jq -r ".permission.bash[\"sudo *\"]" "${ROOT}/ai/opencode/opencode.json")" = "deny" ]'

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
