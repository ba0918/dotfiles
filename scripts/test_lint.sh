#!/usr/bin/env bash
#
# Test harness for scripts/lint.sh (shellcheck over every tracked bash script)
#
# The linter picks its targets by shebang from the git index, so nobody has to
# maintain a file list. Asserted from a fixture repository (LINT_REPO override):
# a tracked bash script with a defect fails the run, a clean tree passes, and a
# file without a bash shebang is not linted even if it looks like shell.
#
# Usage: bash scripts/test_lint.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/lint.sh"

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

fixture_repo() {
	local dir="$1"
	git -c init.defaultBranch=main init -q "${dir}"
}

run() {
	set +e
	OUT="$(LINT_REPO="$1" "${SCRIPT}" 2>&1)"
	RC=$?
	set -e
}

# --- clean tree passes --------------------------------------------------------

CLEAN="${TMP}/clean"
fixture_repo "${CLEAN}"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho "ok"\n' > "${CLEAN}/good.sh"
git -C "${CLEAN}" add good.sh
run "${CLEAN}"
check "a clean bash script passes" '[ "${RC}" -eq 0 ]'

# --- a defect in a tracked bash script fails ----------------------------------

DIRTY="${TMP}/dirty"
fixture_repo "${DIRTY}"
# SC2086: unquoted variable in a command position
printf '#!/usr/bin/env bash\nx="a b"\nls $x\n' > "${DIRTY}/bad.sh"
git -C "${DIRTY}" add bad.sh
run "${DIRTY}"
check "a shellcheck finding fails the run" '[ "${RC}" -ne 0 ] && grep -q "SC2086" <<<"${OUT}"'

# --- only bash shebangs are targets -------------------------------------------

OTHER="${TMP}/other"
fixture_repo "${OTHER}"
printf '#!/usr/bin/env fish\nset x "a b"\n' > "${OTHER}/script.fish"
printf 'x="a b"\nls $x\n' > "${OTHER}/no-shebang.sh"
git -C "${OTHER}" add script.fish no-shebang.sh
run "${OTHER}"
check "files without a bash shebang are not linted" '[ "${RC}" -eq 0 ]'

# --- an untracked file is not a target ----------------------------------------

printf '#!/usr/bin/env bash\nx="a b"\nls $x\n' > "${CLEAN}/untracked.sh"
run "${CLEAN}"
check "an untracked bash script is not linted" '[ "${RC}" -eq 0 ]'

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
