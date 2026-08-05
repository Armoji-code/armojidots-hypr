#!/bin/sh
# Populates the control-room TV (DP-1, workspace 31) with 4 tiled panes:
# htop of debianlab, cava (TTS-only, see control-room-cava.sh), a live
# Jellyfin dashboard, and wake-word voice control for Claude Code.
#
# Reproduces Armin's saved layout exactly:
#   left column (wide):  voice (top, tall) / cava (bottom, short)
#   right column (narrow): jellyfin (top) / htop (bottom)
# using `layout preselect` to force each split direction rather than
# relying on dwindle's aspect-ratio heuristic, which doesn't reliably
# reproduce this shape on its own.
#
# If ALL 4 panes are already up, this is a no-op. If ANY are missing (one
# died, or this is a cold boot), it tears down whichever survivors remain
# and does a full clean rebuild — a partial "just relaunch the missing
# one" fallback was tried first and is exactly what scrambled the layout
# once already: relaunching a single pane in-place lands it wherever
# dwindle's default split happens to put it, not back in its original
# slot, since killing a tiled window hands its space to a sibling and
# there's no cheap way to know which slot to reclaim. A full rebuild is
# the only way to keep this deterministic.

# Mutex: on a cold boot DP-1 (a cheap TV) can connect/disconnect/reconnect
# a few times during HDMI/DP handshake, firing monitor.added repeatedly in
# quick succession — each one calls this script. Without a lock, two
# invocations can both see "0/4 panes up" before either has finished
# building, and both proceed to build a full duplicate set (confirmed
# live after a real crash+reboot: ended up with 4 copies of most panes,
# some even landing on the wrong monitor since a second invocation's
# `focus DP-1`/`focus workspace 31` raced against the first invocation's
# window creation). -n makes this non-blocking: if a build is already in
# progress, later triggers just bail instead of queuing up to build a
# second redundant set right after.
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/control-room-launch.lock"
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

running() {
  hyprctl clients -j | grep -q "\"class\": *\"$1\""
}

kill_class() {
  hyprctl clients -j | python3 -c "
import json, sys, subprocess
for c in json.load(sys.stdin):
    if c['class'] == '$1':
        subprocess.run(['kill', '-9', str(c['pid'])])
"
}

addr_of() {
  hyprctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1':
        print(c['address'])
        break
"
}

wait_for() {
  for _ in $(seq 1 40); do
    a=$(addr_of "$1")
    [ -n "$a" ] && { echo "$a"; return 0; }
    sleep 0.1
  done
  return 1
}

focus_addr() {
  hyprctl dispatch "hl.dsp.focus({window=\"address:$1\"})" >/dev/null 2>&1
  sleep 0.2
}

resize_active() {
  hyprctl dispatch "hl.dsp.window.resize({x=$1, y=$2})" >/dev/null 2>&1
}

preselect() {
  hyprctl dispatch "hl.dsp.layout(\"preselect $1\")" >/dev/null 2>&1
}

hyprctl dispatch 'hl.dsp.focus({monitor="DP-1"})' >/dev/null 2>&1
hyprctl dispatch 'hl.dsp.focus({workspace=31})' >/dev/null 2>&1

ALL_UP=1
for c in control-room-voice control-room-htop control-room-cava control-room-jellyfin; do
  running "$c" || ALL_UP=0
done

if [ "$ALL_UP" = "0" ]; then
  for c in control-room-voice control-room-htop control-room-cava control-room-jellyfin; do
    running "$c" && kill_class "$c"
  done
  sleep 0.5

  kitty --class control-room-voice --title "Hey Claude" ~/.local/bin/control-room-voice.py &
  VOICE=$(wait_for control-room-voice) || exit 1

  preselect r
  kitty --class control-room-jellyfin --title "Jellyfin" ~/.local/bin/control-room-jellyfin.sh &
  JF=$(wait_for control-room-jellyfin) || exit 1
  focus_addr "$JF"
  resize_active 437 300   # sets the root split's width (this is direct/self)

  preselect d
  kitty --class control-room-htop --title "debianlab · htop" ~/.local/bin/control-room-htop.sh &
  HTOP=$(wait_for control-room-htop) || exit 1
  focus_addr "$HTOP"
  # Resizing while focused on the SECOND window of a top/bottom pair sets
  # the FIRST (already-existing) sibling's height, not its own — verified
  # empirically, not documented. So this targets jellyfin's height (300),
  # not htop's; htop gets whatever's left over.
  resize_active 437 300

  focus_addr "$VOICE"
  preselect d
  kitty --class control-room-cava --title "cava" ~/.local/bin/control-room-cava.sh &
  CAVA=$(wait_for control-room-cava) || exit 1
  focus_addr "$CAVA"
  # Same rule: this sets voice's (the first sibling's) height to 510, cava
  # gets the remainder.
  resize_active 881 510
fi
