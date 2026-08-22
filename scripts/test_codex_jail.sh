#!/usr/bin/env bash
#
# Test harness for ai/codex/bin/codex (the Codex jail shim)
#
# The shim owns the filesystem boundary Codex runs in. Everything below is an
# observable property of that boundary, asserted from inside the jail through
# a fake codex binary (CODEX_JAIL_BIN) that echoes its arguments and runs the
# PROBE command it is handed. No real Codex binary, network call, or home
# directory is touched: HOME is pointed at a scratch directory seeded with
# fake secrets and fake Codex state.
#
# Usage: bash scripts/test_codex_jail.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="${ROOT}/ai/codex/bin/codex"

# Scratch must not live under /tmp: /tmp is read-write inside the jail, which
# would make the "HOME is read-only" assertions pass for the wrong reason.
SCRATCH_PARENT="${XDG_RUNTIME_DIR:-${HOME}/.cache}"
mkdir -p "${SCRATCH_PARENT}"
TMP="$(mktemp -d -p "${SCRATCH_PARENT}" codex-jail-test.XXXXXX)"
WT="$(mktemp -d /tmp/codex-jail-wt.XXXXXX)"
cleanup() {
	git -C "${TMP}/main" worktree remove --force "${WT}" >/dev/null 2>&1 || true
	rm -rf "${TMP}" "${WT}"
}
trap cleanup EXIT

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

if [ ! -x "${SHIM}" ]; then
	printf 'FAIL: %s does not exist or is not executable\n' "${SHIM}" >&2
	exit 1
fi

# --- fixtures -----------------------------------------------------------------

FAKE_HOME="${TMP}/home"
mkdir -p "${FAKE_HOME}/.ssh" "${FAKE_HOME}/.codex/sessions" "${FAKE_HOME}/.codex/rules" \
	"${FAKE_HOME}/.cache" "${FAKE_HOME}/.config/gh" "${FAKE_HOME}/extra-rw" "${FAKE_HOME}/plain"
echo "PRIVATE" > "${FAKE_HOME}/.ssh/id_ed25519"
echo "token" > "${FAKE_HOME}/.config/gh/hosts.yml"
echo 'approval_policy = "never"' > "${FAKE_HOME}/.codex/config.toml"
echo "# agents" > "${FAKE_HOME}/.codex/AGENTS.md"
echo "rule" > "${FAKE_HOME}/.codex/rules/default.rules"
echo '{"a":1}' > "${FAKE_HOME}/.codex/auth.json"
mkdir -p "${FAKE_HOME}/.local/share/opencode/log" "${FAKE_HOME}/.claude/projects" "${FAKE_HOME}/.claude/hooks"
echo '{"deepseek":"k"}' > "${FAKE_HOME}/.local/share/opencode/auth.json"
echo '{"permissions":{}}' > "${FAKE_HOME}/.claude/settings.json"
echo '{}' > "${FAKE_HOME}/.claude.json"
# hooks.json is a dotfiles-managed symlink in the real home; skills is dangling.
mkdir -p "${FAKE_HOME}/dotfiles"
echo '{"hooks":[]}' > "${FAKE_HOME}/dotfiles/hooks.json"
ln -s "../dotfiles/hooks.json" "${FAKE_HOME}/.codex/hooks.json"
ln -s "/nonexistent/skills" "${FAKE_HOME}/.codex/skills"

FAKE_BIN="${TMP}/fake-codex"
cat > "${FAKE_BIN}" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS:%s\n' "$*"
printf 'JAIL:%s\n' "${CODEX_JAIL:-0}"
if [ -n "${PROBE:-}" ]; then
	bash -c "${PROBE}"
fi
EOF
chmod +x "${FAKE_BIN}"

git -c init.defaultBranch=main init -q "${TMP}/main"
git -C "${TMP}/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo "SECRET=main" > "${TMP}/main/.env"
rmdir "${WT}"
git -C "${TMP}/main" worktree add -q "${WT}" -b probe
echo "SECRET=wt" > "${WT}/.env"
echo "SECRET=local" > "${WT}/.env.local"
echo "EXAMPLE=1" > "${WT}/.env.example"
mkdir -p "${WT}/sub" "${WT}/vendor/pkg" "${WT}/node_modules/pkg"
echo "SECRET=sub" > "${WT}/sub/.env"
echo "SECRET=vendor" > "${WT}/vendor/pkg/.env"
echo "SECRET=nm" > "${WT}/node_modules/pkg/.env"

