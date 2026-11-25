#!/usr/bin/env bash
#
# Bring the user-scope rule skills in line with ai/apm/apm.yml: follow the
# unpinned entries to their latest state, hold the pinned ones at their pin.
#
# `apm update -g --yes` without package names does not hold a pin. For an entry
# written as `owner/repo#<commit>` it looks for a newer release tag upstream,
# rewrites the hash in apm.yml and deploys that release. So the update is given
# the unpinned entries by name, and `apm install -g` then deploys everything
# else at the commit the manifest and the lock name.
#
# Usage: bash scripts/apm-sync.sh
#
# Overrides (testing):
#   APM_SYNC_MANIFEST   manifest to read in place of ai/apm/apm.yml

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${APM_SYNC_MANIFEST:-${ROOT}/ai/apm/apm.yml}"

if [ ! -f "${MANIFEST}" ]; then
	echo "error: apm manifest not found: ${MANIFEST}" >&2
	exit 1
fi

# The entries of dependencies.apm, one per line, without the list marker and
# without a trailing comment. The regexes stay POSIX: mawk is the default awk
# on Debian and Ubuntu.
entries() {
	awk '
		/^dependencies:/ { in_deps = 1; next }
		/^[^[:space:]#]/ { in_deps = 0; in_apm = 0 }
		in_deps && /^  apm:/ { in_apm = 1; next }
		in_apm && /^[[:space:]]*(#.*)?$/ { next }
		in_apm && /^    -[[:space:]]+/ {
			sub(/^    -[[:space:]]+/, "")
			sub(/[[:space:]]+#.*$/, "")
			sub(/[[:space:]]+$/, "")
			print
			next
		}
		in_apm { in_apm = 0 }
	' "${MANIFEST}"
}

unpinned=()
total=0
while IFS= read -r entry; do
	[ -n "${entry}" ] || continue
	total=$((total + 1))
	case "${entry}" in
		*"#"*) ;;
		*) unpinned+=("${entry}") ;;
	esac
done < <(entries)

# A manifest that yields nothing is a broken manifest or a broken parser, and
# must not pass as "nothing to do".
if [ "${total}" -eq 0 ]; then
	echo "error: no dependencies.apm entries found in ${MANIFEST}" >&2
	exit 1
fi

# Never call update without names: that form moves the pins.
if [ "${#unpinned[@]}" -gt 0 ]; then
	apm update -g --yes "${unpinned[@]}"
fi

apm install -g
