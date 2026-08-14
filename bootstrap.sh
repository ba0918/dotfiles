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

# Scan every argument, not just the first. `mise bootstrap` accepts subcommands
# before its flags (e.g. `bootstrap.sh dotfiles --dry-run`), and treating that as
# a real run would let the destructive post-steps below execute during a dry run.
DRY_RUN=false
for arg in "$@"; do
	case "${arg}" in
		--help|-h)
			sed -n '2,16p' "${BASH_SOURCE[0]}"
			exit 0
			;;
		--dry-run)
			DRY_RUN=true
			;;
	esac
done

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

# Dotfile templates depend on MISE_GLOBAL_CONFIG_ROOT pointing at this repo, so
# both variables are always set from REPO_ROOT here. An inherited value from
# another clone is silently replaced; say so, because the surprising outcome is a
# user who edited one checkout and saw another one applied.
if [ -n "${MISE_GLOBAL_CONFIG_ROOT:-}" ] && [ "${MISE_GLOBAL_CONFIG_ROOT}" != "${REPO_ROOT}" ]; then
	echo "bootstrap: overriding inherited MISE_GLOBAL_CONFIG_ROOT (${MISE_GLOBAL_CONFIG_ROOT}) with ${REPO_ROOT}" >&2
fi

export MISE_GLOBAL_CONFIG_FILE="${REPO_ROOT}/mise/config.toml"
# Resolves {{ config_root }} in the global config so dotfile templates render
# with repo-root paths (used by ai/opencode/opencode.json instructions).
export MISE_GLOBAL_CONFIG_ROOT="${REPO_ROOT}"

# NOTE: the invariant "MISE_GLOBAL_CONFIG_ROOT == repo root" cannot be violated
# from here — it is enforced by the two lines above. It is checked for real in
# mise/config.toml's [bootstrap.hooks.pre-dotfiles], which also covers the case
# that matters: `mise bootstrap` invoked directly, without this wrapper.

mise trust "${MISE_GLOBAL_CONFIG_FILE}"

mise bootstrap "$@"

# Clipboard2path service: unit / wl-paste wrapper はツールの init が生成する。
# fish hook は dotfiles 管理なので --no-hook（冪等 — 再実行しても既存は上書き）。
if [ "${DRY_RUN}" = false ]; then
	mise x aqua:ba0918/clipboard2path-wsl -- init --no-hook 2>/dev/null || \
		clipboard2path-wsl init --no-hook 2>/dev/null || true
fi

# Devbox global: .devbox/（生成物）が無い新規マシンでは config.fish の
# `devbox global shellenv --init-hook | source` が .hooks.sh 不在で失敗する。
# ここで事前に環境を再生成しておく（冪等 — 最新なら何もしない）。
if [ "${DRY_RUN}" = false ]; then
	mise x aqua:jetify-com/devbox -- devbox global shellenv --init-hook -r >/dev/null 2>&1 || true
fi

# Aikido Safe Chain: npm/yarn/pnpm/bun/pip 等のパッケージマネージャをラップし、
# マルウェア検知と最小リリース年齢（デフォルト 48h）を適用する。
# config.fish 側は "$HOME/.safe-chain/..." が存在する場合のみ source する。
#
# 検証チェーン（末端のバイナリまで固定される）:
#   1. SAFE_CHAIN_SHA256 で installer スクリプト自体を検証する
#   2. その installer は VERSION を自身に埋め込んでおり、追加の取得をしない
#   3. installer がプラットフォーム別バイナリの sha256 を焼き込んで検証する
# ゆえに 1 の照合が通れば導入されるバイナリまで一意に決まる。
# 版を上げるときは SAFE_CHAIN_VERSION と SAFE_CHAIN_SHA256 を必ず同時に更新すること。
#
# 未導入でも失敗しても全体は止めない（開発機のブートストラップを塞がないため）。
if [ "${DRY_RUN}" = false ] && [ ! -x "$HOME/.safe-chain/bin/safe-chain" ]; then
	SAFE_CHAIN_VERSION="1.5.15"
	SAFE_CHAIN_SHA256="de0565e3d6346407a604e84e639e95fea8758748063da2216bbfdca5feda5dd2"
	echo "safe-chain: installing v${SAFE_CHAIN_VERSION}"

	# mktemp: a fixed /tmp path is attacker-predictable on a shared host, and the
	# file is executed right after the checksum passes.
	SAFE_CHAIN_INSTALLER="$(mktemp)"
	trap 'rm -f "${SAFE_CHAIN_INSTALLER}"' EXIT

	if curl -fsSL "https://github.com/AikidoSec/safe-chain/releases/download/${SAFE_CHAIN_VERSION}/install-safe-chain.sh" -o "${SAFE_CHAIN_INSTALLER}" \
		&& echo "${SAFE_CHAIN_SHA256}  ${SAFE_CHAIN_INSTALLER}" | sha256sum -c - >/dev/null 2>&1; then
		# The installer honours an inherited SAFE_CHAIN_VERSION, which would both
		# select a different release than the one this checksum pins and switch the
		# Linux build from linuxstatic to linux. Clear it so the pin is the only
		# thing deciding what gets installed.
		if ! env -u SAFE_CHAIN_VERSION sh "${SAFE_CHAIN_INSTALLER}"; then
			echo "safe-chain: install failed (continuing)" >&2
		fi
	else
		echo "safe-chain: installer checksum verification failed (skipping)" >&2
	fi

	rm -f "${SAFE_CHAIN_INSTALLER}"
	trap - EXIT
fi
