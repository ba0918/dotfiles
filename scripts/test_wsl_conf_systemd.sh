#!/usr/bin/env bash
#
# Test harness for scripts/wsl-conf-systemd.sh (the wsl.conf content with
# systemd enabled, printed to stdout; the file itself is never written).
#
# Usage: bash scripts/test_wsl_conf_systemd.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/wsl-conf-systemd.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0

if [ ! -f "${SCRIPT}" ]; then
	printf 'FAIL: %s does not exist\n' "${SCRIPT}" >&2
	exit 1
fi

# expect <description> <input, or "-" for a missing file> <expected output>
expect() {
	local desc="$1" input="$2" expected="$3" file="${TMP}/wsl.conf" actual rc
	rm -f "${file}"
	if [ "${input}" != "-" ]; then
		printf '%s' "${input}" > "${file}"
	fi
	cp -p "${file}" "${TMP}/before" 2>/dev/null || rm -f "${TMP}/before"
	set +e
	actual="$(bash "${SCRIPT}" "${file}" 2>&1; printf x)"
	rc=$?
	set -e
	actual="${actual%x}"
	if [ "${rc}" -eq 0 ] && [ "${actual}" = "${expected}" ] &&
		{ [ ! -e "${TMP}/before" ] && [ ! -e "${file}" ] || cmp -s "${TMP}/before" "${file}"; }; then
		pass=$((pass + 1))
		printf 'PASS: %s\n' "${desc}"
	else
		fail=$((fail + 1))
		printf 'FAIL: %s\n--- expected\n%s--- actual\n%s---\n' "${desc}" "${expected}" "${actual}" >&2
	fi
}

expect "a missing file becomes a [boot] section with systemd on" \
	"-" \
	$'[boot]\nsystemd=true\n'

expect "an empty file becomes a [boot] section with systemd on" \
	"" \
	$'[boot]\nsystemd=true\n'

expect "systemd=false under [boot] is switched in place, not duplicated" \
	$'[boot]\nsystemd=false\n' \
	$'[boot]\nsystemd=true\n'

expect "spaces around the key and value are accepted" \
	$'[boot]\n  systemd = false\n' \
	$'[boot]\nsystemd=true\n'

expect "a [boot] section without the key gets it right after the header" \
	$'[boot]\ncommand=/bin/true\n\n[user]\ndefault=someone\n' \
	$'[boot]\nsystemd=true\ncommand=/bin/true\n\n[user]\ndefault=someone\n'

expect "a file without [boot] gets the section appended after a blank line" \
	$'[user]\ndefault=someone\n' \
	$'[user]\ndefault=someone\n\n[boot]\nsystemd=true\n'

expect "a last line without a newline is kept on its own line" \
	$'[user]\ndefault=someone' \
	$'[user]\ndefault=someone\n\n[boot]\nsystemd=true\n'

expect "a file that already enables systemd is unchanged" \
	$'[boot]\nsystemd=true\n\n[user]\ndefault=someone\n' \
	$'[boot]\nsystemd=true\n\n[user]\ndefault=someone\n'

expect "a commented-out key does not count as set" \
	$'[boot]\n#systemd=true\n' \
	$'[boot]\nsystemd=true\n#systemd=true\n'

expect "a systemd key in another section is left alone" \
	$'[other]\nsystemd=false\n' \
	$'[other]\nsystemd=false\n\n[boot]\nsystemd=true\n'

expect "two [boot] sections, as an append-only edit left them, both end up on" \
	$'[boot]\nsystemd=false\n\n[boot]\nsystemd=true\n' \
	$'[boot]\nsystemd=true\n\n[boot]\nsystemd=true\n'

set +e
bash "${SCRIPT}" >/dev/null 2>&1
rc=$?
set -e
if [ "${rc}" -ne 0 ]; then
	pass=$((pass + 1))
	printf 'PASS: a missing argument is an error\n'
else
	fail=$((fail + 1))
	printf 'FAIL: a missing argument is an error\n' >&2
fi

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
