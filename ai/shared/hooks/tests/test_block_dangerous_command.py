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


def test_plain_rm_under_tmp_is_allowed_without_a_cwd():
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


# --- rm: the target decides, not the flags -----------------------------------
#
# The settings.json deny list used to refuse every `rm -r` / `rm -f` / `rmdir`
# by prefix, which also refused deleting the agent's own scratch directories.
# The hook resolves where the deletion lands instead: the session directory
# and the tmp roots are deletable, everything else is not.

from block_dangerous_command import analyze_rm

CWD = "/home/u/proj"
HOME = "/home/u"
TMP = ("/tmp", "/var/tmp")


def rm_rules(command, cwd=CWD, home=HOME, tmp_roots=TMP, tmpdir=None):
    return [b.rule for b in analyze_rm(command, cwd=cwd, home=home, tmp_roots=tmp_roots, tmpdir=tmpdir)]


def test_rm_under_tmp_scratchpad_is_allowed():
    assert rm_rules("rm -rf /tmp/claude-1000/-home-u-proj/abc/scratchpad/work") == []


def test_rm_of_a_relative_path_inside_cwd_is_allowed():
    assert rm_rules("rm -rf build/") == []
    assert rm_rules("rmdir empty") == []
    assert rm_rules("rm -f out.log") == []


def test_rm_of_an_absolute_path_inside_cwd_is_allowed():
    assert rm_rules("rm -rf /home/u/proj/sub/x") == []


def test_rm_of_a_stale_git_lock_is_allowed():
    assert rm_rules("rm .git/index.lock") == []


def test_tilde_home_pwd_and_tmpdir_expand_before_the_check():
    assert rm_rules("rm -rf ~/proj/sub") == []
    assert rm_rules("rm -rf $HOME/proj/sub") == []
    assert rm_rules("rm -rf ${HOME}/proj/sub") == []
    assert rm_rules("rm -rf $PWD/build") == []
    assert rm_rules("rm -rf $TMPDIR/x", tmp_roots=TMP + ("/run/user/1000/tmp",), tmpdir="/run/user/1000/tmp") == []


def test_glob_below_a_directory_inside_cwd_is_allowed():
    assert rm_rules("rm -rf build/*") == []
    assert rm_rules("rm -f logs/*.log") == []


def test_glob_component_with_a_literal_prefix_stays_inside_its_parent():
    assert rm_rules("rm -rf /tmp/codex-jail-wt.*") == []


def test_quoted_target_with_spaces_is_resolved_as_one_path():
    assert rm_rules('rm -f "a b/c.txt"') == []


def test_rm_inside_a_string_argument_is_not_a_command():
    assert rm_rules('git commit -m "rm -rf /"') == []
    assert rm_rules("grep -rn 'rm -rf' .") == []


def test_rm_without_targets_is_ignored():
    assert rm_rules("rm --help") == []
    assert rm_rules("which rm") == []
    assert rm_rules("command -v rm") == []


def test_rm_after_a_safe_command_in_a_compound_is_allowed():
    assert rm_rules("ls && rm -rf build") == []
    assert rm_rules("make clean; rm -f out.o") == []


def test_rm_outside_cwd_is_blocked():
    assert "outside" in rm_rules("rm -rf ../other")[0]
    assert "outside" in rm_rules("rm -rf ~/.config")[0]
    assert "outside" in rm_rules("rm ~/foo")[0]
    assert "outside" in rm_rules("rm -rf /home/u/other")[0]
    assert "outside" in rm_rules("rm -rf /")[0]
    assert "outside" in rm_rules("rm -rf /etc/passwd")[0]


def test_rm_of_an_allowed_root_itself_is_blocked():
    for cmd in ("rm -rf .", "rm -rf ./", "rm -rf *", "rm -rf ./*", "rm -rf .*", "rm -rf /tmp", "rm -rf /tmp/*", "rm -rf /home/u/proj"):
        assert any("root" in r for r in rm_rules(cmd)), cmd


def test_rm_of_git_metadata_is_blocked():
    for cmd in ("rm -rf .git", "rm -rf .git/objects", "rm -rf sub/.git", "rm .git/HEAD"):
        assert any(".git" in r for r in rm_rules(cmd)), cmd


def test_rm_with_an_unresolved_expansion_is_blocked():
    for cmd in ("rm -rf $DIR/x", "rm -rf ${DIR}/x", "rm -rf $(pwd)/x", "rm -rf `pwd`/x", "rm -rf ~other/x"):
        assert any("expansion" in r for r in rm_rules(cmd)), cmd


