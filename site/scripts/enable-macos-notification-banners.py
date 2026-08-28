#!/usr/bin/env python3
"""Manage reversible macOS preferences for notification evidence capture.

The capture runner temporarily needs Dark appearance and Script Editor banner
delivery. Every mutation is gated by a private snapshot, and restoration
verifies the exact logical preference state before returning successfully.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
from typing import Any, Sequence


BUNDLE_ID = "com.apple.ScriptEditor2"
BANNERS = 1 << 3
ALERTS = 1 << 4
SHOW_IN_NOTIFICATION_CENTER = 1 << 0
PLAY_SOUND = 1 << 2
ALLOW_NOTIFICATIONS = 1 << 25
SNAPSHOT_VERSION = 1
GLOBAL_SETTINGS = (
    ("AppleInterfaceStyle", "string", "Dark"),
    ("AppleInterfaceStyleSwitchesAutomatically", "bool", "false"),
)


def run(*args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    """Run one preference command and return captured output or raise on failure."""
    return subprocess.run(
        args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def read_global_setting(name: str) -> dict[str, Any]:
    """Capture whether a global default exists and its normalized text value."""
    try:
        value = run("defaults", "read", "NSGlobalDomain", name).stdout.decode().strip()
    except subprocess.CalledProcessError:
        return {"present": False, "value": None}
    return {"present": True, "value": value}


def read_notification_preferences() -> tuple[bytes, Any]:
    """Export Notification Center preferences as bytes and parsed plist data."""
    exported = run("defaults", "export", "com.apple.ncprefs", "-").stdout
    return exported, plistlib.loads(exported)


def write_snapshot(path: Path) -> None:
    """Persist the complete pre-mutation state in a private, atomic snapshot."""
    exported, _ = read_notification_preferences()
    payload = {
        "version": SNAPSHOT_VERSION,
        "notificationPreferences": base64.b64encode(exported).decode("ascii"),
        "globalSettings": {
            name: read_global_setting(name) for name, _, _ in GLOBAL_SETTINGS
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary_path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
        temporary_path.chmod(0o600)
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def load_snapshot(path: Path) -> dict[str, Any]:
    """Load and validate a capture snapshot before it can authorize mutation."""
    try:
        snapshot = json.loads(path.read_text(encoding="utf-8"))
        if snapshot.get("version") != SNAPSHOT_VERSION:
            raise ValueError("unsupported snapshot version")
        encoded = snapshot["notificationPreferences"]
        plistlib.loads(base64.b64decode(encoded, validate=True))
        settings = snapshot["globalSettings"]
        for name, _, _ in GLOBAL_SETTINGS:
            state = settings[name]
            if not isinstance(state.get("present"), bool):
                raise ValueError(f"invalid state for {name}")
    except (KeyError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException) as error:
        raise ValueError(f"Invalid macOS preference snapshot {path}: {error}") from error
    return snapshot


def configured_notification_preferences(snapshot: dict[str, Any]) -> tuple[bytes, int, int]:
    """Build banner-enabled preferences from the backed-up plist without mutating it."""
    original = base64.b64decode(snapshot["notificationPreferences"], validate=True)
    preferences = plistlib.loads(original)
    apps = list(preferences.get("apps", []))
    matching_index = next(
        (index for index, app in enumerate(apps) if app.get("bundle-id") == BUNDLE_ID),
        None,
    )

    if matching_index is None:
        app = {
            "bundle-id": BUNDLE_ID,
            "content_visibility": 3,
            "flags": 0,
            "grouping": 0,
        }
        apps.append(app)
        matching_index = len(apps) - 1
        previous_flags = 0
    else:
        app = dict(apps[matching_index])
        previous_flags = int(app.get("flags", 0))

    flags = previous_flags
    flags &= ~ALERTS
    flags &= ~SHOW_IN_NOTIFICATION_CENTER
    flags |= BANNERS | PLAY_SOUND | ALLOW_NOTIFICATIONS
    app["flags"] = flags
    app.setdefault("content_visibility", 3)
    app.setdefault("grouping", 0)
    apps[matching_index] = app
    preferences["apps"] = apps
    payload = plistlib.dumps(preferences, fmt=plistlib.FMT_XML, sort_keys=False)
    return payload, previous_flags, flags


def prepare(snapshot_path: Path) -> None:
    """Apply capture-only preferences after proving a complete snapshot exists."""
    snapshot = load_snapshot(snapshot_path)
    payload, previous_flags, flags = configured_notification_preferences(snapshot)
    for name, value_type, value in GLOBAL_SETTINGS:
        run("defaults", "write", "NSGlobalDomain", name, f"-{value_type}", value)
    run("defaults", "import", "com.apple.ncprefs", "-", input_bytes=payload)
    print(
        f"Configured {BUNDLE_ID}: flags {previous_flags} -> {flags} "
        "(banner, sound, and notification authorization enabled)."
    )


def restore_global_setting(name: str, value_type: str, state: dict[str, Any]) -> None:
    """Restore one global default, including its original absence."""
    if state["present"]:
        run(
            "defaults",
            "write",
            "NSGlobalDomain",
            name,
            f"-{value_type}",
            str(state["value"]),
        )
        return
    try:
        run("defaults", "delete", "NSGlobalDomain", name)
    except subprocess.CalledProcessError:
        if read_global_setting(name)["present"]:
            raise


def restore(snapshot_path: Path) -> None:
    """Restore and verify all preferences, attempting every field after any failure."""
    snapshot = load_snapshot(snapshot_path)
    original_bytes = base64.b64decode(snapshot["notificationPreferences"], validate=True)
    errors: list[str] = []

    try:
        run("defaults", "import", "com.apple.ncprefs", "-", input_bytes=original_bytes)
    except subprocess.CalledProcessError as error:
        errors.append(error.stderr.decode(errors="replace") or "unable to restore com.apple.ncprefs")

    for name, value_type, _ in GLOBAL_SETTINGS:
        try:
            restore_global_setting(name, value_type, snapshot["globalSettings"][name])
        except subprocess.CalledProcessError as error:
            errors.append(error.stderr.decode(errors="replace") or f"unable to restore {name}")

    if not errors:
        _, current_preferences = read_notification_preferences()
        expected_preferences = plistlib.loads(original_bytes)
        if current_preferences != expected_preferences:
            errors.append("com.apple.ncprefs verification mismatch")
        for name, _, _ in GLOBAL_SETTINGS:
            if read_global_setting(name) != snapshot["globalSettings"][name]:
                errors.append(f"{name} verification mismatch")

    if errors:
        raise RuntimeError("Preference restoration failed: " + "; ".join(errors))
    print("Restored and verified macOS notification capture preferences.")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse the internal snapshot, prepare, and restore command contract."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    for operation in ("snapshot", "prepare", "restore"):
        command = subparsers.add_parser(operation)
        command.add_argument("--snapshot", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Execute one reversible preference lifecycle operation."""
    args = parse_args(argv)
    try:
        if args.operation == "snapshot":
            write_snapshot(args.snapshot)
        elif args.operation == "prepare":
            prepare(args.snapshot)
        else:
            restore(args.snapshot)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
