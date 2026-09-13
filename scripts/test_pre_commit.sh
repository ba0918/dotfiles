#!/usr/bin/env bash
#
# Test harness for git/.config/git/template/hooks/pre-commit (secretlint gate
# and environment-specific term gate)
#
# The hook must not depend on what `secretlint` resolves to on PATH: it runs
# the binary installed next to the dotfiles config (git/.config/secretlint/
# node_modules). Asserted from a fixture repository and a fixture
# XDG_CONFIG_HOME, with PATH stripped of any secretlint: a clean staged file
# passes, a staged fake credential is rejected, a missing install is rejected
# with the command that fixes it, and a project-local config takes precedence.
#
# The term gate reads its list from a fixture XDG_STATE_HOME holding a made-up
# term: staged added lines and staged paths containing it are rejected,
# removed lines are not, and a missing or blank list rejects the commit.
#
# Needs the repo-local install present (`npm ci` in git/.config/secretlint,
# done by `mise run bootstrap`).
#
# Usage: bash scripts/test_pre_commit.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/git/.config/git/template/hooks/pre-commit"
SECRETLINT_DIR="${ROOT}/git/.config/secretlint"

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

if [ ! -x "${HOOK}" ]; then
	printf 'FAIL: %s does not exist or is not executable\n' "${HOOK}" >&2
	exit 1
fi
if [ ! -x "${SECRETLINT_DIR}/node_modules/.bin/secretlint" ]; then
	printf 'FAIL: %s/node_modules is missing (run: npm ci --prefix %s)\n' "${SECRETLINT_DIR}" "${SECRETLINT_DIR}" >&2
	exit 1
fi

# --- fixtures -----------------------------------------------------------------

# A config home that mirrors ~/.config/secretlint as dotfiles deploys it.
CONFIG_HOME="${TMP}/config"
mkdir -p "${CONFIG_HOME}/secretlint"
cp "${SECRETLINT_DIR}/.secretlintrc.json" "${CONFIG_HOME}/secretlint/"
ln -s "${SECRETLINT_DIR}/node_modules" "${CONFIG_HOME}/secretlint/node_modules"

# A config home with the config but no install.
BARE_HOME="${TMP}/bare"
mkdir -p "${BARE_HOME}/secretlint"
cp "${SECRETLINT_DIR}/.secretlintrc.json" "${BARE_HOME}/secretlint/"

# The fake credential (a GitHub token shape) is assembled at runtime so no
# scanner trips on this file itself.
FAKE_TOKEN="ghp_$(printf 'A%.0s' $(seq 1 36))"

# The real node binary: a mise shim on PATH would need mise and its config,
# which the isolated environments below deliberately do not carry.
NODE_BIN="$(mise which node 2>/dev/null || command -v node)"

# PATH without any secretlint (only the tools the hook calls): the hook must
# not find one there.
CLEAN_PATH="${TMP}/bin"
mkdir -p "${CLEAN_PATH}"
for tool in git bash sed awk; do
	ln -sf "$(command -v "${tool}")" "${CLEAN_PATH}/${tool}"
done
ln -sf "${NODE_BIN}" "${CLEAN_PATH}/node"

# PATH without node either, plus a fake mise data dir whose shims provide it.
NO_NODE_PATH="${TMP}/bin-no-node"
mkdir -p "${NO_NODE_PATH}"
for tool in git bash sed awk; do
	ln -sf "$(command -v "${tool}")" "${NO_NODE_PATH}/${tool}"
done
FAKE_MISE="${TMP}/mise-data"
mkdir -p "${FAKE_MISE}/shims"
ln -sf "${NODE_BIN}" "${FAKE_MISE}/shims/node"

# A state home holding the term list the hook reads. The term is made up; the
# real list lives outside the repository.
FAKE_TERM="zyx-leak-term"
STATE_HOME="${TMP}/state"
mkdir -p "${STATE_HOME}"
printf '%s\n' "${FAKE_TERM}" > "${STATE_HOME}/leak-terms.txt"

new_repo() {
	local dir="$1"
	git -c init.defaultBranch=main init -q "${dir}"
}

# Commit what is staged without running any hook (the fixture repos may carry
# the real template hook, which would read the real term list).
commit_fixture() {
	git -C "$1" -c user.name=test -c user.email=test@example.invalid commit -q --no-verify -m fixture
}

