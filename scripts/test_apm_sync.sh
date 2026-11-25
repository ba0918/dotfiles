#!/usr/bin/env bash
#
# Test harness for scripts/apm-sync.sh (rule skills: follow the unpinned
# entries, hold the pinned ones).
#
# apm is replaced by a stand-in that records its arguments, so nothing is
# fetched and no skill directory is touched.
#
# Usage: bash scripts/test_apm_sync.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/apm-sync.sh"

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

if [ ! -f "${SCRIPT}" ]; then
	printf 'FAIL: %s does not exist\n' "${SCRIPT}" >&2
	exit 1
fi

mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/apm" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TMP}/calls"
if [ "\$1" = "\${APM_FAIL_ON:-}" ]; then
	exit 3
fi
SH
chmod +x "${TMP}/bin/apm"

run() {
	local manifest="$1"
	: > "${TMP}/calls"
	set +e
	OUT="$(PATH="${TMP}/bin:/usr/bin:/bin" APM_SYNC_MANIFEST="${manifest}" \
		APM_FAIL_ON="${FAIL_ON:-}" bash "${SCRIPT}" 2>&1)"
	RC=$?
	set -e
	CALLS="$(cat "${TMP}/calls")"
}

# --- mixed manifest ------------------------------------------------------------------

cat > "${TMP}/mixed.yml" <<'YAML'
name: dotfiles
targets:
  - claude
dependencies:
  apm:
    # a comment
    - owner/own-rules
    - owner/skills/skills/own-skill
    - other/plugin#0123456789abcdef0123456789abcdef01234567 # 1.2.3
    - other/repo/skills/thing#89abcdef0123456789abcdef0123456789abcdef
  mcp: []
includes: auto
YAML

run "${TMP}/mixed.yml"
check "a mixed manifest succeeds" '[ "${RC}" -eq 0 ]'
check "unpinned entries are the only ones passed to update" \
	'[ "$(sed -n 1p <<<"${CALLS}")" = "update -g --yes owner/own-rules owner/skills/skills/own-skill" ]'
check "install runs after update so pinned entries are deployed at their pin" \
	'[ "$(sed -n 2p <<<"${CALLS}")" = "install -g" ]'
check "entries outside dependencies.apm are not read as packages" '! grep -q "claude" <<<"${CALLS}"'

# --- everything pinned: a bare `apm update` would move every pin ----------------------

cat > "${TMP}/pinned.yml" <<'YAML'
dependencies:
  apm:
    - other/plugin#0123456789abcdef0123456789abcdef01234567
YAML

run "${TMP}/pinned.yml"
check "a fully pinned manifest succeeds" '[ "${RC}" -eq 0 ]'
check "update is never called without package names" '! grep -q "^update" <<<"${CALLS}"'
check "a fully pinned manifest is still installed" 'grep -qx "install -g" <<<"${CALLS}"'

# --- nothing parsed: an empty run must not look like a pass ---------------------------

cat > "${TMP}/empty.yml" <<'YAML'
dependencies:
  apm: []
YAML

run "${TMP}/empty.yml"
check "a manifest with no dependencies fails" '[ "${RC}" -ne 0 ]'
check "nothing is run for a manifest with no dependencies" '[ -z "${CALLS}" ]'

run "${TMP}/absent.yml"
check "a missing manifest fails" '[ "${RC}" -ne 0 ] && [ -z "${CALLS}" ]'

# --- failures propagate --------------------------------------------------------------

FAIL_ON=update run "${TMP}/mixed.yml"
check "a failed update fails the run" '[ "${RC}" -ne 0 ]'
check "install is not attempted after a failed update" '! grep -q "^install" <<<"${CALLS}"'

FAIL_ON=install run "${TMP}/mixed.yml"
check "a failed install fails the run" '[ "${RC}" -ne 0 ]'

# --- the real manifest ---------------------------------------------------------------

run "${ROOT}/ai/apm/apm.yml"
check "the repository manifest is parsed" '[ "${RC}" -eq 0 ] && grep -q "^update -g --yes " <<<"${CALLS}"'
check "no pinned entry of the repository manifest reaches update" '! sed -n 1p <<<"${CALLS}" | grep -q "#"'

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
