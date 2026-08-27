#!/usr/bin/env bash
# Diagnostics and copy-paste daemon command for unified notifications.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PACKAGE_ROOT="$(cd "$SKILL_DIR/../.." && pwd -P)"

daemon_command() {
  printf 'bash %q\n' "$SCRIPT_DIR/activity-watch.sh"
}

doctor() {
  local failures=0 config='none (built-in defaults)' resolved=''
  printf 'Notifications doctor\n'
  printf 'skill_dir=%s\npackage_root=%s\n' "$SKILL_DIR" "$PACKAGE_ROOT"
  if [ -f .git-workflow/config.yaml ]; then
    config="$(cd .git-workflow && pwd -P)/config.yaml"
  elif [ -f .claude/config.yaml ]; then
    config="$(cd .claude && pwd -P)/config.yaml (legacy fallback)"
  fi
  printf 'config=%s\n' "$config"

  for path in \
    "$PACKAGE_ROOT/.codex-plugin/plugin.json" \
    "$PACKAGE_ROOT/hooks/hooks.json" \
    "$PACKAGE_ROOT/hooks/claude-hooks.json" \
    "$SCRIPT_DIR/activity-watch.sh" \
    "$SCRIPT_DIR/activity-events.py" \
    "$SCRIPT_DIR/agent-complete.py" \
    "$SCRIPT_DIR/notification_config.py" \
    "$SCRIPT_DIR/notify.sh"; do
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

  if resolved="$(bash "$SCRIPT_DIR/activity-watch.sh" --show-config 2>&1)"; then
    printf 'OK notification configuration parses\n'
    printf '%s\n' "$resolved" | while IFS= read -r setting; do printf 'config.%s\n' "$setting"; done
  else
    printf 'FAIL notification configuration\n%s\n' "$resolved"
    failures=$((failures + 1))
  fi

  node -e '
const fs = require("fs");
for (const path of process.argv.slice(1)) {
  const hooks = JSON.parse(fs.readFileSync(path, "utf8")).hooks || {};
  const stop = hooks.Stop || [];
  if (!stop.length || !stop.some(group => (group.hooks || []).some(hook => (hook.command || "").includes("agent-complete.py")))) process.exit(1);
}
console.log("OK Claude and Codex Stop hooks registered");
' "$PACKAGE_ROOT/hooks/claude-hooks.json" "$PACKAGE_ROOT/hooks/hooks.json" || failures=$((failures + 1))

  printf 'Claude invocation=/notifications\nCodex invocation=$notifications\n'
  printf 'daemon_command='
  daemon_command
  if [ "$failures" -gt 0 ]; then
    printf 'RESULT: %s failure(s)\n' "$failures"
    return 1
  fi
  printf 'RESULT: ready\n'
}

case "${1:-}" in
  --doctor) doctor ;;
  --daemon-command) daemon_command ;;
  *) printf 'usage: %s <--doctor|--daemon-command>\n' "${0##*/}" >&2; exit 2 ;;
esac
