#!/usr/bin/env bash
# git-workflow — review-watch console daemon.
#
# Listens for pull requests where your review was requested and pings you
# (sound + desktop notification) so you notice while working in another window.
# It stays LIGHT: it discovers PRs, de-duplicates by head SHA, notifies, and
# enqueues them. The actual review (linters + LLM fan-out) is done by the
# `review-watch` skill in your Claude Code / Codex session (run `/review-watch`).
#
# Usage:
#   review-watch.sh [--interval N] [--once] [--repo owner/name]
#
#   --interval N   seconds between polls (default 60)
#   --once         run a single poll and exit (used by tests / cron)
#   --repo o/n     only watch this repository
#
# Needs: gh (authenticated), python3. Never needs the repo checked out.
# Testing hook: set REVIEW_WATCH_PRS_JSON to a gh-search-prs JSON array to
# bypass the live gh call.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INTERVAL=60
ONCE=0
REPO_FILTER=""

need_value() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "review-watch: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --interval)
      need_value "$@"
      case "$2" in ''|*[!0-9]*) echo "review-watch: --interval must be a positive integer" >&2; exit 2 ;; esac
      INTERVAL="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    --repo)
      need_value "$@"
      REPO_FILTER="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "review-watch: unknown arg: $1" >&2; exit 2 ;;
  esac
done

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/git-workflow"
mkdir -p "$STATE_DIR" 2>/dev/null || true
SEEN="$STATE_DIR/review-watch-seen"
QUEUE="$STATE_DIR/review-watch-queue.jsonl"
touch "$SEEN" "$QUEUE" 2>/dev/null || true

fetch_prs() {
  if [ -n "${REVIEW_WATCH_PRS_JSON:-}" ]; then
    printf '%s' "$REVIEW_WATCH_PRS_JSON"
    return 0
  fi
  # Scope the query server-side when a repo is given, so the --limit truncation
  # never drops the target repo's PRs before the client-side filter runs.
  if [ -n "$REPO_FILTER" ]; then
    gh search prs "repo:$REPO_FILTER" --review-requested @me --state open \
      --json number,title,url,repository,headRefOid --limit 50 2>/dev/null
  else
    gh search prs --review-requested @me --state open \
      --json number,title,url,repository,headRefOid --limit 50 2>/dev/null
  fi
}

# Emits one tab-separated line per NEW (unseen head SHA) PR: number<TAB>title<TAB>url
# Also records the key in the seen-ledger and appends the PR to the queue.
find_new() {
  local json tmp rc
  json="$(fetch_prs)" || return 1
  [ -n "$json" ] || json="[]"
  tmp="$(mktemp)" || return 1
  printf '%s' "$json" > "$tmp"
  # Program is read from the heredoc (stdin); the PR JSON is passed as a file arg
  # so it never collides with `python3 -` reading its program from stdin.
  python3 - "$SEEN" "$QUEUE" "$REPO_FILTER" "$tmp" <<'PY'
import json, sys, time

seen_path, queue_path, repo_filter, json_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(json_path) as f:
        prs = json.load(f)
except Exception:
    prs = []
if not isinstance(prs, list):
    prs = []

try:
    with open(seen_path) as f:
        seen = set(line.strip() for line in f if line.strip())
except FileNotFoundError:
    seen = set()

new_keys = []
for pr in prs:
    repo = (pr.get("repository") or {}).get("nameWithOwner") or (pr.get("repository") or {}).get("name") or ""
    if repo_filter and repo != repo_filter:
        continue
    num = pr.get("number")
    sha = pr.get("headRefOid") or ""
    if num is None or not sha:
        continue
    key = f"{repo}#{num}@{sha}"
    if key in seen:
        continue
    new_keys.append(key)
    title = (pr.get("title") or "").replace("\t", " ").replace("\n", " ")
    url = pr.get("url") or ""
    print(f"{num}\t{title}\t{url}")
    with open(queue_path, "a") as q:
        q.write(json.dumps({
            "repo": repo, "number": num, "headRefOid": sha,
            "title": title, "url": url, "queuedAt": int(time.time()),
        }) + "\n")

if new_keys:
    seen |= set(new_keys)
    # Cap the ledger to the most recent 500 keys.
    trimmed = list(seen)[-500:]
    with open(seen_path, "w") as f:
        f.write("\n".join(trimmed) + "\n")
PY
  rc=$?
  rm -f "$tmp"
  return $rc
}

poll() {
  local out rc
  out="$(find_new)"; rc=$?
  if [ $rc -ne 0 ]; then
    echo "review-watch: gh query failed. Is gh authenticated? Try 'gh auth login'." >&2
    return 1
  fi
  [ -n "$out" ] || return 0
  local count=0
  while IFS=$'\t' read -r num title url; do
    [ -n "$num" ] || continue
    count=$((count + 1))
    echo "review-watch: review requested on #$num — $title"
    echo "             $url"
    echo "             run /review-watch $url to review it"
    bash "$SCRIPT_DIR/notify.sh" "Review requested: #$num" "$title" >/dev/null 2>&1 || true
  done <<< "$out"
  [ "$count" -gt 0 ] && echo "review-watch: $count new PR(s) queued for review."
  return 0
}

if [ "$ONCE" -eq 1 ]; then
  poll
  exit 0
fi

echo "review-watch: watching PRs that request your review every ${INTERVAL}s. Ctrl-C to stop."
while true; do
  poll || true
  sleep "$INTERVAL"
done
