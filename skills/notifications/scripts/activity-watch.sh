#!/usr/bin/env bash
# Git Workflow unified GitHub notification daemon.
#
# Watches review requests and reviews submitted on pull requests you authored.
# Both channels are opt-in and share one GraphQL request per polling interval.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_SCRIPT="$SCRIPT_DIR/notification_config.py"
EVENT_SCRIPT="$SCRIPT_DIR/activity-events.py"
NOTIFY_SCRIPT="${GIT_WORKFLOW_NOTIFY_SCRIPT:-${REVIEW_WATCH_NOTIFY_SCRIPT:-$SCRIPT_DIR/notify.sh}}"
INTERVAL=""
ONCE=0
FORCE=0
SHOW_CONFIG=0
REPO_FILTER=""

usage() {
  printf '%s\n' \
    'usage: activity-watch.sh [--interval N] [--once] [--repo owner/name] [--force] [--show-config]' \
    '' \
    '  --interval N   seconds between polls (default: config, then 60)' \
    '  --once         run one poll and exit' \
    '  --repo o/n     limit both searches to one repository' \
    '  --force        enable review-request polling even when configuration is off' \
    '  --show-config  print resolved configuration and exit'
}

need_value() {
  [ $# -ge 2 ] && [ -n "$2" ] || {
    printf 'notifications: %s needs a value\n' "$1" >&2
    exit 2
  }
}

while [ $# -gt 0 ]; do
  case "$1" in
    --interval)
      need_value "$@"
      case "$2" in ''|*[!0-9]*|0) printf 'notifications: --interval must be a positive integer\n' >&2; exit 2 ;; esac
      INTERVAL="$2"
      shift 2
      ;;
    --once) ONCE=1; shift ;;
    --force) FORCE=1; shift ;;
    --show-config) SHOW_CONFIG=1; shift ;;
    --repo)
      need_value "$@"
      REPO_FILTER="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'notifications: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

CONFIG_OUTPUT="$(python3 "$CONFIG_SCRIPT" --project "$PWD" --shell 2>&1)"
CONFIG_STATUS=$?
config_value() {
  printf '%s\n' "$CONFIG_OUTPUT" | awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }'
}

CFG_REQUESTS="$(config_value reviewRequests)"
CFG_AGENT="$(config_value agentComplete)"
CFG_ACTIVITY="$(config_value prActivity)"
CFG_INTERVAL="$(config_value intervalSeconds)"
CFG_SOUND="$(config_value sound)"
[ -n "$CFG_REQUESTS" ] || CFG_REQUESTS=false
[ -n "$CFG_AGENT" ] || CFG_AGENT=false
[ -n "$CFG_ACTIVITY" ] || CFG_ACTIVITY=false
[ -n "$CFG_SOUND" ] || CFG_SOUND=Glass
if [ -z "$INTERVAL" ]; then
  case "$CFG_INTERVAL" in ''|*[!0-9]*|0) INTERVAL=60 ;; *) INTERVAL="$CFG_INTERVAL" ;; esac
fi

if [ "$SHOW_CONFIG" -eq 1 ]; then
  printf 'enabled=%s\nreviewRequests=%s\nagentComplete=%s\nprActivity=%s\nintervalSeconds=%s\nsound=%s\n' \
    "$CFG_REQUESTS" "$CFG_REQUESTS" "$CFG_AGENT" "$CFG_ACTIVITY" "$INTERVAL" "$CFG_SOUND"
  if [ "$CONFIG_STATUS" -ne 0 ]; then
    printf '%s\n' "$CONFIG_OUTPUT" | awk '/^error=/{print > "/dev/stderr"}'
    exit 2
  fi
  exit 0
fi

if [ "$CONFIG_STATUS" -ne 0 ]; then
  printf 'notifications: invalid configuration\n%s\n' "$CONFIG_OUTPUT" >&2
  exit 2
fi

WATCH_REQUESTED="$CFG_REQUESTS"
[ "$FORCE" -eq 1 ] && WATCH_REQUESTED=true
[ -n "${REVIEW_WATCH_PRS_JSON:-}" ] && WATCH_REQUESTED=true
WATCH_ACTIVITY="$CFG_ACTIVITY"

if [ "$WATCH_REQUESTED" != true ] && [ "$WATCH_ACTIVITY" != true ]; then
  printf "review-watch: disabled. Enable 'reviewWatch.enabled' or 'notifications.prActivity' in .git-workflow/config.yaml.\n" >&2
  exit 0
fi

export GIT_WORKFLOW_SOUND="${GIT_WORKFLOW_SOUND:-$CFG_SOUND}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/git-workflow"
REQUEST_SEEN="$STATE_DIR/review-watch-seen"
ACTIVITY_SEEN="$STATE_DIR/pr-activity-seen"
QUEUE="$STATE_DIR/review-watch-queue.jsonl"
mkdir -p "$STATE_DIR" 2>/dev/null || true

