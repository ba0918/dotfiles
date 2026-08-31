#!/usr/bin/env python3
"""PreToolUse hook: block dangerous Bash commands.

Catches variants the settings.json `deny` list typically misses:
  - find ... -delete  /  -exec rm
  - xargs rm
  - dd of=/dev/sd* (disk wipe)
  - mkfs (format)
  - shred, wipefs
  - rm -rf wrapped in `$(...)` or backticks (deny list checks prefix only)

and decides `rm` / `rmdir` by where the deletion lands (`analyze_rm`): the
session directory and the tmp roots are deletable, everything else is not.
The deny list cannot express that — it matches command prefixes and is
evaluated before any hook runs — so rm is judged here and not listed there.

Pure detection lives in `analyze()` / `analyze_rm()` for testability.
"""

import json
import os
import re
import shlex
import sys
from typing import NamedTuple


class Block(NamedTuple):
    rule: str
    match: str


# Each entry: (human-readable rule, regex). Regex operates on a stripped
# (comment-free) command string.
DANGEROUS_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("find ... -delete", re.compile(r"\bfind\b[^|;&`$]*-delete\b")),
    ("find ... -exec rm", re.compile(r"\bfind\b[^|;&`$]*-exec\s+(?:(?:sudo|env)\b(?:\s+-\S+)*\s+)*(?:rm|rmdir)\b")),
    ("xargs rm", re.compile(r"\bxargs\b[^|;&`$]*\s(?:rm|rmdir)\b")),
    ("dd to block device", re.compile(r"\bdd\b[^|;&`$]*\bof=/dev/(?:sd|nvme|hd|vd|mmcblk|xvd)")),
    ("mkfs", re.compile(r"\bmkfs(?:\.[a-z0-9]+)?\b")),
    ("shred", re.compile(r"\bshred\s+(?!-h\b|--help\b)")),
    ("wipefs", re.compile(r"\bwipefs\b")),
    ("rm -rf inside $( ... )", re.compile(r"\$\([^)]*\brm\s+-[a-zA-Z]*[rRf][a-zA-Z]*\s[^)]*\)")),
    ("rm -rf inside backticks", re.compile(r"`[^`]*\brm\s+-[a-zA-Z]*[rRf][a-zA-Z]*\s[^`]*`")),
]


_HEREDOC_START_RE = re.compile(r"<<-?\s*[\"']?(\w+)[\"']?")


def _strip_noise(cmd: str) -> str:
    """Remove shell noise that is not itself executed as a command:
    comments, quoted strings (both kinds), and heredoc bodies.

    Rationale: regex detection was producing false positives on things like
    `git commit -m "... xargs rm ..."` where dangerous words appear inside
    string literals. Stripping these regions first keeps detection focused
    on the actual command surface.

    Single-quoted content is inert. Double-quoted literal content is removed,
    while command substitutions are retained because the shell executes them.
    """
    out: list[str] = []
    i = 0
    n = len(cmd)
    while i < n:
        c = cmd[i]

        if c == "#" and (i == 0 or cmd[i - 1].isspace() or cmd[i - 1] in ";|&()"):
            while i < n and cmd[i] != "\n":
                i += 1
            continue

        if c == "<" and i + 1 < n and cmd[i + 1] == "<":
            m = _HEREDOC_START_RE.match(cmd, i)
            if m:
                delim = m.group(1)
                # Replace the whole heredoc (marker + body + terminator) with
                # a single space so that tokens on either side stay separated
                # for word-boundary regex matching.
                out.append(" ")
                i = m.end()
                end_re = re.compile(rf"\n\t*{re.escape(delim)}(?:\n|$)")
                em = end_re.search(cmd, i)
                i = em.end() if em else n
                continue

        if c in ("'", '"'):
            quote = c
            i += 1
            while i < n and cmd[i] != quote:
                if quote == '"':
                    # Escape sequence
                    if cmd[i] == "\\" and i + 1 < n:
                        i += 2
                        continue
                    # Double quotes preserve command substitution semantics.
                    if cmd[i] == "`":
                        start = i
                        i += 1
                        while i < n and cmd[i] != "`":
                            if cmd[i] == "\\" and i + 1 < n:
                                i += 2
                                continue
                            i += 1
                        i += 1  # past closing backtick (or end)
                        out.append(_strip_noise(cmd[start:i]))
                        continue
                    if cmd[i] == "$" and i + 1 < n and cmd[i + 1] == "(":
                        start = i
                        depth = 1
                        i += 2  # past "$("
                        while i < n and depth > 0:
                            if cmd[i] == "(":
                                depth += 1
                            elif cmd[i] == ")":
                                depth -= 1
                            i += 1
                        out.append(_strip_noise(cmd[start:i]))
                        continue
                i += 1
            i += 1  # skip closing quote (or past end)
            continue

        out.append(c)
        i += 1

    return "".join(out)


