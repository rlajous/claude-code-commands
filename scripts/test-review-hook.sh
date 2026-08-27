#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT_DIR/hooks/review-commit.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

payload() {
  local project_dir="$1"
  local command="$2"
  PROJECT_DIR_VALUE="$project_dir" COMMAND_VALUE="$command" python3 - <<'PY'
import json
import os
print(json.dumps({
    "cwd": os.environ["PROJECT_DIR_VALUE"],
    "tool_name": "Bash",
    "tool_input": {"command": os.environ["COMMAND_VALUE"]},
}))
PY
}

invoke() {
  local project_dir="$1"
  local command="$2"
  local host="${3:-codex}"
  payload "$project_dir" "$command" | bash "$HOOK" --host "$host"
}

git -C "$TEST_DIR" init -q
git -C "$TEST_DIR" config user.name "Git Workflow Test"
git -C "$TEST_DIR" config user.email "git-workflow@example.invalid"
printf 'first\n' > "$TEST_DIR/sample.txt"
git -C "$TEST_DIR" add sample.txt
git -C "$TEST_DIR" commit -qm "first"

if printf '{not-json' | bash "$HOOK" --host codex >/dev/null 2>&1; then
  fail "malformed hook input was accepted"
fi
VALID_PAYLOAD="$(payload "$TEST_DIR" "git commit -m first")"
if printf '%s' "$VALID_PAYLOAD" | GIT_WORKFLOW_PYTHON=missing-python-runtime bash "$HOOK" --host codex >/dev/null 2>&1; then
  fail "missing Python runtime was treated as a no-op"
fi
if printf '%s' "$VALID_PAYLOAD" | bash "$HOOK" --host unknown >/dev/null 2>&1; then
  fail "invalid host was accepted"
fi

[ -z "$(invoke "$TEST_DIR" "git commit -m first")" ] || fail "disabled hook emitted output"

mkdir -p "$TEST_DIR/.git-workflow"
printf 'review-on-commit: true\n' > "$TEST_DIR/.git-workflow/git-workflow.local.md"
[ -z "$(invoke "$TEST_DIR" "git status")" ] || fail "unrelated Bash command emitted output"

CODEX_OUTPUT="$(invoke "$TEST_DIR" "git commit -m first")"
[ -n "$CODEX_OUTPUT" ] || fail "enabled Codex hook emitted no output"
printf '%s' "$CODEX_OUTPUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["hookSpecificOutput"]["hookEventName"] == "PostToolUse"
assert "additionalContext" in d["hookSpecificOutput"]
' || fail "Codex output was not valid additionalContext JSON"

[ -z "$(invoke "$TEST_DIR" "git push")" ] || fail "duplicate SHA was not suppressed"

printf 'second\n' >> "$TEST_DIR/sample.txt"
git -C "$TEST_DIR" add sample.txt
git -C "$TEST_DIR" commit -qm "second"
CLAUDE_OUTPUT="$(invoke "$TEST_DIR" "git push" "claude")"
printf '%s' "$CLAUDE_OUTPUT" | grep -q 'Commits not yet reviewed' || fail "Claude output missing review context"
printf '%s' "$CLAUDE_OUTPUT" | python3 -m json.tool >/dev/null 2>&1 && fail "Claude output unexpectedly used Codex JSON"

SETTINGS_DIR="$TEST_DIR/settings-precedence"
git -C "$TEST_DIR" init -q "$SETTINGS_DIR"
git -C "$SETTINGS_DIR" config user.name "Git Workflow Test"
git -C "$SETTINGS_DIR" config user.email "git-workflow@example.invalid"
printf 'settings\n' > "$SETTINGS_DIR/file.txt"
git -C "$SETTINGS_DIR" add file.txt
git -C "$SETTINGS_DIR" commit -qm "settings"
mkdir -p "$SETTINGS_DIR/.claude"
printf 'review-on-commit: true\n' > "$SETTINGS_DIR/.claude/git-workflow.local.md"
[ -n "$(invoke "$SETTINGS_DIR" "git commit -m settings")" ] || fail "legacy opt-in fallback was not honored"
rm -rf "$SETTINGS_DIR/.git-workflow"
mkdir -p "$SETTINGS_DIR/.git-workflow"
printf 'review-on-commit: false\n' > "$SETTINGS_DIR/.git-workflow/git-workflow.local.md"
[ -z "$(invoke "$SETTINGS_DIR" "git commit -m settings")" ] || fail "legacy opt-in overrode canonical false"

