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
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["version"] == "2.5.1"; assert len(d["managed_files"]) == 8' "$EMPTY_TARGET/.git-workflow/version.json" || fail "invalid version ledger"

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
[ "$(find "$CLAUDE_TARGET/.claude/skills" -name SKILL.md | wc -l | tr -d ' ')" = "19" ] || fail "Claude install did not create 19 skills"
[ "$(find "$CLAUDE_TARGET/.claude/agents" -name '*.md' | wc -l | tr -d ' ')" = "8" ] || fail "Claude install did not create eight agents"
[ -f "$CLAUDE_TARGET/.claude/references/runtime-compatibility.md" ] || fail "Claude install omitted shared compatibility reference"

BOTH_TARGET="$TEST_ROOT/both"
mkdir -p "$BOTH_TARGET"
node "$SYNC" --source "$SOURCE_DIR" --target "$BOTH_TARGET" --host both >/dev/null
CLAUDE_ORPHAN="$BOTH_TARGET/.claude/agents/removed-claude.md"
CODEX_ORPHAN="$BOTH_TARGET/.codex/agents/removed-codex.toml"
printf 'removed claude\n' > "$CLAUDE_ORPHAN"
printf 'name = "removed-codex"\n' > "$CODEX_ORPHAN"
BOTH_LEDGER="$BOTH_TARGET/.git-workflow/version.json"
BOTH_LEDGER="$BOTH_LEDGER" python3 - <<'PY'
import json
import os
p = os.environ["BOTH_LEDGER"]
with open(p) as f:
    data = json.load(f)
data["managed_files"].extend([
    ".claude/agents/removed-claude.md",
    ".codex/agents/removed-codex.toml",
])
with open(p, "w") as f:
    json.dump(data, f)
PY
node "$SYNC" --source "$SOURCE_DIR" --target "$BOTH_TARGET" --host codex --prune --confirm-prune >/dev/null
[ ! -e "$CODEX_ORPHAN" ] || fail "single-host prune retained selected Codex orphan"
[ -f "$CLAUDE_ORPHAN" ] || fail "single-host prune deleted unselected Claude asset"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert ".claude/agents/removed-claude.md" in d["managed_files"]
assert ".codex/agents/removed-codex.toml" not in d["managed_files"]
assert d["hosts"] == ["claude", "codex"]
' "$BOTH_LEDGER" || fail "single-host update discarded unselected ledger state"

UNOWNED_TARGET="$TEST_ROOT/unowned"
mkdir -p "$UNOWNED_TARGET/.codex/agents"
printf 'name = "project-owned"\n' > "$UNOWNED_TARGET/.codex/agents/pr-reviewer.toml"
if node "$SYNC" --source "$SOURCE_DIR" --target "$UNOWNED_TARGET" --host codex >/dev/null 2>&1; then
  fail "pre-existing customization did not produce a preserved-files status"
fi
grep -q 'project-owned' "$UNOWNED_TARGET/.codex/agents/pr-reviewer.toml" || fail "pre-existing customization was overwritten"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert ".codex/agents/pr-reviewer.toml" not in d["managed_files"]
' "$UNOWNED_TARGET/.git-workflow/version.json" || fail "preserved project file was falsely recorded as managed"
node "$SYNC" --source "$SOURCE_DIR" --target "$UNOWNED_TARGET" --host codex --prune --confirm-prune >/dev/null 2>&1 || true
grep -q 'project-owned' "$UNOWNED_TARGET/.codex/agents/pr-reviewer.toml" || fail "prune deleted an unowned customization"

for invalid_case in hosts-string files-string traversal absolute; do
  INVALID_TARGET="$TEST_ROOT/invalid-$invalid_case"
  mkdir -p "$INVALID_TARGET/.git-workflow"
  case "$invalid_case" in
    hosts-string) printf '{"hosts":"codex","managed_files":[]}\n' > "$INVALID_TARGET/.git-workflow/version.json" ;;
    files-string) printf '{"hosts":["codex"],"managed_files":"abc"}\n' > "$INVALID_TARGET/.git-workflow/version.json" ;;
    traversal) printf '{"hosts":["codex"],"managed_files":[".codex/../outside"]}\n' > "$INVALID_TARGET/.git-workflow/version.json" ;;
    absolute) printf '{"hosts":["codex"],"managed_files":["/tmp/outside"]}\n' > "$INVALID_TARGET/.git-workflow/version.json" ;;
  esac
  if node "$SYNC" --source "$SOURCE_DIR" --target "$INVALID_TARGET" --host codex --force --prune --confirm-prune >/dev/null 2>&1; then
    fail "invalid ledger was accepted: $invalid_case"
  fi
  [ ! -e "$INVALID_TARGET/.codex" ] || fail "invalid ledger caused file mutation: $invalid_case"
done

INCOMPLETE_SOURCE="$TEST_ROOT/incomplete-source"
mkdir -p "$INCOMPLETE_SOURCE/skills" "$INCOMPLETE_SOURCE/agents" "$INCOMPLETE_SOURCE/.codex/agents"
if node "$SYNC" --source "$INCOMPLETE_SOURCE" --target "$TEST_ROOT/incomplete-target" --host codex >/dev/null 2>&1; then
  fail "source without Codex manifest was accepted"
fi

DIFF_TARGET="$TEST_ROOT/diff-failure"
mkdir -p "$DIFF_TARGET/.codex/agents"
printf 'custom\n' > "$DIFF_TARGET/.codex/agents/comment-analyzer.toml"
FAKE_BIN="$TEST_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
printf '#!/usr/bin/env bash\nexit 2\n' > "$FAKE_BIN/diff"
chmod +x "$FAKE_BIN/diff"
if PATH="$FAKE_BIN:/usr/bin:/bin" "$(command -v node)" "$SYNC" --source "$SOURCE_DIR" --target "$DIFF_TARGET" --host codex --force >/dev/null 2>&1; then
  fail "failed diff preview did not stop synchronization"
fi
grep -qx 'custom' "$DIFF_TARGET/.codex/agents/comment-analyzer.toml" || fail "failed diff preview allowed overwrite"

URL_SOURCE="$TEST_ROOT/url-source"
mkdir -p "$URL_SOURCE/.codex" "$URL_SOURCE/.codex-plugin"
cp -R "$SOURCE_DIR/skills" "$SOURCE_DIR/agents" "$URL_SOURCE/"
cp -R "$SOURCE_DIR/.codex/agents" "$URL_SOURCE/.codex/"
cp "$SOURCE_DIR/.codex-plugin/plugin.json" "$URL_SOURCE/.codex-plugin/plugin.json"
git -C "$URL_SOURCE" init -q
git -C "$URL_SOURCE" config user.name "Git Workflow Test"
git -C "$URL_SOURCE" config user.email "git-workflow@example.invalid"
git -C "$URL_SOURCE" add .
git -C "$URL_SOURCE" commit -qm "fixture"
URL_TARGET="$TEST_ROOT/url-target"
mkdir -p "$URL_TARGET"
node "$SYNC" --source "file://$URL_SOURCE" --target "$URL_TARGET" --host codex >/dev/null
[ "$(find "$URL_TARGET/.codex/agents" -name '*.toml' | wc -l | tr -d ' ')" = "8" ] || fail "Git URL source did not install agents"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["source"].startswith("file://")' "$URL_TARGET/.git-workflow/version.json" || fail "Git URL source was not retained in ledger"

printf 'ok: setup/update synchronization scenarios\n'
