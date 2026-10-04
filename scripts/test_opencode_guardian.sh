#!/usr/bin/env bash
# Verify plugin registration, release tracking, and deny generation for opencode.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$ROOT" "$TMP" <<'PY'
import json, pathlib, sys, tomllib
root, temporary = map(pathlib.Path, sys.argv[1:])
config = tomllib.loads((root / 'mise/config.toml').read_text())
settings = json.loads((root / 'ai/opencode/opencode.json').read_text())
assert config['dotfiles']['~/.config/opencode/opencode.json']['source'] == '../ai/opencode/opencode.json'
assert '~/.opencode/opencode.json' not in config['dotfiles']
assert settings['shell'] == '/bin/bash'
assert settings['plugins'] == ['{{ vars.command_guardian_plugin }}']
assert config['vars']['command_guardian_plugin'].endswith('/latest/opencode')
assert 'MISE_DATA_DIR' in config['vars']['command_guardian_plugin']
assert config['tools']['github:ba0918/command-guardian']['version'] == 'latest'
assert not any(key in json.dumps(settings) for key in ['serverUrl', 'passwordEnv', 'OPENCODE_SERVER_PASSWORD'])
opencode = config['tools']['npm:@opencode/cli']
assert opencode['version'] == 'latest' and opencode['allow_builds'] == '@opencode/cli'
assert 'opencode' not in config['tools'] and 'http:opencode2' not in config['tools']
target = temporary / '.config/opencode'
target.mkdir(parents=True)
(target / 'opencode.json').write_text(json.dumps(settings))
print('PASS: opencode uses the matching latest release without manual registration or credentials')
PY

HOME="$TMP" bash "$ROOT/scripts/generate-deny.sh" opencode-apply
python3 - "$TMP" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
settings = json.loads((root / '.config/opencode/opencode.json').read_text())
assert settings['plugins'] == ['{{ vars.command_guardian_plugin }}']
assert settings['shell'] == '/bin/bash'
assert settings['permission']['bash']['sudo *'] == 'deny'
assert sum(value == 'deny' for value in settings['permission']['read'].values()) > 100
print('PASS: deny injection preserves the plugin and existing permissions')
PY
