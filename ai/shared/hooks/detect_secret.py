#!/usr/bin/env python3
"""PostToolUse hook: detect likely secrets in edited files.

Shared by Claude Code and Codex; distributed to both ~/.claude/hooks/ and
~/.codex/hooks/. Two event shapes are handled: Write|Edit carries the target in
`tool_input.file_path` (both tools), and apply_patch carries a freeform patch in
`tool_input.command` (Codex only — the branch is simply never taken under Claude
Code). Input normalization lives in `hook_input.edited_files`.

Strategy:
  - High-confidence patterns (cloud keys, PEM blocks, JWT) are matched directly.
  - A generic `KEY = "value"` pattern catches long random-looking assignments
    but filters obvious placeholders to cut false positives.
  - Example/template files skip generic assignments only; high-confidence
    token patterns are always checked.

Pure detection logic lives in `scan()` so it is testable without I/O.
"""

import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

from hook_input import FileTooLargeError, edited_files, read_files


class SecretFinding(NamedTuple):
    line_no: int
    kind: str
    snippet: str


# (name, compiled regex). Ordered; first match wins per line per pattern.
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("AWS Access Key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    (
        "GitHub Token",
        re.compile(r"\b(?:github_pat_[A-Za-z0-9_]{22,}|(?:ghp|gho|ghs|ghu|ghr)_[A-Za-z0-9_]{20,})\b"),
    ),
    ("Anthropic API Key", re.compile(r"\bsk-ant-api\d{2}-[A-Za-z0-9_\-]{20,}\b")),
    # OpenAI: sk-... but NOT sk-ant-
    (
        "OpenAI API Key",
        re.compile(r"\bsk-(?!ant)(?:(?:proj|admin|svcacct)-)?[A-Za-z0-9_-]{20,}\b"),
    ),
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
    p = Path(path).name.lower()
    return any(tok in p for tok in _EXAMPLE_PATH_TOKENS)


def _redact(line: str, limit: int = 120) -> str:
    redacted = line
    for _, pattern in PATTERNS:
        redacted = pattern.sub("<redacted>", redacted)

    def replace_generic_value(match: re.Match[str]) -> str:
        replacement = match.group(0)
        for group in ("value_sq", "value_dq", "value_nq"):
            if match.group(group) is not None:
                start, end = match.span(group)
                relative_start = start - match.start()
                relative_end = end - match.start()
                return (
                    replacement[:relative_start]
                    + "<redacted>"
                    + replacement[relative_end:]
                )
        return replacement

    redacted = _GENERIC_ASSIGN_RE.sub(replace_generic_value, redacted)
    return redacted if len(redacted) <= limit else redacted[:limit] + "..."


def scan(text: str, path: str = "") -> list[SecretFinding]:
    """Return a list of likely secrets in `text`. Pure function."""
    findings: list[SecretFinding] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        high_confidence_match = False
        for kind, pat in PATTERNS:
            if pat.search(line):
                findings.append(SecretFinding(line_no, kind, _redact(line)))
                high_confidence_match = True
                break  # one pattern match per line is enough

        if len(findings) >= 10:
            break
        if high_confidence_match or is_example_path(path):
            continue

        m = _GENERIC_ASSIGN_RE.search(line)
        if m:
            value = m.group("value_sq") or m.group("value_dq") or m.group("value_nq") or ""
            if _PLACEHOLDER_RE.search(line) or _PLACEHOLDER_RE.search(value):
                continue
            if _VERSION_RE.match(value):
                continue
            findings.append(SecretFinding(line_no, "generic secret assignment", _redact(line)))
            if len(findings) >= 10:
                break

    return findings


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    paths = edited_files(event)
    if not paths:
        return 0

    first_findings: list[tuple[Path, SecretFinding]] = []
    extra_findings: list[tuple[Path, SecretFinding]] = []
    try:
        for path, text in read_files(paths):
            path_findings = scan(text, str(path))
            if not path_findings:
                continue
            if len(first_findings) < 10:
                first_findings.append((path, path_findings[0]))
            remaining = 10 - len(extra_findings)
            extra_findings.extend(
                (path, finding) for finding in path_findings[1 : remaining + 1]
            )
    except FileTooLargeError as exc:
        print(f"SECRET SCAN BLOCKED: {exc}", file=sys.stderr)
        return 2

    findings = first_findings + extra_findings[: max(0, 10 - len(first_findings))]

    if not findings:
        return 0

    print(f"SECRET DETECTED in {', '.join(paths)}", file=sys.stderr)
    for path, finding in findings[:10]:
        print(
            f"  {path}:{finding.line_no} [{finding.kind}]: {finding.snippet}",
            file=sys.stderr,
        )
    print("", file=sys.stderr)
    print(
        "Remove the secret immediately. Use environment variables or a secret manager.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
