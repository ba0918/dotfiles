"""Tests for the shared detect_secret hook.

`scan()` / `is_example_path()` are pure and carry the pattern coverage; the
`main()` tests at the bottom pin the event handling for both event shapes the
hook receives — Write/Edit (Claude Code and Codex) and apply_patch (Codex).
"""

import json
import sys
from io import StringIO

import detect_secret
from detect_secret import is_example_path, scan


def test_clean_code_no_findings():
    assert scan("def hello():\n    return 'world'", "hello.py") == []


def test_aws_access_key():
    findings = scan("aws_key = AKIAIOSFODNN7EXAMPLE", "config.py")
    assert any("AWS" in f.kind for f in findings)


def test_aws_session_key():
    findings = scan("tok = ASIAIOSFODNN7EXAMPLE", "config.py")
    assert any("AWS" in f.kind for f in findings)


def test_github_token():
    findings = scan("GITHUB_TOKEN=ghp_" + "a" * 36, "app.env")
    assert any("GitHub" in f.kind for f in findings)


def test_anthropic_api_key():
    findings = scan("key = 'sk-ant-api03-" + "a" * 95 + "'", "config.py")
    assert any("Anthropic" in f.kind for f in findings)


def test_openai_api_key_not_anthropic():
    findings = scan("key = 'sk-" + "a" * 48 + "'", "config.py")
    kinds = [f.kind for f in findings]
    assert any("OpenAI" in k for k in kinds)
    assert not any("Anthropic" in k for k in kinds)


def test_google_api_key():
    findings = scan("key = AIza" + "A" * 35, "config.py")
    assert any("Google" in f.kind for f in findings)


def test_slack_token():
    findings = scan("tok = xoxb-1234567890-abcdefg", "config.py")
    assert any("Slack" in f.kind for f in findings)


def test_jwt():
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    findings = scan(f"token = '{jwt}'", "api.js")
    assert any("JWT" in f.kind for f in findings)


def test_pem_private_key():
    findings = scan("-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n", "key.pem")
    assert any("PEM" in f.kind for f in findings)


def test_pem_openssh_private_key():
    findings = scan("-----BEGIN OPENSSH PRIVATE KEY-----\n...", "id_rsa")
    assert any("PEM" in f.kind for f in findings)


def test_generic_password_assignment():
    findings = scan("password = 'S3cr3tV@lueL0ngEnough1234'", "config.py")
    assert any("generic" in f.kind for f in findings)


def test_generic_api_key_assignment():
    findings = scan("api_key: 'abcdef1234567890abcdef1234567890'", "config.yaml")
    assert any("generic" in f.kind for f in findings)


def test_example_path_ignored():
    assert scan("api_key = AKIAIOSFODNN7EXAMPLE", ".env.example") == []


def test_sample_path_ignored():
    assert scan("api_key = AKIAIOSFODNN7EXAMPLE", "config.sample.json") == []


def test_placeholder_value_ignored():
    assert scan("api_key = 'your_api_key_here_1234567890'", "README.md") == []


def test_angle_bracket_placeholder_ignored():
    assert scan("api_key = <your_api_key>", "docs.md") == []


def test_version_string_not_flagged():
    # generic pattern requires key words (api_key/secret/etc); versions rarely match
    assert scan("version: '1.2.3'", "pyproject.toml") == []


def test_redacts_long_lines():
    long_line = "password = '" + "a" * 200 + "'"
    findings = scan(long_line, "config.py")
    assert findings and len(findings[0].snippet) <= 125


def test_is_example_path():
    assert is_example_path(".env.example")
    assert is_example_path("config.example.json")
    assert is_example_path("sample.env")
    assert is_example_path("docker-compose.template.yml")
    assert not is_example_path("config.env")
    assert not is_example_path("production.py")


def test_reports_correct_line_number():
    text = "line1\nline2\nakey = ghp_" + "a" * 36
    findings = scan(text, "x.txt")
    assert any(f.line_no == 3 for f in findings)


# --- main(): event → exit code ----------------------------------------------


