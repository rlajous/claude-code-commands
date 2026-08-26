#!/usr/bin/env bash
# Diagnostics and copy-paste daemon command for the review-watch skill.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PACKAGE_ROOT="$(cd "$SKILL_DIR/../.." && pwd -P)"

daemon_command() {
  printf 'bash %q\n' "$SCRIPT_DIR/review-watch.sh"
}

doctor() {
  local failures=0
  local config="none (built-in defaults)"
  local resolved_config=""

  printf 'Review Watch doctor\n'
  printf 'skill_dir=%s\n' "$SKILL_DIR"
  printf 'package_root=%s\n' "$PACKAGE_ROOT"

  if [ -f .git-workflow/config.yaml ]; then
    config="$(cd "$(dirname .git-workflow/config.yaml)" && pwd -P)/config.yaml"
  elif [ -f .claude/config.yaml ]; then
    config="$(cd "$(dirname .claude/config.yaml)" && pwd -P)/config.yaml (legacy fallback)"
  fi
  printf 'config=%s\n' "$config"

  for path in \
    "$PACKAGE_ROOT/.codex-plugin/plugin.json" \
    "$SCRIPT_DIR/review-watch.sh" \
    "$SCRIPT_DIR/notify.sh" \
    "$SKILL_DIR/references/known-issues.md" \
    "$PACKAGE_ROOT/skills/review/scripts/review-event.sh"; do
    if [ -f "$path" ]; then
      printf 'OK file %s\n' "$path"
    else
      printf 'FAIL missing %s\n' "$path"
      failures=$((failures + 1))
    fi
  done

  for dependency in bash python3 node git gh; do
    if command -v "$dependency" >/dev/null 2>&1; then
      printf 'OK dependency %s=%s\n' "$dependency" "$(command -v "$dependency")"
    else
      printf 'FAIL dependency %s\n' "$dependency"
      failures=$((failures + 1))
    fi
  done

  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      printf 'OK gh authentication\n'
    else
      printf 'FAIL gh authentication (run gh auth login)\n'
      failures=$((failures + 1))
    fi
  fi

  if resolved_config="$(bash "$SCRIPT_DIR/review-watch.sh" --show-config)"; then
    printf 'OK review-watch configuration parses\n'
    while IFS= read -r setting; do
      printf 'config.%s\n' "$setting"
    done <<< "$resolved_config"
  else
    printf 'FAIL review-watch configuration\n'
    failures=$((failures + 1))
  fi

  printf 'Claude invocation=/review-watch\n'
  printf 'Codex invocation=$review-watch\n'
  printf 'daemon_command='
  daemon_command

  if [ "$failures" -gt 0 ]; then
    printf 'RESULT: %d failure(s)\n' "$failures"
    return 1
  fi
  printf 'RESULT: ready\n'
}

case "${1:-}" in
  --doctor) doctor ;;
  --daemon-command) daemon_command ;;
  *)
    printf 'usage: %s <--doctor|--daemon-command>\n' "${0##*/}" >&2
    exit 2
    ;;
esac
