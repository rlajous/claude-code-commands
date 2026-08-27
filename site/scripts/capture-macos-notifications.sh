#!/usr/bin/env bash
# Capture deterministic documentation evidence from the production macOS notifier.

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
package_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
output_dir="${1:-$package_root/.artifacts/macos-notifications}"
notify_script="$package_root/skills/notifications/scripts/notify.sh"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-workflow-notifications.XXXXXX")"
surface_pid=""

cleanup() {
  if [ -n "$surface_pid" ]; then
    kill "$surface_pid" >/dev/null 2>&1 || true
    wait "$surface_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$temporary_dir"
}
trap cleanup EXIT INT TERM

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'capture-macos-notifications.sh requires macOS.\n' >&2
  exit 1
fi

for command_name in swiftc screencapture sips osascript; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

if [ ! -x "$notify_script" ]; then
  printf 'Production notifier is not executable: %s\n' "$notify_script" >&2
  exit 1
fi

mkdir -p "$output_dir"
rm -f \
  "$output_dir/agent-finished-macos.png" \
  "$output_dir/pr-approved-macos.png" \
  "$output_dir/pr-changes-requested-macos.png"

swiftc "$script_dir/macos-notification-surface.swift" -o "$temporary_dir/notification-surface"
swiftc "$script_dir/macos-notification-window.swift" -o "$temporary_dir/notification-window"

defaults write NSGlobalDomain AppleInterfaceStyle -string Dark >/dev/null 2>&1 || true
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false >/dev/null 2>&1 || true

# Register Script Editor as a notification source, then enable its temporary
# banner style for this disposable CI user. Fresh macOS users commonly default
# AppleScript notifications to Notification Center history without a banner.
"$notify_script" 'Git Workflow capture' 'Preparing notification evidence' Glass
python3 "$script_dir/enable-macos-notification-banners.py" | tee "$output_dir/notification-preferences.log"
killall cfprefsd usernoted >/dev/null 2>&1 || true
launchctl bootstrap \
  "gui/$(id -u)" \
  /System/Library/LaunchAgents/com.apple.notificationcenterui.plist \
  >>"$output_dir/notification-preferences.log" 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/com.apple.notificationcenterui.agent" \
  >>"$output_dir/notification-preferences.log" 2>&1 || true
open -gja /System/Library/CoreServices/NotificationCenter.app \
  >>"$output_dir/notification-preferences.log" 2>&1 || true
launchctl print "gui/$(id -u)/com.apple.notificationcenterui.agent" \
  >>"$output_dir/notification-preferences.log" 2>&1 || true
sleep 3

"$temporary_dir/notification-surface" >"$output_dir/surface.log" 2>&1 &
surface_pid=$!
sleep 3

if ! kill -0 "$surface_pid" >/dev/null 2>&1; then
  printf 'The clean capture surface could not start.\n' >&2
  cat "$output_dir/surface.log" >&2 || true
  exit 1
fi

capture_banner() {
  local filename="$1"
  local title="$2"
  local message="$3"
  local window_id=""
  local attempt

  launchctl bootstrap \
    "gui/$(id -u)" \
    /System/Library/LaunchAgents/com.apple.notificationcenterui.plist \
    >>"$output_dir/${filename%.png}-windows.log" 2>&1 || true
  launchctl kickstart "gui/$(id -u)/com.apple.notificationcenterui.agent" \
    >>"$output_dir/${filename%.png}-windows.log" 2>&1 || true
  open -gja /System/Library/CoreServices/NotificationCenter.app \
    >>"$output_dir/${filename%.png}-windows.log" 2>&1 || true
  sleep 1
  "$notify_script" "$title" "$message" Glass

  : >"$output_dir/${filename%.png}-windows.log"
  for attempt in $(seq 1 30); do
    if window_id="$("$temporary_dir/notification-window" 2>>"$output_dir/${filename%.png}-windows.log")" \
      && [ -n "$window_id" ]; then
      break
    fi
    window_id=""
    sleep 0.2
  done

  screencapture -x "$output_dir/${filename%.png}-diagnostic.png" || true

  if [ -z "$window_id" ]; then
    printf 'Notification window not found for %s.\n' "$filename" >&2
    return 1
  fi

  if ! screencapture -x -o -l "$window_id" "$output_dir/$filename"; then
    printf 'macOS denied the capture for notification window %s.\n' "$window_id" >&2
    return 1
  fi

  local width height
  width="$(sips -g pixelWidth "$output_dir/$filename" | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "$output_dir/$filename" | awk '/pixelHeight/ { print $2 }')"
  if [ -z "$width" ] || [ -z "$height" ] || [ "$width" -lt 250 ] || [ "$height" -lt 50 ]; then
    printf 'Captured image has implausible dimensions: %sx%s (%s).\n' "$width" "$height" "$filename" >&2
    return 1
  fi

  printf '%s\t%sx%s\twindow %s\n' "$filename" "$width" "$height" "$window_id"

  # Let a temporary banner expire before delivering the next fixture.
  sleep 6
}

capture_banner \
  agent-finished-macos.png \
  'rlajous/claude-code-commands · Codex' \
  'Agent finished — Improved macOS notification captures'

capture_banner \
  pr-approved-macos.png \
  'rlajous/claude-code-commands · PR #29' \
  '@reviewer approved — Redesign Agent Tooling documentation UI'

capture_banner \
  pr-changes-requested-macos.png \
  'rlajous/claude-code-commands · PR #29' \
  '@reviewer requested changes — Redesign Agent Tooling documentation UI'

printf 'Captured three real macOS banners in %s\n' "$output_dir"
