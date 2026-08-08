"""Input parsing helpers shared by Codex file hooks.

Codex triggers hooks with an event JSON on stdin. File edits arrive in two
shapes: Claude-compatible `Write`/`Edit` events carrying `tool_input.file_path`,
and Codex's `apply_patch` events carrying a unified diff in `tool_input.command`.
This module normalizes both into a plain list of edited file paths.
"""


def extract_patch_files(diff: str) -> list[str]:
    """Extract changed file paths from a unified diff.

    Only `+++ ` header lines are read (git prefixes them with `b/`, plain
    `diff -u` output has no prefix). `/dev/null` (deletion) is skipped and
    `---` source lines are ignored. Paths are returned relative to cwd.
    """
    files: list[str] = []
    for line in diff.splitlines():
        if not line.startswith("+++ "):
            continue
        path = line[4:].strip()
        if not path or path == "/dev/null":
            continue
        if path.startswith("b/"):
            path = path[2:]
        if path:
            files.append(path)
    return files


def edited_files(event: dict) -> list[str]:
    """Resolve the edited file paths for a hook event (dual-format).

    `Write`/`Edit` events carry the target path directly; `apply_patch` events
    carry a unified diff whose changed files are extracted.
    """
    tool = event.get("tool_name")
    tool_input = event.get("tool_input") or {}
    if tool in ("Write", "Edit"):
        path = tool_input.get("file_path")
        return [path] if path else []
    if tool == "apply_patch":
        return extract_patch_files(tool_input.get("command", ""))
    return []
