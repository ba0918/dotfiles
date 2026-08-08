from codex_input import extract_patch_files


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