printf 'not-a-sha\n' > "$TEST_DIR/.git-workflow/.git-workflow-reviewed-shas"
printf 'third\n' >> "$TEST_DIR/sample.txt"
git -C "$TEST_DIR" add sample.txt
git -C "$TEST_DIR" commit -qm "third"
[ -n "$(invoke "$TEST_DIR" "git commit -m third")" ] || fail "stale ledger prevented review"

rm -f "$TEST_DIR/.git-workflow/.git-workflow-reviewed-shas"
mkdir -p "$TEST_DIR/.claude"
git -C "$TEST_DIR" rev-parse HEAD > "$TEST_DIR/.claude/.git-workflow-reviewed-shas"
[ -z "$(invoke "$TEST_DIR" "git push")" ] || fail "legacy ledger did not suppress duplicate SHA"

rm -f "$TEST_DIR/.claude/.git-workflow-reviewed-shas"
seq 1 650 | sed 's/^/large line /' > "$TEST_DIR/large.txt"
git -C "$TEST_DIR" add large.txt
git -C "$TEST_DIR" commit -qm "large diff"
TRUNCATED="$(invoke "$TEST_DIR" "git commit -m large")"
printf '%s' "$TRUNCATED" | grep -q 'diff truncated' || fail "large diff was not marked truncated"

BRANCH_DIR="$TEST_DIR/branch-switch"
git -C "$TEST_DIR" init -q -b main "$BRANCH_DIR"
git -C "$BRANCH_DIR" config user.name "Git Workflow Test"
git -C "$BRANCH_DIR" config user.email "git-workflow@example.invalid"
printf 'base\n' > "$BRANCH_DIR/base.txt"
git -C "$BRANCH_DIR" add base.txt
git -C "$BRANCH_DIR" commit -qm "base"
mkdir -p "$BRANCH_DIR/.git-workflow" "$BRANCH_DIR/.claude"
printf 'review-on-commit: true\n' > "$BRANCH_DIR/.git-workflow/git-workflow.local.md"
invoke "$BRANCH_DIR" "git commit -m base" >/dev/null
BASE_SHA="$(git -C "$BRANCH_DIR" rev-parse HEAD)"

git -C "$BRANCH_DIR" switch -qc feature
printf 'one\n' > "$BRANCH_DIR/feature-one.txt"
git -C "$BRANCH_DIR" add feature-one.txt
git -C "$BRANCH_DIR" commit -qm "feature one"
FEATURE_ONE_SHA="$(git -C "$BRANCH_DIR" rev-parse HEAD)"
printf 'two\n' > "$BRANCH_DIR/feature-two.txt"
git -C "$BRANCH_DIR" add feature-two.txt
git -C "$BRANCH_DIR" commit -qm "feature two"

git -C "$BRANCH_DIR" switch -qc side main
printf 'side\n' > "$BRANCH_DIR/side.txt"
git -C "$BRANCH_DIR" add side.txt
git -C "$BRANCH_DIR" commit -qm "side"
invoke "$BRANCH_DIR" "git commit -m side" >/dev/null

printf '%s\n' "$FEATURE_ONE_SHA" > "$BRANCH_DIR/.claude/.git-workflow-reviewed-shas"
git -C "$BRANCH_DIR" switch -q feature
BRANCH_OUTPUT="$(invoke "$BRANCH_DIR" "git push")"
printf '%s' "$BRANCH_OUTPUT" | grep -q 'Commits not yet reviewed: 2' || fail "branch switch skipped unreviewed commits"
printf '%s' "$BRANCH_OUTPUT" | grep -q 'feature-one.txt' || fail "branch switch diff omitted first feature commit"
printf '%s' "$BRANCH_OUTPUT" | grep -q 'feature-two.txt' || fail "branch switch diff omitted second feature commit"
grep -qxF "$BASE_SHA" "$BRANCH_DIR/.git-workflow/.git-workflow-reviewed-shas" || fail "canonical ancestor fixture missing"

