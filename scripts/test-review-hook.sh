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

printf 'ok: review hook behavior\n'
