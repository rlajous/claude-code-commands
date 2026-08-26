#!/usr/bin/env bash
# Tests configuration, Stop-hook behavior, diagnostics, and notification safety.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOK="$ROOT_DIR/skills/notifications/scripts/agent-complete.py"
TOOLS="$ROOT_DIR/skills/notifications/scripts/notification-tools.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-workflow-notifications.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
FAILURES=0

check() {
  if [ "$2" -eq 0 ]; then printf 'PASS: %s\n' "$1"; else printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); fi
}

PROJECT="$TEST_ROOT/project"
STATE_HOME="$TEST_ROOT/state"
LOG="$TEST_ROOT/notifications.jsonl"
CAPTURE="$TEST_ROOT/capture.sh"
mkdir -p "$PROJECT/.git-workflow"
git -C "$PROJECT" init -q
git -C "$PROJECT" remote add origin git@github.com:acme/widgets.git
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "title=%s\nmessage=%s\nsound=%s\n" "$1" "$2" "$3" >> "$NOTIFY_LOG"' > "$CAPTURE"
chmod +x "$CAPTURE"

payload() {
  local session="$1" turn="$2" message="$3"
  python3 - "$PROJECT" "$session" "$turn" "$message" <<'PY'
import json,sys
print(json.dumps({"hook_event_name":"Stop","cwd":sys.argv[1],"session_id":sys.argv[2],"turn_id":sys.argv[3],"last_assistant_message":sys.argv[4]}))
PY
}

invoke() {
  local host="$1" data="$2"
  printf '%s' "$data" | XDG_STATE_HOME="$STATE_HOME" GIT_WORKFLOW_NOTIFY_SCRIPT="$CAPTURE" NOTIFY_LOG="$LOG" \
    python3 "$HOOK" --host "$host"
}

# Disabled is the safe default and malformed payloads are harmless JSON no-ops.
printf 'notifications:\n  agentComplete: false\n  prActivity: false\n  sound: Ping\n' > "$PROJECT/.git-workflow/config.yaml"
OUT="$(invoke codex "$(payload s1 t1 'Done')")"
[ "$OUT" = '{}' ] && [ ! -e "$LOG" ]; check 'disabled completion notification is a no-op' $?
OUT="$(printf '{bad' | python3 "$HOOK" --host codex)"
[ "$OUT" = '{}' ]; check 'malformed hook payload is a no-op' $?

printf 'notifications:\n  agentComplete: true\n  prActivity: false\n  sound: Ping\n' > "$PROJECT/.git-workflow/config.yaml"
OUT="$(invoke codex "$(payload s1 t2 $'# Implemented review activity notifications\nMore details')")"
[ "$OUT" = '{}' ]; check 'Codex Stop hook returns valid empty JSON' $?
grep -Fqx 'title=acme/widgets · Codex' "$LOG" && \
  grep -Fqx 'message=Agent finished — Implemented review activity notifications' "$LOG" && \
  grep -Fqx 'sound=Ping' "$LOG"
check 'completion title, summary normalization, and sound are exact' $?

LINES="$(grep -c '^title=' "$LOG")"
invoke codex "$(payload s1 t2 'Different replay text')" >/dev/null
[ "$(grep -c '^title=' "$LOG")" = "$LINES" ]; check 'same host, session, and turn is deduplicated' $?

TRANSCRIPT="$TEST_ROOT/transcript.jsonl"
printf 'turn one\n' > "$TRANSCRIPT"
NO_TURN="$(python3 - "$PROJECT" "$TRANSCRIPT" <<'PY'
import json,sys
print(json.dumps({"hook_event_name":"Stop","cwd":sys.argv[1],"session_id":"no-turn","transcript_path":sys.argv[2],"last_assistant_message":"Repeated summary"}))
PY
)"
BEFORE="$(grep -c '^title=' "$LOG")"
invoke codex "$NO_TURN" >/dev/null
invoke codex "$NO_TURN" >/dev/null
[ "$(( $(grep -c '^title=' "$LOG") - BEFORE ))" -eq 1 ]; check 'transcript metadata deduplicates hosts without a turn ID' $?
printf 'turn two\n' >> "$TRANSCRIPT"
invoke codex "$NO_TURN" >/dev/null
[ "$(( $(grep -c '^title=' "$LOG") - BEFORE ))" -eq 2 ]; check 'a later identical summary remains a new turn when transcript grows' $?

invoke claude "$(payload s1 t2 'Claude is distinct')" >/dev/null
tail -n 3 "$LOG" | grep -Fqx 'title=acme/widgets · Claude Code'; check 'host participates in deduplication identity' $?

