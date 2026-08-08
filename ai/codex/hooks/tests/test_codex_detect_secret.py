import json
import sys
from io import StringIO

from _loader import load

detect_secret = load("detect_secret")


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
    diff = "--- a/sub/config.py\n+++ b/sub/config.py\n@@ -1 +1 @@\n-x\n+y\n"
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 2


def test_apply_patch_clean_file_ok(tmp_path, monkeypatch):
    (tmp_path / "clean.py").write_text("x = 1\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    diff = "--- a/clean.py\n+++ b/clean.py\n@@ -1 +1 @@\n-x\n+x\n"
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 0


def test_apply_patch_example_path_skipped(tmp_path, monkeypatch):
    (tmp_path / ".env.example").write_text(
        "api_key = AKIAIOSFODNN7EXAMPLE\n", encoding="utf-8"
    )
    monkeypatch.chdir(tmp_path)
    diff = "+++ b/.env.example\n"
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 0


def test_apply_patch_without_files_ok(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    rc = run_main(
        {
            "tool_name": "apply_patch",
            "tool_input": {"command": "--- a/x\n+++ /dev/null\n"},
        },
        monkeypatch,
    )
    assert rc == 0


def test_missing_file_in_diff_ok(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": "+++ b/nope.py\n"}},
        monkeypatch,
    )
    assert rc == 0


def test_unknown_tool_ignored(monkeypatch):
    rc = run_main({"tool_name": "NotATool", "tool_input": {}}, monkeypatch)
    assert rc == 0


def test_invalid_json_ok(monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO("not json"))
    assert detect_secret.main() == 0
