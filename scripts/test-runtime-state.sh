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
printf 'workflow:\n  developmentBranch: release@2026+blue\n' > "$TEST_DIR/.git-workflow/config.yaml"
printf '{"ticket_id":"CANON-2","ticket_title":"Canonical"}\n' > "$TEST_DIR/.git-workflow/pr-context.json"

CANONICAL_HTML="$(cd "$TEST_DIR" && node "$ROOT_DIR/scripts/status-report.mjs")"
printf '%s' "$CANONICAL_HTML" | grep -q '"developmentBranch":"release@2026+blue"' || fail "canonical config did not preserve the complete branch value"
printf '%s' "$CANONICAL_HTML" | grep -q '"id":"CANON-2"' || fail "canonical PR context did not win"
if printf '%s' "$CANONICAL_HTML" | grep -q 'LEGACY-1'; then fail "legacy state overrode canonical state"; fi

printf 'workflow:\n  developmentBranch: [broken\n' > "$TEST_DIR/.git-workflow/config.yaml"
printf '{broken json\n' > "$TEST_DIR/.git-workflow/pr-context.json"
CORRUPT_HTML="$(cd "$TEST_DIR" && node "$ROOT_DIR/scripts/status-report.mjs")"
printf '%s' "$CORRUPT_HTML" | grep -q '"developmentBranch":"staging"' || fail "malformed canonical config did not use safe default"
printf '%s' "$CORRUPT_HTML" | grep -q '"ticket":null' || fail "malformed canonical context was not ignored"
printf '%s' "$CORRUPT_HTML" | grep -q 'Could not parse developmentBranch' || fail "malformed canonical config emitted no warning"
printf '%s' "$CORRUPT_HTML" | grep -q 'Could not read .git-workflow/pr-context.json' || fail "malformed canonical context emitted no warning"
if printf '%s' "$CORRUPT_HTML" | grep -q 'LEGACY-1'; then fail "corrupt canonical context silently fell back to legacy"; fi

CURRENT_BRANCH="$(git -C "$TEST_DIR" branch --show-current)"
printf 'workflow:\n  developmentBranch: canonical-dev\n' > "$TEST_DIR/.git-workflow/config.yaml"
printf '{"ticket_id":"STALE-3","branch":"%s-stale"}\n' "$CURRENT_BRANCH" > "$TEST_DIR/.git-workflow/pr-context.json"
STALE_HTML="$(cd "$TEST_DIR" && node "$ROOT_DIR/scripts/status-report.mjs")"
printf '%s' "$STALE_HTML" | grep -q 'Ignored stale .git-workflow/pr-context.json' || fail "stale branch context emitted no warning"
printf '%s' "$STALE_HTML" | grep -q '"ticket":null' || fail "stale branch context was used"

rm -f "$TEST_DIR/.git-workflow/config.yaml"
mkdir "$TEST_DIR/.git-workflow/config.yaml"
UNREADABLE_HTML="$(cd "$TEST_DIR" && node "$ROOT_DIR/scripts/status-report.mjs")"
printf '%s' "$UNREADABLE_HTML" | grep -q 'Could not read .git-workflow/config.yaml' || fail "unreadable canonical config emitted no warning"
if printf '%s' "$UNREADABLE_HTML" | grep -q 'legacy-dev'; then fail "unreadable canonical config silently fell back to legacy"; fi

printf 'ok: runtime state precedence\n'