# Claude does not alert while background or cron work remains.
BACKGROUND="$(payload s2 t1 'Waiting')"
BACKGROUND="$(printf '%s' "$BACKGROUND" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["background_tasks"]=[{"id":"x"}]; print(json.dumps(d))')"
BEFORE="$(grep -c '^title=' "$LOG")"
invoke claude "$BACKGROUND" >/dev/null
[ "$(grep -c '^title=' "$LOG")" = "$BEFORE" ]; check 'Claude background work suppresses completion alert' $?
CRON="$(payload s2 t2 'Waiting')"
CRON="$(printf '%s' "$CRON" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["session_crons"]=["x"]; print(json.dumps(d))')"
invoke claude "$CRON" >/dev/null
[ "$(grep -c '^title=' "$LOG")" = "$BEFORE" ]; check 'Claude pending cron suppresses completion alert' $?

# Empty and long summaries remain useful and bounded.
invoke codex "$(payload s3 t1 '')" >/dev/null
tail -n 3 "$LOG" | grep -Fqx 'message=Agent finished'
check 'empty summary uses a stable fallback' $?
LONG="$(python3 -c 'print("x"*220)')"
invoke codex "$(payload s3 t2 "$LONG")" >/dev/null
tail -n 3 "$LOG" | sed -n 's/^message=Agent finished — //p' | python3 -c 'import sys; s=sys.stdin.read().rstrip("\n"); assert len(s) == 160 and s.endswith("…"), len(s)'
check 'summary is limited to 160 characters' $?

# Concurrent duplicate hooks claim the turn atomically.
CONCURRENT="$(payload concurrent turn 'Only once')"
BEFORE="$(grep -c '^title=' "$LOG")"
invoke codex "$CONCURRENT" >/dev/null & first=$!
invoke codex "$CONCURRENT" >/dev/null & second=$!
wait "$first"; wait "$second"
[ "$(( $(grep -c '^title=' "$LOG") - BEFORE ))" -eq 1 ]; check 'concurrent duplicate hooks emit once' $?

# Configuration precedence and validation stay narrow and deterministic.
mkdir -p "$TEST_ROOT/legacy/.claude"
printf 'notifications:\n  agentComplete: true\n  prActivity: true\n  sound: Glass\n' > "$TEST_ROOT/legacy/.claude/config.yaml"
python3 "$ROOT_DIR/skills/notifications/scripts/notification_config.py" --project "$TEST_ROOT/legacy" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["legacyFallback"] and d["prActivity"]'
check 'legacy config is a read-only fallback' $?
printf 'notifications:\n  agentComplete: maybe\n' > "$PROJECT/.git-workflow/config.yaml"
python3 "$ROOT_DIR/skills/notifications/scripts/notification_config.py" --project "$PROJECT" >/dev/null 2>&1
[ $? -eq 2 ]; check 'invalid booleans fail configuration validation' $?

# Doctor may authenticate but must not poll, create state, or invoke the notifier.
printf 'notifications:\n  agentComplete: false\n  prActivity: false\n' > "$PROJECT/.git-workflow/config.yaml"
FAKE_BIN="$TEST_ROOT/bin"
GH_LOG="$TEST_ROOT/gh.log"
mkdir -p "$FAKE_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$GH_LOG"' '[ "${1:-}" = auth ] && [ "${2:-}" = status ]' > "$FAKE_BIN/gh"
chmod +x "$FAKE_BIN/gh"
rm -rf "$STATE_HOME"
DOCTOR="$(cd "$PROJECT" && PATH="$FAKE_BIN:$PATH" GH_LOG="$GH_LOG" GIT_WORKFLOW_NOTIFY_SCRIPT="$CAPTURE" NOTIFY_LOG="$LOG" XDG_STATE_HOME="$STATE_HOME" bash "$TOOLS" --doctor)"
printf '%s\n' "$DOCTOR" | grep -q 'RESULT: ready'; check 'doctor validates installation and authentication' $?
[ ! -e "$STATE_HOME" ] && ! grep -q 'api graphql' "$GH_LOG"; check 'doctor creates no state and does not query PRs' $?
EXPECTED="$(printf 'bash %q' "$ROOT_DIR/skills/notifications/scripts/activity-watch.sh")"
[ "$(bash "$TOOLS" --daemon-command)" = "$EXPECTED" ]; check 'daemon command uses the absolute skill-local path' $?

if [ "$FAILURES" -gt 0 ]; then printf '%s assertion(s) failed\n' "$FAILURES" >&2; exit 1; fi
printf 'ok: unified notification configuration, hooks, and diagnostics\n'
