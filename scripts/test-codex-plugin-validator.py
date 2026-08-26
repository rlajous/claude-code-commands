#!/usr/bin/env python3
"""Exercise malformed Codex plugin manifests against the dependency-free validator."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def fixture() -> Path:
    target = Path(tempfile.mkdtemp(prefix="git-workflow-manifest-"))
    (target / "scripts").mkdir()
    (target / ".codex-plugin").mkdir()
    (target / "hooks").mkdir()
    shutil.copy2(ROOT / "scripts/validate-codex-plugin.py", target / "scripts")
    shutil.copytree(ROOT / "skills", target / "skills")
    shutil.copy2(ROOT / "hooks/hooks.json", target / "hooks")
    return target


def run_case(label: str, mutate) -> None:
    target = fixture()
    try:
        manifest = json.loads((ROOT / ".codex-plugin/plugin.json").read_text())
        mutate(manifest)
        (target / ".codex-plugin/plugin.json").write_text(json.dumps(manifest))
        result = subprocess.run(
            ["python3", str(target / "scripts/validate-codex-plugin.py")],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0 or "Codex plugin validation failed:" not in result.stderr:
            raise AssertionError(f"{label} was not reported as a friendly validation failure")
    finally:
        shutil.rmtree(target)


run_case("non-object interface", lambda data: data.__setitem__("interface", "invalid"))
run_case("scalar capabilities", lambda data: data["interface"].__setitem__("capabilities", "Write"))
run_case("scalar default prompt", lambda data: data["interface"].__setitem__("defaultPrompt", "prompt"))
run_case("non-object author", lambda data: data.__setitem__("author", "invalid"))
run_case("wrong version type", lambda data: data.__setitem__("version", 240))

print("ok: Codex manifest negative fixtures")
