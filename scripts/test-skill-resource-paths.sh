#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git workflow resources.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

PACKAGE="$TEST_ROOT/plugin with spaces"
mkdir -p "$PACKAGE/.codex" "$PACKAGE/.codex-plugin" "$PACKAGE/scripts"
PACKAGE="$(cd "$PACKAGE" && pwd -P)"
cp -R "$ROOT_DIR/skills" "$ROOT_DIR/agents" "$ROOT_DIR/references" "$ROOT_DIR/templates" "$PACKAGE/"
cp -R "$ROOT_DIR/.codex/agents" "$PACKAGE/.codex/"
cp "$ROOT_DIR/.codex-plugin/plugin.json" "$PACKAGE/.codex-plugin/plugin.json"
cp "$ROOT_DIR/scripts/review-watch.sh" "$ROOT_DIR/scripts/review-event.sh" \
  "$ROOT_DIR/scripts/notify.sh" "$ROOT_DIR/scripts/status-report.mjs" \
  "$ROOT_DIR/scripts/to-sarif.mjs" "$ROOT_DIR/scripts/sync-project.mjs" \
  "$ROOT_DIR/scripts/validate-self-contained-html.py" "$PACKAGE/scripts/"

[ -L "$ROOT_DIR/.agents/skills" ] || fail ".agents/skills is not a symlink"
[ "$(readlink "$ROOT_DIR/.agents/skills")" = "../skills" ] || fail ".agents/skills target is not ../skills"
[ "$(find -L "$ROOT_DIR/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')" = "19" ] \
  || fail "Codex local discovery does not expose 19 skills"

for resource in \
  skills/review-watch/scripts/review-watch.sh \
  skills/review-watch/scripts/notify.sh \
  skills/review-watch/scripts/review-watch-tools.sh \
  skills/review-watch/references/known-issues.md \
  skills/review/scripts/review-event.sh \
  skills/review/scripts/to-sarif.mjs \
  skills/change-brief/scripts/validate-self-contained-html.py \
  skills/status/scripts/status-report.mjs \
  skills/status/assets/status-template.html \
  skills/setup/scripts/sync-project.mjs; do
  [ -f "$PACKAGE/$resource" ] || fail "missing skill-local resource: $resource"
done

DAEMON_COMMAND="$(env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
  bash "$PACKAGE/skills/review-watch/scripts/review-watch-tools.sh" --daemon-command)"
EXPECTED_DAEMON_COMMAND="$(printf 'bash %q' "$PACKAGE/skills/review-watch/scripts/review-watch.sh")"
[ "$DAEMON_COMMAND" = "$EXPECTED_DAEMON_COMMAND" ] \
  || fail "daemon command did not use the absolute installed skill path"

FAKE_BIN="$TEST_ROOT/fake bin"
mkdir -p "$FAKE_BIN"
printf '%s\n' '#!/usr/bin/env bash' '[ "${1:-}" = auth ] && [ "${2:-}" = status ]' > "$FAKE_BIN/gh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\\n"' > "$FAKE_BIN/uname"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/afplay"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$@" > "$NOTIFY_ARGS_FILE"' > "$FAKE_BIN/osascript"
chmod +x "$FAKE_BIN/gh"
chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/afplay" "$FAKE_BIN/osascript"
PROJECT="$TEST_ROOT/project with spaces"
mkdir -p "$PROJECT/.git-workflow"
printf 'reviewWatch:\n  enabled: true\n' > "$PROJECT/.git-workflow/config.yaml"
DOCTOR_OUTPUT="$(cd "$PROJECT" && PATH="$FAKE_BIN:$PATH" env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
  bash "$PACKAGE/skills/review-watch/scripts/review-watch-tools.sh" --doctor)"
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'RESULT: ready' || fail "doctor did not pass with isolated dependencies"
[ ! -e "$PROJECT/.git-workflow/review-watch-queue.jsonl" ] || fail "doctor mutated review state"

NOTIFY_ARGS_FILE="$TEST_ROOT/notification arguments"
NOTIFY_TITLE='dangerous\" & do shell script "touch /tmp/never" & "'
NOTIFY_MESSAGE='message with \ backslashes and "quotes"'
PATH="$FAKE_BIN:$PATH" NOTIFY_ARGS_FILE="$NOTIFY_ARGS_FILE" \
  bash "$PACKAGE/scripts/notify.sh" "$NOTIFY_TITLE" "$NOTIFY_MESSAGE"
python3 - "$NOTIFY_ARGS_FILE" "$NOTIFY_TITLE" "$NOTIFY_MESSAGE" <<'PY'
import sys

with open(sys.argv[1]) as file:
    arguments = file.read().splitlines()
assert arguments == ["-", sys.argv[2], sys.argv[3]], arguments
PY

