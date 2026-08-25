#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

git -C "$TEST_DIR" init -q
git -C "$TEST_DIR" config user.name "Git Workflow Test"
git -C "$TEST_DIR" config user.email "git-workflow@example.invalid"
printf 'fixture\n' > "$TEST_DIR/fixture.txt"
git -C "$TEST_DIR" add fixture.txt
git -C "$TEST_DIR" commit -qm "fixture"

mkdir -p "$TEST_DIR/.claude"
printf 'workflow:\n  developmentBranch: legacy-dev\n' > "$TEST_DIR/.claude/config.yaml"
printf '{"ticket_id":"LEGACY-1","ticket_title":"Legacy"}\n' > "$TEST_DIR/.claude/.pr-context.json"

LEGACY_HTML="$(cd "$TEST_DIR" && node "$ROOT_DIR/scripts/status-report.mjs")"
printf '%s' "$LEGACY_HTML" | grep -q '"developmentBranch":"legacy-dev"' || fail "legacy config fallback was not read"
printf '%s' "$LEGACY_HTML" | grep -q '"id":"LEGACY-1"' || fail "legacy PR context fallback was not read"

mkdir -p "$TEST_DIR/.git-workflow"
printf 'workflow:\n  developmentBranch: canonical-dev\n' > "$TEST_DIR/.git-workflow/config.yaml"
printf '{"ticket_id":"CANON-2","ticket_title":"Canonical"}\n' > "$TEST_DIR/.git-workflow/pr-context.json"

CANONICAL_HTML="$(cd "$TEST_DIR" && node "$ROOT_DIR/scripts/status-report.mjs")"
printf '%s' "$CANONICAL_HTML" | grep -q '"developmentBranch":"canonical-dev"' || fail "canonical config did not win"
printf '%s' "$CANONICAL_HTML" | grep -q '"id":"CANON-2"' || fail "canonical PR context did not win"
if printf '%s' "$CANONICAL_HTML" | grep -q 'LEGACY-1'; then fail "legacy state overrode canonical state"; fi

printf 'ok: runtime state precedence\n'
