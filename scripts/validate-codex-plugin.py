#!/usr/bin/env python3
"""Validate the repository's Codex plugin ingestion contract without dependencies."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / ".codex-plugin" / "plugin.json"
ALLOWED_KEYS = {
    "id", "name", "version", "description", "skills", "apps", "mcpServers",
    "interface", "author", "homepage", "repository", "license", "keywords",
}
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+][0-9A-Za-z.-]+)?$")


def fail(message: str) -> None:
    raise ValueError(message)


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        fail(f"{path.relative_to(ROOT)} has invalid frontmatter")
    return dict(re.findall(r"^([a-z-]+):\s*(.*)$", match.group(1), re.M))


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    unknown = set(manifest) - ALLOWED_KEYS
    if unknown:
        fail(f"unsupported manifest fields: {sorted(unknown)}")
    for field in ("name", "version", "description", "skills", "interface"):
        if field not in manifest:
            fail(f"missing manifest field: {field}")
    if not SEMVER.fullmatch(manifest["version"]):
        fail("version is not strict semver")
    if manifest["skills"] != "./skills/":
        fail("skills must point to ./skills/")
    interface = manifest["interface"]
    for field in ("displayName", "shortDescription", "longDescription", "developerName", "category", "capabilities"):
        if not interface.get(field):
            fail(f"missing interface field: {field}")
    if not (interface.get("defaultPrompt") or interface.get("default_prompt")):
        fail("missing interface default prompt")

    skills = sorted((ROOT / "skills").glob("*/SKILL.md"))
    if len(skills) != 17:
        fail(f"expected 17 skills, found {len(skills)}")
    for skill in skills:
        frontmatter = parse_frontmatter(skill)
        if frontmatter.get("name") != skill.parent.name or not frontmatter.get("description"):
            fail(f"invalid name or description: {skill.relative_to(ROOT)}")
        if frontmatter.get("disable-model-invocation") not in (None, "false"):
            fail(f"Codex plugin skills cannot disable model invocation: {skill.relative_to(ROOT)}")

    hooks = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))
    entries = hooks.get("hooks", {}).get("PostToolUse", [])
    if not any(entry.get("matcher") == "Bash" for entry in entries):
        fail("Codex PostToolUse Bash hook is missing")
    print(f"Codex plugin validation passed: {ROOT}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Codex plugin validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
