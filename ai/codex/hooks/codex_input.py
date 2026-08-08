"""Input parsing helpers shared by Codex file hooks.

Codex triggers hooks with an event JSON on stdin. File edits arrive in two
shapes: Claude-compatible `Write`/`Edit` events carrying `tool_input.file_path`,
and Codex's `apply_patch` events carrying a freeform patch in
`tool_input.command`. This module normalizes both into a plain list of edited
file paths.
"""

_ADD_PREFIX = "*** Add File: "
_UPDATE_PREFIX = "*** Update File: "
_DELETE_PREFIX = "*** Delete File: "
_MOVE_PREFIX = "*** Move to: "


def extract_patch_files(patch: str) -> list[str]:
    """Extract changed file paths from a Codex apply_patch command.

    Codex's apply_patch is freeform: a file is opened with `*** Add File:` or
    `*** Update File:`, may be renamed with `*** Move to:`, and is removed with
    `*** Delete File:`. Paths run to end of line (whitespace stripped), so
    spaces in paths survive. A moved file yields only its new path. Results are
    in first-seen order and deduplicated.
    """
    files: list[str] = []
    current: str | None = None

    def record(path: str) -> None:
        if path and path not in files:
            files.append(path)

    for line in patch.splitlines():
        if line.startswith(_ADD_PREFIX):
            current = line[len(_ADD_PREFIX):].strip()
            record(current)
        elif line.startswith(_UPDATE_PREFIX):
            current = line[len(_UPDATE_PREFIX):].strip()
            record(current)
        elif line.startswith(_MOVE_PREFIX):
            new_path = line[len(_MOVE_PREFIX):].strip()
            if current in files:
                files = [p for p in files if p != current]
            current = new_path
            record(new_path)
        elif line.startswith(_DELETE_PREFIX):
            current = None
    return files


def edited_files(event: dict) -> list[str]:
    """Resolve the edited file paths for a hook event (dual-format).

    `Write`/`Edit` events carry the target path directly; `apply_patch` events
    carry a freeform patch whose touched files are extracted.
    """
    tool = event.get("tool_name")
    tool_input = event.get("tool_input") or {}
    if tool in ("Write", "Edit"):
        path = tool_input.get("file_path")
        return [path] if path else []
    if tool == "apply_patch":
        return extract_patch_files(tool_input.get("command", ""))
    return []
