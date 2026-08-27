#!/usr/bin/env python3
"""Resolve the narrow Git Workflow notification configuration without PyYAML."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from typing import Any


def project_root(start: str | os.PathLike[str]) -> Path:
    candidate = Path(start).expanduser().resolve()
    try:
        result = subprocess.run(
            ["git", "-C", str(candidate), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
        value = result.stdout.strip()
        if value:
            return Path(value).resolve()
    except (OSError, subprocess.SubprocessError):
        pass
    return candidate


def _strip_comment(value: str) -> str:
    quote = ""
    escaped = False
    result: list[str] = []
    for char in value:
        if escaped:
            result.append(char)
            escaped = False
            continue
        if char == "\\" and quote == '"':
            result.append(char)
            escaped = True
            continue
        if char in {"'", '"'}:
            if not quote:
                quote = char
            elif quote == char:
                quote = ""
            result.append(char)
            continue
        if char == "#" and not quote:
            break
        result.append(char)
    return "".join(result).strip()


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        if value[0] == '"':
            try:
                decoded = json.loads(value)
                return decoded if isinstance(decoded, str) else value[1:-1]
            except json.JSONDecodeError:
                return value[1:-1]
        return value[1:-1].replace("''", "'")
    return value


def _read_sections(path: Path) -> tuple[dict[str, dict[str, str]], list[str]]:
    sections: dict[str, dict[str, str]] = {}
    errors: list[str] = []
    current = ""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        return sections, [f"could not read {path}: {error}"]

    for number, line in enumerate(lines, start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(?:#.*)?)?$", line)
            current = match.group(1) if match else ""
            if current:
                sections.setdefault(current, {})
            continue
        if current not in {"notifications", "reviewWatch"}:
            continue
        match = re.match(r"^[ \t]+([A-Za-z0-9_-]+):[ \t]*(.*)$", line)
        if not match:
            continue
        key, raw = match.groups()
        value = _unquote(_strip_comment(raw))
        if value:
            sections[current][key] = value
        elif raw.strip() and not raw.lstrip().startswith("#"):
            errors.append(f"{path}:{number}: invalid scalar for {current}.{key}")
    return sections, errors


def _boolean(sections: dict[str, dict[str, str]], section: str, key: str, errors: list[str]) -> bool:
    value = sections.get(section, {}).get(key)
    if value is None:
        return False
    if value == "true":
        return True
    if value == "false":
        return False
    errors.append(f"{section}.{key} must be true or false")
    return False


def load_config(start: str | os.PathLike[str]) -> dict[str, Any]:
    root = project_root(start)
    canonical = root / ".git-workflow" / "config.yaml"
    legacy = root / ".claude" / "config.yaml"
    path = canonical if canonical.is_file() else legacy if legacy.is_file() else None
    sections: dict[str, dict[str, str]] = {}
    errors: list[str] = []
    if path:
        sections, errors = _read_sections(path)

    interval_raw = sections.get("reviewWatch", {}).get("intervalSeconds", "60")
    try:
        interval = int(interval_raw)
        if interval <= 0:
            raise ValueError
    except ValueError:
        errors.append("reviewWatch.intervalSeconds must be a positive integer")
        interval = 60

    sound = sections.get("notifications", {}).get("sound")
    if sound is None:
        sound = sections.get("reviewWatch", {}).get("sound", "Glass")
    sound = " ".join(sound.replace("\r", " ").replace("\n", " ").split()) or "Glass"

    return {
        "projectRoot": str(root),
        "configPath": str(path) if path else None,
        "legacyFallback": bool(path == legacy),
        "reviewRequests": _boolean(sections, "reviewWatch", "enabled", errors),
        "agentComplete": _boolean(sections, "notifications", "agentComplete", errors),
        "prActivity": _boolean(sections, "notifications", "prActivity", errors),
        "intervalSeconds": interval,
        "sound": sound,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=os.getcwd())
    parser.add_argument("--shell", action="store_true")
    args = parser.parse_args()
    config = load_config(args.project)
    if args.shell:
        for key in ("reviewRequests", "agentComplete", "prActivity", "intervalSeconds", "sound"):
            value = config[key]
            if isinstance(value, bool):
                value = str(value).lower()
            print(f"{key}={value}")
        for error in config["errors"]:
            print(f"error={error}")
    else:
        print(json.dumps(config, ensure_ascii=False, sort_keys=True))
    return 2 if config["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