# Capture stdout+stderr and exit status of one shim invocation.
run() {
	set +e
	OUT="$(HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" "${SHIM}" "$@" 2>&1)"
	RC=$?
	set -e
}

# Run a probe inside the jail from a directory.
probe() {
	local dir="$1"
	shift
	local cmd="$1"
	shift
	set +e
	OUT="$(cd "${dir}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" PROBE="${cmd}" "${SHIM}" "$@" 2>&1)"
	RC=$?
	set -e
}

# --- routing: which invocations are jailed ------------------------------------

run --version
check "--version passes through unjailed" '[ "${RC}" -eq 0 ] && grep -q "^JAIL:0$" <<<"${OUT}"'
check "--version reaches codex unchanged" 'grep -q "^ARGS:--version$" <<<"${OUT}"'

run app-server
check "app-server passes through unjailed" 'grep -q "^JAIL:0$" <<<"${OUT}"'
check "app-server gets no bypass flag" '! grep -q "dangerously" <<<"${OUT}"'

run login status
check "login passes through unjailed" 'grep -q "^JAIL:0$" <<<"${OUT}"'

probe "${WT}" "true"
check "interactive session (no subcommand) is jailed" 'grep -q "^JAIL:1$" <<<"${OUT}"'
check "interactive session bypasses Codex sandbox and approvals" 'grep -q -- "--dangerously-bypass-approvals-and-sandbox" <<<"${OUT}"'

probe "${WT}" "true" exec "write a test"
check "exec is jailed" 'grep -q "^JAIL:1$" <<<"${OUT}"'
check "exec keeps its prompt argument after the bypass flag" 'grep -q "^ARGS:exec --dangerously-bypass-approvals-and-sandbox write a test$" <<<"${OUT}"'

probe "${WT}" "true" -m gpt-5.6-sol exec "prompt"
check "leading options do not hide the subcommand" 'grep -q "^ARGS:-m gpt-5.6-sol exec --dangerously-bypass-approvals-and-sandbox prompt$" <<<"${OUT}"'

probe "${WT}" "true" resume --last
check "resume is jailed" 'grep -q "^JAIL:1$" <<<"${OUT}"'

probe "${WT}" "true" fork --last
check "fork is jailed" 'grep -q "^JAIL:1$" <<<"${OUT}"'

run --no-alt-screen -V
check "-V among options passes through unjailed" 'grep -q "^JAIL:0$" <<<"${OUT}"'

OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_OFF=1 "${SHIM}" exec p 2>&1)"
check "CODEX_JAIL_OFF=1 runs plain codex" 'grep -q "^JAIL:0$" <<<"${OUT}" && grep -q "^ARGS:exec p$" <<<"${OUT}"'

# --- nesting: a codex started from inside the jail must not re-jail ------------

probe "${WT}" "CODEX_JAIL_BIN=${FAKE_BIN} PROBE= ${SHIM} exec inner"
check "nested codex inside the jail does not start a second jail" 'grep -q "^ARGS:exec --dangerously-bypass-approvals-and-sandbox inner$" <<<"${OUT}"'

# --- worktree: the current checkout and its shared .git are writable ----------

probe "${WT}" 'touch probe.txt && echo WT_WRITE_OK'
check "worktree is writable" 'grep -q "WT_WRITE_OK" <<<"${OUT}"'

probe "${WT}" 'touch "$(git rev-parse --git-dir)/index.lock" && rm "$(git rev-parse --git-dir)/index.lock" && echo GITDIR_OK'
check "linked worktree can take index.lock in the shared .git" 'grep -q "GITDIR_OK" <<<"${OUT}"'

# --no-verify: the global git template installs a pre-commit hook that needs
# the real home's secretlint config; the fake HOME has none, and hooks are not
# what this harness measures.
probe "${WT}" 'echo x > c.txt && git add c.txt && git -c user.email=t@t -c user.name=t commit -q --no-verify -m c && echo COMMIT_OK'
check "commit from a linked worktree under /tmp succeeds" 'grep -q "COMMIT_OK" <<<"${OUT}"'

probe "${TMP}/main" 'touch main-probe.txt && echo MAIN_OK'
check "main checkout is writable when started from it" 'grep -q "MAIN_OK" <<<"${OUT}"'

probe "${FAKE_HOME}/plain" 'touch here.txt && echo CWD_OK'
check "a non-git directory is writable as the workspace" 'grep -q "CWD_OK" <<<"${OUT}"'

