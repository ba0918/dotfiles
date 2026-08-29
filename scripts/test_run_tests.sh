#!/usr/bin/env bash
#
# Test harness for scripts/run-tests.sh (the single entry point for every test suite)
#
# The runner exists so that "run the tests" is one command for humans, the
# mise task and CI alike. What matters is asserted here from fixture suites
# (RUN_TESTS_PYTEST_DIR / RUN_TESTS_HARNESS_DIR overrides), so the harness never
# runs the real suites: every suite runs even after an earlier one fails, a
# single failure makes the whole run fail, and an empty suite set is an error
# rather than a silent pass.
#
# Usage: bash scripts/test_run_tests.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/run-tests.sh"

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

# --- fixtures -----------------------------------------------------------------

PY_OK="${TMP}/py-ok"
mkdir -p "${PY_OK}"
printf 'def test_ok():\n    assert True\n' > "${PY_OK}/test_ok.py"

PY_BAD="${TMP}/py-bad"
mkdir -p "${PY_BAD}"
printf 'def test_bad():\n    assert False\n' > "${PY_BAD}/test_bad.py"

HARNESS_OK="${TMP}/harness-ok"
mkdir -p "${HARNESS_OK}"
printf '#!/usr/bin/env bash\necho "1 passed, 0 failed"\n' > "${HARNESS_OK}/test_a.sh"
printf '#!/usr/bin/env bash\necho "1 passed, 0 failed"\n' > "${HARNESS_OK}/test_b.sh"

HARNESS_BAD="${TMP}/harness-bad"
mkdir -p "${HARNESS_BAD}"
printf '#!/usr/bin/env bash\necho "0 passed, 1 failed"\nexit 1\n' > "${HARNESS_BAD}/test_a_fails.sh"
printf '#!/usr/bin/env bash\necho "MARKER_B_RAN"\n' > "${HARNESS_BAD}/test_b_after.sh"

HARNESS_EMPTY="${TMP}/harness-empty"
mkdir -p "${HARNESS_EMPTY}"

run() {
	set +e
	OUT="$(RUN_TESTS_PYTEST_DIR="$1" RUN_TESTS_HARNESS_DIR="$2" "${SCRIPT}" 2>&1)"
	RC=$?
	set -e
}

# --- everything green: exit 0 and every suite is reported ---------------------

run "${PY_OK}" "${HARNESS_OK}"
check "all suites passing exits 0" '[ "${RC}" -eq 0 ]'
check "each bash harness is named in the report" 'grep -q "test_a.sh" <<<"${OUT}" && grep -q "test_b.sh" <<<"${OUT}"'
check "the pytest suite is named in the report" 'grep -q "pytest" <<<"${OUT}"'

# --- one failing harness: the run fails, later suites still run ---------------

run "${PY_OK}" "${HARNESS_BAD}"
check "a failing bash harness makes the run fail" '[ "${RC}" -ne 0 ]'
check "suites after a failure still run" 'grep -q "MARKER_B_RAN" <<<"${OUT}"'
check "the failing suite is named as failed" 'grep -q "FAIL.*test_a_fails.sh" <<<"${OUT}"'

# --- failing pytest: the run fails --------------------------------------------

run "${PY_BAD}" "${HARNESS_OK}"
check "a failing pytest suite makes the run fail" '[ "${RC}" -ne 0 ]'

# --- nothing to run is an error, never a silent pass --------------------------

run "${PY_OK}" "${HARNESS_EMPTY}"
check "no bash harness found is an error" '[ "${RC}" -ne 0 ] && grep -qi "no test harness" <<<"${OUT}"'

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
