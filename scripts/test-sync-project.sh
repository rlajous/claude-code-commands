#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$SOURCE_DIR/scripts/sync-project.mjs"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

EMPTY_TARGET="$TEST_ROOT/empty"
mkdir -p "$EMPTY_TARGET"
node "$SYNC" --source "$SOURCE_DIR" --target "$EMPTY_TARGET" --host codex --migrate-config --initialize-config --dry-run >/dev/null
[ ! -e "$EMPTY_TARGET/.codex" ] || fail "dry-run created Codex directory"
[ ! -e "$EMPTY_TARGET/.git-workflow" ] || fail "dry-run created workflow directory"

node "$SYNC" --source "$SOURCE_DIR" --target "$EMPTY_TARGET" --host codex --migrate-config --initialize-config >/dev/null
[ "$(find "$EMPTY_TARGET/.codex/agents" -name '*.toml' | wc -l | tr -d ' ')" = "8" ] || fail "empty install did not create eight agents"
[ -f "$EMPTY_TARGET/.git-workflow/config.yaml" ] || fail "empty setup did not create canonical config"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["version"] == "2.4.0"; assert len(d["managed_files"]) == 8' "$EMPTY_TARGET/.git-workflow/version.json" || fail "invalid version ledger"

LEGACY_TARGET="$TEST_ROOT/legacy"
mkdir -p "$LEGACY_TARGET/.claude"
printf 'workflow:\n  developmentBranch: legacy\n' > "$LEGACY_TARGET/.claude/config.yaml"
node "$SYNC" --source "$SOURCE_DIR" --target "$LEGACY_TARGET" --host codex --migrate-config >/dev/null
cmp "$LEGACY_TARGET/.claude/config.yaml" "$LEGACY_TARGET/.git-workflow/config.yaml" >/dev/null || fail "legacy config was not migrated"
[ -f "$LEGACY_TARGET/.claude/config.yaml" ] || fail "legacy config was deleted"

node "$SYNC" --source "$SOURCE_DIR" --target "$LEGACY_TARGET" --host codex --migrate-config >/dev/null

CUSTOM_AGENT="$LEGACY_TARGET/.codex/agents/pr-reviewer.toml"
printf '\n# project customization\n' >> "$CUSTOM_AGENT"
if node "$SYNC" --source "$SOURCE_DIR" --target "$LEGACY_TARGET" --host codex >/dev/null 2>&1; then
  fail "customized file did not require confirmation or force"
fi
grep -q 'project customization' "$CUSTOM_AGENT" || fail "customized file was overwritten"
node "$SYNC" --source "$SOURCE_DIR" --target "$LEGACY_TARGET" --host codex --force >/dev/null
if grep -q 'project customization' "$CUSTOM_AGENT"; then fail "force did not replace customized file"; fi

ORPHAN="$LEGACY_TARGET/.codex/agents/removed-agent.toml"
printf 'name = "removed-agent"\n' > "$ORPHAN"
LEDGER="$LEGACY_TARGET/.git-workflow/version.json"
LEDGER="$LEDGER" python3 - <<'PY'
import json
import os
p = os.environ["LEDGER"]
with open(p) as f:
    data = json.load(f)
data["managed_files"].append(".codex/agents/removed-agent.toml")
with open(p, "w") as f:
    json.dump(data, f)
PY
if node "$SYNC" --source "$SOURCE_DIR" --target "$LEGACY_TARGET" --host codex --prune >/dev/null 2>&1; then
  fail "prune did not require separate confirmation"
fi
[ -f "$ORPHAN" ] || fail "unconfirmed prune removed a file"
node "$SYNC" --source "$SOURCE_DIR" --target "$LEGACY_TARGET" --host codex --prune --confirm-prune >/dev/null
[ ! -e "$ORPHAN" ] || fail "confirmed prune retained managed orphan"

CLAUDE_TARGET="$TEST_ROOT/claude"
mkdir -p "$CLAUDE_TARGET"
node "$SYNC" --source "$SOURCE_DIR" --target "$CLAUDE_TARGET" --host claude >/dev/null
[ "$(find "$CLAUDE_TARGET/.claude/skills" -name SKILL.md | wc -l | tr -d ' ')" = "17" ] || fail "Claude install did not create 17 skills"
[ "$(find "$CLAUDE_TARGET/.claude/agents" -name '*.md' | wc -l | tr -d ' ')" = "8" ] || fail "Claude install did not create eight agents"
[ -f "$CLAUDE_TARGET/.claude/references/runtime-compatibility.md" ] || fail "Claude install omitted shared compatibility reference"

printf 'ok: setup/update synchronization scenarios\n'
