import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest


@pytest.fixture
def checkout(tmp_path):
    source = Path(__file__).resolve().parents[3]
    repo = tmp_path / "repo"
    for relative in ("ai/claude/build-settings", "scripts/generate-deny.sh",
                     "ai/shared/deny-patterns.yaml"):
        target = repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)
    config = repo / "ai/claude/conf.d"
    config.mkdir()
    for fragment in (source / "ai/claude/conf.d").glob("*.json"):
        if fragment.name != "20-deny.json":
            shutil.copy2(fragment, config / fragment.name)
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".claude/settings.json").write_text(json.dumps({
        "permissions": {"allow": ["Bash(example-command)"], "ask": []}
    }))
    return repo, home


def run_build(checkout, *args):
    repo, home = checkout
    return subprocess.run(
        ["bash", str(repo / "ai/claude/build-settings"), *args],
        env={**os.environ, "HOME": str(home), "MISE_GLOBAL_CONFIG_ROOT": str(repo)},
        text=True, capture_output=True, check=True,
    )


def snapshot(root):
    return {str(path.relative_to(root)): (path.read_bytes(), path.stat().st_mtime_ns)
            for path in root.rglob("*") if path.is_file()}


@pytest.mark.parametrize("flag", ["--dry-run", "--status"])
@pytest.mark.parametrize("existing_deny", [False, True])
def test_inspection_leaves_all_files_unchanged(checkout, flag, existing_deny):
    repo, home = checkout
    if existing_deny:
        (repo / "ai/claude/conf.d/20-deny.json").write_text(
            '{"permissions":{"deny":["obsolete-rule"]}}')
    before = snapshot(repo), snapshot(home)
    result = run_build(checkout, flag)
    assert (snapshot(repo), snapshot(home)) == before
    if flag == "--dry-run":
        settings = json.loads(result.stdout)
        assert settings["permissions"]["deny"]
        assert "obsolete-rule" not in settings["permissions"]["deny"]
        assert "Bash(example-command)" in settings["permissions"]["allow"]


def test_apply_matches_preview_and_preserves_runtime_permissions(checkout):
    repo, home = checkout
    preview = json.loads(run_build(checkout, "--dry-run").stdout)
    run_build(checkout)
    applied = json.loads((home / ".claude/settings.json").read_text())
    assert applied == preview
    assert "Bash(example-command)" in applied["permissions"]["allow"]
    generated = json.loads((repo / "ai/claude/conf.d/20-deny.json").read_text())
    expected = json.loads(subprocess.run(
        [str(repo / "scripts/generate-deny.sh"), "claude"],
        text=True, capture_output=True, check=True,
    ).stdout)
    assert generated == expected


APM_MARKETPLACE = {"source": {"source": "directory", "path": "/home/user/.agents/plugins"}}


def write_apm_registrations(home):
    path = home / ".claude/settings.json"
    settings = json.loads(path.read_text())
    settings["enabledPlugins"] = {
        "ba0918-rules@apm-u-0123abcd": True,
        "stale-plugin@claude-plugins-official": True,
    }
    settings["extraKnownMarketplaces"] = {
        "apm-u-0123abcd": APM_MARKETPLACE,
        "stale-marketplace": APM_MARKETPLACE,
    }
    path.write_text(json.dumps(settings))


@pytest.mark.parametrize("flag", [None, "--clean"])
def test_apm_plugin_registrations_survive_a_rebuild(checkout, flag):
    repo, home = checkout
    write_apm_registrations(home)
    managed = json.loads(run_build(checkout, "--clean", "--dry-run").stdout)
    run_build(checkout, *([flag] if flag else []))
    applied = json.loads((home / ".claude/settings.json").read_text())
    assert applied["enabledPlugins"]["ba0918-rules@apm-u-0123abcd"] is True
    assert applied["extraKnownMarketplaces"]["apm-u-0123abcd"] == APM_MARKETPLACE
    assert "stale-plugin@claude-plugins-official" not in applied["enabledPlugins"]
    assert "stale-marketplace" not in applied["extraKnownMarketplaces"]
    for key, value in managed["enabledPlugins"].items():
        assert applied["enabledPlugins"][key] == value
