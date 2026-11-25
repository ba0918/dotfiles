#!/usr/bin/env bash
#
# Print the content a wsl.conf needs so that systemd is enabled: the given file
# with `systemd=true` under [boot]. Nothing is written; the caller decides how
# the result reaches /etc/wsl.conf.
#
# Appending "[boot] / systemd=true" to the end of the file, as docker/install.sh
# and ssh/install.sh used to, leaves two [boot] sections whenever the file
# already has one, and two contradicting keys when that one says systemd=false.
# Here the existing section is edited instead:
#   - a systemd key under [boot] is rewritten to systemd=true, whatever it said
#   - a [boot] section without the key gets it right after the header
#   - a file without [boot] gets the section appended
#
# Usage: bash scripts/wsl-conf-systemd.sh <path to wsl.conf>
#        The file may be missing or empty.

set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "usage: wsl-conf-systemd.sh <path to wsl.conf>" >&2
	exit 2
fi

CONF="$1"

if [ ! -s "${CONF}" ]; then
	printf '[boot]\nsystemd=true\n'
	exit 0
fi

# Two passes over the same file: the first learns whether [boot] exists and
# whether it already carries the key, the second prints. The regexes stay
# POSIX: mawk is the default awk on Debian and Ubuntu.
awk '
	function is_header(line) { return line ~ /^[[:space:]]*\[/ }
	function is_boot(line) { return line ~ /^[[:space:]]*\[boot\][[:space:]]*$/ }
	function is_key(line) { return line ~ /^[[:space:]]*systemd[[:space:]]*=/ }

	FNR == NR {
		if (is_header($0)) in_boot = is_boot($0)
		if (in_boot && is_boot($0)) has_boot = 1
		if (in_boot && is_key($0)) has_key = 1
		next
	}
	FNR == 1 { in_boot = 0 }
	is_header($0) {
		in_boot = is_boot($0)
		print
		if (in_boot && !has_key && !inserted) {
			print "systemd=true"
			inserted = 1
		}
		next
	}
	in_boot && is_key($0) { print "systemd=true"; next }
	{ print }
	END {
		if (!has_boot) {
			print ""
			print "[boot]"
			print "systemd=true"
		}
	}
' "${CONF}" "${CONF}"
