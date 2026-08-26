#!/usr/bin/env bash
# Emit an incremental commit diff for the active host to review.

set -euo pipefail

fail() {
  printf 'git-workflow review hook: %s\n' "$1" >&2
  exit 1
}

HOST_KIND="claude"
if [ "${1:-}" = "--host" ]; then
  [ -n "${2:-}" ] || fail "--host requires claude or codex"
  HOST_KIND="$2"
  shift 2
fi
[ "$#" -eq 0 ] || fail "unknown argument: $1"
case "$HOST_KIND" in
  claude|codex) ;;
  *) fail "--host must be claude or codex" ;;
esac

PYTHON_BIN="${GIT_WORKFLOW_PYTHON:-python3}"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python 3 is required to parse hook input"
HOOK_INPUT="$(cat)" || fail "could not read hook input"

PARSED_INPUT="$({ printf '%s' "$HOOK_INPUT" | "$PYTHON_BIN" -c '
import json, sys
try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise TypeError("root must be an object")
    tool_input = data.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        raise TypeError("tool_input must be an object")
    command = tool_input.get("command", "")
    cwd = data.get("cwd", "")
    if not isinstance(command, str) or not isinstance(cwd, str):
        raise TypeError("cwd and tool_input.command must be strings")
    print(json.dumps([command, cwd]))
except (json.JSONDecodeError, TypeError) as error:
    print(f"invalid hook input: {error}", file=sys.stderr)
    raise SystemExit(2)
'; } 2>&1)" || fail "$PARSED_INPUT"

TOOL_COMMAND="$(printf '%s' "$PARSED_INPUT" | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)[0])')" || fail "could not decode hook command"
PROJECT_DIR="$(printf '%s' "$PARSED_INPUT" | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)[1])')" || fail "could not decode hook working directory"
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

git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0
HEAD_SHA="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)" || fail "could not resolve HEAD in $PROJECT_DIR"
[ -n "$HEAD_SHA" ] || fail "HEAD resolved to an empty SHA"

if [ -f "$LEDGER" ]; then
  DUPLICATE_LEDGER="$LEDGER"
else
  DUPLICATE_LEDGER="$LEGACY_LEDGER"
fi
if [ -f "$DUPLICATE_LEDGER" ]; then
  set +e
  grep -qxF "$HEAD_SHA" "$DUPLICATE_LEDGER"
  DUPLICATE_STATUS=$?
  set -e
  [ "$DUPLICATE_STATUS" -le 1 ] || fail "could not read $DUPLICATE_LEDGER"
  [ "$DUPLICATE_STATUS" -eq 0 ] && exit 0
fi

find_latest_ancestor() {
  local ledger_path="$1"
  local candidate
  local ancestor_status
  local reversed
  [ -f "$ledger_path" ] || return 1
  reversed="$(awk 'NF { lines[++count]=$0 } END { for (i=count; i>=1; i--) print lines[i] }' "$ledger_path")" || return 2
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if ! git -C "$PROJECT_DIR" cat-file -e "${candidate}^{commit}" 2>/dev/null; then
      continue
    fi
    if git -C "$PROJECT_DIR" merge-base --is-ancestor "$candidate" "$HEAD_SHA" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    else
      ancestor_status=$?
      [ "$ancestor_status" -eq 1 ] || return 2
    fi
  done <<< "$reversed"
  return 1
}

find_default_branch_base() {
  local candidate
  local merge_base
  local symbolic_default=""
  symbolic_default="$(git -C "$PROJECT_DIR" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  for candidate in "$symbolic_default" origin/main origin/master main master; do
    [ -n "$candidate" ] || continue
    if git -C "$PROJECT_DIR" rev-parse --verify "${candidate}^{commit}" >/dev/null 2>&1; then
      merge_base="$(git -C "$PROJECT_DIR" merge-base "$candidate" "$HEAD_SHA" 2>/dev/null)" || return 2
      if [ -n "$merge_base" ] && [ "$merge_base" != "$HEAD_SHA" ]; then
        printf '%s\n' "$merge_base"
        return 0
      fi
    fi
  done
  return 1
}

LAST_REVIEWED=""
if [ -f "$LEDGER" ]; then
  set +e
  LAST_REVIEWED="$(find_latest_ancestor "$LEDGER")"
  ANCESTOR_STATUS=$?
  set -e
  [ "$ANCESTOR_STATUS" -le 1 ] || fail "could not inspect canonical reviewed-SHA ledger"