def test_rm_no_preserve_root_is_blocked():
    assert any("no-preserve-root" in r for r in rm_rules("rm --no-preserve-root -rf build"))


def test_sudo_rm_is_blocked_regardless_of_target():
    assert any("sudo" in r for r in rm_rules("sudo rm -rf build"))
    assert any("sudo" in r for r in rm_rules("doas rm -rf build"))


def test_relative_rm_after_cd_is_blocked_absolute_is_checked():
    assert any("cd" in r for r in rm_rules("cd /tmp && rm -rf x"))
    assert rm_rules("cd /tmp && rm -rf /tmp/x") == []


def test_rm_through_a_shell_c_or_eval_is_checked_too():
    assert any("outside" in r for r in rm_rules('bash -c "rm -rf ~/x"'))
    assert any("outside" in r for r in rm_rules("eval rm -rf ~/x"))
    assert rm_rules("sh -c 'rm -rf build'") == []


def test_rm_by_path_and_behind_known_wrappers_is_checked():
    for cmd in ("/bin/rm -rf ~/x", "env rm -rf ~/x", "timeout 5 rm -rf ~/x", "nohup rm -rf ~/x", "FOO=1 rm -rf ~/x"):
        assert any("outside" in r for r in rm_rules(cmd)), cmd


def test_rm_behind_an_unrecognized_wrapper_is_blocked():
    assert any("wrapper" in r for r in rm_rules("chronic rm -rf build"))


def test_cwd_at_home_or_root_is_not_a_deletable_area():
    assert any("outside" in r for r in rm_rules("rm -rf foo", cwd="/home/u"))
    assert any("outside" in r for r in rm_rules("rm -rf etc", cwd="/"))
    assert rm_rules("rm -rf /tmp/x", cwd="/home/u") == []


def test_unparseable_rm_command_is_blocked():
    assert any("parse" in r for r in rm_rules("rm 'x"))


def test_symlink_escaping_the_session_directory_is_blocked(tmp_path):
    proj = tmp_path / "proj"
    outside = tmp_path / "outside"
    (proj).mkdir()
    (outside / "sub").mkdir(parents=True)
    (proj / "link").symlink_to(outside)
    rules = rm_rules("rm -rf link/sub", cwd=str(proj), home=str(tmp_path), tmp_roots=())
    assert any("outside" in r for r in rules)
    assert rm_rules("rm -rf link", cwd=str(proj), home=str(tmp_path), tmp_roots=()) == []


def test_heredoc_body_mentioning_rm_does_not_break_parsing():
    # A heredoc may carry apostrophes and rm-looking text (a Python script,
    # a commit message); it is data for the command, not a command.
    cmd = "\n".join(
        [
            "python3 - <<'PY'",
            "old = '''  - \"rm -rf:*\"",
            "# rm is judged by the agent's own hook now",
            "'''",
            "PY",
        ]
    )
    assert rm_rules(cmd) == []


def test_comment_mentioning_rm_is_ignored():
    assert rm_rules("ls # rm -rf 'x") == []


def test_rm_after_a_heredoc_is_still_checked():
    cmd = "cat <<EOF\nnotes\nEOF\nrm -rf ~/x"
    assert any("outside" in r for r in rm_rules(cmd))


def test_analyze_applies_the_rm_policy_with_the_given_cwd():
    blocks = analyze("rm -rf ~/x", cwd=CWD)
    assert any("outside" in b.rule for b in blocks)


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


def test_blocks_rm_outside_the_event_cwd(monkeypatch):
    rc = run_main(
        {"tool_name": "Bash", "tool_input": {"command": "rm -rf ../other"}, "cwd": CWD},
        monkeypatch,
    )
    assert rc == 2


def test_allows_rm_inside_the_event_cwd(monkeypatch):
    rc = run_main(
        {"tool_name": "Bash", "tool_input": {"command": "rm -rf build"}, "cwd": CWD},
        monkeypatch,
    )
    assert rc == 0


def test_a_crash_in_the_rm_policy_blocks_instead_of_allowing(monkeypatch):
    def boom(*_args, **_kwargs):
        raise RuntimeError("bug")

    monkeypatch.setattr(block_dangerous_command, "analyze_rm", boom)
    rc = run_main(
        {"tool_name": "Bash", "tool_input": {"command": "rm -rf build"}, "cwd": CWD},
        monkeypatch,
    )
    assert rc == 2


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