def run_main(event, monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO(json.dumps(event)))
    return detect_secret.main()


def test_scan_still_detects_pure_function():
    findings = detect_secret.scan("tok = ghp_" + "a" * 36, "app.env")
    assert any("GitHub" in f.kind for f in findings)


def test_write_event_scans_file(tmp_path, monkeypatch):
    f = tmp_path / "config.py"
    f.write_text("api_key = AKIAIOSFODNN7EXAMPLE\n", encoding="utf-8")
    rc = run_main(
        {"tool_name": "Write", "tool_input": {"file_path": str(f)}}, monkeypatch
    )
    assert rc == 2


def test_write_event_clean_file_ok(tmp_path, monkeypatch):
    f = tmp_path / "clean.py"
    f.write_text("x = 1\n", encoding="utf-8")
    rc = run_main(
        {"tool_name": "Write", "tool_input": {"file_path": str(f)}}, monkeypatch
    )
    assert rc == 0


def test_edit_event_scans_file(tmp_path, monkeypatch):
    f = tmp_path / "app.env"
    f.write_text("GITHUB_TOKEN=ghp_" + "a" * 36 + "\n", encoding="utf-8")
    rc = run_main(
        {"tool_name": "Edit", "tool_input": {"file_path": str(f)}}, monkeypatch
    )
    assert rc == 2


def test_apply_patch_event_scans_extracted_file(tmp_path, monkeypatch):
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "config.py").write_text(
        "password = 'S3cr3tV@lueL0ngEnough1234'\n", encoding="utf-8"
    )
    monkeypatch.chdir(tmp_path)
    diff = (
        "*** Begin Patch\n"
        "*** Update File: sub/config.py\n"
        "@@\n"
        "-x\n"
        "+y\n"
        "*** End Patch\n"
    )
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 2


def test_apply_patch_github_token_detected(tmp_path, monkeypatch):
    (tmp_path / "config.py").write_text(
        'GITHUB_TOKEN = "ghp_' + "A" * 36 + '"\n', encoding="utf-8"
    )
    monkeypatch.chdir(tmp_path)
    diff = (
        "*** Begin Patch\n"
        "*** Update File: config.py\n"
        "@@\n"
        "-x\n"
        "+y\n"
        "*** End Patch\n"
    )
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 2


def test_apply_patch_clean_file_ok(tmp_path, monkeypatch):
    (tmp_path / "clean.py").write_text("x = 1\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    diff = (
        "*** Begin Patch\n"
        "*** Update File: clean.py\n"
        "@@\n"
        "-x\n"
        "+x = 1\n"
        "*** End Patch\n"
    )
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 0


def test_apply_patch_example_path_skipped(tmp_path, monkeypatch):
    (tmp_path / ".env.example").write_text(
        "api_key = AKIAIOSFODNN7EXAMPLE\n", encoding="utf-8"
    )
    monkeypatch.chdir(tmp_path)
    diff = (
        "*** Begin Patch\n"
        "*** Add File: .env.example\n"
        "@@\n"
        "+api_key = AKIAIOSFODNN7EXAMPLE\n"
        "*** End Patch\n"
    )
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 0


def test_apply_patch_without_files_ok(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    rc = run_main(
        {
            "tool_name": "apply_patch",
            "tool_input": {"command": "*** Begin Patch\n*** Delete File: x\n*** End Patch\n"},
        },
        monkeypatch,
    )
    assert rc == 0


def test_missing_file_in_diff_ok(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    rc = run_main(
        {
            "tool_name": "apply_patch",
            "tool_input": {
                "command": (
                    "*** Begin Patch\n"
                    "*** Update File: nope.py\n"
                    "@@\n"
                    "-x\n"
                    "+x\n"
                    "*** End Patch\n"
                )
            },
        },
        monkeypatch,
    )
    assert rc == 0


def test_unknown_tool_ignored(monkeypatch):
    rc = run_main({"tool_name": "NotATool", "tool_input": {}}, monkeypatch)
    assert rc == 0


def test_invalid_json_ok(monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO("not json"))
    assert detect_secret.main() == 0
