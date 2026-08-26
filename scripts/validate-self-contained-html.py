#!/usr/bin/env python3
"""Compatibility wrapper for the change-brief HTML validator."""

from pathlib import Path
import runpy


runpy.run_path(
    Path(__file__).resolve().parents[1]
    / "skills"
    / "change-brief"
    / "scripts"
    / "validate-self-contained-html.py",
    run_name="__main__",
)
