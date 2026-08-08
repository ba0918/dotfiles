from codex_input import extract_patch_files


def test_extracts_git_prefixed_new_file():
    diff = "--- a/foo.py\n+++ b/foo.py\n@@ -0,0 +1 @@\n+x = 1\n"
    assert extract_patch_files(diff) == ["foo.py"]


def test_extracts_bare_path_without_prefix():
    diff = "--- foo.py\n+++ foo.py\n@@ -1 +1 @@\n-x\n+x\n"
    assert extract_patch_files(diff) == ["foo.py"]


def test_strips_b_prefix_for_nested_path():
    assert extract_patch_files("+++ b/sub/deep/file.py\n") == ["sub/deep/file.py"]


def test_ignores_source_header():
    assert extract_patch_files("--- a/foo.py\n") == []


def test_skips_dev_null_deletion():
    diff = "--- a/foo.py\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n"
    assert extract_patch_files(diff) == []


def test_extracts_multiple_files_in_order():
    diff = (
        "diff --git a/a.py b/a.py\n--- a/a.py\n+++ b/a.py\n@@ -1 +1 @@\n-x\n+x\n"
        "diff --git a/b.py b/b.py\n--- a/b.py\n+++ b/b.py\n@@ -1 +1 @@\n-y\n+y\n"
    )
    assert extract_patch_files(diff) == ["a.py", "b.py"]


def test_added_line_starting_with_plus_plus_not_treated_as_header():
    # `++b` is an added line whose content is `+b`; only the real `+++ ` header
    # (with a trailing space) must be parsed as a file marker.
    diff = "--- a/f.txt\n+++ b/f.txt\n@@ -1 +1,2 @@\n-a\n++b\n"
    assert extract_patch_files(diff) == ["f.txt"]


def test_empty_diff_returns_no_files():
    assert extract_patch_files("") == []
