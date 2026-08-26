#!/usr/bin/env bash
# Resolve the GitHub pull-request review event from verdict, authorship, and
# review.postEvent configuration. Prints exactly one of REQUEST_CHANGES,
# APPROVE, or COMMENT.
#
# Usage: review-event.sh --has-blocking <true|false> [--self-authored] [--config <path>]

set -uo pipefail

HAS_BLOCKING=""
SELF_AUTHORED=0
CONFIG_PATH=""

need_value() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "review-event: $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --has-blocking)
      need_value "$@"
      case "$2" in true|false) HAS_BLOCKING="$2" ;; *) echo "review-event: --has-blocking must be true or false" >&2; exit 2 ;; esac
      shift 2 ;;
    --self-authored) SELF_AUTHORED=1; shift ;;
    --config) need_value "$@"; CONFIG_PATH="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "review-event: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$HAS_BLOCKING" ] || { echo "review-event: --has-blocking is required" >&2; exit 2; }

if [ -z "$CONFIG_PATH" ]; then
  if [ -f .git-workflow/config.yaml ]; then CONFIG_PATH=.git-workflow/config.yaml
  elif [ -f .claude/config.yaml ]; then CONFIG_PATH=.claude/config.yaml
  fi
fi

POST_EVENT=auto
if [ -n "$CONFIG_PATH" ]; then
  [ -f "$CONFIG_PATH" ] || { echo "review-event: config not found: $CONFIG_PATH" >&2; exit 2; }
  configured="$(awk '
    /^[^[:space:]#]/ { inblock = ($0 ~ /^review:/) ? 1 : 0 }
    inblock && $0 ~ "^[[:space:]]+postEvent:" {
      line=$0
      sub("^[[:space:]]+postEvent:[[:space:]]*", "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      first=substr(line, 1, 1); last=substr(line, length(line), 1)
      if ((first == "\"" && last == "\"") || (first == sprintf("%c", 39) && last == sprintf("%c", 39)))
        line=substr(line, 2, length(line) - 2)
      print line; exit
    }
  ' "$CONFIG_PATH")"
  [ -z "$configured" ] || POST_EVENT="$configured"
fi

case "$POST_EVENT" in auto|comment) ;; *) echo "review-event: review.postEvent must be auto or comment" >&2; exit 2 ;; esac

if [ "$SELF_AUTHORED" -eq 1 ] || [ "$POST_EVENT" = comment ]; then
  printf 'COMMENT\n'
elif [ "$HAS_BLOCKING" = true ]; then
  printf 'REQUEST_CHANGES\n'
else
  printf 'APPROVE\n'
fi
