#!/usr/bin/env bash
#
# dotfiles bootstrap - one-shot setup for a fresh machine.
#
# Sets MISE_GLOBAL_CONFIG_FILE relative to this repo's location, trusts the
# config, and runs `mise bootstrap`, so the repo can live at any directory
# (clone location does not need to be fixed). After the first run, interactive
# fish shells pick up the same variable from config.fish.
#
# Bundled apt repos (apt/*.sources) are installed into /etc/apt/sources.list.d/
# if missing; this requires sudo and prompts for a password on a fresh machine.
#
# Usage:
#   ./bootstrap.sh            Apply packages, dotfiles, and tools
#   ./bootstrap.sh --dry-run  Show what would happen
#   ./bootstrap.sh --help     Show this help

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
	--help|-h)
		sed -n '2,16p' "${BASH_SOURCE[0]}"
		exit 0
		;;
esac

DRY_RUN=false
case "${1:-}" in
	--dry-run)
		DRY_RUN=true
		;;
esac

# Install bundled apt repos (apt/*.sources) into /etc/apt/sources.list.d/.
install_apt_repos() {
	local repo updated=false
	for repo in "${REPO_ROOT}"/apt/*.sources; do
		[ -e "${repo}" ] || continue
		if [ ! -e "/etc/apt/sources.list.d/$(basename "${repo}")" ]; then
			echo "apt: installing $(basename "${repo}")"
			if [ "${DRY_RUN}" = false ]; then
				sudo cp "${repo}" /etc/apt/sources.list.d/
				updated=true
			fi
		fi
	done
	if [ "${updated}" = true ]; then
		echo "apt: updating package lists"
		sudo apt-get update
	fi
}

install_apt_repos

export MISE_GLOBAL_CONFIG_FILE="${REPO_ROOT}/mise/config.toml"
# 自作ツールの aqua カスタムレジストリはツール repo が公開する URL を参照
export MISE_AQUA_REGISTRIES="https://raw.githubusercontent.com/ba0918/clipboard2path-wsl/main/registry.yaml"
mise trust "${MISE_GLOBAL_CONFIG_FILE}"

mise bootstrap "$@"

# Clipboard2path service: unit / wl-paste wrapper はツールの init が生成する。
# fish hook は dotfiles 管理なので --no-hook（冪等 — 再実行しても既存は上書き）。
if [ "${DRY_RUN}" = false ]; then
	mise x aqua:ba0918/clipboard2path-wsl -- init --no-hook 2>/dev/null || \
		clipboard2path-wsl init --no-hook 2>/dev/null || true
fi
