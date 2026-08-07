#!/usr/bin/env bash
#
# dotfiles installer - git-credential-manager only
#
# The dotfiles themselves and the system packages (stow / git-delta) are now
# managed declaratively by mise. This script only installs GCM, which is not
# available in the mise registry and must be fetched from GitHub releases.
#
# Usage:
#   ./install.sh             Install git-credential-manager (apt-based systems)
#   ./install.sh --check     Report whether GCM is already installed

set -euo pipefail

GCM="git-credential-manager"

log() { printf '[gcm] %s\n' "$1"; }
die() { printf '[gcm][error] %s\n' "$1" >&2; exit 1; }

check_gcm() {
	if command -v "${GCM}" >/dev/null 2>&1; then
		log "already installed ($(${GCM} --version 2>/dev/null | head -1))"
		return 0
	fi
	log "not installed"
	return 1
}

install_gcm() {
	if command -v "${GCM}" >/dev/null 2>&1; then
		log "already installed ($(${GCM} --version 2>/dev/null | head -1))"
		return
	fi

	if ! command -v apt-get >/dev/null 2>&1; then
		echo "[gcm][warn] automatic install only supports apt-based systems." >&2
		echo "[gcm][warn] see https://github.com/git-ecosystem/git-credential-manager/releases" >&2
		return 1
	fi

	local arch
	case "$(uname -m)" in
		x86_64)  arch="x64"    ;;
		aarch64) arch="arm64"  ;;
		*) die "unsupported arch: $(uname -m)" ;;
	esac

	local api="https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest"
	local deb_url
	deb_url=$(curl -sL "$api" \
		| grep -oE "https://[^\"]*gcm-linux-${arch}-[^\"]*\.deb" \
		| head -1)

	if [[ -z "$deb_url" ]]; then
		die "failed to resolve latest .deb url for arch=${arch}"
	fi

	log "downloading ${deb_url}"
	local tmp
	tmp=$(mktemp --suffix=.deb)
	if curl -fL -o "$tmp" "$deb_url" \
		&& { sudo dpkg -i "$tmp" || sudo apt-get install -f -y; }; then
		rm -f "$tmp"
	else
		rm -f "$tmp"
		die "install failed"
	fi
	"${GCM}" configure
	log "configured; on WSL credentials are stored via Windows Credential Manager"
}

case "${1:-install}" in
	--check|-c) check_gcm ;;
	--help|-h)
		sed -n '2,9p' "${BASH_SOURCE[0]}"
		exit 0
		;;
	install|"") install_gcm ;;
	*)
		echo "Unknown flag: $1" >&2
		exit 2
		;;
esac