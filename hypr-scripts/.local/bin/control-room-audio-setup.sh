#!/bin/sh
# Dedicated audio path for the control-room TV's TTS voice (see
# control-room-voice.py): a null-sink TTS output is routed to, plus a
# loopback so it's still actually audible through real speakers. cava
# (control-room-cava.sh) captures the null-sink's monitor directly,
# upstream of the loopback, so it only reacts to Claude's speech and
# nothing else playing on the system.
#
# Mutex: same reasoning as control-room-launch.sh's lock — a cold boot's
# monitor.added can fire this more than once in quick succession, and the
# plain "check then create" idempotency check below has a race window
# where two concurrent invocations both see nothing yet and both create
# their own sink/loopback. Confirmed live after a real crash+reboot: ended
# up with two same-named null-sinks and two loopbacks, which makes it
# ambiguous which one paplay/cava actually land on.
LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/control-room-audio-setup.lock"
exec 8>"$LOCKFILE"
flock -n 8 || exit 0

if ! pactl list sinks short | grep -q '\bcontrol_room_tts\b'; then
  pactl load-module module-null-sink sink_name=control_room_tts \
    sink_properties=device.description=Control-Room-TTS >/dev/null
fi

if ! pactl list modules short | grep -q 'module-loopback.*source=control_room_tts.monitor'; then
  # latency_msec=1 was tried first and caused audible crackling/glitching
  # (aggressive enough that any scheduling jitter in the PipeWire graph
  # shows up as noise) — 50ms is still low-latency enough for a live
  # voice reply, just not fighting the scheduler.
  pactl load-module module-loopback source=control_room_tts.monitor \
    sink=@DEFAULT_SINK@ latency_msec=50 >/dev/null
fi
