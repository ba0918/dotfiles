"""Tests for the shared block_dangerous_command hook.

`analyze()` is the pure rule engine and carries the bulk of the coverage;
the `main()` tests at the bottom pin the stdin/exit-code contract that both
Claude Code and Codex drive the hook through.
"""

import json
import sys
from io import StringIO

import block_dangerous_command
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


def test_xargs_detects_options_and_sudo_wrapped_rm():
    blocks = analyze("printf x | xargs -0 sudo rm")
    assert any("xargs rm" in block.rule for block in blocks)


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


def test_single_quoted_string_body_is_not_analyzed():
    # We used to flag this conservatively, but it caused false positives in
    # real usage (e.g. `git commit -m '... find -delete ...'`). Trade-off
    # accepted: adversarial inputs like `echo '$(rm -rf /)'` slip through.
    assert analyze("echo 'find /tmp -delete'") == []


def test_double_quoted_string_body_is_not_analyzed():
    assert analyze('echo "find /tmp -delete"') == []


def test_git_commit_message_with_dangerous_words_not_flagged():
    # The exact shape that self-blocked our own commit
    cmd = 'git commit -m "fix find -delete handling and xargs rm path"'
    assert analyze(cmd) == []


def test_heredoc_body_is_not_analyzed():
    cmd = (
        'git commit -m "$(cat <<\'EOF\'\n'
        'fix: find -delete now handled\n'
        'also mkfs and shred safety improved\n'
        'EOF\n'
        ')"'
    )
    assert analyze(cmd) == []


def test_unquoted_heredoc_body_is_not_analyzed():
    cmd = (
        "cat <<EOF\n"
        "find /tmp -delete\n"
        "xargs rm\n"
        "EOF"
    )
    assert analyze(cmd) == []


def test_dangerous_outside_quotes_still_caught():
    # Quoted decoy plus a real dangerous command afterwards
    blocks = analyze('echo "safe"; find /tmp -delete')
    assert any("-delete" in b.rule for b in blocks)


def test_dangerous_after_heredoc_still_caught():
    cmd = (
        "cat <<EOF\n"
        "docs\n"
        "EOF\n"
        "find /tmp -delete"
    )
    blocks = analyze(cmd)
    assert any("-delete" in b.rule for b in blocks)


def test_backtick_in_double_quote_does_not_break_quote_parsing():
    # Regression: a backtick block inside a double-quoted string contains
    # its own `"..."` pair. Naive quote tracking would think the inner `"`
    # closes the outer double quote, re-exposing later dangerous text.
    cmd = (
        'git commit -m "$(cat <<\'EOF\'\n'
        'mention `git commit -m "... find -delete ..."` in the body\n'
        'also show $(rm -rf /) as an example\n'
        'EOF\n'
        ')"'
    )
    assert analyze(cmd) == []


def test_heredoc_inside_double_quoted_substitution_is_safe():
    cmd = 'echo "pre $(cat <<\'EOF\'\nfind -delete\nEOF\n) post"'
    assert analyze(cmd) == []


def test_dangerous_command_substitution_inside_double_quotes_is_blocked():
    blocks = analyze('echo "$(find /tmp -delete)"')
    assert any("-delete" in block.rule for block in blocks)


def test_dangerous_backticks_inside_double_quotes_are_blocked():
    blocks = analyze('echo "`find /tmp -delete`"')
    assert any("-delete" in block.rule for block in blocks)


def test_hash_inside_word_does_not_start_comment():
    blocks = analyze("echo foo#tag; find /tmp -delete")
    assert any("-delete" in block.rule for block in blocks)


def test_find_exec_detects_sudo_wrapped_rm():
    blocks = analyze("find . -exec sudo rm {} \\;")
    assert any("exec rm" in block.rule for block in blocks)


def test_nested_parens_in_dollar_paren():
    # $(echo $(echo x)) — balanced depth must be tracked so we don't stop
    # at the first `)` and re-enter the surrounding string.
    cmd = 'echo "wrap $(cat <<\'EOF\'\nfind -delete\nsomething with (parens) inside\nEOF\n) end"'
    assert analyze(cmd) == []


def test_multiple_rules_can_match():
    blocks = analyze("find /tmp -delete; mkfs.ext4 /dev/sda1")
    rules = {b.rule for b in blocks}
    assert any("-delete" in r for r in rules)
    assert any("mkfs" in r for r in rules)


# --- main(): stdin event → exit code -----------------------------------------


def run_main(event, monkeypatch):
    monkeypatch.setattr(sys, "stdin", StringIO(json.dumps(event)))
    return block_dangerous_command.main()


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
    # apply_patch is a file edit, not a shell command; the detectors handle it.
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
