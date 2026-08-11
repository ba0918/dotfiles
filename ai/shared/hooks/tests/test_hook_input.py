from pathlib import Path

from hook_input import edited_files, extract_patch_files, read_files


def test_add_file_marker_yields_path():
    diff = "*** Begin Patch\n*** Add File: foo.py\n@@\n+print(1)\n*** End Patch\n"
    assert extract_patch_files(diff) == ["foo.py"]


def test_update_file_marker_yields_path():
    diff = "*** Begin Patch\n*** Update File: foo.py\n@@\n-x\n+x\n*** End Patch\n"
    assert extract_patch_files(diff) == ["foo.py"]


def test_delete_file_marker_is_skipped():
    diff = "*** Begin Patch\n*** Delete File: gone.py\n*** End Patch\n"
    assert extract_patch_files(diff) == []


def test_move_to_returns_new_path():
    diff = (
        "*** Begin Patch\n"
        "*** Update File: old.py\n"
        "*** Move to: new.py\n"
        "@@\n"
        "-x\n"
        "+y\n"
        "*** End Patch\n"
    )
    assert extract_patch_files(diff) == ["new.py"]


def test_extracts_multiple_files_in_order():
    diff = (
        "*** Begin Patch\n"
        "*** Add File: a.py\n@@\n+1\n"
        "*** Update File: b.py\n@@\n-x\n+x\n"
        "*** Delete File: c.py\n"
        "*** Update File: d.py\n@@\n-y\n+y\n"
        "*** End Patch\n"
    )
    assert extract_patch_files(diff) == ["a.py", "b.py", "d.py"]


def test_repeated_paths_are_deduplicated():
    diff = (
        "*** Begin Patch\n"
        "*** Add File: a.py\n@@\n+1\n"
        "*** Update File: a.py\n@@\n-x\n+x\n"
        "*** End Patch\n"
    )
    assert extract_patch_files(diff) == ["a.py"]


def test_path_with_spaces_is_kept_whole():
    diff = (
        "*** Begin Patch\n"
        "*** Update File: my dir/settings file.toml\n"
        "@@\n"
        "-x\n"
        "+x\n"
        "*** End Patch\n"
    )
    assert extract_patch_files(diff) == ["my dir/settings file.toml"]


def test_begin_end_markers_alone_yield_no_files():
    assert extract_patch_files("*** Begin Patch\n*** End Patch\n") == []


def test_empty_patch_yields_no_files():
    assert extract_patch_files("") == []


def test_git_format_headers_yield_no_files():
    # Codex's apply_patch is freeform (*** markers); git unified diff headers
    # are never produced, so parsing them would silently miss every file.
    diff = "--- a/foo.py\n+++ b/foo.py\n@@ -1 +1 @@\n-x\n+x\n"
    assert extract_patch_files(diff) == []


def test_edited_files_drops_absolute_path(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    event = {
        "tool_name": "apply_patch",
        "tool_input": {
            "command": "*** Begin Patch\n*** Update File: /etc/passwd\n@@\n-x\n+x\n*** End Patch\n"
        },
    }
    assert edited_files(event) == []


def test_edited_files_drops_escape(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    event = {
        "tool_name": "apply_patch",
        "tool_input": {
            "command": (
                "*** Begin Patch\n"
                "*** Update File: ../../etc/passwd\n"
                "@@\n"
                "-x\n"
                "+x\n"
                "*** End Patch\n"
            )
        },
    }
    assert edited_files(event) == []


def test_edited_files_keeps_contained_path(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    event = {
        "tool_name": "apply_patch",
        "tool_input": {
            "command": (
                "*** Begin Patch\n"
                "*** Update File: sub/config.py\n"
                "@@\n"
                "-x\n"
                "+x\n"
                "*** End Patch\n"
            )
        },
    }
    assert edited_files(event) == ["sub/config.py"]


def test_edited_files_honors_event_cwd(tmp_path, monkeypatch):
    inner = tmp_path / "inner"
    inner.mkdir()
    (tmp_path / "outer.py").write_text("x = 1\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    event = {
        "cwd": str(inner),
        "tool_name": "apply_patch",
        "tool_input": {
            "command": (
                "*** Begin Patch\n"
                "*** Update File: ../outer.py\n"
                "@@\n"
                "-x\n"
                "+x\n"
                "*** End Patch\n"
            )
        },
    }
    # ../outer.py resolves outside inner/ (the event cwd) → dropped
    assert edited_files(event) == []


# --- read_files(): shared text reading for the file-scanner hooks ------------


def test_read_files_returns_path_and_text(tmp_path):
    f = tmp_path / "note.txt"
    f.write_text("hello", encoding="utf-8")
    assert read_files([str(f)]) == [(Path(str(f)), "hello")]


def test_read_files_skips_missing_files(tmp_path):
    assert read_files([str(tmp_path / "nope.txt")]) == []


def test_read_files_skips_unreadable_files(tmp_path, monkeypatch):
    f = tmp_path / "note.txt"
    f.write_text("hello", encoding="utf-8")

    def boom(self, *args, **kwargs):
        raise OSError("denied")

    monkeypatch.setattr(Path, "read_text", boom)
    assert read_files([str(f)]) == []


def test_read_files_applies_skip_predicate(tmp_path):
    f = tmp_path / "bin.dat"
    f.write_bytes(b"\x00\x01")
    kept = read_files([str(f)], skip=lambda p: p.suffix == ".dat")
    assert kept == []
    assert read_files([str(f)], skip=lambda p: False) == [(Path(str(f)), "\x00\x01")]
