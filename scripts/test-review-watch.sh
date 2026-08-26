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
SEEN_FILE="$STATE_HOME/git-workflow/review-watch-seen"
NOTIFY_LOG="$STATE_HOME/notifications.log"
NOTIFY_CAPTURE="$STATE_HOME/capture-notification.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "title=%s\nmessage=%s\n" "${1:-}" "${2:-}" >> "$REVIEW_WATCH_NOTIFY_LOG"' \
  > "$NOTIFY_CAPTURE"

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
  printf '[{"number":42,"title":"Fix login redirect","url":"https://github.com/acme/app/pull/42","repository":{"nameWithOwner":"acme/app"},"headRefOid":"%s","author":{"login":"alice"}}]' "$head_sha"
}

run_once() {
  local json="$1"
  XDG_STATE_HOME="$STATE_HOME" REVIEW_WATCH_PRS_JSON="$json" \
    REVIEW_WATCH_NOTIFY_SCRIPT="$NOTIFY_CAPTURE" REVIEW_WATCH_NOTIFY_LOG="$NOTIFY_LOG" \
    bash "$SCRIPT" --once
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

# 1. A NEW PR json fires with a useful console line and notification, and the
# queue persists the author for consumers that understand the newer schema.
OUTPUT_1="$(run_once "$(pr_json "aaa111")")"
printf '%s' "$OUTPUT_1" | grep -q 'review requested on acme/app PR #42 by @alice — Fix login redirect'
check "new PR output identifies repo, number, author, and title" $?

grep -qx 'title=acme/app · PR #42' "$NOTIFY_LOG"
check "notification title identifies repo and PR" $?
grep -qx 'message=@alice — Fix login redirect' "$NOTIFY_LOG"
check "notification message identifies author and title" $?

[ -s "$QUEUE_FILE" ]
check "queue file has a line after new PR" $?
python3 - "$QUEUE_FILE" <<'PY'
import json, sys

with open(sys.argv[1]) as queue:
    first = json.loads(queue.readline())
assert first["author"] == "alice", first
PY
check "queue persists PR author" $?

# 2. Re-running with the SAME headRefOid: no output (dedup via seen-ledger).
OUTPUT_2="$(run_once "$(pr_json "aaa111")")"
[ -z "$OUTPUT_2" ]
check "same headRefOid produces no output (dedup)" $?
[ "$(wc -l < "$NOTIFY_LOG" | tr -d ' ')" = "2" ]
check "same headRefOid does not notify again" $?

# 3. A NEW headRefOid for the same PR fires again.
OUTPUT_3="$(run_once "$(pr_json "bbb222")")"
printf '%s' "$OUTPUT_3" | grep -q 'review requested on acme/app PR #42 by @alice'
check "new headRefOid fires again" $?

# 4. An empty array produces no output.
OUTPUT_4="$(run_once '[]')"
[ -z "$OUTPUT_4" ]
check "empty array produces no output" $?

# 5. The 500-key cap preserves observation order: the oldest entry is evicted,
# while the newest prior entry and the newly observed head remain.
python3 - "$SEEN_FILE" <<'PY'
import sys

with open(sys.argv[1], "w") as ledger:
    for index in range(500):
        ledger.write(f"acme/app#7@old-{index:03d}\n")
PY
OUTPUT_5="$(run_once "$(pr_json "ccc333")")"
printf '%s' "$OUTPUT_5" | grep -q 'review requested on acme/app PR #42 by @alice'
check "new PR still fires when the seen ledger is full" $?
[ "$(wc -l < "$SEEN_FILE" | tr -d ' ')" = "500" ]
check "seen ledger remains capped at 500 ordered keys" $?
grep -qx 'acme/app#7@old-499' "$SEEN_FILE"
check "most recent prior key remains after trimming" $?
grep -qx 'acme/app#42@ccc333' "$SEEN_FILE"
check "new key remains after trimming" $?
if grep -qx 'acme/app#7@old-000' "$SEEN_FILE"; then
  check "oldest key is evicted after trimming" 1
else
  check "oldest key is evicted after trimming" 0
fi

# 6. Deleted/anonymous authors use an explicit fallback instead of emitting an
# empty @handle. Older queue lines without the new author field remain valid.
printf '%s\n' '{"repo":"acme/legacy","number":7,"headRefOid":"old","title":"legacy","url":"https://github.com/acme/legacy/pull/7","queuedAt":1}' >> "$QUEUE_FILE"
UNKNOWN_AUTHOR_JSON='[{"number":43,"title":"Dependency update","url":"https://github.com/acme/app/pull/43","repository":{"nameWithOwner":"acme/app"},"headRefOid":"ddd444","author":null}]'
OUTPUT_6="$(run_once "$UNKNOWN_AUTHOR_JSON")"
printf '%s' "$OUTPUT_6" | grep -q 'review requested on acme/app PR #43 by unknown author — Dependency update'
check "missing author uses an explicit fallback" $?
tail -n 2 "$NOTIFY_LOG" | grep -qx 'message=unknown author — Dependency update'
check "fallback author is passed to the notifier" $?
python3 - "$QUEUE_FILE" <<'PY'
import json, sys

with open(sys.argv[1]) as queue:
    entries = [json.loads(line) for line in queue if line.strip()]
assert any(entry.get("repo") == "acme/legacy" and "author" not in entry for entry in entries)
assert any(entry.get("number") == 43 and entry.get("author") is None for entry in entries)
PY
check "old and new queue schemas coexist" $?

QUEUE_LINES_BEFORE_BAD="$(wc -l < "$QUEUE_FILE" | tr -d ' ')"
NOTIFY_LINES_BEFORE_BAD="$(wc -l < "$NOTIFY_LOG" | tr -d ' ')"
MALFORMED_JSON='[{"number":44,"title":"No repository","headRefOid":"bad444","author":{"login":"mallory"}},{"number":45,"title":"No SHA","repository":{"nameWithOwner":"acme/app"},"author":{"login":"mallory"}}]'
OUTPUT_BAD="$(run_once "$MALFORMED_JSON")"
[ -z "$OUTPUT_BAD" ]
check "malformed PR records produce no output" $?
[ "$(wc -l < "$QUEUE_FILE" | tr -d ' ')" = "$QUEUE_LINES_BEFORE_BAD" ]
check "malformed PR records are not queued" $?
[ "$(wc -l < "$NOTIFY_LOG" | tr -d ' ')" = "$NOTIFY_LINES_BEFORE_BAD" ]
check "malformed PR records do not notify" $?

# 7. Exercise the live fetch path with a fake gh. This catches regressions back
# to `gh search prs --json headRefOid`, which the GitHub CLI does not support.
FAKE_GH_BIN="$STATE_HOME/fake-gh-bin"
FAKE_GH_ARGS="$STATE_HOME/fake-gh-args"
mkdir -p "$FAKE_GH_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$FAKE_GH_ARGS"' \
  'printf '\''[{"number":99,"title":"Add audit log","url":"https://github.com/acme/api/pull/99","repository":{"nameWithOwner":"acme/api"},"headRefOid":"live999","author":{"login":"bob"}}]'\''' \
  > "$FAKE_GH_BIN/gh"
chmod +x "$FAKE_GH_BIN/gh"
OUTPUT_7="$(cd "$CONFIG_PROJECT" && PATH="$FAKE_GH_BIN:$PATH" FAKE_GH_ARGS="$FAKE_GH_ARGS" \
  XDG_STATE_HOME="$STATE_HOME" REVIEW_WATCH_NOTIFY_SCRIPT="$NOTIFY_CAPTURE" \
  REVIEW_WATCH_NOTIFY_LOG="$NOTIFY_LOG" env -u REVIEW_WATCH_PRS_JSON \
  bash "$SCRIPT" --once --repo acme/api)"
printf '%s' "$OUTPUT_7" | grep -q 'review requested on acme/api PR #99 by @bob — Add audit log'
check "GraphQL live path returns notification metadata" $?
grep -qx 'api' "$FAKE_GH_ARGS" && grep -qx 'graphql' "$FAKE_GH_ARGS"
check "live path uses gh api graphql" $?
grep -qx 'searchQuery=repo:acme/api is:pr is:open review-requested:@me' "$FAKE_GH_ARGS"
check "GraphQL search keeps repo and review-request filters" $?
if grep -qx 'search' "$FAKE_GH_ARGS" || grep -q 'headRefOid.*--json\|--json.*headRefOid' "$FAKE_GH_ARGS"; then
  check "live path avoids unsupported gh search fields" 1
else
  check "live path avoids unsupported gh search fields" 0
fi

if [ "$FAILURES" -gt 0 ]; then
  printf '%d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

printf 'ok: review-watch behavior\n'