# Run the hook inside a repo with the given XDG_CONFIG_HOME and, optionally,
# XDG_STATE_HOME (defaults to the fixture term list).
run() {
	local repo="$1"
	local config_home="$2"
	local state_home="${3:-${STATE_HOME}}"
	set +e
	OUT="$(cd "${repo}" && env -i HOME="${TMP}" PATH="${CLEAN_PATH}" XDG_CONFIG_HOME="${config_home}" XDG_STATE_HOME="${state_home}" bash "${HOOK}" 2>&1)"
	RC=$?
	set -e
}

# --- clean staged file passes -------------------------------------------------

R="${TMP}/clean"; new_repo "${R}"
echo "hello" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}"
check "a clean staged file passes" '[ "${RC}" -eq 0 ]'

# --- nothing staged is a no-op ------------------------------------------------

R="${TMP}/empty"; new_repo "${R}"
run "${R}" "${CONFIG_HOME}"
check "nothing staged exits 0" '[ "${RC}" -eq 0 ]'

# --- a staged credential is rejected ------------------------------------------

R="${TMP}/leak"; new_repo "${R}"
printf 'aws_key = "%s"\n' "${FAKE_TOKEN}" > "${R}/config.txt"; git -C "${R}" add config.txt
run "${R}" "${CONFIG_HOME}"
check "a staged fake token is rejected" '[ "${RC}" -ne 0 ]'
check "the rejection names secretlint" 'grep -qi "secretlint" <<<"${OUT}"'

# --- an unstaged credential does not block ------------------------------------

R="${TMP}/unstaged"; new_repo "${R}"
echo "ok" > "${R}/a.txt"; git -C "${R}" add a.txt
printf 'aws_key = "%s"\n' "${FAKE_TOKEN}" > "${R}/untracked.txt"
run "${R}" "${CONFIG_HOME}"
check "an unstaged file is not scanned" '[ "${RC}" -eq 0 ]'

# --- node missing from PATH: the mise shims are the fallback ------------------

R="${TMP}/nonode"; new_repo "${R}"
echo "hello" > "${R}/notes.txt"; git -C "${R}" add notes.txt
set +e
OUT="$(cd "${R}" && env -i HOME="${TMP}" PATH="${NO_NODE_PATH}" XDG_CONFIG_HOME="${CONFIG_HOME}" XDG_STATE_HOME="${STATE_HOME}" MISE_DATA_DIR="${FAKE_MISE}" bash "${HOOK}" 2>&1)"
RC=$?
set -e
check "node is found through the mise shims when absent from PATH" '[ "${RC}" -eq 0 ]'

# --- no install: fail closed and say how to fix it ----------------------------

R="${TMP}/noinstall"; new_repo "${R}"
echo "hello" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${BARE_HOME}"
check "a missing install rejects the commit" '[ "${RC}" -ne 0 ]'
check "the rejection tells how to install (mise run bootstrap)" 'grep -q "mise run bootstrap" <<<"${OUT}"'

# --- a project-local config wins over the global one --------------------------

R="${TMP}/project"; new_repo "${R}"
printf '{ "rules": [] }\n' > "${R}/.secretlintrc.json"
printf 'aws_key = "%s"\n' "${FAKE_TOKEN}" > "${R}/config.txt"
git -C "${R}" add .secretlintrc.json config.txt
run "${R}" "${CONFIG_HOME}"
check "a project-local config (no rules) takes precedence" '[ "${RC}" -eq 0 ]'

# --- renamed and non-ASCII paths reach secretlint -----------------------------

R="${TMP}/renamed-token"; new_repo "${R}"
printf 'aws_key = "%s"\n' "${FAKE_TOKEN}" > "${R}/config.txt"; git -C "${R}" add config.txt; commit_fixture "${R}"
git -C "${R}" mv config.txt moved.txt
run "${R}" "${CONFIG_HOME}"
check "a renamed file is scanned by secretlint" '[ "${RC}" -ne 0 ] && grep -qi "secretlint detected" <<<"${OUT}"'

R="${TMP}/non-ascii-clean"; new_repo "${R}"
echo "hello" > "${R}/メモ.txt"; git -C "${R}" add .
run "${R}" "${CONFIG_HOME}"
check "a clean staged file with a non-ASCII name passes" '[ "${RC}" -eq 0 ]'

# --- term gate: added lines ---------------------------------------------------

R="${TMP}/term-line"; new_repo "${R}"
printf 'path = /srv/%s/work\n' "${FAKE_TERM}" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}"
check "a staged line containing a listed term is rejected" '[ "${RC}" -ne 0 ]'
check "the rejection shows the file and the offending line" 'grep -qF "notes.txt:+path = /srv/${FAKE_TERM}/work" <<<"${OUT}"'

