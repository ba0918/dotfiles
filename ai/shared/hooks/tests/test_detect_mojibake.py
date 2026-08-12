"""Tests for the shared detect_mojibake hook.

`scan()` is pure and carries the detection coverage; the `main()` tests at the
bottom pin the event handling for both event shapes the hook receives —
Write/Edit (Claude Code and Codex) and apply_patch (Codex).
"""

import json
import sys
from io import StringIO

import detect_mojibake
from detect_mojibake import _is_binary, scan


def test_clean_text_returns_no_findings():
    assert scan("hello world\nregular text") == []


def test_detects_u_fffd_replacement_char():
    findings = scan("hello\ufffd world")
    assert len(findings) == 1
    assert findings[0].line_no == 1
    assert "U+FFFD" in findings[0].reason


def test_detects_bom_at_file_start():
    findings = scan("\ufeffhello")
    assert any("BOM" in f.reason for f in findings)


def test_does_not_flag_bom_mid_line():
    # BOM not at start of file should not be flagged by BOM rule
    findings = scan("hello\n\ufeffworld")
    assert not any("BOM" in f.reason for f in findings)


def test_detects_null_byte():
    findings = scan("line1\nbad\x00char")
    assert any("control char" in f.reason for f in findings)


def test_allows_tab_lf_cr():
    assert scan("tab\there\nnewline\rcarriage") == []


def test_detects_question_mark_run():
    findings = scan("lost??????? encoding")
    assert any("question-mark run" in f.reason for f in findings)


def test_short_question_mark_run_is_ignored():
    # 2-3 ?s are normal punctuation
    assert scan("what?? really???") == []


def test_reports_correct_line_number():
    findings = scan("first\nsecond\nthird\ufffd")
    assert any(f.line_no == 3 for f in findings)


def test_multiple_findings_in_text():
    findings = scan("a\ufffd\nb\x00\nc?????????")
    assert len(findings) >= 3


def test_scan_stops_collecting_after_display_limit():
    assert len(scan("\n".join("bad�" for _ in range(20)))) == 10


def test_binary_detection_uses_file_content(tmp_path):
    binary = tmp_path / "image.png"
    binary.write_bytes(b"\x89PNG\r\n\x1a\n\x00payload")
    text = tmp_path / "note.txt"
    text.write_text("binary is just a word", encoding="utf-8")
    assert _is_binary(binary)
    assert not _is_binary(text)


# --- main(): event → exit code ----------------------------------------------


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
    diff = (
        "*** Begin Patch\n"
        "*** Update File: data.txt\n"
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
    (tmp_path / "clean.txt").write_text("fine\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    diff = (
        "*** Begin Patch\n"
        "*** Update File: clean.txt\n"
        "@@\n"
        "-fine\n"
        "+fine\n"
        "*** End Patch\n"
    )
    rc = run_main(
        {"tool_name": "apply_patch", "tool_input": {"command": diff}}, monkeypatch
    )
    assert rc == 0


def test_multiple_file_diagnostics_include_each_path(tmp_path, monkeypatch, capsys):
    first = tmp_path / "first.txt"
    second = tmp_path / "second.txt"
    first.write_text("\n".join("bad�" for _ in range(10)), encoding="utf-8")
    second.write_text("bad�", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    rc = run_main(
        {
            "tool_name": "apply_patch",
            "cwd": str(tmp_path),
            "tool_input": {
                "command": (
                    f"*** Update File: {first.name}\n"
                    f"*** Update File: {second.name}\n"
                )
            },
        },
        monkeypatch,
    )
    assert rc == 2
    stderr = capsys.readouterr().err
    assert f"{first}:1" in stderr
    assert f"{second}:1" in stderr


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


def test_unknown_tool_ignored(monkeypatch):
    rc = run_main({"tool_name": "NotATool", "tool_input": {}}, monkeypatch)
    assert rc == 0


def test_invalid_json_ok(monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO("not json"))
    assert detect_mojibake.main() == 0
