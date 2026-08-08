#!/usr/bin/env python3
"""PreToolUse hook: block dangerous Bash commands.

Catches variants the settings.json `deny` list typically misses:
  - find ... -delete  /  -exec rm
  - xargs rm
  - dd of=/dev/sd* (disk wipe)
  - mkfs (format)
  - shred, wipefs
  - rm -rf wrapped in `$(...)` or backticks (deny list checks prefix only)

Pure detection lives in `analyze()` for testability.
"""

import json
import re
import sys
from typing import NamedTuple


class Block(NamedTuple):
    rule: str
    match: str


# Each entry: (human-readable rule, regex). Regex operates on a stripped
# (comment-free) command string.
DANGEROUS_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("find ... -delete", re.compile(r"\bfind\b[^|;&`$]*-delete\b")),
    ("find ... -exec rm", re.compile(r"\bfind\b[^|;&`$]*-exec\s+(?:rm|rmdir)\b")),
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

    Trade-off: this also masks command substitutions (`$(...)`, backticks)
    that are nested inside double quotes, so pathological cases such as
    `echo "$(rm -rf /)"` slip through. Acceptable — for this user-scope
    hook we optimize for low FP rate over exotic attack coverage.
    """
    out: list[str] = []
    i = 0
    n = len(cmd)
    while i < n:
        c = cmd[i]

        if c == "#":
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
                    # Nested backtick command substitution — skip whole block
                    # so the inner `"..."` doesn't look like the outer closer
                    if cmd[i] == "`":
                        i += 1
                        while i < n and cmd[i] != "`":
                            if cmd[i] == "\\" and i + 1 < n:
                                i += 2
                                continue
                            i += 1
                        i += 1  # past closing backtick (or end)
                        continue
                    # Nested $( ... ) command substitution with balanced parens
                    if cmd[i] == "$" and i + 1 < n and cmd[i + 1] == "(":
                        depth = 1
                        i += 2  # past "$("
                        while i < n and depth > 0:
                            if cmd[i] == "(":
                                depth += 1
                            elif cmd[i] == ")":
                                depth -= 1
                            i += 1
                        continue
                i += 1
            i += 1  # skip closing quote (or past end)
            continue

        out.append(c)
        i += 1

    return "".join(out)


def analyze(command: str) -> list[Block]:
    """Return dangerous-rule matches for `command`. Pure function."""
    stripped = _strip_noise(command)
    blocks: list[Block] = []
    for rule, pat in DANGEROUS_PATTERNS:
        m = pat.search(stripped)
        if m:
            blocks.append(Block(rule, m.group(0)[:120]))
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

    blocks = analyze(command)
    if not blocks:
        return 0

    print(f"DANGEROUS COMMAND BLOCKED: {command[:160]}", file=sys.stderr)
    for b in blocks:
        print(f"  rule : {b.rule}", file=sys.stderr)
        print(f"  match: {b.match}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "If this is intentional, pick a safer equivalent or ask the user to run it manually.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
