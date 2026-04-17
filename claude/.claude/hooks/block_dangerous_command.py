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


def _strip_comment(cmd: str) -> str:
    """Drop everything after an unquoted `#`."""
    out: list[str] = []
    in_sq = False
    in_dq = False
    for c in cmd:
        if c == "'" and not in_dq:
            in_sq = not in_sq
        elif c == '"' and not in_sq:
            in_dq = not in_dq
        elif c == "#" and not in_sq and not in_dq:
            break
        out.append(c)
    return "".join(out)


def analyze(command: str) -> list[Block]:
    """Return dangerous-rule matches for `command`. Pure function."""
    stripped = _strip_comment(command)
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
