from block_dangerous_command import analyze


def test_safe_command():
    assert analyze("ls -la") == []


def test_safe_git_command():
    assert analyze("git status") == []


def test_find_with_delete():
    blocks = analyze("find /tmp -name '*.log' -delete")
    assert any("-delete" in b.rule for b in blocks)


def test_find_with_exec_rm():
    blocks = analyze("find . -name '*.tmp' -exec rm {} \\;")
    assert any("exec rm" in b.rule for b in blocks)


def test_find_without_dangerous_action_is_safe():
    assert analyze("find . -name '*.py' -print") == []


def test_xargs_rm():
    blocks = analyze("ls | xargs rm")
    assert any("xargs rm" in b.rule for b in blocks)


def test_xargs_cat_is_safe():
    assert analyze("ls | xargs cat") == []


def test_dd_to_sda():
    blocks = analyze("dd if=/dev/zero of=/dev/sda bs=1M")
    assert any("block device" in b.rule for b in blocks)


def test_dd_to_sdb1():
    blocks = analyze("sudo dd if=image.iso of=/dev/sdb1")
    assert any("block device" in b.rule for b in blocks)


def test_dd_to_regular_file_is_safe():
    assert analyze("dd if=/dev/urandom of=output.bin bs=1M count=10") == []


def test_dd_to_nvme():
    blocks = analyze("dd if=/dev/zero of=/dev/nvme0n1")
    assert any("block device" in b.rule for b in blocks)


def test_mkfs_ext4():
    blocks = analyze("mkfs.ext4 /dev/sda1")
    assert any("mkfs" in b.rule for b in blocks)


def test_mkfs_bare():
    blocks = analyze("mkfs /dev/sdb")
    assert any("mkfs" in b.rule for b in blocks)


def test_shred():
    blocks = analyze("shred -u /tmp/foo")
    assert any("shred" in b.rule for b in blocks)


def test_shred_help_is_allowed():
    assert analyze("shred --help") == []


def test_wipefs():
    blocks = analyze("sudo wipefs /dev/sda")
    assert any("wipefs" in b.rule for b in blocks)


def test_rm_rf_in_dollar_parens():
    blocks = analyze("echo $(rm -rf /tmp/cache)")
    assert any("$(" in b.rule for b in blocks)


def test_rm_rf_in_backticks():
    blocks = analyze("echo `rm -rf /tmp/cache`")
    assert any("backticks" in b.rule for b in blocks)


def test_plain_rm_rf_not_caught_here():
    # settings.json deny list already catches `rm -rf *`; this hook does not
    # duplicate the bare case to avoid double-warnings.
    assert analyze("rm -rf /tmp/cache") == []


def test_comment_strips_dangerous_look():
    # After unquoted `#`, the rest is a comment and must not trigger.
    assert analyze("ls # find /tmp -delete") == []


def test_comment_inside_single_quotes_still_lexes_as_code():
    # Conservative: if quoted, the parser keeps scanning. A find...-delete
    # inside single quotes is still flagged; we'd rather false-positive than
    # miss.
    blocks = analyze("echo 'find /tmp -delete'")
    assert len(blocks) >= 1


def test_multiple_rules_can_match():
    blocks = analyze("find /tmp -delete; mkfs.ext4 /dev/sda1")
    rules = {b.rule for b in blocks}
    assert any("-delete" in r for r in rules)
    assert any("mkfs" in r for r in rules)
