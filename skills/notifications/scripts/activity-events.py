#!/usr/bin/env python3
"""Convert GitHub GraphQL activity into deduplicated queue and notification events."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile
import time


REVIEW_MESSAGES = {
    "APPROVED": "approved",
    "CHANGES_REQUESTED": "requested changes",
    "COMMENTED": "left review feedback",
}


def clean(value: object) -> str:
    return " ".join(str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").split())


def read_lines(path: Path) -> list[str]:
    try:
        values: list[str] = []
        known: set[str] = set()
        for line in path.read_text(encoding="utf-8").splitlines():
            value = line.strip()
            if value and value not in known:
                known.add(value)
                values.append(value)
        return values
    except FileNotFoundError:
        return []


def write_lines(path: Path, values: list[str], limit: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            if values:
                handle.write("\n".join(values[-limit:]) + "\n")
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def process_requested(payload: dict[str, object], args: argparse.Namespace) -> list[list[str]]:
    if not args.watch_requested:
        return []
    seen_order = read_lines(args.request_seen)
    seen = set(seen_order)
    events: list[list[str]] = []
    requested = payload.get("requested")
    if not isinstance(requested, list):
        return events
    for pr in requested:
        if not isinstance(pr, dict):
            continue
        repository = pr.get("repository")
        repo = clean(repository.get("nameWithOwner")) if isinstance(repository, dict) else ""
        number = pr.get("number")
        sha = clean(pr.get("headRefOid"))
        if not repo or not isinstance(number, int) or not sha or (args.repo and repo != args.repo):
            continue
        key = f"{repo}#{number}@{sha}"
        if key in seen:
            continue
        seen.add(key)
        seen_order.append(key)
        author_value = pr.get("author")
        author = clean(author_value.get("login")) if isinstance(author_value, dict) else ""
        author_label = f"@{author}" if author else "unknown author"
        title = clean(pr.get("title")) or "Untitled pull request"
        url = clean(pr.get("url"))
        events.append(["REQUESTED", repo, str(number), author_label, title, url])
        args.queue.parent.mkdir(parents=True, exist_ok=True)
        with args.queue.open("a", encoding="utf-8") as queue:
            queue.write(json.dumps({
                "repo": repo,
                "number": number,
                "headRefOid": sha,
                "author": author or None,
                "title": title,
                "url": url,
                "queuedAt": int(time.time()),
            }) + "\n")
    write_lines(args.request_seen, seen_order, 500)
    return events


def process_authored(payload: dict[str, object], args: argparse.Namespace) -> list[list[str]]:
    if not args.watch_activity:
        return []
    baseline = not args.activity_seen.exists()
    seen_order = read_lines(args.activity_seen)
    seen = set(seen_order)
    viewer = clean(payload.get("viewer"))
    candidates: list[tuple[str, dict[str, object], dict[str, object]]] = []
    authored = payload.get("authored")
    if isinstance(authored, list):
        for pr in authored:
            if not isinstance(pr, dict):
                continue
            reviews = pr.get("reviews")
            nodes = reviews.get("nodes") if isinstance(reviews, dict) else None
            if not isinstance(nodes, list):
                continue
            for review in nodes:
                if isinstance(review, dict):
                    candidates.append((clean(review.get("submittedAt")), pr, review))
    candidates.sort(key=lambda item: (item[0], clean(item[2].get("id"))))

    events: list[list[str]] = []
    baseline_count = 0
    for _, pr, review in candidates:
        repository = pr.get("repository")
        repo = clean(repository.get("nameWithOwner")) if isinstance(repository, dict) else ""
        number = pr.get("number")
        review_id = clean(review.get("id"))
        state = clean(review.get("state"))
        if not repo or not isinstance(number, int) or not review_id or state not in REVIEW_MESSAGES:
            continue
        if args.repo and repo != args.repo:
            continue
        if review_id in seen:
            continue
        seen.add(review_id)
        seen_order.append(review_id)
        if baseline:
            baseline_count += 1
            continue
        author_value = review.get("author")
        author = clean(author_value.get("login")) if isinstance(author_value, dict) else ""
        if author and viewer and author == viewer:
            continue
        reviewer = f"@{author}" if author else "unknown reviewer"
        title = clean(pr.get("title")) or "Untitled pull request"
        url = clean(pr.get("url"))
        events.append([state, repo, str(number), reviewer, title, url])

    write_lines(args.activity_seen, seen_order, 2000)
    if baseline:
        events.insert(0, ["BASELINE", str(baseline_count), "", "", "", ""])
    return events


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--request-seen", type=Path, required=True)
    parser.add_argument("--activity-seen", type=Path, required=True)
    parser.add_argument("--queue", type=Path, required=True)
    parser.add_argument("--repo", default="")
    parser.add_argument("--watch-requested", action="store_true")
    parser.add_argument("--watch-activity", action="store_true")
    args = parser.parse_args()
    try:
        payload = json.loads(args.payload.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    events = process_requested(payload, args) + process_authored(payload, args)
    for event in events:
        print("\t".join(event))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