# --- rm: the target decides, not the flags ----------------------------------
#
# Kept in this file rather than a module of its own: the hook files are
# distributed one by one (mise/config.toml lists every ~/.claude/hooks and
# ~/.codex/hooks entry), so a helper module would have to be registered in
# both places and a missing copy would fail at import time inside the hook.

_RM_NAMES = frozenset({"rm", "rmdir"})
_PRIVILEGE_WRAPPERS = frozenset({"sudo", "doas"})
_TRANSPARENT_WRAPPERS = frozenset(
    {"env", "command", "nice", "ionice", "timeout", "nohup", "time", "exec", "builtin", "stdbuf", "setsid", "flock"}
)
_SHELLS = frozenset({"bash", "sh", "dash", "zsh", "ksh", "fish"})
# Programs with a subcommand spelled `rm` that is not the rm binary.
_RM_IS_SUBCOMMAND_OF = frozenset(
    {"git", "docker", "podman", "kubectl", "helm", "npm", "pnpm", "yarn", "bun", "gh", "mise", "cargo", "rclone", "aws", "gsutil"}
)
_SEPARATOR_CHARS = ";|&\n"
_GLOB_CHARS = "*?["
_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_DURATION_RE = re.compile(r"^\d+(?:\.\d+)?[smhd]?$")
_RM_WORD_RE = re.compile(r"\brm(?:dir)?\b")


class _RmContext(NamedTuple):
    cwd: str | None
    home: str | None
    tmpdir: str | None
    roots: tuple[str, ...]


def _deletable_roots(cwd: str | None, home: str | None, tmp_roots: tuple[str, ...]) -> tuple[str, ...]:
    roots = [os.path.normpath(r) for r in tmp_roots if r]
    if cwd:
        c = os.path.normpath(cwd)
        # A session started in $HOME (or above it) would make the whole home
        # deletable; only the tmp roots remain in that case.
        covers_home = c == "/" or (home is not None and (home == c or home.startswith(c + "/")))
        if not covers_home:
            roots.insert(0, c)
    return tuple(roots)


