#!/usr/bin/env bash
#
# Run every test suite of this repository: the pytest suite for the security
# hooks and each bash harness under scripts/test_*.sh.
#
# This is the single entry point shared by `mise run test` and CI. Every suite
# runs even when an earlier one fails, so one run shows the whole picture; the
# exit status is non-zero if any suite failed. Finding no suite at all is an
# error, never a pass: an empty run must not look green.
#
# Usage: bash scripts/run-tests.sh
#
# Overrides (testing):
#   RUN_TESTS_PYTEST_DIRS  colon-separated pytest targets in place of the defaults
#   RUN_TESTS_HARNESS_DIR  directory holding test_*.sh in place of scripts/

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Colon-separated: pytest suites live wherever the code they cover lives, so
# the list grows as packages gain tests. Each runs as its own suite, keeping
# the report readable and one failure from hiding the others.
PYTEST_DIRS="${RUN_TESTS_PYTEST_DIRS:-${ROOT}/ai/shared/hooks/tests:${ROOT}/ai/claude/tests}"
HARNESS_DIR="${RUN_TESTS_HARNESS_DIR:-${ROOT}/scripts}"

failed=()
ran=0

report() {
	local status="$1"
	local name="$2"
	printf '\n==== %s: %s\n' "${status}" "${name}"
}

run_suite() {
	local name="$1"
	shift
	printf '\n---- %s\n' "${name}"
	ran=$((ran + 1))
	if "$@"; then
		report PASS "${name}"
	else
		failed+=("${name}")
		report FAIL "${name}"
	fi
}

if ! command -v pytest >/dev/null 2>&1; then
	echo "error: pytest is not on PATH (mise bootstrap installs pipx:pytest)" >&2
	exit 1
fi

IFS=':' read -r -a pytest_dirs <<<"${PYTEST_DIRS}"
for dir in "${pytest_dirs[@]}"; do
	[ -n "${dir}" ] || continue
	if [ ! -d "${dir}" ]; then
		echo "error: pytest directory not found: ${dir}" >&2
		exit 1
	fi
	run_suite "pytest ${dir}" pytest -q "${dir}"
done

harnesses=("${HARNESS_DIR}"/test_*.sh)
if [ ! -e "${harnesses[0]}" ]; then
	echo "error: no test harness found under ${HARNESS_DIR} (expected test_*.sh)" >&2
	exit 1
fi

for harness in "${harnesses[@]}"; do
	run_suite "$(basename "${harness}")" bash "${harness}"
done

printf '\n%d suites, %d failed\n' "${ran}" "${#failed[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
	printf 'failed: %s\n' "${failed[@]}" >&2
	exit 1
fi