fi
if [ -z "$LAST_REVIEWED" ] && [ -f "$LEGACY_LEDGER" ]; then
  set +e
  LAST_REVIEWED="$(find_latest_ancestor "$LEGACY_LEDGER")"
  ANCESTOR_STATUS=$?
  set -e
  [ "$ANCESTOR_STATUS" -le 1 ] || fail "could not inspect legacy reviewed-SHA ledger"
fi

EMPTY_TREE="$(git -C "$PROJECT_DIR" hash-object -t tree /dev/null 2>/dev/null)" || fail "could not resolve the empty Git tree"
if [ -n "$LAST_REVIEWED" ]; then
  DIFF_BASE="$LAST_REVIEWED"
  REVLIST_RANGE="$LAST_REVIEWED..$HEAD_SHA"
else
  set +e
  DEFAULT_BRANCH_BASE="$(find_default_branch_base)"
  DEFAULT_BASE_STATUS=$?
  set -e
  [ "$DEFAULT_BASE_STATUS" -le 1 ] || fail "could not compute the default-branch merge-base"
  if [ -n "$DEFAULT_BRANCH_BASE" ]; then
    DIFF_BASE="$DEFAULT_BRANCH_BASE"
    REVLIST_RANGE="$DEFAULT_BRANCH_BASE..$HEAD_SHA"
  else
    DIFF_BASE="$EMPTY_TREE"
    REVLIST_RANGE="$HEAD_SHA"
  fi
fi

NEW_SHAS="$(git -C "$PROJECT_DIR" rev-list --reverse --max-count=20 "$REVLIST_RANGE" 2>/dev/null)" \
  || fail "git rev-list failed for $REVLIST_RANGE"
if [ -z "$NEW_SHAS" ]; then
  NEW_SHAS="$HEAD_SHA"
fi

DIFF="$(git -C "$PROJECT_DIR" diff "$DIFF_BASE" "$HEAD_SHA" 2>/dev/null)" \
  || fail "git diff failed for $DIFF_BASE..$HEAD_SHA"

record_reviewed_shas() {
  mkdir -p "$CANONICAL_DIR" || fail "could not create $CANONICAL_DIR"
  touch "$LEDGER" || fail "could not write $LEDGER"
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    set +e
    grep -qxF "$sha" "$LEDGER" 2>/dev/null
    RECORDED_STATUS=$?
    set -e
    [ "$RECORDED_STATUS" -le 1 ] || fail "could not read $LEDGER"
    if [ "$RECORDED_STATUS" -eq 1 ]; then
      printf '%s\n' "$sha" >> "$LEDGER" || fail "could not update $LEDGER"
    fi
  done <<< "$NEW_SHAS"
}

if [ -z "$DIFF" ]; then
  record_reviewed_shas
  exit 0
fi

COMMIT_COUNT="$(printf '%s\n' "$NEW_SHAS" | awk 'NF { count++ } END { print count+0 }')"
DIFF_LINES="$(printf '%s\n' "$DIFF" | wc -l | tr -d ' ')"
LOG="$(git -C "$PROJECT_DIR" log --no-decorate --oneline --max-count=20 "$REVLIST_RANGE" 2>/dev/null)" \
  || fail "git log failed for $REVLIST_RANGE"
TRUNCATED_DIFF="$(printf '%s\n' "$DIFF" | sed -n "1,${MAX_DIFF_LINES}p")"

PAYLOAD="Commits not yet reviewed: $COMMIT_COUNT ($REVLIST_RANGE)

$LOG

----- diff (truncated to ${MAX_DIFF_LINES} lines) -----
$TRUNCATED_DIFF"
if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
  PAYLOAD="$PAYLOAD
... (diff truncated; $DIFF_LINES lines total — read the files directly for the rest)"
fi

if [ "$HOST_KIND" = "codex" ]; then
  REVIEW_CONTEXT="Background review of newly committed or pushed changes. Review this diff, delegate non-trivial analysis to the pr-reviewer project agent, surface only real issues, and then continue the user's request:

$PAYLOAD"
  SERIALIZER_BIN="${GIT_WORKFLOW_SERIALIZER:-$PYTHON_BIN}"
  command -v "$SERIALIZER_BIN" >/dev/null 2>&1 || fail "Codex output serializer is unavailable"
  CODEX_OUTPUT="$(REVIEW_CONTEXT="$REVIEW_CONTEXT" "$SERIALIZER_BIN" -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":os.environ["REVIEW_CONTEXT"]}}))')" \
    || fail "could not serialize Codex additionalContext output"
  printf '%s\n' "$CODEX_OUTPUT" || fail "could not emit Codex hook output"
else
  printf '%s\n' "$PAYLOAD" || fail "could not emit Claude hook output"
fi

# Only suppress future reviews after useful context was delivered successfully.
record_reviewed_shas
