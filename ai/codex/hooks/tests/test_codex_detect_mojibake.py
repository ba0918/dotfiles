import json
import sys
from io import StringIO

from _loader import load

detect_mojibake = load("detect_mojibake")


def run_main(event, monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO(json.dumps(event)))
    return detect_mojibake.main()


def test_scan_still_detects_pure_function():
    findings = detect_mojibake.scan("bad \ufffd")
    assert any("U+FFFD" in f.reason for f in findings)


def test_write_event_scans_file(tmp_path, monkeypatch):
    f = tmp_path / "note.txt"
    f.write_text("hello\ufffd world\n", encoding="utf-8")
    rc = run_main(
        {"tool_name": "Write", "tool_input": {"file_path": str(f)}}, monkeypatch
    )
    assert rc == 2


def test_write_event_clean_file_ok(tmp_path, monkeypatch):
    f = tmp_path / "clean.txt"
    f.write_text("hello\n", encoding="utf-8")
    rc = run_main(
        {"tool_name": "Write", "tool_input": {"file_path": str(f)}}, monkeypatch
    )
    assert rc == 0


def test_edit_event_scans_file(tmp_path, monkeypatch):
    f = tmp_path / "data.txt"
    f.write_text("\ufeffhello\n", encoding="utf-8")
    rc = run_main(
        {"tool_name": "Edit", "tool_input": {"file_path": str(f)}}, monkeypatch
    )
    assert rc == 2


def test_apply_patch_event_scans_extracted_file(tmp_path, monkeypatch):
    (tmp_path / "data.txt").write_text("mojibake: \ufffd\ufffd\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    diff = "--- a/data.txt\n+++ b/data.txt\n@@ -1 +1 @@\n-x\n+y\n"
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 2


def test_apply_patch_clean_file_ok(tmp_path, monkeypatch):
    (tmp_path / "clean.txt").write_text("fine\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    diff = "--- a/clean.txt\n+++ b/clean.txt\n@@ -1 +1 @@\n-fine\n+ok\n"
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


def test_unknown_tool_ignored(monkeypatch):
    rc = run_main({"tool_name": "NotATool", "tool_input": {}}, monkeypatch)
    assert rc == 0


def test_invalid_json_ok(monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO("not json"))
    assert detect_mojibake.main() == 0
