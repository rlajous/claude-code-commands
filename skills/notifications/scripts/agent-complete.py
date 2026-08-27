#!/usr/bin/env python3
"""Best-effort Stop-hook adapter for Claude Code and Codex."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Iterator, TextIO

if os.name == "nt":
    import msvcrt
else:
    import fcntl

from notification_config import load_config, project_root


def _clean_line(message: object) -> str:
    if not isinstance(message, str):
        return ""
    for raw in message.splitlines():
        line = " ".join(raw.strip().split())
        line = re.sub(r"^(?:#{1,6}|[-*+>]|\d+[.)])\s+", "", line)
        if line:
            return line if len(line) <= 160 else f"{line[:159].rstrip()}…"
    return ""


def _repository_label(root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "remote", "get-url", "origin"],
            check=True,
            capture_output=True,
            text=True,
        )
        remote = result.stdout.strip().rstrip("/")
        match = re.search(r"(?:[:/])([^/:\s]+/[^/\s]+?)(?:\.git)?$", remote)
        if match:
            return match.group(1)
    except (OSError, subprocess.SubprocessError):
        pass
    return root.name or "workspace"


@contextmanager
def _exclusive_lock(handle: TextIO) -> Iterator[None]:
    """Hold an exclusive ledger lock on Unix or native Windows."""
    if os.name == "nt":
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            # Windows locks a byte range. A blank line supplies one byte without
            # becoming a ledger entry because readers discard empty lines.
            handle.write("\n")
            handle.flush()
        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
    else:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    try:
        yield
    finally:
        if os.name == "nt":
            handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _claim_once(payload: dict[str, object], host: str) -> bool:
    session = str(payload.get("session_id") or "unknown-session")
    turn = str(payload.get("turn_id") or "")
    if not turn:
        transcript = payload.get("transcript_path")
        if isinstance(transcript, str) and transcript:
            try:
                metadata = Path(transcript).stat()
                turn = f"{transcript}:{metadata.st_size}:{metadata.st_mtime_ns}"
            except OSError:
                pass
    if not turn:
        message = str(payload.get("last_assistant_message") or "")
        turn = hashlib.sha256(message.encode("utf-8")).hexdigest()
    digest = hashlib.sha256(f"{host}:{session}:{turn}".encode("utf-8")).hexdigest()

    state_root = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state")))
    state_dir = state_root / "git-workflow"
    state_dir.mkdir(parents=True, exist_ok=True)
    ledger = state_dir / "agent-complete-seen"
    with ledger.open("a+", encoding="utf-8") as handle:
        with _exclusive_lock(handle):
            handle.seek(0)
            seen = [line.strip() for line in handle if line.strip()]
            if digest in seen:
                return False
            seen.append(digest)
            handle.seek(0)
            handle.truncate()
            handle.write("\n".join(seen[-500:]) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
    return True


def _emit_empty_result() -> None:
    # Codex Stop hooks require JSON on successful exit; Claude accepts the same no-op object.
    print("{}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True, choices=("claude", "codex"))
    args = parser.parse_args()
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict) or payload.get("hook_event_name") != "Stop":
            _emit_empty_result()
            return 0
        cwd = payload.get("cwd")
        if not isinstance(cwd, str) or not cwd:
            _emit_empty_result()
            return 0
        config = load_config(cwd)
        if config["errors"] or not config["agentComplete"]:
            _emit_empty_result()
            return 0
        if args.host == "claude" and (payload.get("background_tasks") or payload.get("session_crons")):
            _emit_empty_result()
            return 0
        if not _claim_once(payload, args.host):
            _emit_empty_result()
            return 0

        root = project_root(cwd)
        label = "Claude Code" if args.host == "claude" else "Codex"
        summary = _clean_line(payload.get("last_assistant_message"))
        title = f"{_repository_label(root)} · {label}"
        message = "Agent finished" if not summary else f"Agent finished — {summary}"
        notifier = os.environ.get("GIT_WORKFLOW_NOTIFY_SCRIPT") or str(Path(__file__).with_name("notify.sh"))
        subprocess.run(
            ["bash", notifier, title, message, str(config["sound"])],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        # Notifications are advisory and must never turn a successful agent stop into a failure.
        pass
    _emit_empty_result()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
