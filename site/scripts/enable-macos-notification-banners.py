#!/usr/bin/env python3
"""Enable Script Editor banners on an ephemeral macOS capture runner.

`osascript display notification` is the production notification path, but a new
macOS user may register Script Editor with the Desktop banner style disabled.
This helper changes only the disposable runner user's Notification Center
preferences. It is documentation tooling, never part of the shipped runtime.
"""

from __future__ import annotations

import plistlib
import subprocess
import sys


BUNDLE_ID = "com.apple.ScriptEditor2"
BANNERS = 1 << 3
ALERTS = 1 << 4
SHOW_IN_NOTIFICATION_CENTER = 1 << 0
PLAY_SOUND = 1 << 2
ALLOW_NOTIFICATIONS = 1 << 25


def run(*args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def main() -> int:
    try:
        exported = run("defaults", "export", "com.apple.ncprefs", "-").stdout
        preferences = plistlib.loads(exported)
    except (subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f"Unable to read com.apple.ncprefs: {error}", file=sys.stderr)
        return 1

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
    try:
        run("defaults", "import", "com.apple.ncprefs", "-", input_bytes=payload)
    except subprocess.CalledProcessError as error:
        print(error.stderr.decode("utf-8", errors="replace"), file=sys.stderr)
        return error.returncode or 1

    print(
        f"Configured {BUNDLE_ID}: flags {previous_flags} -> {flags} "
        f"(banner, sound, and notification authorization enabled)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
