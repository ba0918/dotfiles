#!/usr/bin/env python3
"""PostToolUse hook: detect likely secrets in edited files (Codex port).

Codex triggers this for Write|Edit (target path in `tool_input.file_path`)
and apply_patch (unified diff in `tool_input.command`). Pure detection logic
(`scan` / patterns) is identical to the Claude Code version.

Strategy:
  - High-confidence patterns (cloud keys, PEM blocks, JWT) are matched directly.
  - A generic `KEY = "value"` pattern catches long random-looking assignments
    but filters obvious placeholders to cut false positives.
  - Files that look like examples / templates are skipped entirely.

Pure detection logic lives in `scan()` so it is testable without I/O.
"""

import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

from codex_input import edited_files


class SecretFinding(NamedTuple):
    line_no: int
    kind: str
    snippet: str


# (name, compiled regex). Ordered; first match wins per line per pattern.
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("AWS Access Key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("GitHub Token", re.compile(r"\b(?:ghp|gho|ghs|ghu|ghr)_[A-Za-z0-9]{36}\b")),
    ("Anthropic API Key", re.compile(r"\bsk-ant-api\d{2}-[A-Za-z0-9_\-]{20,}\b")),
    # OpenAI: sk-... but NOT sk-ant-
    ("OpenAI API Key", re.compile(r"\bsk-(?!ant)[A-Za-z0-9]{20,}\b")),
    ("Google API Key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("Slack Token", re.compile(r"\bxox[abprs]-[0-9A-Za-z\-]{10,}\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b")),
    ("PEM Private Key", re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----")),
]

_GENERIC_ASSIGN_RE = re.compile(
    r"(?i)(?:api[_-]?key|secret(?:[_-]?key)?|access[_-]?token|auth[_-]?token|bearer[_-]?token|password|passwd|pwd)"
    r"\s*[:=]\s*"
    r"(?:"
    r"'(?P<value_sq>[^']{16,})'"            # single-quoted, min 16 chars (any non-quote)
    r'|"(?P<value_dq>[^"]{16,})"'           # double-quoted, min 16 chars
    r"|(?P<value_nq>[A-Za-z0-9_\-+/=]{24,})"  # unquoted, min 24 alnum-ish
    r")"
)

_PLACEHOLDER_RE = re.compile(
    r"(?i)(?:your|sample|example|placeholder|dummy|change[_-]?me|insert[_-]?here|fake|fill[_-]?in|todo|xxx{2,})"
    r"|<[a-z_\-]+>"
)

_VERSION_RE = re.compile(r"^[\d.]+$")

_EXAMPLE_PATH_TOKENS = (".example", "example.", ".sample", "sample.", ".template", "template.")


def is_example_path(path: str) -> bool:
    p = path.lower()
    return any(tok in p for tok in _EXAMPLE_PATH_TOKENS)


def _redact(line: str, limit: int = 120) -> str:
    return line if len(line) <= limit else line[:limit] + "..."


def scan(text: str, path: str = "") -> list[SecretFinding]:
    """Return a list of likely secrets in `text`. Pure function."""
    if is_example_path(path):
        return []

    findings: list[SecretFinding] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for kind, pat in PATTERNS:
            if pat.search(line):
                findings.append(SecretFinding(line_no, kind, _redact(line)))
                break  # one pattern match per line is enough

        m = _GENERIC_ASSIGN_RE.search(line)
        if m:
            value = m.group("value_sq") or m.group("value_dq") or m.group("value_nq") or ""
            if _PLACEHOLDER_RE.search(line) or _PLACEHOLDER_RE.search(value):
                continue
            if _VERSION_RE.match(value):
                continue
            findings.append(SecretFinding(line_no, "generic secret assignment", _redact(line)))

    return findings


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    paths = edited_files(event)
    if not paths:
        return 0

    findings: list[SecretFinding] = []
    for file_str in paths:
        path = Path(file_str)
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        findings.extend(scan(text, str(path)))

    if not findings:
        return 0

    print(f"SECRET DETECTED in {', '.join(paths)}", file=sys.stderr)
    for f in findings[:10]:
        print(f"  line {f.line_no} [{f.kind}]: {f.snippet}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "Remove the secret immediately. Use environment variables or a secret manager.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
