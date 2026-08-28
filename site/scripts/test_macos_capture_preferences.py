#!/usr/bin/env python3
"""Unit tests for reversible macOS capture preferences using a fake defaults CLI."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("enable-macos-notification-banners.py")
SPEC = importlib.util.spec_from_file_location("macos_capture_preferences", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {MODULE_PATH}")
PREFERENCES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREFERENCES)


class FakeDefaults:
    """Model only the defaults operations used by the preference manager."""

    def __init__(self, globals_state: dict[str, str] | None = None) -> None:
        self.globals = dict(globals_state or {})
        self.notifications = {"apps": [{"bundle-id": "existing.app", "flags": 7}]}
        self.calls: list[tuple[str, ...]] = []
        self.fail_exports = 0
        self.fail_imports = 0
        self.fail_reads: set[str] = set()

    def __call__(
        self,
        *args: str,
        input_bytes: bytes | None = None,
    ) -> subprocess.CompletedProcess[bytes]:
        """Execute one simulated defaults command and update the in-memory state."""
        self.calls.append(args)
        command = args[1:]
        if command == ("export", "com.apple.ncprefs", "-"):
            if self.fail_exports:
                self.fail_exports -= 1
                raise subprocess.CalledProcessError(1, args, stderr=b"export failed")
            output = plistlib.dumps(self.notifications, fmt=plistlib.FMT_XML)
            return subprocess.CompletedProcess(args, 0, output, b"")
        if command[:2] == ("read", "NSGlobalDomain"):
            name = command[2]
            if name in self.fail_reads:
                raise subprocess.CalledProcessError(1, args, stderr=b"permission denied")
            if name not in self.globals:
                raise subprocess.CalledProcessError(
                    1,
                    args,
                    stderr=b"The domain/default pair does not exist",
                )
            return subprocess.CompletedProcess(args, 0, f"{self.globals[name]}\n".encode(), b"")
        if command[:2] == ("write", "NSGlobalDomain"):
            self.globals[command[2]] = command[4]
            return subprocess.CompletedProcess(args, 0, b"", b"")
        if command[:2] == ("delete", "NSGlobalDomain"):
            name = command[2]
            if name not in self.globals:
                raise subprocess.CalledProcessError(1, args, stderr=b"missing")
            del self.globals[name]
            return subprocess.CompletedProcess(args, 0, b"", b"")
        if command == ("import", "com.apple.ncprefs", "-"):
            if self.fail_imports:
                self.fail_imports -= 1
                raise subprocess.CalledProcessError(1, args, stderr=b"import failed")
            if input_bytes is None:
                raise AssertionError("defaults import requires plist bytes")
            self.notifications = plistlib.loads(input_bytes)
            return subprocess.CompletedProcess(args, 0, b"", b"")
        raise AssertionError(f"Unexpected defaults command: {args}")


class PreferenceLifecycleTests(unittest.TestCase):
    """Verify mutation ordering, exact restoration, and failure behavior."""

    def snapshot_path(self, directory: str) -> Path:
        """Return the private snapshot path used by one isolated test."""
        return Path(directory, "capture-preferences.json")

    def test_existing_preferences_round_trip_exactly(self) -> None:
        """Restore existing appearance values and the complete notification plist."""
        fake = FakeDefaults({
            "AppleInterfaceStyle": "Light",
            "AppleInterfaceStyleSwitchesAutomatically": "1",
        })
        original_notifications = fake.notifications.copy()
        with tempfile.TemporaryDirectory() as directory, patch.object(PREFERENCES, "run", fake):
            snapshot = self.snapshot_path(directory)
            PREFERENCES.write_snapshot(snapshot)
            PREFERENCES.prepare(snapshot)
            self.assertEqual(fake.globals["AppleInterfaceStyle"], "Dark")
            self.assertEqual(fake.globals["AppleInterfaceStyleSwitchesAutomatically"], "false")
            self.assertTrue(any(app.get("bundle-id") == PREFERENCES.BUNDLE_ID for app in fake.notifications["apps"]))
            PREFERENCES.restore(snapshot)

        self.assertEqual(fake.globals, {
            "AppleInterfaceStyle": "Light",
            "AppleInterfaceStyleSwitchesAutomatically": "1",
        })
        self.assertEqual(fake.notifications, original_notifications)
        first_mutation = next(index for index, call in enumerate(fake.calls) if call[1] in {"write", "import"})
        self.assertTrue(all(call[1] in {"export", "read"} for call in fake.calls[:first_mutation]))

    def test_absent_global_settings_are_deleted_on_restore(self) -> None:
        """Return global appearance keys to absence instead of inventing defaults."""
        fake = FakeDefaults()
        with tempfile.TemporaryDirectory() as directory, patch.object(PREFERENCES, "run", fake):
            snapshot = self.snapshot_path(directory)
            PREFERENCES.write_snapshot(snapshot)
            PREFERENCES.prepare(snapshot)
            PREFERENCES.restore(snapshot)
        self.assertEqual(fake.globals, {})

    def test_snapshot_failure_prevents_all_mutation(self) -> None:
        """Refuse prepare authorization when Notification Center cannot be backed up."""
        fake = FakeDefaults()
        fake.fail_exports = 1
        with tempfile.TemporaryDirectory() as directory, patch.object(PREFERENCES, "run", fake):
            with self.assertRaises(subprocess.CalledProcessError):
                PREFERENCES.write_snapshot(self.snapshot_path(directory))
        self.assertFalse(any(call[1] in {"write", "import", "delete"} for call in fake.calls))

    def test_unexpected_global_read_failure_prevents_all_mutation(self) -> None:
        """Propagate permission and transport failures instead of recording false absence."""
        fake = FakeDefaults()
        fake.fail_reads.add("AppleInterfaceStyle")
        with tempfile.TemporaryDirectory() as directory, patch.object(PREFERENCES, "run", fake):
            with self.assertRaises(subprocess.CalledProcessError):
                PREFERENCES.write_snapshot(self.snapshot_path(directory))
        self.assertFalse(any(call[1] in {"write", "import", "delete"} for call in fake.calls))

    def test_partial_prepare_can_still_be_restored(self) -> None:
        """Recover the original state after a prepare import fails mid-sequence."""
        fake = FakeDefaults({"AppleInterfaceStyle": "Light"})
        original_notifications = fake.notifications.copy()
        with tempfile.TemporaryDirectory() as directory, patch.object(PREFERENCES, "run", fake):
            snapshot = self.snapshot_path(directory)
            PREFERENCES.write_snapshot(snapshot)
            fake.fail_imports = 1
            with self.assertRaises(subprocess.CalledProcessError):
                PREFERENCES.prepare(snapshot)
            PREFERENCES.restore(snapshot)
        self.assertEqual(fake.globals, {"AppleInterfaceStyle": "Light"})
        self.assertEqual(fake.notifications, original_notifications)

    def test_restore_failure_is_reported_after_other_fields_are_attempted(self) -> None:
        """Surface a failed plist import while still restoring both global settings."""
        fake = FakeDefaults({"AppleInterfaceStyle": "Light"})
        with tempfile.TemporaryDirectory() as directory, patch.object(PREFERENCES, "run", fake):
            snapshot = self.snapshot_path(directory)
            PREFERENCES.write_snapshot(snapshot)
            PREFERENCES.prepare(snapshot)
            fake.fail_imports = 1
            with self.assertRaisesRegex(RuntimeError, "Preference restoration failed"):
                PREFERENCES.restore(snapshot)
        self.assertEqual(fake.globals, {"AppleInterfaceStyle": "Light"})


if __name__ == "__main__":
    unittest.main()
