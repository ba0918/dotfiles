#!/usr/bin/env bash
# Verify V2-only registration, release tracking, and shared deny generation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$ROOT" "$TMP" <<'PY'
import json, pathlib, sys, tomllib
root, temporary = map(pathlib.Path, sys.argv[1:])
config = tomllib.loads((root / 'mise/config.toml').read_text())
v1 = json.loads((root / 'ai/opencode/opencode.json').read_text())
v2 = json.loads((root / 'ai/opencode/opencode-v2.json').read_text())
assert config['dotfiles']['~/.opencode/opencode.json']['source'] == '../ai/opencode/opencode.json'
assert config['dotfiles']['~/.config/opencode/opencode.json']['source'] == '../ai/opencode/opencode-v2.json'
assert 'plugins' not in v1 and 'shell' not in v1
assert v2['shell'] == '/bin/bash'
assert v2['plugins'] == ['{{ vars.command_guardian_plugin }}']
assert config['vars']['command_guardian_plugin'].endswith('/latest/opencode')
assert 'MISE_DATA_DIR' in config['vars']['command_guardian_plugin']
assert config['tools']['github:ba0918/command-guardian']['version'] == 'latest'
assert not any(key in json.dumps(v2) for key in ['serverUrl', 'passwordEnv', 'OPENCODE_SERVER_PASSWORD'])
assert {k: v for k, v in v2.items() if k not in ('shell', 'plugins')} == v1
for location, value in [('.opencode', v1), ('.config/opencode', v2)]:
    target = temporary / location
    target.mkdir(parents=True)
    (target / 'opencode.json').write_text(json.dumps(value))
print('PASS: V2 uses the matching latest release without manual registration or credentials')
PY

HOME="$TMP" bash "$ROOT/scripts/generate-deny.sh" opencode-apply
python3 - "$TMP" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
v1 = json.loads((root / '.opencode/opencode.json').read_text())
v2 = json.loads((root / '.config/opencode/opencode.json').read_text())
assert v2['plugins'] == ['{{ vars.command_guardian_plugin }}']
assert v2['shell'] == '/bin/bash'
assert v2['permission'] == v1['permission']
assert sum(value == 'deny' for value in v2['permission']['read'].values()) > 100
print('PASS: deny injection preserves V2 integration and existing permissions')
PY
