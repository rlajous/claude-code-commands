#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/review-event.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_event() {
  local expected="$1"
  shift
  local actual
  actual="$(bash "$SCRIPT" "$@")"
  [ "$actual" = "$expected" ] || fail "expected $expected, got $actual"
}

# No configuration defaults to auto: findings request changes and a clean
# review approves. Self-authored PRs always degrade to COMMENT.
(cd "$TEST_ROOT" && expect_event REQUEST_CHANGES --has-blocking true)
(cd "$TEST_ROOT" && expect_event APPROVE --has-blocking false)
(cd "$TEST_ROOT" && expect_event COMMENT --has-blocking true --self-authored)
(cd "$TEST_ROOT" && expect_event COMMENT --has-blocking false --self-authored)

# Explicit comment mode is safe for both findings and clean reviews.
mkdir -p "$TEST_ROOT/.git-workflow"
printf 'review:\n  postEvent: "comment"\n' > "$TEST_ROOT/.git-workflow/config.yaml"
(cd "$TEST_ROOT" && expect_event COMMENT --has-blocking true)
(cd "$TEST_ROOT" && expect_event COMMENT --has-blocking false)

# Canonical configuration wins over the legacy fallback.
mkdir -p "$TEST_ROOT/.claude"
printf 'review:\n  postEvent: auto\n' > "$TEST_ROOT/.claude/config.yaml"
(cd "$TEST_ROOT" && expect_event COMMENT --has-blocking true)

rm "$TEST_ROOT/.git-workflow/config.yaml"
(cd "$TEST_ROOT" && expect_event REQUEST_CHANGES --has-blocking true)

# An explicit path works independently of cwd, and invalid modes fail closed.
EXPLICIT_CONFIG="$TEST_ROOT/config with spaces.yaml"
printf 'review:\n  postEvent: comment\n' > "$EXPLICIT_CONFIG"
expect_event COMMENT --has-blocking false --config "$EXPLICIT_CONFIG"
printf 'review:\n  postEvent: approve\n' > "$EXPLICIT_CONFIG"
if bash "$SCRIPT" --has-blocking false --config "$EXPLICIT_CONFIG" >/dev/null 2>&1; then
  fail "invalid postEvent mode did not fail closed"
fi

printf 'ok: review event configuration scenarios\n'
