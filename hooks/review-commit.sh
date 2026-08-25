#!/usr/bin/env bash
# Emit an incremental commit diff for the active host to review.

set -uo pipefail

HOST_KIND="claude"
if [ "${1:-}" = "--host" ] && [ -n "${2:-}" ]; then
  HOST_KIND="$2"
fi

HOOK_INPUT="$(cat)"

json_field() {
  local expression="$1"
  printf '%s' "$HOOK_INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); v=$expression; print(v if isinstance(v, str) else '')" 2>/dev/null
}

TOOL_COMMAND="$(json_field "(d.get('tool_input') or {}).get('command', '')")"
PROJECT_DIR="$(json_field "d.get('cwd', '')")"
PROJECT_DIR="${PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

# Codex invokes this hook for every Bash call; Claude may pre-filter with `if`.
case "$TOOL_COMMAND" in
  *"git commit"*|*"git push"*) ;;
  *) exit 0 ;;
esac

CANONICAL_DIR="$PROJECT_DIR/.git-workflow"
CANONICAL_SETTINGS="$CANONICAL_DIR/git-workflow.local.md"
LEGACY_SETTINGS="$PROJECT_DIR/.claude/git-workflow.local.md"
LEDGER="$CANONICAL_DIR/.git-workflow-reviewed-shas"
LEGACY_LEDGER="$PROJECT_DIR/.claude/.git-workflow-reviewed-shas"
MAX_DIFF_LINES=500

SETTINGS=""
if [ -f "$CANONICAL_SETTINGS" ]; then
  SETTINGS="$CANONICAL_SETTINGS"
elif [ -f "$LEGACY_SETTINGS" ]; then
  SETTINGS="$LEGACY_SETTINGS"
fi

if [ -z "$SETTINGS" ] || ! grep -qiE '^[[:space:]]*review-on-commit:[[:space:]]*true[[:space:]]*$' "$SETTINGS"; then
  exit 0
fi

if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

HEAD_SHA="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)" || exit 0
[ -n "$HEAD_SHA" ] || exit 0

mkdir -p "$CANONICAL_DIR" 2>/dev/null || exit 0
touch "$LEDGER" 2>/dev/null || exit 0

if grep -qxF "$HEAD_SHA" "$LEDGER" 2>/dev/null || grep -qxF "$HEAD_SHA" "$LEGACY_LEDGER" 2>/dev/null; then
  exit 0
fi

LAST_REVIEWED="$(tail -n 1 "$LEDGER" 2>/dev/null)"
if [ -z "$LAST_REVIEWED" ] && [ -f "$LEGACY_LEDGER" ]; then
  LAST_REVIEWED="$(tail -n 1 "$LEGACY_LEDGER" 2>/dev/null)"
fi
EMPTY_TREE="$(git -C "$PROJECT_DIR" hash-object -t tree /dev/null 2>/dev/null)"

if [ -n "$LAST_REVIEWED" ] && git -C "$PROJECT_DIR" merge-base --is-ancestor "$LAST_REVIEWED" "$HEAD_SHA" 2>/dev/null; then
  DIFF_BASE="$LAST_REVIEWED"
  REVLIST_RANGE="$LAST_REVIEWED..$HEAD_SHA"
elif git -C "$PROJECT_DIR" rev-parse "$HEAD_SHA~1" >/dev/null 2>&1; then
  DIFF_BASE="$HEAD_SHA~1"
  REVLIST_RANGE="$HEAD_SHA~1..$HEAD_SHA"
else
  DIFF_BASE="$EMPTY_TREE"
  REVLIST_RANGE="$HEAD_SHA"
fi

NEW_SHAS="$(git -C "$PROJECT_DIR" rev-list --reverse --max-count=20 "$REVLIST_RANGE" 2>/dev/null)"
[ -n "$NEW_SHAS" ] || {
  printf '%s\n' "$HEAD_SHA" >> "$LEDGER" 2>/dev/null || true
  exit 0
}

DIFF="$(git -C "$PROJECT_DIR" diff "$DIFF_BASE" "$HEAD_SHA" 2>/dev/null)"
if [ -z "$DIFF" ]; then
  printf '%s\n' $NEW_SHAS >> "$LEDGER" 2>/dev/null || true
  exit 0
fi

COMMIT_COUNT="$(printf '%s\n' "$NEW_SHAS" | grep -c .)"
DIFF_LINES="$(printf '%s\n' "$DIFF" | wc -l | tr -d ' ')"
LOG="$(git -C "$PROJECT_DIR" log --no-decorate --oneline "$REVLIST_RANGE" 2>/dev/null | head -n 20)"
TRUNCATED_DIFF="$(printf '%s\n' "$DIFF" | head -n "$MAX_DIFF_LINES")"

PAYLOAD="Commits not yet reviewed: $COMMIT_COUNT ($REVLIST_RANGE)

$LOG

----- diff (truncated to ${MAX_DIFF_LINES} lines) -----
$TRUNCATED_DIFF"
if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  PAYLOAD="$PAYLOAD
... (diff truncated; $DIFF_LINES lines total — read the files directly for the rest)"
fi

printf '%s\n' $NEW_SHAS >> "$LEDGER" 2>/dev/null || true

if [ "$HOST_KIND" = "codex" ]; then
  REVIEW_CONTEXT="Background review of newly committed or pushed changes. Review this diff, delegate non-trivial analysis to the pr-reviewer project agent, surface only real issues, and then continue the user's request:

$PAYLOAD"
  REVIEW_CONTEXT="$REVIEW_CONTEXT" python3 -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":os.environ["REVIEW_CONTEXT"]}}))'
else
  printf '%s\n' "$PAYLOAD"
fi
