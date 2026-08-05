#!/bin/sh
# Reliable DPMS wake for hypridle's on-resume listeners. Doesn't blindly
# "toggle" — checks each monitor's REAL current dpms state first and only
# toggles the ones that are actually off. hl.dsp.dpms({status="toggle"})
# alone is fragile: it assumes the target is definitely off whenever this
# runs (true in the simple case, on-resume always follows on-timeout),
# but that assumption breaks if anything fires the listeners out of the
# expected order or twice — confirmed this actually happened once already
# (DP-2 stuck black, moving the mouse did nothing, likely from leftover
# duplicate processes after a crash+reboot — see [[oled-idle-off]]).
# Checking real state first makes this self-correcting regardless of cause.
#
# Usage: dpms-wake.sh [MONITOR]  — no arg = check/wake every monitor.
TARGET="$1"
WAYBAR_MONITORS="DP-2 HDMI-A-2"  # outputs that have a bar in waybar/config.jsonc

WOKEN=$(hyprctl monitors -j | python3 -c "
import json, sys
target = sys.argv[1] if len(sys.argv) > 1 else None
for m in json.load(sys.stdin):
    if target and m['name'] != target:
        continue
    if not m['dpmsStatus']:
        print(m['name'])
" "$TARGET")

[ -z "$WOKEN" ] && exit 0

for mon in $WOKEN; do
  hyprctl dispatch "hl.dsp.dpms({status=\"toggle\", monitor=\"$mon\"})" >/dev/null 2>&1
done

sleep 0.3

# Waking a monitor from DPMS-off repeatedly leaves waybar's layer-shell
# surface on it stale/detached — confirmed this happens on ~every cycle,
# not a one-off (the waybar process itself survives fine, it's
# specifically that output's surface that goes missing/never reattaches
# on its own). Self-heal: if any monitor that should have a waybar just
# got woken and doesn't actually have one, do a full restart.
NEEDS_RESTART=0
for mon in $WOKEN; do
  case " $WAYBAR_MONITORS " in
    *" $mon "*)
      HAS_WAYBAR=$(hyprctl layers -j | python3 -c "
import json, sys
d = json.load(sys.stdin)
mon = sys.argv[1]
layers = [l.get('namespace') for lvl in d.get(mon, {}).get('levels', {}).values() for l in lvl]
print('yes' if 'waybar' in layers else 'no')
" "$mon")
      [ "$HAS_WAYBAR" = "no" ] && NEEDS_RESTART=1
      ;;
  esac
done

if [ "$NEEDS_RESTART" = "1" ]; then
  pkill -x waybar
  pkill -9 -f '[m]edia.sh cover'
  pkill -9 -f '[m]edia.sh cava'
  pkill -9 -f '[m]edia.sh playpause'
  pkill -9 -f '[m]edia.sh info'
  sleep 0.5
  nohup waybar >/dev/null 2>&1 &
  disown
fi
