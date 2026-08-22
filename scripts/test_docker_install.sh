#!/usr/bin/env bash
#
# Test harness for docker/install.sh (native dockerd inside WSL, opt-in)
#
# The installer needs sudo for every real step, so only its planning is
# asserted here: what it decides to do from a given machine state, and that it
# refuses to run where Docker Desktop already provides the daemon. Machine
# state is injected through the DOCKER_INSTALL_* variables the script reads
# instead of the real /etc, dpkg and group membership.
#
# Usage: bash scripts/test_docker_install.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/docker/install.sh"

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

# Fresh machine: nothing configured, no Docker Desktop.
fresh() {
	local state="$1"
	mkdir -p "${state}/sources.list.d" "${state}/docker" "${state}/desktop-absent"
	printf '[boot]\nsystemd=false\n' > "${state}/wsl.conf"
}

run() {
	local state="$1"
	shift
	set +e
	OUT="$(DOCKER_DESKTOP_ROOT="${state}/desktop" \
		DOCKER_INSTALL_SOURCES_DIR="${state}/sources.list.d" \
		DOCKER_INSTALL_DAEMON_JSON="${state}/docker/daemon.json" \
		DOCKER_INSTALL_WSL_CONF="${state}/wsl.conf" \
		DOCKER_INSTALL_INSTALLED_PKGS="${INSTALLED:-}" \
		DOCKER_INSTALL_GROUPS="${GROUPS_:-}" \
		"${SCRIPT}" "$@" 2>&1)"
	RC=$?
	set -e
}

# --- refuses where Docker Desktop owns the daemon --------------------------------

S="${TMP}/desktop"; fresh "${S}"; mkdir -p "${S}/desktop/cli-tools"
run "${S}" --dry-run
check "Docker Desktop integration is detected and refused" '[ "${RC}" -ne 0 ] && grep -qi "docker desktop" <<<"${OUT}"'
check "nothing is planned when refused" '! grep -q "^plan:" <<<"${OUT}"'

# --- fresh machine: every step is planned ----------------------------------------

S="${TMP}/fresh"; fresh "${S}"
INSTALLED="" GROUPS_="mizumi sudo" run "${S}" --dry-run
check "dry-run exits 0 on a fresh machine" '[ "${RC}" -eq 0 ]'
check "plans the apt source" 'grep -q "^plan: apt source" <<<"${OUT}"'
check "plans the package install" 'grep -q "^plan: install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" <<<"${OUT}"'
check "plans daemon.json" 'grep -q "^plan: daemon.json" <<<"${OUT}"'
check "plans the docker group" 'grep -q "^plan: group" <<<"${OUT}"'
check "plans systemd in wsl.conf and says a WSL restart is needed" 'grep -q "^plan: wsl.conf" <<<"${OUT}" && grep -q "wsl --shutdown" <<<"${OUT}"'
check "dry-run changes nothing" '[ -z "$(ls -A "${S}/sources.list.d")" ] && [ ! -e "${S}/docker/daemon.json" ]'

# --- configured machine: nothing to do -----------------------------------------------

S="${TMP}/done"; fresh "${S}"
cp "${ROOT}/docker/docker.sources" "${S}/sources.list.d/"
cp "${ROOT}/docker/daemon.json" "${S}/docker/daemon.json"
printf '[boot]\nsystemd=true\n' > "${S}/wsl.conf"
INSTALLED="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" GROUPS_="mizumi docker" run "${S}" --dry-run
check "a configured machine plans nothing" '[ "${RC}" -eq 0 ] && ! grep -q "^plan:" <<<"${OUT}"'

# --- partial state: only the missing pieces are planned ----------------------------

S="${TMP}/partial"; fresh "${S}"
cp "${ROOT}/docker/docker.sources" "${S}/sources.list.d/"
printf '[boot]\nsystemd=true\n' > "${S}/wsl.conf"
INSTALLED="docker-ce docker-ce-cli containerd.io" GROUPS_="mizumi docker" run "${S}" --dry-run
check "only missing packages are planned" 'grep -q "^plan: install docker-buildx-plugin docker-compose-plugin$" <<<"${OUT}"'
check "present apt source is not re-planned" '! grep -q "^plan: apt source" <<<"${OUT}"'
check "present group membership is not re-planned" '! grep -q "^plan: group" <<<"${OUT}"'

# --- a legacy one-line docker.list counts as the source being present ------------

S="${TMP}/legacy"; fresh "${S}"
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > "${S}/sources.list.d/docker.list"
INSTALLED="" GROUPS_="" run "${S}" --dry-run
check "an existing docker.list is not duplicated by docker.sources" '! grep -q "^plan: apt source" <<<"${OUT}"'

# --- an existing daemon.json is never overwritten --------------------------------

S="${TMP}/daemon"; fresh "${S}"
echo '{"bip":"10.9.0.1/24"}' > "${S}/docker/daemon.json"
INSTALLED="" GROUPS_="" run "${S}" --dry-run
check "a differing daemon.json is reported, not replaced" 'grep -qi "daemon.json differs" <<<"${OUT}" && ! grep -q "^plan: daemon.json" <<<"${OUT}"'

# --- summary ------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
