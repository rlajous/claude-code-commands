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

run_in_project() {
  local project="$1"
  shift
  (cd "$project" && XDG_STATE_HOME="$STATE_HOME" bash "$SCRIPT" "$@")
}

# 0. Configuration defaults are safe: absent config is disabled, and values
# resolve to the documented interval and sound.
NO_CONFIG_PROJECT="$STATE_HOME/no-config-project"
mkdir -p "$NO_CONFIG_PROJECT"
CONFIG_DEFAULTS="$(run_in_project "$NO_CONFIG_PROJECT" --show-config)"
printf '%s\n' "$CONFIG_DEFAULTS" | grep -qx 'enabled=false'
check "absent config defaults to disabled" $?
printf '%s\n' "$CONFIG_DEFAULTS" | grep -qx 'intervalSeconds=60'
check "absent config uses 60-second interval" $?
printf '%s\n' "$CONFIG_DEFAULTS" | grep -qx 'sound=Glass'
check "absent config uses Glass sound" $?

DISABLED_OUTPUT="$(run_in_project "$NO_CONFIG_PROJECT" --once 2>&1)"
printf '%s\n' "$DISABLED_OUTPUT" | grep -q 'review-watch: disabled'
check "absent config does not poll" $?

# Explicit canonical config overrides every daemon setting. The CLI interval
# remains highest precedence.
CONFIG_PROJECT="$STATE_HOME/config-project"
mkdir -p "$CONFIG_PROJECT/.git-workflow"
printf 'reviewWatch:\n  enabled: true\n  intervalSeconds: "17"\n  sound: '\''Ping'\''\n' > "$CONFIG_PROJECT/.git-workflow/config.yaml"
CONFIG_OVERRIDES="$(run_in_project "$CONFIG_PROJECT" --show-config)"
printf '%s\n' "$CONFIG_OVERRIDES" | grep -qx 'enabled=true'
check "canonical config enables polling" $?
printf '%s\n' "$CONFIG_OVERRIDES" | grep -qx 'intervalSeconds=17'
check "canonical config overrides interval" $?
printf '%s\n' "$CONFIG_OVERRIDES" | grep -qx 'sound=Ping'
check "canonical config overrides sound" $?

CLI_OVERRIDE="$(run_in_project "$CONFIG_PROJECT" --interval 9 --show-config)"
printf '%s\n' "$CLI_OVERRIDE" | grep -qx 'intervalSeconds=9'
check "CLI interval overrides config" $?

bash "$SCRIPT" --interval >/dev/null 2>&1
[ $? -eq 2 ]
check "missing interval value exits with usage error" $?
bash "$SCRIPT" --interval 0 >/dev/null 2>&1
[ $? -eq 2 ]
check "zero interval exits with usage error" $?
bash "$SCRIPT" --repo >/dev/null 2>&1
[ $? -eq 2 ]
check "missing repo value exits with usage error" $?

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
