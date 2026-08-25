#!/usr/bin/env bash
# git-workflow — background review of new commits.
#
# Fired by hooks/hooks.json on `git commit` / `git push` (PostToolUse, asyncRewake).
# Self-contained: only needs bash + git (no Python, no Agent SDK, no jq).
#
# OPT-IN: does nothing unless the project enables it in .claude/git-workflow.local.md:
#
#     review-on-commit: true
#
# When enabled, it emits the diff of commits not yet reviewed (tracked in a local
# ledger) so the agent can review them. Prints nothing when disabled or when there
# is nothing new — so it never adds noise by default.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SETTINGS="$PROJECT_DIR/.claude/git-workflow.local.md"
LEDGER="$PROJECT_DIR/.claude/.git-workflow-reviewed-shas"
MAX_DIFF_LINES=500

# --- opt-in gate -------------------------------------------------------------
# Disabled unless the settings file explicitly turns it on.
if [ ! -f "$SETTINGS" ] || ! grep -qiE '^[[:space:]]*review-on-commit:[[:space:]]*true[[:space:]]*$' "$SETTINGS"; then
  exit 0
fi

# --- must be a git repo ------------------------------------------------------
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

HEAD_SHA="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)" || exit 0
[ -n "$HEAD_SHA" ] || exit 0

mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || true
touch "$LEDGER" 2>/dev/null || true

# Already reviewed this exact HEAD? Nothing to do.
if grep -qxF "$HEAD_SHA" "$LEDGER" 2>/dev/null; then
  exit 0
fi

# --- determine what to review ------------------------------------------------
# DIFF_BASE..HEAD is what we diff; REVLIST_RANGE lists the commits to record.
LAST_REVIEWED="$(tail -n 1 "$LEDGER" 2>/dev/null)"
EMPTY_TREE="$(git -C "$PROJECT_DIR" hash-object -t tree /dev/null 2>/dev/null)"

if [ -n "$LAST_REVIEWED" ] && git -C "$PROJECT_DIR" merge-base --is-ancestor "$LAST_REVIEWED" "$HEAD_SHA" 2>/dev/null; then
  DIFF_BASE="$LAST_REVIEWED"; REVLIST_RANGE="$LAST_REVIEWED..$HEAD_SHA"
elif git -C "$PROJECT_DIR" rev-parse "$HEAD_SHA~1" >/dev/null 2>&1; then
  DIFF_BASE="$HEAD_SHA~1"; REVLIST_RANGE="$HEAD_SHA~1..$HEAD_SHA"   # first review, or ledger stale
else
  DIFF_BASE="$EMPTY_TREE"; REVLIST_RANGE="$HEAD_SHA"                # root commit: diff against the empty tree
fi

# Commit SHAs to record, OLDEST-first so the ledger's last line is the newest
# reviewed commit (which becomes the next baseline via `tail -n 1`).
NEW_SHAS="$(git -C "$PROJECT_DIR" rev-list --reverse --max-count=20 "$REVLIST_RANGE" 2>/dev/null)"
[ -n "$NEW_SHAS" ] || { echo "$HEAD_SHA" >> "$LEDGER" 2>/dev/null || true; exit 0; }

# --- emit the diff for the agent to review -----------------------------------
DIFF="$(git -C "$PROJECT_DIR" diff "$DIFF_BASE" "$HEAD_SHA" 2>/dev/null)"
if [ -z "$DIFF" ]; then
  # Merge/empty commit with no content diff — record and skip.
  printf '%s\n' $NEW_SHAS >> "$LEDGER" 2>/dev/null || true
  exit 0
fi

COMMIT_COUNT="$(printf '%s\n' "$NEW_SHAS" | grep -c . )"
echo "Commits not yet reviewed: $COMMIT_COUNT ($REVLIST_RANGE)"
echo
git -C "$PROJECT_DIR" log --no-decorate --oneline "$REVLIST_RANGE" 2>/dev/null | head -n 20
echo
echo "----- diff (truncated to ${MAX_DIFF_LINES} lines) -----"
printf '%s\n' "$DIFF" | head -n "$MAX_DIFF_LINES"
DIFF_LINES="$(printf '%s\n' "$DIFF" | wc -l | tr -d ' ')"
if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  echo "... (diff truncated; $DIFF_LINES lines total — read the files directly for the rest)"
fi

# Record the reviewed SHAs (oldest-first) so they are not reviewed again.
printf '%s\n' $NEW_SHAS >> "$LEDGER" 2>/dev/null || true
exit 0
