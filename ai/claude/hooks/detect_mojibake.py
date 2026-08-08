#!/usr/bin/env python3
"""PostToolUse hook: detect mojibake, BOM, control chars, question-mark runs.

Triggered for Write|Edit events. Scans the edited file and, if any of the
patterns is found, exits 2 so Claude Code surfaces the warning back to the
assistant for immediate fix.

Pure detection logic lives in `scan()` so it is testable without I/O.
"""

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple


MOJIBAKE_CHAR = "\ufffd"
BOM_CHAR = "\ufeff"
_CONTROL_CHAR_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
_QUESTION_RUN_RE = re.compile(r"\?{5,}")


class Finding(NamedTuple):
    line_no: int
    reason: str
    snippet: str


def scan(text: str) -> list[Finding]:
    """Return a list of suspicious findings in `text`.

    Pure function. Line numbers are 1-indexed.
    """
    findings: list[Finding] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        if MOJIBAKE_CHAR in line:
            idx = line.index(MOJIBAKE_CHAR)
            snippet = line[max(0, idx - 20):idx + 20]
            findings.append(Finding(line_no, "U+FFFD replacement character", snippet))

        if line_no == 1 and line.startswith(BOM_CHAR):
            findings.append(Finding(line_no, "UTF-8 BOM at file start", line[:40]))

        m = _CONTROL_CHAR_RE.search(line)
        if m:
            findings.append(
                Finding(line_no, f"control char 0x{ord(m.group()):02x}", line[:40])
            )

        m = _QUESTION_RUN_RE.search(line)
        if m:
            findings.append(Finding(line_no, "question-mark run (possible lost encoding)", m.group()))
    return findings


def _is_binary(path: Path) -> bool:
    try:
        result = subprocess.run(
            ["file", str(path)],
            capture_output=True, text=True, timeout=2,
        )
        return "binary" in result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if event.get("tool_name") not in ("Write", "Edit"):
        return 0

    file_str = event.get("tool_input", {}).get("file_path")
    if not file_str:
        return 0

    path = Path(file_str)
    if not path.is_file():
        return 0

    if _is_binary(path):
        return 0

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0

    findings = scan(text)
    if not findings:
        return 0

    print(f"MOJIBAKE/CONTROL CHAR DETECTED in {path}", file=sys.stderr)
    for f in findings[:10]:
        print(f"  line {f.line_no} [{f.reason}]: {f.snippet}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Fix the corrupted characters immediately.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
