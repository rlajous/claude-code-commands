#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$SOURCE_DIR/scripts/sync-agent-skills.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

skill() {
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: test\n---\n' "$(basename "$1")" > "$1/SKILL.md"
}

export HOME="$TEST_ROOT/home"
unset CODEX_HOME SKILL_SOURCES CLAUDE_ONLY_SKILLS
mkdir -p "$HOME"

# Fixtures: a skill created from Claude, one from Codex, a duplicate Codex link,
# claude.ai synced skills (one shareable, one Claude-only), and Codex system skills.
skill "$HOME/.claude/skills/from-claude"
skill "$HOME/.codex/skills/from-codex"
mkdir -p "$HOME/.codex/skills/.system"
ln -s "$SOURCE_DIR/skills/commit" "$HOME/.codex/skills/commit"
skill "$HOME/.claude/skills/synced/bucket/pdf"
skill "$HOME/.claude/skills/synced/bucket/docs"
ln -s "$TEST_ROOT/missing" "$HOME/.claude/skills/broken"

bash "$SYNC" >/dev/null

store="$HOME/.agents/skills"
for d in "$SOURCE_DIR"/skills/*/; do
  n="$(basename "$d")"
  [ "$(readlink "$store/$n")" = "${d%/}" ] || fail "$n not linked from checkout"
  [ -f "$HOME/.claude/skills/$n/SKILL.md" ] || fail "$n not exposed to Claude"
done
[ "$(find "$HOME/.claude/agents" -name '*.md' | wc -l | tr -d ' ')" = "$(find "$SOURCE_DIR/agents" -name '*.md' | wc -l | tr -d ' ')" ] || fail "Claude agents not linked"
[ "$(find "$HOME/.codex/agents" -name '*.toml' | wc -l | tr -d ' ')" = "$(find "$SOURCE_DIR/.codex/agents" -name '*.toml' | wc -l | tr -d ' ')" ] || fail "Codex agents not linked"

for n in from-claude from-codex; do
  [ -d "$store/$n" ] && [ ! -L "$store/$n" ] || fail "$n not adopted into the store"
  [ -f "$HOME/.claude/skills/$n/SKILL.md" ] || fail "$n not exposed to Claude"
done
[ -L "$HOME/.claude/skills/from-claude" ] || fail "adopted Claude skill not replaced by a link"
[ ! -e "$HOME/.codex/skills/from-codex" ] || fail "adopted Codex skill left a duplicate"
[ ! -e "$HOME/.codex/skills/commit" ] || fail "duplicate Codex link not removed"
[ -d "$HOME/.codex/skills/.system" ] || fail "Codex system skills touched"

[ -f "$store/pdf/SKILL.md" ] || fail "synced skill not shared"
[ ! -e "$store/docs" ] || fail "Claude-only synced skill shared"
[ ! -e "$HOME/.claude/skills/pdf" ] || fail "synced skill duplicated for Claude"
[ ! -L "$HOME/.claude/skills/broken" ] || fail "broken link not removed"

before="$(cd "$HOME" && find . -printf '%p %l\n' | sort)"
output="$(bash "$SYNC")"
after="$(cd "$HOME" && find . -printf '%p %l\n' | sort)"
[ -z "$output" ] || fail "second run was not quiet: $output"
[ "$before" = "$after" ] || fail "second run changed the layout"

# CODEX_HOME is honored.
export CODEX_HOME="$TEST_ROOT/codex-home"
skill "$CODEX_HOME/skills/from-custom-codex"
bash "$SYNC" >/dev/null
[ -d "$store/from-custom-codex" ] || fail "CODEX_HOME skills not adopted"
[ -n "$(find "$CODEX_HOME/agents" -name '*.toml')" ] || fail "CODEX_HOME agents not linked"

printf 'ok: sync-agent-skills\n'
