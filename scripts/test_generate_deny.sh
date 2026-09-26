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

# Count patterns under one category, mirroring generate-deny.sh's awk extractor
# (POSIX regex; must stay in sync with extract_category in the script).
category_pattern_count() {
	awk -v cat="$1" '
		$0 ~ "^"cat":" { found=1; next }
		found && /^[a-zA-Z_]+:/ { exit }
		found && /^[[:space:]]+-[[:space:]]+"/ { c++ }
		END { print c + 0 }
	' "${REAL_YAML}"
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
# Exact count: every non-directory pattern emits one entry, every directory
# pattern emits two. Any category forgotten in an emitter branch would break
# this equality even though the coverage guard (which only sums extractions)
# still passes.
dir_count="$(category_pattern_count directories)"
check "claude emit count is exact (patterns + one per directory pattern)" \
	'[ "${claude_count}" -eq "$((yaml_total + dir_count))" ]'
# opencode emits file + directory categories only; the Claude-only categories
# (personal_directories / read_shortform / write_deny / bash_destructive) are
# deliberately excluded. Every file pattern emits two keys (`**/p` and bare `p`,
# see section 10), every directory pattern one.
claude_only_count="$(( $(category_pattern_count personal_directories) + $(category_pattern_count read_shortform) + $(category_pattern_count write_deny) + $(category_pattern_count bash_destructive) ))"
file_count="$((yaml_total - claude_only_count - dir_count))"
check "opencode emit count is exact (two per file pattern, one per directory pattern)" \
	'[ "${opencode_count}" -eq "$((file_count * 2 + dir_count))" ]'

# --- 2. known-secret patterns actually survive the conversion ----------------
claude_json="$("${SCRIPT}" claude)"
for want in 'Read(**/.env)' 'Read(**/id_rsa)' 'Read(**/*.pem)' 'Edit(.env*)' 'Bash(sudo:*)'; do
	check "claude deny contains ${want}" \
		'[ "$(echo "${claude_json}" | jq --arg w "${want}" ".permissions.deny | index(\$w) != null")" = "true" ]'
done
# Claude Code ignores Write(...) in file permission checks; only Edit(...) rules
# cover the file-editing tools, so a Write form would be a deny that blocks nothing.
check "claude deny emits no Write(...) rules" \
	'[ "$(echo "${claude_json}" | jq "[.permissions.deny[] | select(startswith(\"Write(\"))] | length")" = "0" ]'

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
# Both config locations get the same deny set: v1 reads ~/.opencode/, v2
# (opencode2) reads ~/.config/opencode/. A target left unpatched is an agent
# running with no read denials at all.
FAKE_HOME="${TMP}/home"
OC_V1="${FAKE_HOME}/.opencode/opencode.json"
OC_V2="${FAKE_HOME}/.config/opencode/opencode.json"
mkdir -p "$(dirname "${OC_V1}")" "$(dirname "${OC_V2}")"
for target in "${OC_V1}" "${OC_V2}"; do
	cat > "${target}" <<'JSON'
{
  "permission": {
    "read": { "*": "allow", "*.env.example": "allow", "**/stale-leftover": "deny" },
    "external_directory": { "*": "ask" },
    "edit": "allow"
  }
}
JSON
done

if HOME="${FAKE_HOME}" "${SCRIPT}" opencode-apply >/dev/null 2>&1; then
	for applied in "${OC_V1}" "${OC_V2}"; do
		label="${applied#"${FAKE_HOME}"/}"
		check "apply keeps non-deny read entries (${label})" \
			'[ "$(jq -r ".permission.read[\"*.env.example\"]" "${applied}")" = "allow" ]'
		check "apply drops stale deny entries not in the yaml (${label})" \
			'[ "$(jq -r ".permission.read | has(\"**/stale-leftover\")" "${applied}")" = "false" ]'
		check "apply injects the generated deny set into read (${label})" \
			'[ "$(jq -r ".permission.read[\"**/.netrc\"]" "${applied}")" = "deny" ]'
		check "apply injects the generated deny set into external_directory (${label})" \
			'[ "$(jq -r ".permission.external_directory[\"**/.netrc\"]" "${applied}")" = "deny" ]'
		check "apply leaves unrelated keys untouched (${label})" \
			'[ "$(jq -r ".permission.edit" "${applied}")" = "allow" ]'
	done
else
	fail=$((fail + 1))
	printf 'FAIL: opencode-apply failed\n' >&2
fi

# --- 8. opencode-apply refuses to run unless every target exists ------------
check_fails "opencode-apply fails when no opencode.json exists" \
	env HOME="${TMP}/no-such-home" "${SCRIPT}" opencode-apply

# With only one of the two targets present, apply must fail without touching
# the one that exists: a half-applied deny set that exits 0 is the failure
# mode AGENTS.md rule 7 forbids.
ONLY_V1_HOME="${TMP}/only-v1"
mkdir -p "${ONLY_V1_HOME}/.opencode"
printf '{"permission":{"read":{"*":"allow"},"external_directory":{"*":"ask"}}}\n' > "${ONLY_V1_HOME}/.opencode/opencode.json"
check_fails "opencode-apply fails when the v2 opencode.json is absent" \
	env HOME="${ONLY_V1_HOME}" "${SCRIPT}" opencode-apply
check "opencode-apply leaves the v1 file unpatched when the v2 one is absent" \
	'[ "$(jq -r ".permission.read | has(\"**/.netrc\")" "${ONLY_V1_HOME}/.opencode/opencode.json")" = "false" ]'

ONLY_V2_HOME="${TMP}/only-v2"
mkdir -p "${ONLY_V2_HOME}/.config/opencode"
printf '{"permission":{"read":{"*":"allow"},"external_directory":{"*":"ask"}}}\n' > "${ONLY_V2_HOME}/.config/opencode/opencode.json"
check_fails "opencode-apply fails when the v1 opencode.json is absent" \
	env HOME="${ONLY_V2_HOME}" "${SCRIPT}" opencode-apply

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

# --- 11. a typo'd emitter fails loudly for every subcommand ------------------
# The CATEGORIES table pairs each category with an emitter name. A misspelled
# emitter (e.g. `fil` instead of `file`) must abort the run: silently treating
# it as Claude-only would pass the coverage guard (which never inspects emitter
# names) while dropping the category from the opencode deny set.
FX_SCRIPT="${TMP}/generate-deny-typo.sh"
sed 's/^credentials:file$/credentials:fil/' "${SCRIPT}" > "${FX_SCRIPT}"
chmod +x "${FX_SCRIPT}"
check_fails "typo'd emitter fails for claude" "${FX_SCRIPT}" claude
check_fails "typo'd emitter fails for opencode" "${FX_SCRIPT}" opencode

# --- 10. opencode directory denies are home-scoped ---------------------------
# deny-patterns.yaml declares `.dir/**` as $HOME-relative. Claude already emits
# Read(~/.dir/**); opencode must not emit `**/.config/**` because that glob also
# matches the repo's own managed config dirs (fish/.config, git/.config, ...),
# which would block the agent from reading the very files it maintains.
check "opencode scopes directory denies to home (~/.config/** present)" \
	'[ "$("${SCRIPT}" opencode | jq -r "has(\"~/.config/**\")")" = "true" ]'
check "opencode emits no unscoped directory deny (**/.config/** absent)" \
	'[ "$("${SCRIPT}" opencode | jq -r "has(\"**/.config/**\")")" = "false" ]'
check "opencode keeps file denies global (**/.env still present)" \
	'[ "$("${SCRIPT}" opencode | jq -r "has(\"**/.env\")")" = "true" ]'
# opencode v2 matches read rules against the project-relative path, and
# `**/.env` does not match a top-level `.env` there (observed with opencode2
# 2.0.17: sub/.env denied, ./.env read). The bare form closes that gap; v1
# already denied both, so the extra key only adds coverage.
check "opencode also emits the bare file pattern (.env present)" \
	'[ "$("${SCRIPT}" opencode | jq -r "has(\".env\")")" = "true" ]'
check "opencode bare file pattern is a deny (*.pem)" \
	'[ "$("${SCRIPT}" opencode | jq -r ".[\"*.pem\"]")" = "deny" ]'

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
