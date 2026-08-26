#!/usr/bin/env bash
# git-workflow — test for scripts/review-watch.sh
#
# Exercises the review-watch daemon's single-poll mode (--once) using its
# REVIEW_WATCH_PRS_JSON injection hook, with an isolated XDG_STATE_HOME so
# the seen-ledger/queue never touch a real user state directory.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/review-watch.sh"
STATE_HOME="$(mktemp -d)"
trap 'rm -rf "$STATE_HOME"' EXIT

QUEUE_FILE="$STATE_HOME/git-workflow/review-watch-queue.jsonl"

FAILURES=0

check() {
  local description="$1"
  local result="$2"
  if [ "$result" -eq 0 ]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    FAILURES=$((FAILURES + 1))
  fi
}

pr_json() {
  local head_sha="$1"
  printf '[{"number":42,"title":"t","url":"https://github.com/acme/app/pull/42","repository":{"nameWithOwner":"acme/app"},"headRefOid":"%s"}]' "$head_sha"
}

run_once() {
  local json="$1"
  XDG_STATE_HOME="$STATE_HOME" REVIEW_WATCH_PRS_JSON="$json" bash "$SCRIPT" --once
}

# 1. A NEW PR json fires: output mentions the PR and the queue gets a line.
OUTPUT_1="$(run_once "$(pr_json "aaa111")")"
printf '%s' "$OUTPUT_1" | grep -q 'review requested on #42'
check "new PR fires and mentions #42" $?

[ -s "$QUEUE_FILE" ]
check "queue file has a line after new PR" $?

# 2. Re-running with the SAME headRefOid: no output (dedup via seen-ledger).
OUTPUT_2="$(run_once "$(pr_json "aaa111")")"
[ -z "$OUTPUT_2" ]
check "same headRefOid produces no output (dedup)" $?

# 3. A NEW headRefOid for the same PR fires again.
OUTPUT_3="$(run_once "$(pr_json "bbb222")")"
printf '%s' "$OUTPUT_3" | grep -q 'review requested on #42'
check "new headRefOid fires again" $?

# 4. An empty array produces no output.
OUTPUT_4="$(run_once '[]')"
[ -z "$OUTPUT_4" ]
check "empty array produces no output" $?

if [ "$FAILURES" -gt 0 ]; then
  printf '%d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok: review-watch behavior\n'
