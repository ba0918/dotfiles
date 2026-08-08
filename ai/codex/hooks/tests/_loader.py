import importlib.util
from pathlib import Path

_HOOKS_DIR = Path(__file__).resolve().parent.parent


def load(name: str):
    """Load a Codex hook script under a unique module name.

    The Claude suite imports the same bare module names (detect_secret,
    detect_mojibake, block_dangerous_command) from its own tree. Loading the
    Codex copies under distinct names keeps both suites' imports unambiguous
    when they run in a single interpreter.
    """
    spec = importlib.util.spec_from_file_location(
        f"codex_{name}", _HOOKS_DIR / f"{name}.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
