#!/bin/sh
# cava, self-healing, listening ONLY to the control-room TTS sink (see
# control-room-voice.py) via a dedicated config — NOT the shared
# ~/.config/cava/config waybar's own cava module uses for real system
# audio. So this bar only moves when Claude is actually speaking.
#
# Also self-healing: a brand-new kitty window's PTY size isn't always
# negotiated yet the instant cava's ncurses backend inits, so the very
# first attempt can fail with "Error opening terminal: unknown" — same
# race waybar's own cava module already works around (see
# waybar/scripts/media.sh's restart-on-death loop). Retrying fixes it.
while :; do
  cava -p ~/.config/cava/control-room.conf
  sleep 0.5
done
