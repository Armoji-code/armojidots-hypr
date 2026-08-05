#!/bin/sh
# Runs the actual volume/brightness change, then pushes the new level to
# armoji-osd's socket so the pill shows/updates. Called from media-keys.conf.
SOCK="${XDG_RUNTIME_DIR:-/tmp}/armoji-osd.sock"

send() {
  python3 - "$SOCK" "$1" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
try:
    s.sendto(sys.argv[2].encode(), sys.argv[1])
except OSError:
    pass
PY
}

notify_volume() {
  raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
  pct=$(printf '%s' "$raw" | awk '{printf "%d", ($2*100)+0.5}')
  muted=0
  case "$raw" in *MUTED*) muted=1 ;; esac
  send "volume|${pct:-0}|$muted"
}

notify_brightness() {
  pct=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub("%","",$4); print $4}')
  send "brightness|${pct:-0}|0"
}

case "$1" in
  volume-up)       wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+; notify_volume ;;
  volume-down)     wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-; notify_volume ;;
  mute-toggle)     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle; notify_volume ;;
  brightness-up)   brightnessctl set 5%+ >/dev/null; notify_brightness ;;
  brightness-down) brightnessctl set 5%- >/dev/null; notify_brightness ;;
esac
