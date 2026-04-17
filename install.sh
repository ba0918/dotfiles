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

	local arch
	case "$(uname -m)" in
		x86_64)  arch="amd64"  ;;
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
		| grep -oE "https://[^\"]*gcm-linux_${arch}[^\"]*\.deb" \
		| head -1)

	if [[ -z "$deb_url" ]]; then
		echo "[gcm][error] failed to resolve latest .deb url" >&2
		return 1
	fi

	local tmp
	tmp=$(mktemp --suffix=.deb)
	trap 'rm -f "$tmp"' RETURN
	curl -sL -o "$tmp" "$deb_url"
	sudo dpkg -i "$tmp" || sudo apt-get install -f -y
	git-credential-manager configure
	echo "[gcm] configured; on WSL credentials are stored via Windows Credential Manager"
}

install_deps() {
	install_stow
	install_delta
	install_gcm
}

# ----- stow runner -----

run_stow() {
	local flag="$1"
	shift
	local package="$1"

	if [[ ! -d "${DOTFILES_DIR}/${package}" ]]; then
		echo "[skip] package not found: ${package}"
		return
	fi

	echo "[stow ${flag}] ${package} -> ${TARGET}"
	stow --verbose=1 --dir="${DOTFILES_DIR}" --target="${TARGET}" "${flag}" "${package}"
}

# ----- main -----

case "${MODE}" in
	deps)
		install_deps
		;;
	dry-run)
		install_stow
		for pkg in "${PACKAGES[@]}"; do run_stow "--no --stow" "${pkg}"; done
		;;
	unlink)
		install_stow
		for pkg in "${PACKAGES[@]}"; do run_stow "-D" "${pkg}"; done
		;;
	install)
		install_stow
		echo "[phase 1] dry-run to detect conflicts"
		for pkg in "${PACKAGES[@]}"; do run_stow "--no --stow" "${pkg}"; done
		echo "[phase 2] linking"
		for pkg in "${PACKAGES[@]}"; do run_stow "-S" "${pkg}"; done
		echo "[done] symlinks installed"
		echo ""
		echo "[hint] install external tools (delta / GCM) via:"
		echo "  ./install.sh --deps"
		;;
esac
