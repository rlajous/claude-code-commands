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
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
INTERFACE_FIELDS = {
    "displayName", "shortDescription", "longDescription", "developerName",
    "category", "capabilities", "websiteURL", "defaultPrompt", "default_prompt",
}


def fail(message: str) -> None:
    raise ValueError(message)


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        fail(f"{path.relative_to(ROOT)} has invalid frontmatter")
    return dict(re.findall(r"^([a-z-]+):\s*(.*)$", match.group(1), re.M))


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} must be a nonempty string")
    return value


def require_string_list(value: object, label: str, *, minimum: int = 1, maximum: int | None = None) -> list[str]:
    if not isinstance(value, list) or len(value) < minimum or (maximum is not None and len(value) > maximum):
        suffix = f" between {minimum} and {maximum}" if maximum is not None else f" at least {minimum}"
        fail(f"{label} must contain{suffix} string value(s)")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        fail(f"{label} must contain only nonempty strings")
    return value


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        fail("manifest root must be an object")
    unknown = set(manifest) - ALLOWED_KEYS
    if unknown:
        fail(f"unsupported manifest fields: {sorted(unknown)}")
    for field in ("name", "version", "description", "skills", "interface"):
        if field not in manifest:
            fail(f"missing manifest field: {field}")
    name = require_string(manifest["name"], "name")
    if not SLUG.fullmatch(name) or len(name) > 64:
        fail("name must be a lowercase hyphenated slug of at most 64 characters")
    version = require_string(manifest["version"], "version")
    require_string(manifest["description"], "description")
    if not SEMVER.fullmatch(version):
        fail("version is not strict semver")
    if require_string(manifest["skills"], "skills") != "./skills/":
        fail("skills must point to ./skills/")
    for field in ("id", "homepage", "repository", "license"):
        if field in manifest:
            require_string(manifest[field], field)
    if "keywords" in manifest:
        require_string_list(manifest["keywords"], "keywords")
    author = manifest.get("author")
    if author is not None:
        if not isinstance(author, dict):
            fail("author must be an object")
        require_string(author.get("name"), "author.name")
        if "url" in author:
            require_string(author["url"], "author.url")
    interface = manifest["interface"]
    if not isinstance(interface, dict):
        fail("interface must be an object")
    unknown_interface = set(interface) - INTERFACE_FIELDS
    if unknown_interface:
        fail(f"unsupported interface fields: {sorted(unknown_interface)}")
    for field in ("displayName", "shortDescription", "longDescription", "developerName", "category", "capabilities"):
        if field not in interface:
            fail(f"missing interface field: {field}")
    for field in ("displayName", "shortDescription", "longDescription", "developerName", "category"):
        require_string(interface[field], f"interface.{field}")
    if "websiteURL" in interface:
        require_string(interface["websiteURL"], "interface.websiteURL")
    capabilities = require_string_list(interface["capabilities"], "interface.capabilities")
    unsupported_capabilities = set(capabilities) - {"Interactive", "Read", "Write"}
    if unsupported_capabilities:
        fail(f"unsupported interface capabilities: {sorted(unsupported_capabilities)}")
    prompt_key = "defaultPrompt" if "defaultPrompt" in interface else "default_prompt"
    if prompt_key not in interface:
        fail("missing interface default prompt")
    require_string_list(interface[prompt_key], f"interface.{prompt_key}", maximum=3)

    skills = sorted((ROOT / "skills").glob("*/SKILL.md"))
    if len(skills) != 20:
        fail(f"expected 20 skills, found {len(skills)}")
    for skill in skills:
        frontmatter = parse_frontmatter(skill)
        if frontmatter.get("name") != skill.parent.name or not frontmatter.get("description"):
            fail(f"invalid name or description: {skill.relative_to(ROOT)}")
        if frontmatter.get("disable-model-invocation") not in (None, "false"):
            fail(f"Codex plugin skills cannot disable model invocation: {skill.relative_to(ROOT)}")

    hooks = json.loads((ROOT / "hooks" / "hooks.json").read_text(encoding="utf-8"))
    if not isinstance(hooks, dict):
        fail("hooks root must be an object")
    entries = hooks.get("hooks", {}).get("PostToolUse", [])
    if not isinstance(entries, list) or not any(isinstance(entry, dict) and entry.get("matcher") == "Bash" for entry in entries):
        fail("Codex PostToolUse Bash hook is missing")
    print(f"Codex plugin validation passed: {ROOT}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError, AttributeError, json.JSONDecodeError) as error:
        print(f"Codex plugin validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