# The target must not live under /tmp (writable regardless), so the main
# checkout under the scratch HOME is used: it is read-only unless selected.
probe "${FAKE_HOME}/plain" "touch ${TMP}/main/from-cd.txt && echo CD_OK" -C "${TMP}/main" exec p
check "-C <dir> selects that checkout as the workspace" 'grep -q "CD_OK" <<<"${OUT}"'

probe "${FAKE_HOME}/plain" "touch ${TMP}/main/from-cd-eq.txt && echo CDEQ_OK" "--cd=${TMP}/main" exec p
check "--cd=<dir> selects that checkout as the workspace" 'grep -q "CDEQ_OK" <<<"${OUT}"'

probe "${FAKE_HOME}/plain" "touch ${TMP}/main/x 2>/dev/null && echo OTHER_WRITABLE || echo OTHER_RO"
check "a checkout that is not the workspace is read-only" 'grep -q "OTHER_RO" <<<"${OUT}"'

probe "${WT}" 'touch "$HOME/extra-rw/z" && echo ADDDIREQ_OK' "--add-dir=${FAKE_HOME}/extra-rw"
check "--add-dir=<dir> is writable inside the jail" 'grep -q "ADDDIREQ_OK" <<<"${OUT}"'

# --- boundary: everything else is read-only or hidden -------------------------

probe "${WT}" 'touch "$HOME/leak.txt" 2>/dev/null && echo HOME_WRITABLE || echo HOME_RO'
check "HOME is read-only" 'grep -q "HOME_RO" <<<"${OUT}"'

probe "${WT}" 'touch /usr/leak 2>/dev/null && echo ROOT_WRITABLE || echo ROOT_RO'
check "system root is read-only" 'grep -q "ROOT_RO" <<<"${OUT}"'

probe "${WT}" 'touch /tmp/codex-jail-tmp-probe && rm /tmp/codex-jail-tmp-probe && echo TMP_OK'
check "/tmp is writable" 'grep -q "TMP_OK" <<<"${OUT}"'

probe "${WT}" 'echo "ssh:$(ls -A "$HOME/.ssh" | wc -l)"'
check "~/.ssh is hidden" 'grep -q "^ssh:0$" <<<"${OUT}"'

probe "${WT}" 'echo "gh:$(ls -A "$HOME/.config/gh" | wc -l)"'
check "~/.config/gh is hidden" 'grep -q "^gh:0$" <<<"${OUT}"'

# WSL: Windows drives are 9p/drvfs mounts under /mnt; /mnt/wsl holds the
# resolv.conf that /etc/resolv.conf points at and must stay visible.
mapfile -t WIN_DRIVES < <(findmnt -rn -o TARGET,FSTYPE 2>/dev/null | awk '$1 ~ "^/mnt/" && ($2 == "9p" || $2 == "drvfs") {print $1}')
for drive in "${WIN_DRIVES[@]}"; do
	probe "${WT}" "echo \"drive:\$(ls -A ${drive} | wc -l)\""
	check "Windows drive ${drive} is hidden" 'grep -q "^drive:0$" <<<"${OUT}"'
done
if [ -r /etc/resolv.conf ]; then
	probe "${WT}" 'cat /etc/resolv.conf >/dev/null && echo RESOLV_OK'
	check "/etc/resolv.conf (DNS) is still readable" 'grep -q "RESOLV_OK" <<<"${OUT}"'
fi

probe "${WT}" 'echo "env:$(wc -c < .env):$(wc -c < .env.local):$(wc -c < sub/.env)"'
check ".env files in the worktree read as empty" 'grep -q "^env:0:0:0$" <<<"${OUT}"'
check ".env files on the host are untouched" '[ "$(cat "${WT}/.env")" = "SECRET=wt" ] && [ "$(cat "${WT}/sub/.env")" = "SECRET=sub" ]'

probe "${WT}" 'echo "vendor:$(wc -c < vendor/pkg/.env)"'
check ".env under vendor/ (composer packages) is masked too" 'grep -q "^vendor:0$" <<<"${OUT}"'

probe "${WT}" 'echo "nm:$(cat node_modules/pkg/.env)"'
check ".env under node_modules/ is left alone (no secrets, huge trees)" 'grep -q "^nm:SECRET=nm$" <<<"${OUT}"'

probe "${WT}" 'echo "example:$(cat .env.example)"'
check ".env.example is not masked" 'grep -q "^example:EXAMPLE=1$" <<<"${OUT}"'

