#!/usr/bin/env bash
# git-workflow — cross-platform desktop ping (sound + notification).
#
# Usage: notify.sh "<title>" "<message>" [sound-name]
#
# Plays a sound and shows a desktop notification so you get pinged while you
# work in another window. Degrades gracefully everywhere and never fails the
# caller (always exits 0) — a notification must not break a workflow.
#
#   macOS : afplay a system sound + osascript notification
#   Linux : paplay/aplay a sound if available + notify-send
#   any   : terminal bell as a last resort
#
# Sound name: a macOS system sound (default "Glass"), or set GIT_WORKFLOW_SOUND.

set -u

title="${1:-git-workflow}"
message="${2:-}"
sound="${3:-${GIT_WORKFLOW_SOUND:-Glass}}"

have() { command -v "$1" >/dev/null 2>&1; }

notified=0

case "$(uname -s)" in
  Darwin)
    # Sound (non-blocking).
    if have afplay; then
      snd="/System/Library/Sounds/${sound}.aiff"
      [ -f "$snd" ] || snd="/System/Library/Sounds/Glass.aiff"
      [ -f "$snd" ] && afplay "$snd" >/dev/null 2>&1 &
    fi
    # Pass untrusted notification text as argv, never as AppleScript source.
    if have osascript; then
      osascript - "$title" "$message" >/dev/null 2>&1 <<'APPLESCRIPT' && notified=1
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
    fi
    ;;
  Linux)
    if have paplay; then
      for s in /usr/share/sounds/freedesktop/stereo/complete.oga \
               /usr/share/sounds/freedesktop/stereo/message.oga; do
        [ -f "$s" ] && { paplay "$s" >/dev/null 2>&1 &  break; }
      done
    elif have aplay; then
      [ -f /usr/share/sounds/alsa/Front_Center.wav ] && aplay /usr/share/sounds/alsa/Front_Center.wav >/dev/null 2>&1 &
    fi
    if have notify-send; then
      notify-send "$title" "$message" >/dev/null 2>&1 && notified=1
    fi
    ;;
esac

# Terminal bell fallback (also a nice audible cue in the console daemon).
if [ "$notified" -eq 0 ]; then
  printf '\a' >&2
fi

exit 0
