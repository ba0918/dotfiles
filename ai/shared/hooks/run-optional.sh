#!/usr/bin/env bash
#
# Run a hook command only when its dependency is present.
#
# Several agent hooks call into things this repository does not install:
# a status line script, a notifier living in a separate repository, a helper
# owned by another tool. On a freshly bootstrapped machine those paths do not
# exist yet, and the agent surfaces a "command not found" error on every single
# event. This wrapper turns that into a silent no-op.
#
# The guard is deliberately explicit rather than inferred from the command: the
# thing to test for is often a directory or a module, not the executable itself.
#
# Usage:
#   run-optional.sh [--cd DIR] GUARD -- COMMAND [ARGS...]
#
#   GUARD    path that must exist for COMMAND to run (file or directory)
#   --cd DIR change into DIR before running COMMAND (must exist as well)
#
# Exit status: COMMAND's status when it runs, 0 when the guard is missing.
# Failures of COMMAND itself are propagated so a broken dependency stays visible.

set -euo pipefail

# Hook command strings are shell-expanded by the agent, but a quoted "~/x" is
# not. Expand a leading tilde here so both spellings behave the same.
expand_tilde() {
	case "$1" in
		"~/"*) printf '%s\n' "${HOME}/${1#\~/}" ;;
		"~") printf '%s\n' "${HOME}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}

CD_DIR=""

while [ $# -gt 0 ]; do
	case "$1" in
		--cd)
			shift
			[ $# -gt 0 ] || { echo "run-optional: --cd requires a directory" >&2; exit 2; }
			CD_DIR="$(expand_tilde "$1")"
			shift
			;;
		--)
			echo "run-optional: missing GUARD before --" >&2
			exit 2
			;;
		*)
			break
			;;
	esac
done

[ $# -gt 0 ] || { echo "run-optional: missing GUARD" >&2; exit 2; }
GUARD="$(expand_tilde "$1")"
shift

[ "${1:-}" = "--" ] || { echo "run-optional: expected -- after GUARD" >&2; exit 2; }
shift

[ $# -gt 0 ] || { echo "run-optional: missing COMMAND after --" >&2; exit 2; }

# Dependency absent: nothing to do. Stay silent — this runs on every hook event
# and the machine is not in a broken state, the feature is simply not installed.
[ -e "$GUARD" ] || exit 0

if [ -n "$CD_DIR" ]; then
	[ -d "$CD_DIR" ] || exit 0
	cd "$CD_DIR"
fi

exec "$@"