probe "${WT}" 'echo "x" >> .env 2>/dev/null && echo ENV_WRITABLE || echo ENV_RO'
check "masked .env cannot be written" 'grep -q "ENV_RO" <<<"${OUT}"'

# --- ~/.codex: state is writable, configuration is not -------------------------

probe "${WT}" 'touch "$HOME/.codex/sessions/s.jsonl" && echo "$HOME/.codex/history.jsonl" > "$HOME/.codex/history.jsonl" && echo STATE_OK'
check "~/.codex state (sessions, history) is writable" 'grep -q "STATE_OK" <<<"${OUT}"'

probe "${WT}" 'echo "{}" > "$HOME/.codex/auth.json" && echo AUTH_OK'
check "~/.codex/auth.json is writable (token refresh)" 'grep -q "AUTH_OK" <<<"${OUT}"'

probe "${WT}" 'echo "x" >> "$HOME/.codex/config.toml" 2>/dev/null && echo CONFIG_WRITABLE || echo CONFIG_RO'
check "~/.codex/config.toml is read-only" 'grep -q "CONFIG_RO" <<<"${OUT}"'

probe "${WT}" 'echo "x" >> "$HOME/.codex/AGENTS.md" 2>/dev/null && echo AGENTS_WRITABLE || echo AGENTS_RO'
check "~/.codex/AGENTS.md is read-only" 'grep -q "AGENTS_RO" <<<"${OUT}"'

probe "${WT}" 'touch "$HOME/.codex/rules/new.rules" 2>/dev/null && echo RULES_WRITABLE || echo RULES_RO'
check "~/.codex/rules/ is read-only" 'grep -q "RULES_RO" <<<"${OUT}"'

probe "${WT}" 'grep -q never "$HOME/.codex/config.toml" && echo CONFIG_READ_OK'
check "~/.codex/config.toml is still readable" 'grep -q "CONFIG_READ_OK" <<<"${OUT}"'

probe "${WT}" 'grep -q hooks "$HOME/.codex/hooks.json" && echo HOOKS_READ_OK'
check "a symlinked ~/.codex/hooks.json is readable through the link" 'grep -q "HOOKS_READ_OK" <<<"${OUT}"'

probe "${WT}" 'echo "x" >> "$HOME/.codex/hooks.json" 2>/dev/null && echo HOOKS_WRITABLE || echo HOOKS_RO'
check "a symlinked ~/.codex/hooks.json cannot be written through the link" 'grep -q "HOOKS_RO" <<<"${OUT}"'

probe "${WT}" 'echo DANGLING_OK'
check "a dangling symlink under ~/.codex does not break the jail" 'grep -q "DANGLING_OK" <<<"${OUT}"'

# --- other agent CLIs hosted inside the jail (shipped jail.conf) ----------------

probe "${WT}" 'touch "$HOME/.local/share/opencode/log/opencode.log" && echo OC_LOG_OK'
check "opencode can write its log under ~/.local/share/opencode" 'grep -q "OC_LOG_OK" <<<"${OUT}"'

probe "${WT}" 'echo "{}" > "$HOME/.local/share/opencode/auth.json" && echo OC_AUTH_OK'
check "opencode auth.json stays writable (token refresh)" 'grep -q "OC_AUTH_OK" <<<"${OUT}"'

probe "${WT}" 'touch "$HOME/.claude/projects/p.jsonl" && echo "{}" > "$HOME/.claude.json" && echo CL_STATE_OK'
check "claude code state (~/.claude, ~/.claude.json) is writable" 'grep -q "CL_STATE_OK" <<<"${OUT}"'

probe "${WT}" 'echo "x" >> "$HOME/.claude/settings.json" 2>/dev/null && echo CL_SETTINGS_WRITABLE || echo CL_SETTINGS_RO'
check "claude code settings.json is read-only" 'grep -q "CL_SETTINGS_RO" <<<"${OUT}"'

probe "${WT}" 'touch "$HOME/.claude/hooks/new.sh" 2>/dev/null && echo CL_HOOKS_WRITABLE || echo CL_HOOKS_RO'
check "claude code hooks/ is read-only" 'grep -q "CL_HOOKS_RO" <<<"${OUT}"'

# --- jail.conf: the mount table is data, overridable with CODEX_JAIL_CONF -------

CONF="${TMP}/custom.conf"
mkdir -p "${FAKE_HOME}/conf-rw/inner" "${FAKE_HOME}/conf-hide"
echo "v" > "${FAKE_HOME}/conf-rw/inner/locked"
echo "s" > "${FAKE_HOME}/conf-hide/secret"
cat > "${CONF}" <<EOF_CONF
# comment line

