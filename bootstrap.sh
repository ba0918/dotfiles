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
# Resolves {{ config_root }} in the global config so dotfile templates render
# with repo-root paths (used by ai/opencode/opencode.json instructions).
export MISE_GLOBAL_CONFIG_ROOT="${REPO_ROOT}"

# Guard: dotfile templates depend on MISE_GLOBAL_CONFIG_ROOT == repo root. If an
# inherited shell value differs (or an env-less invocation slipped through), a
# render would silently write wrong absolute paths. Refuse to apply in that case.
if [ "${DRY_RUN}" = false ] && [ "${MISE_GLOBAL_CONFIG_ROOT}" != "${REPO_ROOT}" ]; then
	echo "bootstrap: aborting because MISE_GLOBAL_CONFIG_ROOT (${MISE_GLOBAL_CONFIG_ROOT}) != repo root (${REPO_ROOT})" >&2
	echo "bootstrap: dotfile templates (ai/opencode/opencode.json) would render with wrong paths" >&2
	exit 1
fi

mise trust "${MISE_GLOBAL_CONFIG_FILE}"

mise bootstrap "$@"

# Clipboard2path service: unit / wl-paste wrapper はツールの init が生成する。
# fish hook は dotfiles 管理なので --no-hook（冪等 — 再実行しても既存は上書き）。
if [ "${DRY_RUN}" = false ]; then
	mise x aqua:ba0918/clipboard2path-wsl -- init --no-hook 2>/dev/null || \
		clipboard2path-wsl init --no-hook 2>/dev/null || true
fi

# Aikido Safe Chain: npm/yarn/pnpm/bun/pip 等のパッケージマネージャをラップし、
# マルウェア検知と最小リリース年齢（デフォルト 48h）を適用する。
# インストールは sha256 検証付き（実体は ~/.safe-chain/）。未導入でも失敗しても全体は止めない。
# config.fish 側は "$HOME/.safe-chain/..." が存在する場合のみ source する。
if [ "${DRY_RUN}" = false ]; then
	if [ ! -x "$HOME/.safe-chain/bin/safe-chain" ]; then
		SAFE_CHAIN_VERSION="1.5.15"
		SAFE_CHAIN_SHA256="de0565e3d6346407a604e84e639e95fea8758748063da2216bbfdca5feda5dd2"
		echo "safe-chain: installing v${SAFE_CHAIN_VERSION}"
		if curl -fsSL "https://github.com/AikidoSec/safe-chain/releases/download/${SAFE_CHAIN_VERSION}/install-safe-chain.sh" -o /tmp/install-safe-chain.sh \
			&& echo "${SAFE_CHAIN_SHA256}  /tmp/install-safe-chain.sh" | sha256sum -c - >/dev/null; then
			sh /tmp/install-safe-chain.sh || echo "safe-chain: install failed (continuing)"
		else
			echo "safe-chain: install script checksum verification failed (skipping)"
		fi
		rm -f /tmp/install-safe-chain.sh
	fi
fi