def _strip_heredocs_and_comments(cmd: str) -> str:
    """Drop heredoc bodies and comments but keep quoted strings, which the
    tokenizer needs to recover paths with spaces. Quotes are tracked only so
    a `#` or `<<` inside them is not mistaken for a comment or heredoc."""
    out: list[str] = []
    i = 0
    n = len(cmd)
    quote: str | None = None
    while i < n:
        c = cmd[i]
        if quote:
            out.append(c)
            if c == "\\" and quote == '"' and i + 1 < n:
                out.append(cmd[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in ("'", '"'):
            quote = c
            out.append(c)
            i += 1
            continue
        if c == "#" and (i == 0 or cmd[i - 1].isspace() or cmd[i - 1] in ";|&()"):
            while i < n and cmd[i] != "\n":
                i += 1
            continue
        if c == "<" and i + 1 < n and cmd[i + 1] == "<":
            m = _HEREDOC_START_RE.match(cmd, i)
            if m:
                delim = m.group(1)
                # The terminator's newline is consumed with the body; a newline
                # is put back so the next line stays a separate subcommand.
                out.append("\n")
                end_re = re.compile(rf"\n\t*{re.escape(delim)}(?:\n|$)")
                em = end_re.search(cmd, m.end())
                i = em.end() if em else n
                continue
        out.append(c)
        i += 1
    return "".join(out)


def _tokenize(command: str) -> list[str]:
    lex = shlex.shlex(_strip_heredocs_and_comments(command), posix=True, punctuation_chars=_SEPARATOR_CHARS)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    return list(lex)


def _is_separator(tok: str) -> bool:
    return tok != "" and all(c in _SEPARATOR_CHARS for c in tok)


def _subcommands(tokens: list[str]) -> list[list[str]]:
    subs: list[list[str]] = [[]]
    for tok in tokens:
        if _is_separator(tok):
            subs.append([])
        else:
            subs[-1].append(tok)
    return [s for s in subs if s]


def _basename(tok: str) -> str:
    return tok.rsplit("/", 1)[-1] if "/" in tok else tok


def _expand(raw: str, ctx: _RmContext) -> str | None:
    """Expand the few variables whose value the hook knows; None if anything
    else would still be expanded by the shell."""
    s = raw
    if s == "~" or s.startswith("~/"):
        if ctx.home is None:
            return None
        s = ctx.home + s[1:]
    elif s.startswith("~"):
        return None
    for name, value in (("HOME", ctx.home), ("PWD", ctx.cwd), ("TMPDIR", ctx.tmpdir)):
        for form in ("${" + name + "}", "$" + name):
            if value and s.startswith(form) and (len(s) == len(form) or s[len(form)] == "/"):
                s = value + s[len(form):]
                break
    if "$" in s or "`" in s:
        return None
    return s


def _glob_base(path: str) -> tuple[str, bool]:
    """Longest prefix of `path` that a glob cannot widen. A component whose
    literal prefix before the first glob char is empty (or only dots, as in
    `.*`) can match anything in its parent, so the parent is the base."""
    parts = path.split("/")
    for i, comp in enumerate(parts):
        pos = next((k for k, ch in enumerate(comp) if ch in _GLOB_CHARS), -1)
        if pos < 0:
            continue
        if comp[:pos].strip(".") == "":
            base = "/".join(parts[:i])
            return (base or "/", True)
    return (path, False)


def _real_target(path: str, trailing_slash: bool) -> str:
    # rm on a symlink removes the link, not what it points to, so only the
    # parent is resolved; with a trailing slash rm follows the link instead.
    if trailing_slash:
        return os.path.realpath(path)
    return os.path.join(os.path.realpath(os.path.dirname(path)), os.path.basename(path))


def _inside(path: str, root: str) -> bool:
    return path == root or path.startswith(root + "/")


def _containing_root(path: str, real: str, roots: tuple[str, ...]) -> str | None:
    for root in roots:
        if _inside(path, root) and _inside(real, os.path.realpath(root)):
            return root
    return None


def _touches_git_metadata(path: str) -> bool:
    parts = path.split("/")
    if ".git" not in parts:
        return False
    tail = parts[parts.index(".git") + 1:]
    if not tail:
        return True
    return not tail[-1].endswith(".lock")


def _check_target(raw: str, ctx: _RmContext, relative_ok: bool) -> Block | None:
    path = _expand(raw, ctx)
    if path is None:
        return Block("rm with unresolved expansion", raw[:120])
    if not os.path.isabs(path):
        if not relative_ok:
            return Block("rm relative path after cd", raw[:120])
        if not ctx.cwd:
            return Block("rm outside the session directory and tmp", raw[:120])
        path = os.path.join(ctx.cwd, path)
    path = os.path.normpath(path)
    base, _widened = _glob_base(path)
    real = _real_target(base, raw.endswith("/"))
    root = _containing_root(base, real, ctx.roots)
    if root is None:
        return Block("rm outside the session directory and tmp", f"{raw} -> {base}"[:120])
    if base == root:
        return Block("rm of an allowed root itself", f"{raw} -> {base}"[:120])
    if _touches_git_metadata(base):
        return Block("rm of .git", f"{raw} -> {base}"[:120])
    return None


def _check_rm_args(args: list[str], ctx: _RmContext, relative_ok: bool) -> list[Block]:
    targets: list[str] = []
    options_done = False
    for a in args:
        if not options_done:
            if a == "--":
                options_done = True
                continue
            if a.startswith("-") and a != "-":
                if a == "--no-preserve-root":
                    return [Block("rm --no-preserve-root", " ".join(args)[:120])]
                continue
        targets.append(a)
    blocks: list[Block] = []
    for t in targets:
        b = _check_target(t, ctx, relative_ok)
        if b:
            blocks.append(b)
    return blocks


def _check_subcommand(sub: list[str], ctx: _RmContext, relative_ok: bool) -> list[Block]:
    i = 0
    while i < len(sub):
        tok = sub[i]
        if _ASSIGNMENT_RE.match(tok) or tok.startswith("-") or _DURATION_RE.match(tok) or _basename(tok) in _TRANSPARENT_WRAPPERS:
            i += 1
            continue
        break
    if i >= len(sub):
        return []
    head = _basename(sub[i])
    rest = sub[i + 1:]
    joined = " ".join(sub)[:120]
    if head in _PRIVILEGE_WRAPPERS:
        if any(_basename(t) in _RM_NAMES for t in rest):
            return [Block("sudo rm", joined)]
        return []
    if head in _SHELLS:
        for j, t in enumerate(rest):
            if t.startswith("-") and "c" in t and j + 1 < len(rest):
                return _analyze_rm(rest[j + 1], ctx, relative_ok)
        return []
    if head == "eval":
        return _analyze_rm(" ".join(rest), ctx, relative_ok)
    if head in _RM_NAMES:
        return _check_rm_args(rest, ctx, relative_ok)
    if head in _RM_IS_SUBCOMMAND_OF:
        return []
    # `rm` behind a program this hook does not know: it may be a wrapper that
    # executes it (chronic, strace, ...), so refuse rather than guess.
    for j, t in enumerate(rest):
        if _basename(t) in _RM_NAMES and j + 1 < len(rest):
            return [Block("rm behind an unrecognized wrapper", joined)]
    return []


def _analyze_rm(command: str, ctx: _RmContext, relative_ok: bool) -> list[Block]:
    if not _RM_WORD_RE.search(command):
        return []
    try:
        tokens = _tokenize(command)
    except ValueError as e:
        return [Block("rm command could not be parsed", str(e)[:120])]
    subs = _subcommands(tokens)
    if any(_basename(s[0]) in ("cd", "pushd") for s in subs):
        relative_ok = False
    blocks: list[Block] = []
    for sub in subs:
        blocks.extend(_check_subcommand(sub, ctx, relative_ok))
    return blocks


def analyze_rm(
    command: str,
    *,
    cwd: str | None,
    home: str | None,
    tmp_roots: tuple[str, ...],
    tmpdir: str | None = None,
) -> list[Block]:
    """Blocks for every `rm` / `rmdir` in `command` whose target is not
    inside `cwd` or one of `tmp_roots`. Pure function."""
    ctx = _RmContext(cwd=cwd, home=home, tmpdir=tmpdir, roots=_deletable_roots(cwd, home, tmp_roots))
    return _analyze_rm(command, ctx, relative_ok=True)


def analyze(command: str, cwd: str | None = None) -> list[Block]:
    """Return dangerous-rule matches for `command`. Pure function."""
    stripped = _strip_noise(command)
    blocks: list[Block] = []
    for rule, pat in DANGEROUS_PATTERNS:
        m = pat.search(stripped)
        if m:
            blocks.append(Block(rule, m.group(0)[:120]))
    tmpdir = os.environ.get("TMPDIR") or None
    tmp_roots: tuple[str, ...] = ("/tmp", "/var/tmp") + ((tmpdir,) if tmpdir else ())
    blocks.extend(analyze_rm(command, cwd=cwd, home=os.environ.get("HOME"), tmp_roots=tmp_roots, tmpdir=tmpdir))
    return blocks


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if event.get("tool_name") != "Bash":
        return 0

    command = event.get("tool_input", {}).get("command", "")
    if not command:
        return 0

    cwd = event.get("cwd") or os.getcwd()
    try:
        blocks = analyze(command, cwd=cwd)
    except Exception as e:  # noqa: BLE001 - a broken guard must refuse, not wave through
        print(f"DANGEROUS COMMAND HOOK FAILED, refusing the command: {e!r}", file=sys.stderr)
        return 2
    if not blocks:
        return 0

    print(f"DANGEROUS COMMAND BLOCKED: {command[:160]}", file=sys.stderr)
    for b in blocks:
        print(f"  rule : {b.rule}", file=sys.stderr)
        print(f"  match: {b.match}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "rm/rmdir may only delete inside the session directory or /tmp; use a literal path there,"
        " or ask the user to run it manually.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