rw ~/conf-rw
ro ~/conf-rw/inner/locked
hide ~/conf-hide
rw ~/does-not-exist
EOF_CONF
OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_CONF="${CONF}" \
	PROBE='touch "$HOME/conf-rw/a" && echo RW_OK; echo x >> "$HOME/conf-rw/inner/locked" 2>/dev/null && echo RO_WRITABLE || echo RO_OK; echo "hidden:$(ls -A "$HOME/conf-hide" | wc -l)"; ls -A "$HOME/.ssh" | wc -l | sed "s/^/ssh:/"' "${SHIM}" 2>&1)" || true
check "jail.conf rw directive binds read-write (~ expanded)" 'grep -q "RW_OK" <<<"${OUT}"'
check "jail.conf ro directive overlays read-only inside an rw bind" 'grep -q "RO_OK" <<<"${OUT}"'
check "jail.conf hide directive blanks a directory" 'grep -q "^hidden:0$" <<<"${OUT}"'
check "jail.conf rw of a missing path is skipped, not fatal" 'grep -q "RW_OK" <<<"${OUT}"'
check "a custom jail.conf replaces the shipped one (~/.ssh no longer hidden)" 'grep -q "^ssh:1$" <<<"${OUT}"'

OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_CONF="${TMP}/missing.conf" "${SHIM}" 2>&1)" && RC=0 || RC=$?
check "a missing jail.conf refuses to start rather than running without hides" '[ "${RC}" -ne 0 ] && grep -q "jail.conf" <<<"${OUT}"'

printf 'bogus ~/x\n' > "${CONF}"
OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_CONF="${CONF}" "${SHIM}" 2>&1)" && RC=0 || RC=$?
check "an unknown directive in jail.conf is an error" '[ "${RC}" -ne 0 ] && grep -q "bogus" <<<"${OUT}"'

# --- extension points ---------------------------------------------------------

probe "${WT}" 'touch "$HOME/.cache/c" && echo CACHE_OK'
check "~/.cache is writable" 'grep -q "CACHE_OK" <<<"${OUT}"'

OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_RW="${FAKE_HOME}/extra-rw" \
	PROBE='touch "$HOME/extra-rw/x" && echo EXTRA_OK' "${SHIM}" 2>&1)"
check "CODEX_JAIL_RW adds a writable path" 'grep -q "EXTRA_OK" <<<"${OUT}"'

OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_HIDE="${FAKE_HOME}/plain" \
	PROBE='echo "plain:$(ls -A "$HOME/plain" | wc -l)"' "${SHIM}" 2>&1)"
check "CODEX_JAIL_HIDE hides an extra path" 'grep -q "^plain:0$" <<<"${OUT}"'

# A repo kept on a hidden drive (e.g. /mnt/c on a work PC) must still be the
# workspace: the hide of the ancestor must not swallow the worktree bind.
mkdir -p "${TMP}/drive/other"
echo "SIBLING" > "${TMP}/drive/other/file"
git -c init.defaultBranch=main init -q "${TMP}/drive/repo"
OUT="$(cd "${TMP}/drive/repo" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" CODEX_JAIL_HIDE="${TMP}/drive" \
	PROBE='touch under-hidden.txt && git status --short >/dev/null && echo "UNDER_HIDDEN_OK sibling:$(ls -A ../other 2>/dev/null | wc -l)"' "${SHIM}" 2>&1)" || true
check "a worktree under a hidden ancestor stays writable" 'grep -q "UNDER_HIDDEN_OK" <<<"${OUT}"'
check "the rest of the hidden ancestor stays hidden" 'grep -q "sibling:0" <<<"${OUT}"'

OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${FAKE_BIN}" \
	PROBE='touch "$HOME/extra-rw/y" && echo ADDDIR_OK' "${SHIM}" --add-dir "${FAKE_HOME}/extra-rw" 2>&1)"
check "--add-dir <dir> is writable inside the jail" 'grep -q "ADDDIR_OK" <<<"${OUT}"'

OUT="$(cd "${WT}" && HOME="${FAKE_HOME}" CODEX_JAIL_BIN="${TMP}/does-not-exist" "${SHIM}" exec p 2>&1)" && RC=0 || RC=$?
check "a missing codex binary is reported, not silently run" '[ "${RC}" -ne 0 ] && grep -qi "codex" <<<"${OUT}"'

# --- summary -------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
