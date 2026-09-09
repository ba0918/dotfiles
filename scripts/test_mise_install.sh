#!/usr/bin/env bash
#
# Test harness for mise/install.sh (signature-verified mise bootstrap)
#
# The installer fetches a signed installer script and runs it, so the parts
# worth asserting are the ones that decide whether it runs at all: that a good
# signature is required, that a tampered one stops the run, and that no
# decrypted script survives a failed verification. A throwaway GPG key signs
# local fixtures here, so no network and no real mise release is involved.
#
# Usage: bash scripts/test_mise_install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/mise/install.sh"

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

if [ ! -x "${SCRIPT}" ]; then
	printf 'FAIL: %s does not exist or is not executable\n' "${SCRIPT}" >&2
	exit 1
fi

# --- fixtures: a throwaway signing key, a signed payload, a tampered copy ---------

export GNUPGHOME="${TMP}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

gpg --batch --quiet --passphrase '' --quick-generate-key \
	'dotfiles test <test@example.invalid>' rsa2048 sign never >/dev/null 2>&1

# The installer reads the key out of a deb822 .sources file, the same shape as
# apt/mise.sources: the armored block indented by one space, blank lines as ".".
KEY_SOURCES="${TMP}/test.sources"
{
	printf 'Types: deb\nURIs: https://example.invalid/deb\nSuites: stable\nComponents: main\nSigned-By:\n'
	gpg --batch --armor --export 'test@example.invalid' \
		| sed -e 's/^$/./' -e 's/^/ /'
} > "${KEY_SOURCES}"

printf '#!/bin/sh\necho fixture-installer-ran\n' > "${TMP}/payload.sh"
gpg --batch --quiet --yes --output "${TMP}/good.sig" --sign "${TMP}/payload.sh"

cp "${TMP}/good.sig" "${TMP}/tampered.sig"
printf 'X' | dd of="${TMP}/tampered.sig" bs=1 seek=300 conv=notrunc status=none

# A scratch TMPDIR the installer's own mktemp will use, so the harness can see
# whether a failed verification left a decrypted script behind.
SCRATCH="${TMP}/scratch"

run_installer() {
	local sig="$1"
	shift
	rm -rf "${SCRATCH}"
	mkdir -p "${SCRATCH}"
	env TMPDIR="${SCRATCH}" \
		MISE_INSTALL_KEY_FILE="${KEY_SOURCES}" \
		MISE_INSTALL_SIG_URL="file://${sig}" \
		MISE_INSTALL_MISE_BIN='' \
		"${SCRIPT}" "$@" 2>&1
}

scratch_files() {
	find "${SCRATCH}" -type f 2>/dev/null | wc -l
}

# --- argument handling -----------------------------------------------------------

out="$("${SCRIPT}" --help 2>&1)" && status=0 || status=$?
check '--help exits 0' '[ "${status}" -eq 0 ]'
check '--help prints usage' 'printf %s "${out}" | grep -q -- "--dry-run"'

out="$("${SCRIPT}" --bogus 2>&1)" && status=0 || status=$?
check 'unknown argument exits 2' '[ "${status}" -eq 2 ]'

# --- already installed -----------------------------------------------------------

out="$(env MISE_INSTALL_MISE_BIN=/bin/true "${SCRIPT}" 2>&1)" && status=0 || status=$?
check 'exits 0 when mise is already present' '[ "${status}" -eq 0 ]'
check 'says nothing to do when mise is already present' \
	'printf %s "${out}" | grep -qi "already"'

# --- good signature --------------------------------------------------------------

out="$(run_installer "${TMP}/good.sig" --dry-run)" && status=0 || status=$?
check 'good signature exits 0' '[ "${status}" -eq 0 ]'
check 'good signature reports the verification' \
	'printf %s "${out}" | grep -qi "signature verified"'
check 'good signature reaches the run step' \
	'printf %s "${out}" | grep -q "would run"'

# --- tampered signature ----------------------------------------------------------

out="$(run_installer "${TMP}/tampered.sig" --dry-run)" && status=0 || status=$?
check 'tampered signature exits non-zero' '[ "${status}" -ne 0 ]'
check 'tampered signature never reaches the run step' \
	'! printf %s "${out}" | grep -q "would run"'
check 'tampered signature leaves no decrypted script behind' \
	'[ "$(scratch_files)" -eq 0 ]'

# --- unusable key ----------------------------------------------------------------

printf 'Types: deb\nURIs: https://example.invalid/deb\nSigned-By:\n' > "${TMP}/nokey.sources"
out="$(env TMPDIR="${SCRATCH}" \
	MISE_INSTALL_KEY_FILE="${TMP}/nokey.sources" \
	MISE_INSTALL_SIG_URL="file://${TMP}/good.sig" \
	MISE_INSTALL_MISE_BIN='' \
	"${SCRIPT}" --dry-run 2>&1)" && status=0 || status=$?
check 'a sources file carrying no key exits non-zero' '[ "${status}" -ne 0 ]'

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