R="${TMP}/term-case"; new_repo "${R}"
printf 'owner: %s\n' "$(tr '[:lower:]' '[:upper:]' <<<"${FAKE_TERM}")" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}"
check "terms match regardless of letter case" '[ "${RC}" -ne 0 ] && grep -q "contain a term listed" <<<"${OUT}"'

# An added line whose text starts with "++" shows up as "+++" in the diff, the
# same prefix as a file header.
R="${TMP}/term-plusplus"; new_repo "${R}"
printf '++ %s\n' "${FAKE_TERM}" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}"
check "an added line starting with ++ is still scanned" '[ "${RC}" -ne 0 ] && grep -q "contain a term listed" <<<"${OUT}"'

R="${TMP}/term-removed"; new_repo "${R}"
printf 'keep\n%s\n' "${FAKE_TERM}" > "${R}/notes.txt"; git -C "${R}" add notes.txt; commit_fixture "${R}"
printf 'keep\n' > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}"
check "a removed line containing a listed term does not block" '[ "${RC}" -eq 0 ]'

# --- term gate: paths ---------------------------------------------------------

R="${TMP}/term-path"; new_repo "${R}"
mkdir -p "${R}/${FAKE_TERM}"; echo "hello" > "${R}/${FAKE_TERM}/notes.txt"; git -C "${R}" add .
run "${R}" "${CONFIG_HOME}"
check "a staged path containing a listed term is rejected" '[ "${RC}" -ne 0 ]'
check "the rejection shows the offending path" 'grep -qF "${FAKE_TERM}/notes.txt" <<<"${OUT}"'

R="${TMP}/term-rename"; new_repo "${R}"
echo "hello" > "${R}/notes.txt"; git -C "${R}" add notes.txt; commit_fixture "${R}"
git -C "${R}" mv notes.txt "${FAKE_TERM}.txt"
run "${R}" "${CONFIG_HOME}"
check "a file renamed to a path containing a listed term is rejected" '[ "${RC}" -ne 0 ] && grep -q "contain a term listed" <<<"${OUT}"'

NON_ASCII_STATE="${TMP}/state-non-ascii"
mkdir -p "${NON_ASCII_STATE}"
printf '%s\n' "語句サンプル" > "${NON_ASCII_STATE}/leak-terms.txt"
R="${TMP}/term-non-ascii"; new_repo "${R}"
echo "hello" > "${R}/語句サンプル.txt"; git -C "${R}" add .
run "${R}" "${CONFIG_HOME}" "${NON_ASCII_STATE}"
check "a non-ASCII term in a staged path is rejected" '[ "${RC}" -ne 0 ]'
check "the rejection shows the non-ASCII path unquoted" 'grep -qF "語句サンプル.txt" <<<"${OUT}"'

# --- term gate: the list itself -----------------------------------------------

R="${TMP}/term-nolist"; new_repo "${R}"
echo "hello" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}" "${TMP}/state-missing"
check "a missing term list rejects the commit" '[ "${RC}" -ne 0 ]'
check "the rejection names where the list is expected" 'grep -qF "${TMP}/state-missing/leak-terms.txt" <<<"${OUT}"'

BLANK_STATE="${TMP}/state-blank"
mkdir -p "${BLANK_STATE}"
printf '\n  \n\t\n' > "${BLANK_STATE}/leak-terms.txt"
run "${R}" "${CONFIG_HOME}" "${BLANK_STATE}"
check "a term list with only blank lines rejects the commit" '[ "${RC}" -ne 0 ] && grep -q "no terms in" <<<"${OUT}"'

# The list is written by hand: blank lines and stray spaces must neither match
# everything nor stop the term from matching.
PADDED_STATE="${TMP}/state-padded"
mkdir -p "${PADDED_STATE}"
printf '\n  %s  \n\n' "${FAKE_TERM}" > "${PADDED_STATE}/leak-terms.txt"
run "${R}" "${CONFIG_HOME}" "${PADDED_STATE}"
check "blank lines in the term list do not match every line" '[ "${RC}" -eq 0 ]'
R="${TMP}/term-padded"; new_repo "${R}"
printf 'dir: %s\n' "${FAKE_TERM}" > "${R}/notes.txt"; git -C "${R}" add notes.txt
run "${R}" "${CONFIG_HOME}" "${PADDED_STATE}"
check "a term padded with spaces in the list still matches" '[ "${RC}" -ne 0 ] && grep -q "contain a term listed" <<<"${OUT}"'

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