STATE_HOME="$TEST_ROOT/state with spaces"
WATCH_NOTIFY_ARGS_FILE="$TEST_ROOT/watcher notification arguments"
WATCH_NOTIFY_SCRIPT="$TEST_ROOT/capture watcher notification.sh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" > "$WATCH_NOTIFY_ARGS_FILE"' > "$WATCH_NOTIFY_SCRIPT"
PR_JSON='[{"number":42,"title":"Fix login redirect","url":"https://github.com/acme/app/pull/42","repository":{"nameWithOwner":"acme/app"},"headRefOid":"abc123","author":{"login":"alice"}}]'
WATCH_OUTPUT="$(cd "$PROJECT" && XDG_STATE_HOME="$STATE_HOME" REVIEW_WATCH_PRS_JSON="$PR_JSON" \
  REVIEW_WATCH_NOTIFY_SCRIPT="$WATCH_NOTIFY_SCRIPT" WATCH_NOTIFY_ARGS_FILE="$WATCH_NOTIFY_ARGS_FILE" \
  env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
  bash "$PACKAGE/scripts/review-watch.sh" --once)"
printf '%s\n' "$WATCH_OUTPUT" | grep -Fq 'Claude: run /review-watch' || fail "watcher omitted Claude invocation"
printf '%s\n' "$WATCH_OUTPUT" | grep -Fq 'Codex:  run $review-watch' || fail "watcher omitted Codex invocation"
printf '%s\n' "$WATCH_OUTPUT" | grep -Fq 'acme/app PR #42 by @alice — Fix login redirect' \
  || fail "watcher output omitted repo, PR, author, or title"
python3 - "$WATCH_NOTIFY_ARGS_FILE" <<'PY'
import sys

with open(sys.argv[1]) as file:
    arguments = file.read().splitlines()
assert arguments == ["acme/app · PR #42", "@alice — Fix login redirect"], arguments
PY
[ -s "$STATE_HOME/git-workflow/review-watch-queue.jsonl" ] || fail "watcher wrapper did not enqueue the PR"

[ "$(cd "$PROJECT" && env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
  bash "$PACKAGE/skills/review/scripts/review-event.sh" --has-blocking false)" = APPROVE ] \
  || fail "skill-local review event resolver failed"
[ "$(cd "$PROJECT" && env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
  bash "$PACKAGE/scripts/review-event.sh" --has-blocking true)" = REQUEST_CHANGES ] \
  || fail "root review event wrapper failed"

PAGE="$TEST_ROOT/page with spaces.html"
printf '%s\n' '<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src '\''none'\''"></head><body>ok</body></html>' > "$PAGE"
env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT python3 \
  "$PACKAGE/skills/change-brief/scripts/validate-self-contained-html.py" "$PAGE" \
  || fail "skill-local HTML validator failed"
env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT python3 "$PACKAGE/scripts/validate-self-contained-html.py" "$PAGE" \
  || fail "root HTML validator wrapper failed"

env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT node "$PACKAGE/skills/status/scripts/status-report.mjs" \
  | grep -q '<!doctype html>' || fail "skill-local status report failed"
env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT node "$PACKAGE/scripts/status-report.mjs" \
  | grep -q '<!doctype html>' || fail "root status wrapper failed"

FINDING='[{"file":"src/a.js","line":2,"severity":"HIGH","confidence":95,"message":"x"}]'
printf '%s' "$FINDING" | env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT \
  node "$PACKAGE/skills/review/scripts/to-sarif.mjs" \
  | python3 -c 'import json,sys; assert json.load(sys.stdin)["runs"][0]["results"][0]["level"] == "error"' \
  || fail "skill-local SARIF converter failed"
printf '%s' "$FINDING" | env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT node "$PACKAGE/scripts/to-sarif.mjs" \
  | python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == "2.1.0"' \
  || fail "root SARIF wrapper failed"

SYNC_TARGET="$TEST_ROOT/sync target"
mkdir -p "$SYNC_TARGET"
env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT node "$PACKAGE/skills/setup/scripts/sync-project.mjs" \
  --target "$SYNC_TARGET" --host codex --dry-run >/dev/null \
  || fail "skill-local synchronizer did not derive its package root"
[ ! -e "$SYNC_TARGET/.codex" ] || fail "skill-local synchronizer dry-run wrote files"
env -u PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT node "$PACKAGE/scripts/sync-project.mjs" \
  --target "$SYNC_TARGET" --host codex --dry-run >/dev/null \
  || fail "root synchronizer wrapper failed"

MANUAL_SKILL="$TEST_ROOT/manual claude skill/setup"
mkdir -p "$MANUAL_SKILL/scripts"
cp "$PACKAGE/skills/setup/scripts/sync-project.mjs" "$MANUAL_SKILL/scripts/"
CLAUDE_PLUGIN_ROOT="$PACKAGE" env -u PLUGIN_ROOT node "$MANUAL_SKILL/scripts/sync-project.mjs" \
  --target "$SYNC_TARGET" --host codex --dry-run >/dev/null \
  || fail "CLAUDE_PLUGIN_ROOT compatibility fallback failed"

printf 'ok: skill-local resources, wrappers, spaces, and environment-free paths\n'
