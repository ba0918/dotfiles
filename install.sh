#!/usr/bin/env bash
#
# dotfiles installer - GNU Stow based symlink manager for $HOME
#
# Usage:
#   ./install.sh             Default packages: dry-run then link
#   ./install.sh --dry-run   Show what stow would do without linking
#   ./install.sh --unlink    Remove symlinks
#   ./install.sh --deps      Install external tools only (stow/delta/GCM)
#   ./install.sh git fish    Target specific packages

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}"

# Default packages to stow (directory names)
DEFAULT_PACKAGES=(git)

MODE="install"
PACKAGES=()

for arg in "$@"; do
	case "$arg" in
		--dry-run|-n) MODE="dry-run" ;;
		--unlink|-D)  MODE="unlink"  ;;
		--deps)       MODE="deps"    ;;
		--help|-h)
			sed -n '2,10p' "${BASH_SOURCE[0]}"
			exit 0
			;;
		-*)
			echo "Unknown flag: $arg" >&2
			exit 2
			;;
		*)
			PACKAGES+=("$arg")
			;;
	esac
done

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
	PACKAGES=("${DEFAULT_PACKAGES[@]}")
fi

# ----- package manager helper -----

pm_install() {
	if command -v apt-get >/dev/null 2>&1; then
		sudo apt-get update -y
		sudo apt-get install -y "$@"
	elif command -v dnf >/dev/null 2>&1; then
		sudo dnf install -y "$@"
	elif command -v pacman >/dev/null 2>&1; then
		sudo pacman -S --noconfirm "$@"
	elif command -v brew >/dev/null 2>&1; then
		brew install "$@"
	else
		echo "[error] no supported package manager found; install manually: $*" >&2
		return 1
	fi
}

# ----- tool installers -----

install_stow() {
	if command -v stow >/dev/null 2>&1; then
		echo "[stow] already installed ($(stow --version | head -1))"
		return
	fi
	echo "[stow] installing..."
	pm_install stow
}

install_delta() {
	if command -v delta >/dev/null 2>&1; then
		echo "[delta] already installed ($(delta --version))"
		return
	fi
	echo "[delta] installing..."
	if command -v apt-get >/dev/null 2>&1; then
		# Ubuntu 22.04+ / Debian 12+ ships git-delta
		pm_install git-delta || pm_install delta
	else
		pm_install git-delta
	fi
}

install_gcm() {
	if command -v git-credential-manager >/dev/null 2>&1; then
		echo "[gcm] already installed ($(git-credential-manager --version 2>/dev/null | head -1))"
		return
	fi
	echo "[gcm] installing git-credential-manager..."

	# GCM release asset naming: gcm-linux-<x64|arm64>-<version>.deb
	local arch
	case "$(uname -m)" in
		x86_64)  arch="x64"    ;;
		aarch64) arch="arm64"  ;;
		*) echo "[gcm][error] unsupported arch: $(uname -m)" >&2; return 1 ;;
	esac

	if ! command -v apt-get >/dev/null 2>&1; then
		echo "[gcm][warn] automatic install only supports apt-based systems." >&2
		echo "[gcm][warn] see https://github.com/git-ecosystem/git-credential-manager/releases" >&2
		return 1
	fi

	local api="https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest"
	local deb_url
	deb_url=$(curl -sL "$api" \
		| grep -oE "https://[^\"]*gcm-linux-${arch}-[^\"]*\.deb" \
		| head -1)

	if [[ -z "$deb_url" ]]; then
		echo "[gcm][error] failed to resolve latest .deb url for arch=${arch}" >&2
		return 1
	fi

	echo "[gcm] downloading ${deb_url}"
	local tmp
	tmp=$(mktemp --suffix=.deb)
	# Explicit cleanup (avoid RETURN trap leaking into enclosing function
	# scope under set -u, which triggered "tmp: unbound variable" once the
	# install_deps wrapper returned).
	if curl -fL -o "$tmp" "$deb_url" \
		&& { sudo dpkg -i "$tmp" || sudo apt-get install -f -y; }; then
		rm -f "$tmp"
	else
		rm -f "$tmp"
		echo "[gcm][error] install failed" >&2
		return 1
	fi
	git-credential-manager configure
	echo "[gcm] configured; on WSL credentials are stored via Windows Credential Manager"
}

install_deps() {
	# Prime sudo once so subsequent apt/dpkg calls don't re-prompt.
	if command -v sudo >/dev/null 2>&1; then
		echo "[sudo] caching credentials for dependency install"
		sudo -v
	fi
	install_stow
	install_delta
	install_gcm
}

# ----- stow runner -----

run_stow() {
	local package="$1"
	shift
	# remaining args are stow flags

	if [[ ! -d "${DOTFILES_DIR}/${package}" ]]; then
		echo "[skip] package not found: ${package}"
		return
	fi

	echo "[stow $*] ${package} -> ${TARGET}"
	stow --verbose=1 --dir="${DOTFILES_DIR}" --target="${TARGET}" "$@" "${package}"
}

# ----- main -----

case "${MODE}" in
	deps)
		install_deps
		;;
	dry-run)
		install_stow
		for pkg in "${PACKAGES[@]}"; do run_stow "${pkg}" -n -S; done
		;;
	unlink)
		install_stow
		for pkg in "${PACKAGES[@]}"; do run_stow "${pkg}" -D; done
		;;
	install)
		install_stow
		echo "[phase 1] dry-run to detect conflicts"
		for pkg in "${PACKAGES[@]}"; do run_stow "${pkg}" -n -S; done
		echo "[phase 2] linking"
		for pkg in "${PACKAGES[@]}"; do run_stow "${pkg}" -S; done
		echo "[done] symlinks installed"
		echo ""
		echo "[hint] install external tools (delta / GCM) via:"
		echo "  ./install.sh --deps"
		;;
esac
