#!/usr/bin/env bash
#
# sshd inside WSL, reachable from the Windows host — opt-in, not part of
# `mise bootstrap`.
#
# Lets tools on the Windows side (an IDE, an agent runner) drive the distro
# over ssh. openssh-server stays out of [bootstrap.packages] on purpose: the
# package enables and starts the listener the moment it is installed, and the
# hardening below has to be in place before that first start.
#
# What it sets up (each step idempotent, each needs sudo unless noted):
#   1. /etc/ssh/sshd_config.d/10-dotfiles.conf — key-only auth, no root login
#   2. openssh-server
#   3. /etc/systemd/system/ssh.socket.d/10-dotfiles.conf — listen on loopback only
#   4. the Windows user's public key in ~/.ssh/authorized_keys (no sudo)
#   5. systemd=true in /etc/wsl.conf, which ssh.socket needs; this takes
#      effect only after `wsl --shutdown` from Windows
#   6. ssh.socket enabled and (re)started when systemd is already running
#
# Usage:
#   ssh/install.sh            apply
#   ssh/install.sh --dry-run  print the plan only
#
# Then from Windows: ssh <user>@localhost
#
# Test injection (scripts/test_ssh_install.sh): SSH_INSTALL_SSHD_CONF_DIR,
# SSH_INSTALL_SOCKET_CONF_DIR, SSH_INSTALL_WSL_CONF, SSH_INSTALL_INSTALLED_PKGS,
# SSH_INSTALL_AUTHORIZED_KEYS, SSH_INSTALL_WINDOWS_PUBKEY.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
for arg in "$@"; do
	case "${arg}" in
		--dry-run) DRY_RUN=true ;;
		--help|-h)
			sed -n '2,24p' "${BASH_SOURCE[0]}"
			exit 0
			;;
		*)
			printf 'ssh/install.sh: unknown argument: %s\n' "${arg}" >&2
			exit 2
			;;
	esac
done

SSHD_CONF_DIR="${SSH_INSTALL_SSHD_CONF_DIR:-/etc/ssh/sshd_config.d}"
SOCKET_CONF_DIR="${SSH_INSTALL_SOCKET_CONF_DIR:-/etc/systemd/system/ssh.socket.d}"
WSL_CONF="${SSH_INSTALL_WSL_CONF:-/etc/wsl.conf}"
AUTHORIZED_KEYS="${SSH_INSTALL_AUTHORIZED_KEYS:-${HOME}/.ssh/authorized_keys}"
DROPIN="10-dotfiles.conf"

# %USERPROFILE% as Windows reports it, or nothing. Asked through cmd.exe, which
# every WSL distro reaches through interop, so no extra package is needed (this
# used to be `wslvar` from wslu, which is discontinued upstream). cmd.exe
# complains on stderr when started from a WSL directory and ends its line with
# CR LF. A variable that Windows does not know comes back unexpanded.
windows_profile() {
	local cmd answer
	cmd="$(command -v cmd.exe 2>/dev/null || true)"
	[ -n "${cmd}" ] || cmd=/mnt/c/Windows/System32/cmd.exe
	[ -x "${cmd}" ] || return 0
	answer="$("${cmd}" /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' | head -n 1 || true)"
	case "${answer}" in
		''|*%*) return 0 ;;
	esac
	printf '%s\n' "${answer}"
}

# The Windows user's key pair. When the profile cannot be resolved the key is
# treated as absent and step 4 is reported rather than performed.
windows_pubkey() {
	if [ -n "${SSH_INSTALL_WINDOWS_PUBKEY+x}" ]; then
		printf '%s\n' "${SSH_INSTALL_WINDOWS_PUBKEY}"
		return
	fi
	local profile home
	profile="$(windows_profile)"
	[ -n "${profile}" ] || return 0
	home="$(wslpath "${profile}" 2>/dev/null || true)"
	if [ -n "${home}" ]; then
		printf '%s\n' "${home}/.ssh/id_ed25519.pub"
	fi
}
WINDOWS_PUBKEY="$(windows_pubkey)"

plan() {
	printf 'plan: %s\n' "$*"
}

run() {
	if [ "${DRY_RUN}" = true ]; then
		printf '  would run: %s\n' "$*"
	else
		"$@"
	fi
}

pkg_installed() {
	if [ -n "${SSH_INSTALL_INSTALLED_PKGS+x}" ]; then
		case " ${SSH_INSTALL_INSTALLED_PKGS} " in
			*" $1 "*) return 0 ;;
		esac
		return 1
	fi
	[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
}

