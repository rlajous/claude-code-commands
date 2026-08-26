#!/usr/bin/env python3
"""Reject generated HTML that can initiate external network requests."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path


NETWORK_URL = re.compile(r"(?i)(?:https?:)?//")
CSS_URL = re.compile(r"(?i)url\(\s*([^)]+?)\s*\)")
SCRIPT_NETWORK = re.compile(
    r"(?i)\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\s*\(|"
    r"\bnavigator\.sendBeacon\s*\(|\bwindow\.open\s*\(|"
    r"\b(?:window\.)?location\.(?:assign|replace)\s*\(|"
    r"\b(?:window\.)?location(?:\.href)?\s*="
)
RESOURCE_ATTRIBUTES = {
    "audio": {"src"},
    "embed": {"src"},
    "iframe": {"src", "srcdoc"},
    "img": {"src", "srcset"},
    "input": {"src"},
    "link": {"href"},
    "object": {"data"},
    "script": {"src"},
    "source": {"src", "srcset"},
    "track": {"src"},
    "video": {"poster", "src"},
    "image": {"href", "xlink:href"},
    "use": {"href", "xlink:href"},
}


def css_has_network(css: str) -> bool:
    if re.search(r"(?i)@import\b", css):
        return True
    for match in CSS_URL.finditer(css):
        target = match.group(1).strip().strip("'\"").lower()
        if target and not target.startswith(("data:", "#")):
            return True
    return False


def csp_blocks_connections(content: str) -> bool:
    """Require default-src 'none' and no broader connect-src override."""
    directives: dict[str, list[str]] = {}
    for raw_directive in content.lower().split(";"):
        parts = raw_directive.split()
        if parts and parts[0] not in directives:
            directives[parts[0]] = parts[1:]
    default_sources = directives.get("default-src")
    connect_sources = directives.get("connect-src")
    return default_sources == ["'none'"] and connect_sources in (None, ["'none'"])


class SelfContainedParser(HTMLParser):
    """Inspect markup and executable content without scanning escaped PR text."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.context: list[str] = []
        self.violations: list[str] = []
        self.has_csp = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values: dict[str, str] = {}
        for name, value in attrs:
            lower_name = name.lower()
            if lower_name in values:
                self.violations.append(f"<{tag.lower()}> has duplicate attribute {lower_name!r}")
                continue
            values[lower_name] = value or ""
        lower_tag = tag.lower()
        self.context.append(lower_tag)

        if lower_tag == "meta" and values.get("http-equiv", "").lower() == "content-security-policy":
            if csp_blocks_connections(values.get("content", "")):
                self.has_csp = True

        for attribute in RESOURCE_ATTRIBUTES.get(lower_tag, set()):
            value = values.get(attribute, "").strip()
            is_external = attribute == "srcset" or (
                not value.lower().startswith("data:") and not value.startswith("#")
            )
            if value and is_external:
                self.violations.append(f"<{lower_tag}> has resource attribute {attribute}={value!r}")

        style = values.get("style", "")
        if style and css_has_network(style):
            self.violations.append(f"<{lower_tag}> inline style contains a network URL")

        if any(name.startswith("on") and value.strip() for name, value in values.items()):
            self.violations.append(f"<{lower_tag}> has an inline event handler")

        if lower_tag == "meta" and values.get("http-equiv", "").lower() == "refresh":
            self.violations.append("meta refresh is not allowed")
        if lower_tag == "form" and values.get("action", "").strip():
            self.violations.append("form action is not allowed")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        lower_tag = tag.lower()
        for index in range(len(self.context) - 1, -1, -1):
            if self.context[index] == lower_tag:
                del self.context[index:]
                break

    def handle_data(self, data: str) -> None:
        context = self.context[-1] if self.context else ""
        if context == "style" and css_has_network(data):
            self.violations.append("<style> contains an external URL or @import")
        elif context == "script" and (NETWORK_URL.search(data) or SCRIPT_NETWORK.search(data)):
            self.violations.append("inline script contains a network URL or API")


def validate(path: Path) -> list[str]:
    parser = SelfContainedParser()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    if not parser.has_csp:
        parser.violations.append(
            "missing restrictive Content-Security-Policy with default-src 'none' and connect-src 'none' or omitted"
        )
    return parser.violations


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <index.html>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"not a file: {path}", file=sys.stderr)
        return 2
    violations = validate(path)
    for violation in violations:
        print(f"{path}: {violation}", file=sys.stderr)
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
