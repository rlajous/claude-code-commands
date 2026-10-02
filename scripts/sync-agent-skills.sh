#!/usr/bin/env bash
# Install Git Workflow user-wide for every local agent and keep one shared skill set.
#
# Canonical store: ~/.agents/skills (read by Codex and other agents that follow the
# shared skills convention). On each run:
#   0. Skills from source checkouts ($SKILL_SOURCES, default: this checkout) are linked
#      into the store, and their agents into ~/.claude/agents and $CODEX_HOME/agents.
#      A `git pull` in the checkout is enough to pick up new skills.
#   1. Real skill directories created in ~/.claude/skills or $CODEX_HOME/skills are moved
#      into the store and replaced by a symlink, so a skill added from any agent is shared.
#   2. claude.ai synced skills are linked into the store (except Claude-only ones).
#   3. Every non-synced skill in the store is linked into ~/.claude/skills (unprefixed).
#   4. Symlinks in $CODEX_HOME/skills that duplicate store skills are removed (Codex does
#      not merge duplicate names), and broken links are cleaned up.
# Idempotent; safe to run from a Claude Code SessionStart hook or cron.
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SOURCES="${SKILL_SOURCES:-$(cd "$SCRIPT_DIR/.." && pwd)/skills}"
AGENTS="$HOME/.agents/skills"
CLAUDE="$HOME/.claude/skills"
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"
CODEX="$CODEX_ROOT/skills"
# Synced from claude.ai but depend on Claude-only tools.
CLAUDE_ONLY="${CLAUDE_ONLY_SKILLS:-docs morning import-memory}"

mkdir -p "$AGENTS" "$CLAUDE" "$CODEX"

is_skill() { [ -f "$1/SKILL.md" ]; }

# 0. Link skills (and named agents) from source checkouts.
for src in $SOURCES; do
  for d in "$src"/*/; do
    d="${d%/}"; n="$(basename "$d")"
    is_skill "$d" || continue
    [ -e "$AGENTS/$n" ] || [ -L "$AGENTS/$n" ] || ln -s "$d" "$AGENTS/$n"
  done
  root="$(dirname "$src")"
  if [ -d "$root/agents" ]; then
    mkdir -p "$HOME/.claude/agents"
    for f in "$root"/agents/*.md; do
      t="$HOME/.claude/agents/$(basename "$f")"
      [ -e "$t" ] && [ ! -L "$t" ] || ln -sfn "$f" "$t"
    done
  fi
  if [ -d "$root/.codex/agents" ]; then
    mkdir -p "$CODEX_ROOT/agents"
    for f in "$root"/.codex/agents/*.toml; do
      t="$CODEX_ROOT/agents/$(basename "$f")"
      [ -e "$t" ] && [ ! -L "$t" ] || ln -sfn "$f" "$t"
    done
  fi
done

# 1. Adopt real skill directories living in agent-specific folders.
for src in "$CLAUDE" "$CODEX"; do
  for d in "$src"/*/; do
    d="${d%/}"; n="$(basename "$d")"
    [ -L "$d" ] && continue
    is_skill "$d" || continue            # skips "synced", ".system", etc.
    if [ -e "$AGENTS/$n" ]; then
      echo "skip $d: $AGENTS/$n already exists" >&2
      continue
    fi
    mv "$d" "$AGENTS/$n"
    ln -s "$AGENTS/$n" "$d"
    echo "adopted $n from $src"
  done
done

# 2. Link claude.ai synced skills into the shared store.
for d in "$CLAUDE"/synced/*/*/; do
  d="${d%/}"; n="$(basename "$d")"
  is_skill "$d" || continue
  case " $CLAUDE_ONLY " in *" $n "*) continue ;; esac
  if [ -L "$AGENTS/$n" ] || [ ! -e "$AGENTS/$n" ]; then ln -sfn "$d" "$AGENTS/$n"; fi
done

# 3. Expose shared skills to Claude Code (synced ones it already loads natively).
for d in "$AGENTS"/*; do
  n="$(basename "$d")"
  if [[ "$(readlink "$d" || true)" == "$CLAUDE/synced/"* ]]; then
    [ -L "$CLAUDE/$n" ] && rm "$CLAUDE/$n"
    continue
  fi
  [ -e "$CLAUDE/$n" ] && [ ! -L "$CLAUDE/$n" ] && continue
  ln -sfn "$AGENTS/$n" "$CLAUDE/$n"
done

# 4. Drop Codex symlinks that duplicate shared skills, and broken links everywhere.
for l in "$CODEX"/*; do
  n="$(basename "$l")"
  [ -L "$l" ] && [ -e "$AGENTS/$n" ] && rm "$l"
done
for dir in "$AGENTS" "$CLAUDE" "$CODEX" "$HOME/.claude/agents" "$CODEX_ROOT/agents"; do
  for l in "$dir"/*; do [ -L "$l" ] && [ ! -e "$l" ] && rm "$l"; done
done
exit 0