fetch_activity() {
  if [ -n "${GIT_WORKFLOW_GITHUB_JSON:-}" ]; then
    printf '%s' "$GIT_WORKFLOW_GITHUB_JSON"
    return 0
  fi
  if [ -n "${REVIEW_WATCH_PRS_JSON:-}" ]; then
    REVIEW_WATCH_PRS_JSON="$REVIEW_WATCH_PRS_JSON" python3 -c \
      'import json,os; raw=os.environ["REVIEW_WATCH_PRS_JSON"]; requested=json.loads(raw); print(json.dumps({"viewer":"","requested":requested,"authored":[]}))'
    return 0
  fi

  local requested_query='is:pr is:open review-requested:@me'
  local authored_query='is:pr is:open author:@me'
  if [ -n "$REPO_FILTER" ]; then
    requested_query="repo:$REPO_FILTER $requested_query"
    authored_query="repo:$REPO_FILTER $authored_query"
  fi

  gh api graphql \
    -f 'query=query($requestedQuery: String!, $authoredQuery: String!, $watchRequested: Boolean!, $watchAuthored: Boolean!) {
      viewer { login }
      requested: search(query: $requestedQuery, type: ISSUE, first: 50) @include(if: $watchRequested) {
        nodes { ... on PullRequest { number title url headRefOid author { login } repository { nameWithOwner } } }
      }
      authored: search(query: $authoredQuery, type: ISSUE, first: 50) @include(if: $watchAuthored) {
        nodes { ... on PullRequest {
          number title url repository { nameWithOwner }
          reviews(last: 20) { nodes { id state submittedAt author { login } comments { totalCount } } }
        } }
      }
    }' \
    -f requestedQuery="$requested_query" \
    -f authoredQuery="$authored_query" \
    -F watchRequested="$WATCH_REQUESTED" \
    -F watchAuthored="$WATCH_ACTIVITY" \
    --jq '{viewer: (.data.viewer.login // ""), requested: (.data.requested.nodes // []), authored: (.data.authored.nodes // [])}' \
    2>/dev/null
}

find_events() {
  local payload_file status
  payload_file="$(mktemp "${TMPDIR:-/tmp}/git-workflow-activity.XXXXXX")" || return 1
  fetch_activity > "$payload_file"
  status=$?
  if [ "$status" -ne 0 ]; then
    rm -f "$payload_file"
    return "$status"
  fi
  local args=(
    --payload "$payload_file"
    --request-seen "$REQUEST_SEEN"
    --activity-seen "$ACTIVITY_SEEN"
    --queue "$QUEUE"
    --repo "$REPO_FILTER"
  )
  [ "$WATCH_REQUESTED" = true ] && args+=(--watch-requested)
  [ "$WATCH_ACTIVITY" = true ] && args+=(--watch-activity)
  python3 "$EVENT_SCRIPT" "${args[@]}"
  status=$?
  rm -f "$payload_file"
  return "$status"
}

notify() {
  bash "$NOTIFY_SCRIPT" "$1" "$2" "$CFG_SOUND" >/dev/null 2>&1 || true
}

poll() {
  local events status requested_count=0 activity_count=0
  events="$(find_events)"
  status=$?
  if [ "$status" -ne 0 ]; then
    printf "notifications: GitHub query failed. Is gh authenticated? Try 'gh auth login'.\n" >&2
    return 1
  fi
  [ -n "$events" ] || return 0

  while IFS=$'\t' read -r event repo number actor title url; do
    case "$event" in
      REQUESTED)
        requested_count=$((requested_count + 1))
        printf 'review-watch: review requested on %s PR #%s by %s — %s\n' "$repo" "$number" "$actor" "$title"
        [ -n "$url" ] && printf '             %s\n' "$url"
        printf '             Claude: run /review-watch %s\n' "$url"
        printf '             Codex:  run $review-watch %s\n' "$url"
        notify "$repo · PR #$number" "$actor — $title"
        ;;
      BASELINE)
        printf 'notifications: recorded baseline for %s existing review(s).\n' "$repo"
        ;;
      APPROVED|CHANGES_REQUESTED|COMMENTED)
        activity_count=$((activity_count + 1))
        local verb
        case "$event" in
          APPROVED) verb='approved' ;;
          CHANGES_REQUESTED) verb='requested changes' ;;
          COMMENTED) verb='left review feedback' ;;
        esac
        printf 'notifications: %s %s on %s PR #%s — %s\n' "$actor" "$verb" "$repo" "$number" "$title"
        [ -n "$url" ] && printf '               %s\n' "$url"
        notify "$repo · PR #$number" "$actor $verb — $title"
        ;;
    esac
  done < <(printf '%s\n' "$events")
  [ "$requested_count" -gt 0 ] && printf 'review-watch: %s new PR(s) queued for review.\n' "$requested_count"
  [ "$activity_count" -gt 0 ] && printf 'notifications: %s new review event(s).\n' "$activity_count"
  return 0
}

if [ "$ONCE" -eq 1 ]; then
  poll
  exit $?
fi

printf 'notifications: watching every %ss (review requests: %s; PR activity: %s). Ctrl-C to stop.\n' \
  "$INTERVAL" "$WATCH_REQUESTED" "$WATCH_ACTIVITY"
while true; do
  poll || true
  sleep "$INTERVAL"
done
