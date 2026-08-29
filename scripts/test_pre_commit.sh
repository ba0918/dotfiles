#!/usr/bin/env bash
#
# Test harness for git/.config/git/template/hooks/pre-commit (secretlint gate)
#
# The hook must not depend on what `secretlint` resolves to on PATH: it runs
# the binary installed next to the dotfiles config (git/.config/secretlint/
# node_modules). Asserted from a fixture repository and a fixture
# XDG_CONFIG_HOME, with PATH stripped of any secretlint: a clean staged file
# passes, a staged fake credential is rejected, a missing install is rejected
# with the command that fixes it, and a project-local config takes precedence.
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

# PATH without any secretlint: the hook must not find one there.
CLEAN_PATH="${TMP}/bin"
mkdir -p "${CLEAN_PATH}"
for tool in git bash; do
	ln -sf "$(command -v "${tool}")" "${CLEAN_PATH}/${tool}"
done
ln -sf "${NODE_BIN}" "${CLEAN_PATH}/node"

# PATH without node either, plus a fake mise data dir whose shims provide it.
NO_NODE_PATH="${TMP}/bin-no-node"
mkdir -p "${NO_NODE_PATH}"
for tool in git bash; do
	ln -sf "$(command -v "${tool}")" "${NO_NODE_PATH}/${tool}"
done
FAKE_MISE="${TMP}/mise-data"
mkdir -p "${FAKE_MISE}/shims"
ln -sf "${NODE_BIN}" "${FAKE_MISE}/shims/node"

new_repo() {
	local dir="$1"
	git -c init.defaultBranch=main init -q "${dir}"
}

# Run the hook inside a repo with the given XDG_CONFIG_HOME.
run() {
	local repo="$1"
	local config_home="$2"
	set +e
	OUT="$(cd "${repo}" && env -i HOME="${TMP}" PATH="${CLEAN_PATH}" XDG_CONFIG_HOME="${config_home}" bash "${HOOK}" 2>&1)"
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
OUT="$(cd "${R}" && env -i HOME="${TMP}" PATH="${NO_NODE_PATH}" XDG_CONFIG_HOME="${CONFIG_HOME}" MISE_DATA_DIR="${FAKE_MISE}" bash "${HOOK}" 2>&1)"
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

# --- summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
