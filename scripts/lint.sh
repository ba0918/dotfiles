#!/usr/bin/env bash
#
# Run shellcheck over every tracked bash script.
#
# Targets are picked by shebang from the git index rather than from a file
# list, so a new script is linted the moment it is committed and nobody has to
# remember to register it. Repository-wide exclusions live in .shellcheckrc.
#
# Usage: bash scripts/lint.sh
#
# Overrides (testing):
#   LINT_REPO   repository to lint in place of this one

set -euo pipefail

REPO="${LINT_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! command -v shellcheck >/dev/null 2>&1; then
	echo "error: shellcheck is not on PATH (mise bootstrap installs it)" >&2
	exit 1
fi

cd "${REPO}"

mapfile -t targets < <(git ls-files -z | xargs -0 grep -lE '^#!(/usr/bin/env bash|/bin/bash)' 2>/dev/null || true)

if [ "${#targets[@]}" -eq 0 ]; then
	echo "no bash scripts tracked in ${REPO}"
	exit 0
fi

printf 'shellcheck: %d script(s)\n' "${#targets[@]}"
shellcheck "${targets[@]}"
