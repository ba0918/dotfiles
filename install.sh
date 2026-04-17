#!/usr/bin/env bash
#
# dotfiles installer — GNU Stow ベースで $HOME に symlink を張る
#
# Usage:
#   ./install.sh            # デフォルトパッケージを ドライラン → 実リンク
#   ./install.sh --dry-run  # 何が起きるかだけ見る
#   ./install.sh --unlink   # リンクを剥がす
#   ./install.sh --deps     # 依存ツール (stow/delta/GCM) のみインストール
#   ./install.sh git fish   # 個別パッケージ指定

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}"

# デフォルトで stow するパッケージ（ディレクトリ名）
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

# ----- パッケージマネージャ共通 -----

pm_install() {
	# $@ = install 対象（複数可）
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
		echo "[error] パッケージマネージャが見つからない。手動で $* 入れてね〜" >&2
		return 1
	fi
}

# ----- 個別ツールのインストーラ -----

install_stow() {
	if command -v stow >/dev/null 2>&1; then
		echo "[stow] 既に入ってるよ〜 ($(stow --version | head -1))"
		return
	fi
	echo "[stow] インストールするね〜"
	pm_install stow
}

install_delta() {
	if command -v delta >/dev/null 2>&1; then
		echo "[delta] 既に入ってるよ〜 ($(delta --version))"
		return
	fi
	echo "[delta] インストールするね〜"
	if command -v apt-get >/dev/null 2>&1; then
		# Ubuntu 22.04+ / Debian 12+ は git-delta パッケージあり
		pm_install git-delta || pm_install delta
	else
		pm_install git-delta
	fi
}

install_gcm() {
	if command -v git-credential-manager >/dev/null 2>&1; then
		echo "[GCM] 既に入ってるよ〜 ($(git-credential-manager --version 2>/dev/null | head -1))"
		return
	fi
	echo "[GCM] git-credential-manager をインストールするね〜"

	local arch
	case "$(uname -m)" in
		x86_64)  arch="amd64"  ;;
		aarch64) arch="arm64"  ;;
		*) echo "[GCM][error] 未対応の arch: $(uname -m)" >&2; return 1 ;;
	esac

	if ! command -v apt-get >/dev/null 2>&1; then
		echo "[GCM][warn] apt 以外は自動対応してない。https://github.com/git-ecosystem/git-credential-manager/releases を参考に手動インストールしてね〜" >&2
		return 1
	fi

	local api="https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest"
	local deb_url
	deb_url=$(curl -sL "$api" \
		| grep -oE "https://[^\"]*gcm-linux_${arch}[^\"]*\.deb" \
		| head -1)

	if [[ -z "$deb_url" ]]; then
		echo "[GCM][error] 最新 .deb の URL を取得できなかった" >&2
		return 1
	fi

	local tmp
	tmp=$(mktemp --suffix=.deb)
	trap 'rm -f "$tmp"' RETURN
	curl -sL -o "$tmp" "$deb_url"
	sudo dpkg -i "$tmp" || sudo apt-get install -f -y
	git-credential-manager configure
	echo "[GCM] 完了〜！ WSL なら Windows 側の Credential Manager に保存されるよ〜"
}

install_deps() {
	install_stow
	install_delta
	install_gcm
}

# ----- stow 実行 -----

run_stow() {
	local flag="$1"
	shift
	local package="$1"

	if [[ ! -d "${DOTFILES_DIR}/${package}" ]]; then
		echo "[skip] ${package} パッケージが存在しない"
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
		echo "[phase 1] dry-run で衝突を確認するよ〜"
		for pkg in "${PACKAGES[@]}"; do run_stow "--no --stow" "${pkg}"; done
		echo "[phase 2] 実リンクを張るよ〜"
		for pkg in "${PACKAGES[@]}"; do run_stow "-S" "${pkg}"; done
		echo "[done] オタクくん、完了〜！"
		echo ""
		echo "[hint] delta / GCM など外部ツールがまだなら:"
		echo "  ./install.sh --deps"
		;;
esac
