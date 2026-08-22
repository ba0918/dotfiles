#!/usr/bin/env bash
#
# Native dockerd inside WSL — opt-in, not part of `mise bootstrap`.
#
# Two kinds of machine share these dotfiles: ones where Docker Desktop on
# Windows provides the daemon through its WSL integration, and ones with
# docker-ce running directly in the distro (no Desktop). docker-ce must never
# be installed on the former — a second daemon fights Desktop over
# /var/run/docker.sock — so this is a separate script rather than an
# [bootstrap.packages] entry, and it refuses to run when Desktop is detected.
#
# What it sets up (each step idempotent, each needs sudo):
#   1. Docker's apt repository (docker/docker.sources, key inline)
#   2. docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#   3. /etc/docker/daemon.json from docker/daemon.json (never overwrites one
#      that already exists and differs)
#   4. the current user in the `docker` group
#   5. systemd=true in /etc/wsl.conf, which docker.service needs; this takes
#      effect only after `wsl --shutdown` from Windows
#   6. docker.service enabled and started (when systemd is already running)
#
# Usage:
#   docker/install.sh            apply
#   docker/install.sh --dry-run  print the plan only
#
# Test injection (scripts/test_docker_install.sh): DOCKER_DESKTOP_ROOT,
# DOCKER_INSTALL_SOURCES_DIR, DOCKER_INSTALL_DAEMON_JSON,
# DOCKER_INSTALL_WSL_CONF, DOCKER_INSTALL_INSTALLED_PKGS, DOCKER_INSTALL_GROUPS.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
for arg in "$@"; do
	case "${arg}" in
		--dry-run) DRY_RUN=true ;;
		--help|-h)
			sed -n '2,26p' "${BASH_SOURCE[0]}"
			exit 0
			;;
		*)
			printf 'docker/install.sh: unknown argument: %s\n' "${arg}" >&2
			exit 2
			;;
	esac
done

DESKTOP_ROOT="${DOCKER_DESKTOP_ROOT:-/mnt/wsl/docker-desktop}"
SOURCES_DIR="${DOCKER_INSTALL_SOURCES_DIR:-/etc/apt/sources.list.d}"
DAEMON_JSON="${DOCKER_INSTALL_DAEMON_JSON:-/etc/docker/daemon.json}"
WSL_CONF="${DOCKER_INSTALL_WSL_CONF:-/etc/wsl.conf}"
PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

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

# --- refuse under Docker Desktop -------------------------------------------------

docker_desktop_present() {
	[ -d "${DESKTOP_ROOT}" ] && return 0
	local cli
	cli="$(command -v docker 2>/dev/null || true)"
	[ -n "${cli}" ] && case "$(readlink -f "${cli}")" in
		"${DESKTOP_ROOT}"/*) return 0 ;;
	esac
	return 1
}

if docker_desktop_present; then
	printf 'docker/install.sh: Docker Desktop integration detected (%s); the daemon is provided by Windows. Nothing to install here.\n' "${DESKTOP_ROOT}" >&2
	exit 1
fi

# --- state probes (injectable) --------------------------------------------------------

pkg_installed() {
	if [ -n "${DOCKER_INSTALL_INSTALLED_PKGS+x}" ]; then
		case " ${DOCKER_INSTALL_INSTALLED_PKGS} " in
			*" $1 "*) return 0 ;;
		esac
		return 1
	fi
	[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
}

in_docker_group() {
	local groups
	if [ -n "${DOCKER_INSTALL_GROUPS+x}" ]; then
		groups="${DOCKER_INSTALL_GROUPS}"
	else
		groups="$(id -nG)"
	fi
	case " ${groups} " in
		*" docker "*) return 0 ;;
	esac
	return 1
}

wsl_systemd_enabled() {
	[ -f "${WSL_CONF}" ] && grep -Eq '^\s*systemd\s*=\s*true' "${WSL_CONF}"
}

# --- 1. apt source ---------------------------------------------------------------------

SOURCE_NAME="docker.sources"
# Any existing entry for download.docker.com counts (a hand-made docker.list
# from the official docs, say): a second definition makes apt warn about
# duplicate targets on every update.
docker_source_present() {
	[ -e "${SOURCES_DIR}/${SOURCE_NAME}" ] && return 0
	grep -rlq 'download\.docker\.com' "${SOURCES_DIR}" 2>/dev/null
}
if ! docker_source_present; then
	plan "apt source ${SOURCES_DIR}/${SOURCE_NAME}"
	run sudo install -m 0644 "${HERE}/${SOURCE_NAME}" "${SOURCES_DIR}/${SOURCE_NAME}"
	run sudo apt-get update
fi

# --- 2. packages ----------------------------------------------------------------------------

missing=()
for p in "${PACKAGES[@]}"; do
	pkg_installed "${p}" || missing+=("${p}")
done
if [ "${#missing[@]}" -gt 0 ]; then
	plan "install ${missing[*]}"
	run sudo apt-get install -y "${missing[@]}"
fi

# --- 3. daemon.json ---------------------------------------------------------------------------

if [ ! -e "${DAEMON_JSON}" ]; then
	plan "daemon.json ${DAEMON_JSON}"
	run sudo install -D -m 0644 "${HERE}/daemon.json" "${DAEMON_JSON}"
elif ! cmp -s "${HERE}/daemon.json" "${DAEMON_JSON}"; then
	printf 'note: %s exists and daemon.json differs from %s/daemon.json; left untouched\n' "${DAEMON_JSON}" "${HERE}"
fi

# --- 4. group ----------------------------------------------------------------------------------

if ! in_docker_group; then
	plan "group: add ${USER} to docker (re-login to take effect)"
	run sudo usermod -aG docker "${USER}"
fi

# --- 5. systemd in wsl.conf ------------------------------------------------------------------

if ! wsl_systemd_enabled; then
	plan "wsl.conf: enable systemd in ${WSL_CONF} (then run \`wsl --shutdown\` from Windows and reopen the distro)"
	if [ "${DRY_RUN}" = true ]; then
		printf '  would append: [boot] systemd=true\n'
	else
		printf '\n[boot]\nsystemd=true\n' | sudo tee -a "${WSL_CONF}" >/dev/null
	fi
fi

# --- 6. service --------------------------------------------------------------------------------

if [ "${DRY_RUN}" = false ] && [ -d /run/systemd/system ]; then
	sudo systemctl enable --now docker
fi

exit 0
