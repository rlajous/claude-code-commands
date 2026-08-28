#!/usr/bin/env bash
# Capture deterministic documentation evidence from the production macOS notifier.

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
package_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
mode="local"
output_dir="$package_root/.artifacts/macos-notifications"
notify_script="$package_root/skills/notifications/scripts/notify.sh"
preference_script="$script_dir/enable-macos-notification-banners.py"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-workflow-notifications.XXXXXX")"
runner_snapshot="$temporary_dir/capture-preferences.json"
surface_pid=""
preferences_before=""
script_editor_started=0
runner_snapshot_created=0

usage() {
  cat <<'EOF'
Usage: capture-macos-notifications.sh [OUTPUT_DIR]
       capture-macos-notifications.sh --mode local|runner [--output OUTPUT_DIR]

Modes:
  local   Capture from the current Mac without changing notification or appearance preferences (default).
  runner  Temporarily prepare a dedicated runner, then restore and verify its preferences.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      [ "$#" -ge 2 ] || { printf '%s\n' 'Missing value for --mode.' >&2; exit 2; }
      mode="$2"
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || { printf '%s\n' 'Missing value for --output.' >&2; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      # Preserve the original positional OUTPUT_DIR interface used by existing automation.
      output_dir="$1"
      shift
      ;;
  esac
done

if [ "$mode" != "local" ] && [ "$mode" != "runner" ]; then
  printf 'Unsupported capture mode: %s\n' "$mode" >&2
  exit 2
fi

output_dir="$(mkdir -p "$output_dir" && CDPATH= cd -- "$output_dir" && pwd -P)"
raw_dir="$output_dir/raw"

snapshot_preferences() {
  {
    printf '%s\n' '--- NSGlobalDomain ---'
    defaults read NSGlobalDomain 2>/dev/null || true
    printf '%s\n' '--- Notification preferences ---'
    defaults export com.apple.ncprefs - 2>/dev/null || true
  } | shasum -a 256 | awk '{ print $1 }'
}

# Refresh the macOS agents that cache appearance and Notification Center preferences.
restart_notification_services() {
  killall cfprefsd usernoted >/dev/null 2>&1 || true
  launchctl bootstrap \
    "gui/$(id -u)" \
    /System/Library/LaunchAgents/com.apple.notificationcenterui.plist \
    >>"$output_dir/notification-preferences.log" 2>&1 || true
  launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui.agent" \
    >>"$output_dir/notification-preferences.log" 2>&1 || true
  open -gja /System/Library/CoreServices/NotificationCenter.app \
    >>"$output_dir/notification-preferences.log" 2>&1 || true
}

# Restore every temporary process and preference while preserving the original exit status.
cleanup() {
  local exit_code="${1:-$?}"
  trap - EXIT INT TERM
  if [ -n "$surface_pid" ]; then
    kill "$surface_pid" >/dev/null 2>&1 || true
    wait "$surface_pid" >/dev/null 2>&1 || true
  fi

  if [ "$runner_snapshot_created" -eq 1 ]; then
    if ! python3 "$preference_script" restore --snapshot "$runner_snapshot" \
      >>"$output_dir/notification-preferences.log" 2>&1; then
      printf '%s\n' 'Unable to restore the runner macOS preferences; see notification-preferences.log.' >&2
      exit_code=1
    fi
    restart_notification_services
    if ! launchctl print "gui/$(id -u)/com.apple.notificationcenterui.agent" >/dev/null 2>&1; then
      printf '%s\n' 'Notification Center did not recover after restoring runner preferences.' >&2
      exit_code=1
    fi
  fi

  if [ "$script_editor_started" -eq 1 ]; then
    osascript -e 'tell application id "com.apple.ScriptEditor2" to quit' >/dev/null 2>&1 || true
  fi
  rm -rf "$temporary_dir"

  if [ "$mode" = "local" ] && [ -n "$preferences_before" ]; then
    local preferences_after
    preferences_after="$(snapshot_preferences)"
    if [ "$preferences_before" != "$preferences_after" ]; then
      printf '%s\n' 'Local capture changed appearance or notification preferences; refusing the evidence.' >&2
      exit_code=1
    fi
  fi
  exit "$exit_code"
}
trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'capture-macos-notifications.sh requires macOS.\n' >&2
  exit 1
fi

for command_name in swiftc screencapture sips osascript node ffmpeg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

if [ ! -x "$notify_script" ]; then
  printf 'Production notifier is not executable: %s\n' "$notify_script" >&2
  exit 1
fi

if [ ! -d "$package_root/site/node_modules/sharp" ]; then
  printf '%s\n' 'Missing site dependency: run npm ci --prefix site before capturing.' >&2
  exit 1
fi

mkdir -p "$raw_dir"
# Remove full-screen diagnostics left by older versions; this script never recreates them.
rm -f \
  "$output_dir/agent-finished-macos.png" \
  "$output_dir/pr-approved-macos.png" \
  "$output_dir/pr-changes-requested-macos.png" \
  "$output_dir/notifications-macos.apng" \
  "$raw_dir/agent-finished-macos.png" \
  "$raw_dir/pr-approved-macos.png" \
  "$raw_dir/pr-changes-requested-macos.png" \
  "$output_dir/agent-finished-macos-diagnostic.png" \
  "$output_dir/pr-approved-macos-diagnostic.png" \
  "$output_dir/pr-changes-requested-macos-diagnostic.png"

swiftc "$script_dir/macos-notification-surface.swift" -o "$temporary_dir/notification-surface"
swiftc "$script_dir/macos-notification-window.swift" -o "$temporary_dir/notification-region"

if [ "$mode" = "runner" ]; then
  # Snapshot first so even Script Editor's initial notification registration is reversible.
  python3 "$preference_script" snapshot --snapshot "$runner_snapshot"
  runner_snapshot_created=1
  "$notify_script" 'Git Workflow capture' 'Preparing notification evidence' Glass
  python3 "$preference_script" prepare --snapshot "$runner_snapshot" \
    | tee "$output_dir/notification-preferences.log"
  restart_notification_services
  if ! pgrep -x 'Script Editor' >/dev/null 2>&1; then
    open -gja '/System/Applications/Utilities/Script Editor.app' \
      >>"$output_dir/notification-preferences.log" 2>&1 || true
    script_editor_started=1
  fi
  sleep 3
else
  # Recent macOS releases deliver `osascript display notification` banners only after
  # Script Editor has joined the current GUI session. Launch it hidden and restore its
  # previous running state during cleanup; notification delivery still uses notify.sh.
  if ! pgrep -x 'Script Editor' >/dev/null 2>&1; then
    open -gja '/System/Applications/Utilities/Script Editor.app'
    script_editor_started=1
    sleep 2
  fi
  preferences_before="$(snapshot_preferences)"
  if ! launchctl print "gui/$(id -u)/com.apple.notificationcenterui.agent" >/dev/null 2>&1; then
    printf '%s\n' 'Notification Center is not running for the current macOS user.' >&2
    exit 1
  fi
  if [ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true)" != "Dark" ]; then
    printf '%s\n' 'Local evidence capture requires the current macOS appearance to be Dark; no setting was changed.' >&2
    exit 1
  fi
  printf '%s\n' 'Local mode: current appearance and notification preferences will not be changed.'
fi

"$temporary_dir/notification-surface" >"$output_dir/surface.log" 2>&1 &
surface_pid=$!
sleep 3

if ! kill -0 "$surface_pid" >/dev/null 2>&1; then
  printf 'The clean capture surface could not start.\n' >&2
  sed -n '1,120p' "$output_dir/surface.log" >&2 || true
  exit 1
fi

capture_banner() {
  local filename="$1"
  local title="$2"
  local message="$3"
  local capture_region=""
  local window_log="$output_dir/${filename%.png}-windows.log"

  : >"$window_log"
  if ! capture_region="$("$temporary_dir/notification-region" 2>>"$window_log")" \
    || [ -z "$capture_region" ]; then
    printf 'Unable to resolve the Notification Center banner region for %s.\n' "$filename" >&2
    return 1
  fi
  "$notify_script" "$title" "$message" Glass
  sleep 0.45

  if ! screencapture -x -R"$capture_region" "$raw_dir/$filename"; then
    printf 'macOS denied the banner-region capture. Allow Screen Recording for the terminal host.\n' >&2
    return 1
  fi

  local width height
  width="$(sips -g pixelWidth "$raw_dir/$filename" | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$raw_dir/$filename" | awk '/pixelHeight/ { print $2 }')"
  if [ -z "$width" ] || [ -z "$height" ] || [ "$width" -lt 250 ] || [ "$height" -lt 50 ]; then
    printf 'Captured image has implausible dimensions: %sx%s (%s).\n' "$width" "$height" "$filename" >&2
    return 1
  fi

  printf '%s\t%sx%s\tregion %s\n' "$filename" "$width" "$height" "$capture_region"

  # Let the temporary banner expire before delivering the next fixture.
  sleep 6
}

capture_banner \
  agent-finished-macos.png \
  'rlajous/claude-code-commands · Codex' \
  'Agent finished — Improved notification evidence'

capture_banner \
  pr-changes-requested-macos.png \
  'rlajous/claude-code-commands · PR #29' \
  '@reviewer requested changes — Redesign Agent Tooling documentation UI'

capture_banner \
  pr-approved-macos.png \
  'rlajous/claude-code-commands · PR #29' \
  '@reviewer approved — Redesign Agent Tooling documentation UI'

node "$script_dir/build-notification-assets.mjs" \
  --input "$raw_dir" \
  --output "$output_dir"

printf 'Captured and processed three real macOS banners in %s\n' "$output_dir"
