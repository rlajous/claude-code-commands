#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reset_fixture() {
  rm -rf "$TEST_DIR/fixture"
  mkdir -p "$TEST_DIR/fixture/scripts" "$TEST_DIR/fixture/.codex"
  cp "$ROOT_DIR/scripts/generate-codex-agents.mjs" "$TEST_DIR/fixture/scripts/"
  cp -R "$ROOT_DIR/agents" "$TEST_DIR/fixture/agents"
  cp -R "$ROOT_DIR/.codex/agents" "$TEST_DIR/fixture/.codex/agents"
}

reset_fixture
node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" --check >/dev/null || fail "clean fixture reported drift"

printf '\nnew canonical instruction\n' >> "$TEST_DIR/fixture/agents/pr-reviewer.md"
if node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" --check >/dev/null 2>&1; then
  fail "check mode missed canonical drift"
fi
node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" >/dev/null
node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" --check >/dev/null || fail "generation did not repair drift"

printf 'name = "orphan"\n' > "$TEST_DIR/fixture/.codex/agents/orphan.toml"
node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" >/dev/null
[ ! -e "$TEST_DIR/fixture/.codex/agents/orphan.toml" ] || fail "generation retained orphan output"

reset_fixture
printf 'do-not-replace\n' > "$TEST_DIR/fixture/.codex/agents/pr-reviewer.toml"
perl -0pi -e 's/name: pr-reviewer/name: different-reviewer/' "$TEST_DIR/fixture/agents/pr-reviewer.md"
if node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" >/dev/null 2>&1; then
  fail "filename/frontmatter mismatch was accepted"
fi
grep -qx 'do-not-replace' "$TEST_DIR/fixture/.codex/agents/pr-reviewer.toml" || fail "validation failure changed generated output"

reset_fixture
perl -0pi -e 's/name: pr-reviewer/name: ..\/..\/escape/' "$TEST_DIR/fixture/agents/pr-reviewer.md"
if node "$TEST_DIR/fixture/scripts/generate-codex-agents.mjs" >/dev/null 2>&1; then
  fail "traversal agent name was accepted"
fi
[ ! -e "$TEST_DIR/escape.toml" ] || fail "agent name escaped the output directory"

python3 - "$TEST_DIR/fixture/.codex/agents" <<'PY' || fail "generated TOML did not parse"
import pathlib
import sys
import tomllib
for path in pathlib.Path(sys.argv[1]).glob("*.toml"):
    with path.open("rb") as file:
        tomllib.load(file)
PY

printf 'ok: Codex agent generation safety\n'
