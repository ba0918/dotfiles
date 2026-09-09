#!/usr/bin/env bash
#
# mise itself, from a signature-verified installer.
#
# `curl https://mise.run | sh` runs the installer before anything has checked
# it, so whoever controls that host runs arbitrary code here. mise publishes
# the same script signed as install.sh.sig; this verifies that signature and
# runs the script only when it holds.
#
# The verifying key is the one already embedded in apt/mise.sources, so no
# keyserver is contacted and any change to the key appears as a diff in this
# repository. gpg runs against a throwaway keyring inside the work directory,
# so the user's own keyring is never touched.
#
# gpg writes its output file even when the signature is bad, so the decrypted
# script lives in a mktemp directory removed on every exit path: a failed
# verification must never leave a runnable script behind.
#
# Usage:
#   mise/install.sh            install mise when it is not already present
#   mise/install.sh --dry-run  verify and print the plan without running it
#
# Test injection (scripts/test_mise_install.sh): MISE_INSTALL_KEY_FILE,
# MISE_INSTALL_SIG_URL, MISE_INSTALL_MISE_BIN.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
for arg in "$@"; do
	case "${arg}" in
		--dry-run) DRY_RUN=true ;;
		--help|-h)
			sed -n '2,21p' "${BASH_SOURCE[0]}"
			exit 0
			;;
		*)
			printf 'mise/install.sh: unknown argument: %s\n' "${arg}" >&2
			exit 2
			;;
	esac
done

KEY_FILE="${MISE_INSTALL_KEY_FILE:-${HERE}/../apt/mise.sources}"
SIG_URL="${MISE_INSTALL_SIG_URL:-https://mise.jdx.dev/install.sh.sig}"

die() {
	printf 'mise/install.sh: %s\n' "$*" >&2
	exit 1
}

# --- skip when mise is already installed -----------------------------------------

if [ -n "${MISE_INSTALL_MISE_BIN+x}" ]; then
	mise_bin="${MISE_INSTALL_MISE_BIN}"
else
	mise_bin="$(command -v mise 2>/dev/null || true)"
fi

if [ -n "${mise_bin}" ]; then
	printf 'mise/install.sh: mise is already installed (%s); nothing to do.\n' "${mise_bin}"
	exit 0
fi

# --- work directory, removed on every exit path ----------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

export GNUPGHOME="${WORK}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

# --- import the verifying key ----------------------------------------------------

[ -r "${KEY_FILE}" ] || die "verifying key file not found: ${KEY_FILE}"

# deb822 inlines the armored block indented by one space, with "." for the
# blank line that separates the armor header from the key data.
sed -n '/BEGIN PGP/,/END PGP/p' "${KEY_FILE}" \
	| sed -e 's/^ //' -e 's/^\.$//' > "${WORK}/key.asc"

[ -s "${WORK}/key.asc" ] || die "no PGP public key found in ${KEY_FILE}"

gpg --batch --quiet --import "${WORK}/key.asc" 2>/dev/null \
	|| die "could not import the verifying key from ${KEY_FILE}"

# --- fetch and verify the installer ----------------------------------------------

printf 'plan: fetch %s\n' "${SIG_URL}"
curl -fsSL --max-time 60 -o "${WORK}/install.sh.sig" "${SIG_URL}" \
	|| die "could not download the signed installer from ${SIG_URL}"

# gpg's human-readable output is not a stable interface; --status-fd is.
gpg --batch --status-fd 3 --output "${WORK}/install.sh" \
	--decrypt "${WORK}/install.sh.sig" 3>"${WORK}/status" >/dev/null 2>&1 || true

fingerprint="$(sed -n 's/^\[GNUPG:\] VALIDSIG \([0-9A-F]*\) .*/\1/p' "${WORK}/status" | head -1)"

if [ -z "${fingerprint}" ] || ! grep -q '^\[GNUPG:\] GOODSIG ' "${WORK}/status"; then
	die "signature verification failed for ${SIG_URL}; refusing to run the installer"
fi

[ -s "${WORK}/install.sh" ] || die "the verified installer is empty"

printf 'mise/install.sh: signature verified (%s)\n' "${fingerprint}"

# --- run it ----------------------------------------------------------------------

if [ "${DRY_RUN}" = true ]; then
	printf '  would run: sh %s\n' "${WORK}/install.sh"
	exit 0
fi

sh "${WORK}/install.sh"