BASELINE_DIR="$TEST_DIR/default-baseline"
git -C "$TEST_DIR" init -q -b main "$BASELINE_DIR"
git -C "$BASELINE_DIR" config user.name "Git Workflow Test"
git -C "$BASELINE_DIR" config user.email "git-workflow@example.invalid"
printf 'baseline\n' > "$BASELINE_DIR/base-only.txt"
git -C "$BASELINE_DIR" add base-only.txt
git -C "$BASELINE_DIR" commit -qm "baseline"
git -C "$BASELINE_DIR" switch -qc feature
printf 'feature\n' > "$BASELINE_DIR/feature-only.txt"
git -C "$BASELINE_DIR" add feature-only.txt
git -C "$BASELINE_DIR" commit -qm "feature"
mkdir -p "$BASELINE_DIR/.git-workflow"
printf 'review-on-commit: true\n' > "$BASELINE_DIR/.git-workflow/git-workflow.local.md"
BASELINE_OUTPUT="$(invoke "$BASELINE_DIR" "git push")"
printf '%s' "$BASELINE_OUTPUT" | grep -q 'feature-only.txt' || fail "default-branch baseline omitted feature change"
if printf '%s' "$BASELINE_OUTPUT" | grep -q 'base-only.txt'; then fail "default-branch baseline included full repository history"; fi

FAILURE_DIR="$TEST_DIR/failure-retry"
git -C "$TEST_DIR" init -q "$FAILURE_DIR"
git -C "$FAILURE_DIR" config user.name "Git Workflow Test"
git -C "$FAILURE_DIR" config user.email "git-workflow@example.invalid"
printf 'failure\n' > "$FAILURE_DIR/file.txt"
git -C "$FAILURE_DIR" add file.txt
git -C "$FAILURE_DIR" commit -qm "failure"
mkdir -p "$FAILURE_DIR/.git-workflow"
printf 'review-on-commit: true\n' > "$FAILURE_DIR/.git-workflow/git-workflow.local.md"
REAL_GIT="$(command -v git)"
HOOK_FAKE_BIN="$TEST_DIR/hook-fake-bin"
mkdir -p "$HOOK_FAKE_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'for arg in "$@"; do' '  if [ "$arg" = "${GIT_FAIL_COMMAND:-}" ]; then exit 73; fi' 'done' 'exec "$REAL_GIT" "$@"' > "$HOOK_FAKE_BIN/git"
chmod +x "$HOOK_FAKE_BIN/git"
for failing_git_command in rev-list diff; do
  rm -f "$FAILURE_DIR/.git-workflow/.git-workflow-reviewed-shas"
  if REAL_GIT="$REAL_GIT" GIT_FAIL_COMMAND="$failing_git_command" PATH="$HOOK_FAKE_BIN:$PATH" invoke "$FAILURE_DIR" "git push" >/dev/null 2>&1; then
    fail "$failing_git_command failure was treated as success"
  fi
  [ ! -s "$FAILURE_DIR/.git-workflow/.git-workflow-reviewed-shas" ] || fail "$failing_git_command failure recorded reviewed SHA"
done
rm -f "$FAILURE_DIR/.git-workflow/.git-workflow-reviewed-shas"
if GIT_WORKFLOW_SERIALIZER=false invoke "$FAILURE_DIR" "git push" >/dev/null 2>&1; then
  fail "Codex serialization failure was treated as success"
fi
[ ! -s "$FAILURE_DIR/.git-workflow/.git-workflow-reviewed-shas" ] || fail "serialization failure recorded reviewed SHA"
[ -n "$(invoke "$FAILURE_DIR" "git push")" ] || fail "failed delivery was not retryable"

python3 - "$ROOT_DIR" <<'PY' || fail "host hook descriptors are inconsistent"
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
claude_descriptor = json.loads((root / "hooks/claude-hooks.json").read_text())["hooks"]
codex_descriptor = json.loads((root / "hooks/hooks.json").read_text())["hooks"]
claude = claude_descriptor["PostToolUse"]
codex = codex_descriptor["PostToolUse"]
assert all(hook.get("asyncRewake") is True and "--host claude" in hook["command"] for entry in claude for hook in entry["hooks"])
assert all("async" not in hook and "--host codex" in hook["command"] for entry in codex for hook in entry["hooks"])
assert all(entry.get("matcher") == "Bash" for entry in codex)
for descriptor, host in ((claude_descriptor, "claude"), (codex_descriptor, "codex")):
    stop = descriptor["Stop"]
    commands = [hook["command"] for entry in stop for hook in entry["hooks"]]
    assert len(commands) == 1
    assert "agent-complete.py" in commands[0] and f"--host {host}" in commands[0]
    assert "SubagentStop" not in descriptor
PY

printf 'ok: review hook behavior\n'
