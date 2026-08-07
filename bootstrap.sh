#!/usr/bin/env bash
#
# dotfiles bootstrap - one-shot setup for a fresh machine.
#
# Sets MISE_GLOBAL_CONFIG_FILE relative to this repo's location, trusts the
# config, and runs `mise bootstrap`, so the repo can live at any directory
# (clone location does not need to be fixed). After the first run, interactive
# fish shells pick up the same variable from config.fish.
#
# Usage:
#   ./bootstrap.sh            Apply packages, dotfiles, and tools
#   ./bootstrap.sh --dry-run  Show what would happen
#   ./bootstrap.sh --help     Show this help

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
	--help|-h)
		sed -n '2,9p' "${BASH_SOURCE[0]}"
		exit 0
		;;
esac

export MISE_GLOBAL_CONFIG_FILE="${REPO_ROOT}/mise/config.toml"
mise trust "${MISE_GLOBAL_CONFIG_FILE}"
exec mise bootstrap "$@"