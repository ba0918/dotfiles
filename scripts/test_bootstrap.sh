#!/usr/bin/env bash
# Verify optional initialization failures are visible without aborting bootstrap.
# External installers are replaced to avoid modifying packages or user services.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/repo" "${TMP}/bin" "${TMP}/home/.safe-chain/bin"
cp "${ROOT}/bootstrap.sh" "${TMP}/repo/bootstrap.sh"
# The installed Safe Chain reports the version bootstrap.sh pins, so the
# installer is not fetched unless a test replaces this stand-in.
PINNED_SAFE_CHAIN="$(sed -n 's/^[[:space:]]*SAFE_CHAIN_VERSION="\(.*\)"$/\1/p' "${ROOT}/bootstrap.sh")"
if [ -z "${PINNED_SAFE_CHAIN}" ]; then
    echo 'FAIL: could not read SAFE_CHAIN_VERSION from bootstrap.sh' >&2
    exit 1
fi
install_safe_chain_stub() {
    printf '#!/bin/sh\necho "Current safe-chain version: %s"\n' "$1" \
        > "${TMP}/home/.safe-chain/bin/safe-chain"
    chmod +x "${TMP}/home/.safe-chain/bin/safe-chain"
}
install_safe_chain_stub "${PINNED_SAFE_CHAIN}"
# No test may reach the network: a download attempt is recorded and fails.
cat > "${TMP}/bin/curl" <<SH
#!/usr/bin/env bash
echo "\$*" >> "${TMP}/curl-calls"
exit 22
SH

cat > "${TMP}/bin/mise" <<'SH'
#!/usr/bin/env bash
case "$1" in
    trust|bootstrap) exit 0 ;;
    x)
        if [ "${INIT_FAIL}" = 1 ]; then
            echo 'initialization dependency unavailable' >&2
            exit 1
        fi
        ;;
    *) exit 2 ;;
esac
SH
cat > "${TMP}/bin/clipboard2path-wsl" <<'SH'
#!/usr/bin/env bash
exit "${FALLBACK_FAIL}"
SH
chmod +x "${TMP}/bin/"*

run() {
    env -u MISE_GLOBAL_CONFIG_ROOT HOME="${TMP}/home" PATH="${TMP}/bin:/usr/bin:/bin" \
        INIT_FAIL="$1" FALLBACK_FAIL="$2" bash "${TMP}/repo/bootstrap.sh" "${@:3}" \
        >"${TMP}/out" 2>"${TMP}/err"
}

run 1 1
if ! grep -q 'warning: clipboard2path initialization failed' "${TMP}/err" ||
    ! grep -q 'warning: devbox initialization failed' "${TMP}/err"; then
    echo 'FAIL: optional initialization failures must warn and continue' >&2
    exit 1
fi
grep -q 'initialization dependency unavailable' "${TMP}/err"
echo 'PASS: initialization failures warn, retain diagnostics, and continue'

run 1 0
if grep -q 'warning: clipboard2path' "${TMP}/err"; then
    echo 'FAIL: successful clipboard fallback must not report total failure' >&2
    exit 1
fi
grep -q 'warning: devbox' "${TMP}/err"
echo 'PASS: successful clipboard fallback avoids a failure warning'

run 0 0
test ! -s "${TMP}/err"
echo 'PASS: successful initialization emits no warnings'

run 1 1 dotfiles --dry-run
test ! -s "${TMP}/err"
echo 'PASS: dry-run does not execute optional initialization'

: > "${TMP}/curl-calls"
run 0 0
test ! -s "${TMP}/curl-calls"
echo 'PASS: an installed Safe Chain at the pinned version is not fetched again'

install_safe_chain_stub 0.0.1
: > "${TMP}/curl-calls"
run 0 0
if ! grep -q "releases/download/${PINNED_SAFE_CHAIN}/install-safe-chain.sh" "${TMP}/curl-calls"; then
    echo 'FAIL: an installed Safe Chain older than the pin must be reinstalled from the pinned release' >&2
    exit 1
fi
echo 'PASS: an installed Safe Chain of another version is reinstalled from the pinned release'

install_safe_chain_stub 0.0.1
: > "${TMP}/curl-calls"
run 0 0 --dry-run
test ! -s "${TMP}/curl-calls"
echo 'PASS: dry-run does not reinstall Safe Chain'