# The wsl.conf content with systemd enabled, from the shared helper. Comparing
# it with the file decides whether anything has to be written: a `systemd=true`
# outside [boot], or a second [boot] section, no longer passes for enabled.
WSL_CONF_WANTED="$(mktemp)"
trap 'rm -f "${WSL_CONF_WANTED}"' EXIT
bash "${HERE}/../scripts/wsl-conf-systemd.sh" "${WSL_CONF}" > "${WSL_CONF_WANTED}"

wsl_systemd_enabled() {
	[ -f "${WSL_CONF}" ] && cmp -s "${WSL_CONF_WANTED}" "${WSL_CONF}"
}

# Our own drop-ins are owned by this repo, so a drifted copy is replaced
# (unlike docker/daemon.json, which may carry a local edit).
dropin_current() {
	cmp -s "$1" "$2"
}

units_changed=false

# --- 1. sshd hardening (before the package, so the first start is already key-only) ---

if ! dropin_current "${HERE}/sshd_config.d/${DROPIN}" "${SSHD_CONF_DIR}/${DROPIN}"; then
	plan "sshd drop-in ${SSHD_CONF_DIR}/${DROPIN} (key-only auth, no root login)"
	run sudo install -D -m 0644 "${HERE}/sshd_config.d/${DROPIN}" "${SSHD_CONF_DIR}/${DROPIN}"
	units_changed=true
fi

# --- 2. package ------------------------------------------------------------------------

if ! pkg_installed openssh-server; then
	plan "install openssh-server"
	run sudo apt-get install -y openssh-server
fi

# --- 3. loopback-only socket ------------------------------------------------------------

if ! dropin_current "${HERE}/ssh.socket.d/${DROPIN}" "${SOCKET_CONF_DIR}/${DROPIN}"; then
	plan "ssh.socket drop-in ${SOCKET_CONF_DIR}/${DROPIN} (listen on 127.0.0.1 / ::1 only)"
	run sudo install -D -m 0644 "${HERE}/ssh.socket.d/${DROPIN}" "${SOCKET_CONF_DIR}/${DROPIN}"
	units_changed=true
fi

# --- 4. authorized_keys (no sudo) ---------------------------------------------------------

if [ -z "${WINDOWS_PUBKEY}" ] || [ ! -r "${WINDOWS_PUBKEY}" ]; then
	printf 'note: no Windows public key at %s; create one from Windows with `ssh-keygen -t ed25519`, then re-run\n' "${WINDOWS_PUBKEY:-%USERPROFILE%\\.ssh\\id_ed25519.pub}"
elif ! { [ -r "${AUTHORIZED_KEYS}" ] && grep -qxF -f "${WINDOWS_PUBKEY}" "${AUTHORIZED_KEYS}"; }; then
	plan "authorized_keys: add the Windows key from ${WINDOWS_PUBKEY} to ${AUTHORIZED_KEYS}"
	if [ "${DRY_RUN}" = false ]; then
		install -d -m 0700 "$(dirname "${AUTHORIZED_KEYS}")"
		[ -e "${AUTHORIZED_KEYS}" ] || install -m 0600 /dev/null "${AUTHORIZED_KEYS}"
		cat "${WINDOWS_PUBKEY}" >> "${AUTHORIZED_KEYS}"
	fi
fi

# --- 5. systemd in wsl.conf --------------------------------------------------------------

if ! wsl_systemd_enabled; then
	plan "wsl.conf: enable systemd in ${WSL_CONF} (then run \`wsl --shutdown\` from Windows and reopen the distro)"
	if [ "${DRY_RUN}" = true ]; then
		printf '  would write %s as:\n' "${WSL_CONF}"
		sed 's/^/    /' "${WSL_CONF_WANTED}"
	else
		sudo install -m 0644 "${WSL_CONF_WANTED}" "${WSL_CONF}"
	fi
fi

# --- 6. service ----------------------------------------------------------------------------

if [ "${DRY_RUN}" = false ] && [ -d /run/systemd/system ]; then
	sudo sshd -t
	sudo systemctl daemon-reload
	if [ "${units_changed}" = true ]; then
		# A running sshd keeps the old listen socket and the old config; both
		# must be stopped for the drop-ins to take effect.
		sudo systemctl stop ssh.service ssh.socket
	fi
	sudo systemctl enable --now ssh.socket
fi

exit 0
