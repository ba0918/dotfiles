#!/usr/bin/env bash
#
# Test harness for ssh/install.sh (sshd reachable from the Windows host, key-only)
#
# Every real step of the installer needs sudo, so only its planning is
# asserted: what it decides to do from a given machine state, and in which
# order. Machine state is injected through the SSH_INSTALL_* variables the
# script reads instead of the real /etc, dpkg and $HOME/.ssh.
#
# Usage: bash scripts/test_ssh_install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/ssh/install.sh"

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

PUBKEY_LINE="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE test@windows"

# Fresh machine: nothing configured, a Windows key pair exists.
fresh() {
	local state="$1"
	mkdir -p "${state}/sshd_config.d" "${state}/ssh.socket.d" "${state}/home/.ssh" "${state}/win/.ssh"
	printf '[boot]\nsystemd=false\n' > "${state}/wsl.conf"
	printf '%s\n' "${PUBKEY_LINE}" > "${state}/win/.ssh/id_ed25519.pub"
}

run() {
	local state="$1"
	shift
	set +e
	OUT="$(SSH_INSTALL_SSHD_CONF_DIR="${state}/sshd_config.d" \
		SSH_INSTALL_SOCKET_CONF_DIR="${state}/ssh.socket.d" \
		SSH_INSTALL_WSL_CONF="${state}/wsl.conf" \
		SSH_INSTALL_INSTALLED_PKGS="${INSTALLED:-}" \
		SSH_INSTALL_AUTHORIZED_KEYS="${state}/home/.ssh/authorized_keys" \
		SSH_INSTALL_WINDOWS_PUBKEY="${state}/win/.ssh/id_ed25519.pub" \
		"${SCRIPT}" "$@" 2>&1)"
	RC=$?
	set -e
}

# --- fresh machine: every step is planned ----------------------------------------

S="${TMP}/fresh"; fresh "${S}"
INSTALLED="" run "${S}" --dry-run
check "dry-run exits 0 on a fresh machine" '[ "${RC}" -eq 0 ]'
check "plans the sshd hardening drop-in" 'grep -q "^plan: sshd drop-in" <<<"${OUT}"'
check "plans the package install" 'grep -q "^plan: install openssh-server$" <<<"${OUT}"'
check "hardens sshd before the package can start it" '[ "$(grep -n "^plan: sshd drop-in" <<<"${OUT}" | cut -d: -f1)" -lt "$(grep -n "^plan: install openssh-server" <<<"${OUT}" | cut -d: -f1)" ]'
check "plans the loopback-only socket drop-in" 'grep -q "^plan: ssh.socket drop-in" <<<"${OUT}"'
check "plans authorizing the Windows public key" 'grep -q "^plan: authorized_keys" <<<"${OUT}"'
check "plans systemd in wsl.conf and says a WSL restart is needed" 'grep -q "^plan: wsl.conf" <<<"${OUT}" && grep -q "wsl --shutdown" <<<"${OUT}"'
check "dry-run changes nothing" '[ -z "$(ls -A "${S}/sshd_config.d")" ] && [ -z "$(ls -A "${S}/ssh.socket.d")" ] && [ ! -e "${S}/home/.ssh/authorized_keys" ]'
check "dry-run never prints the public key" '! grep -q "AAAAC3NzaC1lZDI1NTE5" <<<"${OUT}"'

# --- configured machine: nothing to do -----------------------------------------------

S="${TMP}/done"; fresh "${S}"
cp "${ROOT}/ssh/sshd_config.d/10-dotfiles.conf" "${S}/sshd_config.d/"
cp "${ROOT}/ssh/ssh.socket.d/10-dotfiles.conf" "${S}/ssh.socket.d/"
printf '%s\n' "${PUBKEY_LINE}" > "${S}/home/.ssh/authorized_keys"
printf '[boot]\nsystemd=true\n' > "${S}/wsl.conf"
INSTALLED="openssh-server" run "${S}" --dry-run
check "a configured machine plans nothing" '[ "${RC}" -eq 0 ] && ! grep -q "^plan:" <<<"${OUT}"'

# --- our own drop-ins are brought back in line when they drift ----------------------

S="${TMP}/drift"; fresh "${S}"
echo "PasswordAuthentication yes" > "${S}/sshd_config.d/10-dotfiles.conf"
cp "${ROOT}/ssh/ssh.socket.d/10-dotfiles.conf" "${S}/ssh.socket.d/"
printf '%s\n' "${PUBKEY_LINE}" > "${S}/home/.ssh/authorized_keys"
printf '[boot]\nsystemd=true\n' > "${S}/wsl.conf"
INSTALLED="openssh-server" run "${S}" --dry-run
check "a drifted sshd drop-in is re-planned" 'grep -q "^plan: sshd drop-in" <<<"${OUT}"'
check "an unchanged socket drop-in is not re-planned" '! grep -q "^plan: ssh.socket drop-in" <<<"${OUT}"'

# --- an already authorized key is not appended twice -------------------------------

S="${TMP}/keyed"; fresh "${S}"
printf 'ssh-ed25519 AAAAOTHERKEY other@host\n%s\n' "${PUBKEY_LINE}" > "${S}/home/.ssh/authorized_keys"
INSTALLED="" run "${S}" --dry-run
check "a key already in authorized_keys is not re-planned" '! grep -q "^plan: authorized_keys" <<<"${OUT}"'

# --- no Windows key pair yet: say how to make one, keep going --------------------------

S="${TMP}/nokey"; fresh "${S}"
rm "${S}/win/.ssh/id_ed25519.pub"
INSTALLED="" run "${S}" --dry-run
check "a missing Windows key does not abort the run" '[ "${RC}" -eq 0 ]'
check "a missing Windows key is reported with the ssh-keygen command" 'grep -q "^note:.*ssh-keygen" <<<"${OUT}"'
check "nothing is planned for authorized_keys without a key" '! grep -q "^plan: authorized_keys" <<<"${OUT}"'

# --- wslu missing or silent: the Windows key is absent, not fatal ---------------------

S="${TMP}/nowslu"; fresh "${S}"
mkdir -p "${S}/bin"
printf '#!/bin/sh\nexit 0\n' > "${S}/bin/wslvar"; chmod +x "${S}/bin/wslvar"
set +e
OUT="$(PATH="${S}/bin:${PATH}" \
	SSH_INSTALL_SSHD_CONF_DIR="${S}/sshd_config.d" \
	SSH_INSTALL_SOCKET_CONF_DIR="${S}/ssh.socket.d" \
	SSH_INSTALL_WSL_CONF="${S}/wsl.conf" \
	SSH_INSTALL_INSTALLED_PKGS="" \
	SSH_INSTALL_AUTHORIZED_KEYS="${S}/home/.ssh/authorized_keys" \
	"${SCRIPT}" --dry-run 2>&1)"
RC=$?
set -e
check "a wslvar that resolves nothing does not abort the run" '[ "${RC}" -eq 0 ]'
check "a wslvar that resolves nothing is reported as a missing Windows key" 'grep -q "^note:.*ssh-keygen" <<<"${OUT}"'

# --- arguments -----------------------------------------------------------------------

S="${TMP}/args"; fresh "${S}"
INSTALLED="" run "${S}" --bogus
check "an unknown argument is rejected" '[ "${RC}" -eq 2 ] && grep -q "unknown argument" <<<"${OUT}"'

# --- summary ------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
