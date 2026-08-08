import json
import sys
from io import StringIO

from _loader import load

block = load("block_dangerous_command")


def run_main(event, monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO(json.dumps(event)))
    return block.main()


def test_blocks_dangerous_bash(monkeypatch):
    rc = run_main(
        {"tool_name": "Bash", "tool_input": {"command": "find /tmp -delete"}},
        monkeypatch,
    )
    assert rc == 2


def test_allows_safe_bash(monkeypatch):
    rc = run_main(
        {"tool_name": "Bash", "tool_input": {"command": "ls -la"}}, monkeypatch
    )
    assert rc == 0


def test_skips_apply_patch(monkeypatch):
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": "+++ b/x\n"}},
        monkeypatch,
    )
    assert rc == 0


def test_skips_write(monkeypatch):
    rc = run_main(
        {"tool_name": "Write", "tool_input": {"file_path": "/tmp/x"}}, monkeypatch
    )
    assert rc == 0
