#!/usr/bin/env bash
# Verify optional initialization failures are visible without aborting bootstrap.
# External installers are replaced to avoid modifying packages or user services.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/repo" "${TMP}/bin" "${TMP}/home/.safe-chain/bin"
cp "${ROOT}/bootstrap.sh" "${TMP}/repo/bootstrap.sh"
touch "${TMP}/home/.safe-chain/bin/safe-chain"
chmod +x "${TMP}/home/.safe-chain/bin/safe-chain"

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
