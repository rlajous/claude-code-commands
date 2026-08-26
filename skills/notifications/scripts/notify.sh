#!/usr/bin/env bash
# Git Workflow cross-platform desktop notification.
# Usage: notify.sh "<title>" "<message>" [sound-name]

set -u

title="${1:-git-workflow}"
message="${2:-}"
sound="${3:-${GIT_WORKFLOW_SOUND:-Glass}}"

have() { command -v "$1" >/dev/null 2>&1; }
notified=0

case "$(uname -s)" in
  Darwin)
    if have afplay; then
      snd="/System/Library/Sounds/${sound}.aiff"
      [ -f "$snd" ] || snd="/System/Library/Sounds/Glass.aiff"
      [ -f "$snd" ] && afplay "$snd" >/dev/null 2>&1 &
    fi
    if have osascript; then
      osascript \
        -e 'on run argv' \
        -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
        -e 'end run' \
        "$title" "$message" >/dev/null 2>&1 && notified=1
    fi
    ;;
  Linux)
    if have paplay; then
      for candidate in /usr/share/sounds/freedesktop/stereo/complete.oga \
                       /usr/share/sounds/freedesktop/stereo/message.oga; do
        [ -f "$candidate" ] && { paplay "$candidate" >/dev/null 2>&1 & break; }
      done
    elif have aplay && [ -f /usr/share/sounds/alsa/Front_Center.wav ]; then
      aplay /usr/share/sounds/alsa/Front_Center.wav >/dev/null 2>&1 &
    fi
    if have notify-send; then
      notify-send "$title" "$message" >/dev/null 2>&1 && notified=1
    fi
    ;;
esac

[ "$notified" -eq 1 ] || printf '\a' >&2
exit 0
