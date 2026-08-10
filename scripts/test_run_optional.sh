#!/usr/bin/env bash
#
# Test harness for ai/shared/hooks/run-optional.sh
#
# The wrapper guards agent hooks whose dependencies this repository does not
# install. Two properties matter and are asserted here: a missing dependency is
# a silent success (hooks fire on every event, so noise is not acceptable), and
# a present dependency runs with its exit status propagated (a broken
# dependency must stay visible instead of being swallowed).
#
# Usage: bash scripts/test_run_optional.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/ai/shared/hooks/run-optional.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

pass=0
fail=0

check() {
	local desc="$1"
	local cond="$2"
	if eval "${cond}"; then
		pass=$((pass + 1))
		printf 'PASS: %s\n' "${desc}"
	else
		fail=$((fail + 1))
		printf 'FAIL: %s\n' "${desc}" >&2
	fi
}

if [ ! -x "${SCRIPT}" ]; then
	printf 'FAIL: %s does not exist or is not executable\n' "${SCRIPT}" >&2
	exit 1
fi

# Capture stdout+stderr and exit status of one invocation.
run() {
	set +e
	OUT="$("${SCRIPT}" "$@" 2>&1)"
	RC=$?
	set -e
}

GUARD_FILE="${TMP}/present.txt"
echo "present" > "${GUARD_FILE}"
GUARD_DIR="${TMP}/present-dir"
mkdir -p "${GUARD_DIR}"
MISSING="${TMP}/absent"

# --- missing dependency: silent success --------------------------------------
run "${MISSING}" -- echo RAN
check "missing guard exits 0" '[ "${RC}" -eq 0 ]'
check "missing guard produces no output" '[ -z "${OUT}" ]'
check "missing guard does not run the command" '[ "${OUT}" != "RAN" ]'

# --- present dependency: command runs ----------------------------------------
run "${GUARD_FILE}" -- echo RAN
check "present guard runs the command" '[ "${OUT}" = "RAN" ]'
check "present guard exits 0 on success" '[ "${RC}" -eq 0 ]'

run "${GUARD_DIR}" -- echo RAN
check "a directory works as a guard" '[ "${OUT}" = "RAN" ]'

# --- exit status of the wrapped command is propagated ------------------------
run "${GUARD_FILE}" -- sh -c 'exit 3'
check "command exit status propagates" '[ "${RC}" -eq 3 ]'

# --- arguments reach the command intact --------------------------------------
run "${GUARD_FILE}" -- printf '%s|%s' one "two three"
check "arguments with spaces survive" '[ "${OUT}" = "one|two three" ]'

# --- --cd changes directory --------------------------------------------------
run --cd "${GUARD_DIR}" "${GUARD_FILE}" -- pwd
check "--cd runs the command in that directory" '[ "${OUT}" = "$(cd "${GUARD_DIR}" && pwd)" ]'

# --- --cd to a missing directory is also a silent skip -----------------------
run --cd "${TMP}/no-such-dir" "${GUARD_FILE}" -- echo RAN
check "--cd to a missing directory exits 0" '[ "${RC}" -eq 0 ]'
check "--cd to a missing directory stays silent" '[ -z "${OUT}" ]'

# --- tilde in the guard is expanded even when quoted -------------------------
# Hook command strings are shell-expanded, but a quoted "~/x" is not; the
# wrapper has to handle that spelling itself.
HOME="${TMP}" run '~/present.txt' -- echo RAN
check "quoted tilde guard resolves against HOME" '[ "${OUT}" = "RAN" ]'

HOME="${TMP}" run '~/nope.txt' -- echo RAN
check "quoted tilde guard skips when absent" '[ "${RC}" -eq 0 ] && [ -z "${OUT}" ]'

# --- usage errors are loud (exit 2), never silent ----------------------------
run
check "no arguments is a usage error" '[ "${RC}" -eq 2 ]'

run "${GUARD_FILE}"
check "missing -- is a usage error" '[ "${RC}" -eq 2 ]'

run "${GUARD_FILE}" --
check "missing command after -- is a usage error" '[ "${RC}" -eq 2 ]'

run --cd
check "--cd without a directory is a usage error" '[ "${RC}" -eq 2 ]'

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
