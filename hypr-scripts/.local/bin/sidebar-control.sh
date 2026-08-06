#!/bin/sh
# Sidebar terminal geometry: position (which edge) + size (3 stages).
#   sidebar-control.sh apply <name>               re-apply saved geometry
#   sidebar-control.sh position <l|r|top|bottom>  set an exact position directly
#   sidebar-control.sh toggle-sides   left<->right, or top<->bottom — whichever
#                                      axis it's currently docked on
#   sidebar-control.sh toggle-mode    sides (left/right) <-> middle (top/bottom)
#   sidebar-control.sh toggle-size    cycle default -> half -> full -> default
#
# Position: which edge it docks to — left/right keep it vertical (full
# height); top/bottom flip it horizontal (a slim, centered 90-cell-wide
# strip, not full width).
# Size: 3 stages on the "thickness" axis (width for left/right, height for
# top/bottom) — default (25%) -> half (50%) -> full (100% of the true safe
# max for that axis, so "full" always means the actual biggest it can go).
#
# State is kept per-sidebar (term vs claude). Which sidebar these keybinds
# act on is the LAST ONE SHOWN (scripts/sidebar.sh records this on every
# show) — NOT "currently focused window", which is unreliable here (the
# sidebar doesn't always hold keyboard focus after being summoned).
#
# Unlike sway on the ThinkPad, Hyprland's `move`/`resize` here take the
# requested pixel values directly — no compositor-quirk offset compensation
# needed, just a real bar-clearance constant for top-docked sidebars.

STATE_DIR="$HOME/.local/state/armojidots-hypr"
mkdir -p "$STATE_DIR"

GAP=12         # visual inset from a true screen edge, no bar involved
BAR_CLEARANCE=50   # waybar height (34) + its top margin (8) + a little buffer
CROSS_TB=920   # ~90 terminal cells at font_size 13 (JetBrainsMono Nerd Font)

last_sidebar() {
  cat "$STATE_DIR/last-sidebar" 2>/dev/null
}

# exits (no-op) if there's no last-shown sidebar; otherwise prints its name
require_sidebar() {
  name=$(last_sidebar)
  case "$name" in
    sidebar-*) printf '%s' "$name" ;;
    *) exit 0 ;;
  esac
}

current_pos() {
  cat "$STATE_DIR/${1}.pos" 2>/dev/null || echo left
}

focused_output() {
  # hyprctl reports width/height as the pre-rotation mode size even when the
  # output is transformed (confirmed live: HDMI-A-2 is transform=1 90°
  # portrait, hyprctl says 1920x1080, but its actual logical/visible area is
  # 1080x1920 — grim screenshots confirm the swap). transform 1/3 are the 90°
  # rotations, so swap width/height for those; 2 (180°) doesn't change shape.
  #
  # `hyprctl monitors -j` can come back as an empty list `[]` for a brief
  # window right after a cold boot (Hyprland still settling monitor state) —
  # confirmed as the actual cause of "sidebar doesn't appear when pressing
  # the keybind" right after turning the PC on: with no monitors, this used
  # to print nothing at all, so every coordinate downstream in apply()
  # silently became empty/zero instead of erroring, producing a broken,
  # invisible window. Retry briefly (bounded) instead of failing silently —
  # a no-op on every invocation except possibly the very first one post-boot.
  tries=0
  while [ "$tries" -lt 10 ]; do
    n=$(hyprctl monitors -j 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
    [ "${n:-0}" -ge 1 ] 2>/dev/null && break
    tries=$((tries + 1))
    sleep 0.3
  done

  hyprctl monitors -j | python3 -c "
import json, sys
mons = json.load(sys.stdin)
m = next((m for m in mons if m.get('focused')), mons[0] if mons else None)
if m:
    w, h = m['width'], m['height']
    if m.get('transform') in (1, 3):
        w, h = h, w
    print(m['x'], m['y'], w, h)
"
}

# Dedicated workspace ID that no monitor group's Win+N binds can ever reach
# (hyprland.lua's group_ws tops out at group*10+10, so max 110/210/310) and
# that's excluded from waybar's workspace switcher (see its
# ignore-workspaces config) — hidden sidebars live here. See the long
# comment on HIDE/SHOW in apply() below for why this replaced the old
# move-off-screen-while-still-pinned approach.
#
# IMPORTANT: every window.move dispatch that sets `workspace` below also
# needs `follow=false`, or it does NOT behave like a plain reassignment —
# confirmed live it drags the monitor's ACTIVE workspace along with it too
# (i.e. it's the "movetoworkspace" behavior, not "movetoworkspacesilent"),
# which briefly switched the whole visible desktop to workspace 999 during
# testing. `silent=true` looked like the obvious flag name and does NOT
# work — `follow=false` is the one that actually suppresses it.
HIDDEN_WS=999

is_pinned() {
  hyprctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c.get('class') == sys.argv[1]:
        print('yes' if c.get('pinned') else 'no')
        break
" "$1"
}

client_workspace() {
  hyprctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c.get('class') == sys.argv[1]:
        print(c['workspace']['id'])
        break
" "$1"
}

active_workspace() {
  hyprctl activeworkspace -j | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
}

apply() {
  name="$1"

  # hidden = single source of truth for "where is this sidebar right now",
  # shown or not (see sidebar.sh for the toggle logic).
  hidden=$(cat "$STATE_DIR/${name}.hidden" 2>/dev/null || echo yes)

  pos=$(cat "$STATE_DIR/${name}.pos" 2>/dev/null || echo left)
  stage=$(cat "$STATE_DIR/${name}.stage" 2>/dev/null || echo default)

  set -- $(focused_output)
  ox=$1; oy=$2; ow=$3; oh=$4

  # thickness stages — percentages of the TRUE SAFE MAX for that axis (not
  # raw screen width/height), so "full" always means the actual biggest it
  # can go without clipping, and default/half scale proportionally to that.
  case "$pos" in
    left|right) safe_max=$((ow - GAP * 2)) ;;                       # width axis
    top|bottom) safe_max=$((oh - BAR_CLEARANCE - GAP)) ;;           # height axis (bar clearance eats into it)
  esac
  case "$pos:$stage" in
    left:default|right:default) thick=$((safe_max * 25 / 100)) ;;
    top:default|bottom:default) thick=$((safe_max * 32 / 100)) ;;  # a bit roomier than the side default
    *:half)                     thick=$((safe_max * 50 / 100)) ;;
    *:full)                     thick=$safe_max ;;
  esac

  case "$pos" in
    left)
      ax=$GAP;                    ay=$BAR_CLEARANCE
      w=$thick;                   h=$((oh - BAR_CLEARANCE - GAP))
      ;;
    right)
      ax=$((ow - thick - GAP));   ay=$BAR_CLEARANCE
      w=$thick;                   h=$((oh - BAR_CLEARANCE - GAP))
      ;;
    top)
      if [ "$stage" = default ]; then
        ax=$(((ow - CROSS_TB) / 2)); w=$CROSS_TB
      else
        ax=$GAP;                     w=$((ow - GAP * 2))
      fi
      ay=$BAR_CLEARANCE; h=$thick
      ;;
    bottom)
      if [ "$stage" = default ]; then
        ax=$(((ow - CROSS_TB) / 2)); w=$CROSS_TB
      else
        ax=$GAP;                     w=$((ow - GAP * 2))
      fi
      ay=$((oh - thick - GAP)); h=$thick
      ;;
  esac

  rx=$((ox + ax))
  ry=$((oy + ay))

  hyprctl dispatch "hl.dsp.window.resize({window=\"class:$name\", x=$w, y=$h})" >/dev/null

  # HIDE/SHOW via pin state + workspace, NOT off-screen positioning.
  #
  # The old approach kept the window permanently pinned (visible on every
  # workspace by design) and "hid" it by moving it just off a monitor edge.
  # That looked right in every manual test, but broke for real: confirmed
  # live that switching workspaces ON THE SAME MONITOR — via the exact
  # hl.dsp.focus({workspace=...}) dispatch these binds already use, no
  # window creation or fullscreen involved — makes Hyprland clamp every
  # PINNED floating window back inside that monitor's visible box. It
  # doesn't matter which direction or how far off-screen it was moved
  # (tested up/above AND far to the right, past neighboring monitors
  # entirely — both got yanked back to just inside the monitor's edge the
  # instant the active workspace changed). A pinned window being
  # off-monitor is apparently not a state Hyprland is willing to leave
  # alone across a workspace switch. Cross-monitor switches don't trigger
  # this — only same-monitor ones, which matches what was actually
  # reported ("sidebar reappears switching workspaces" — always meant same
  # monitor, never explicitly cross-monitor, and testing confirmed the
  # distinction is real).
  #
  # Fix: while hidden, UNPIN it and park it on $HIDDEN_WS — a workspace ID
  # no monitor ever makes active (see the constant's own comment). An
  # unpinned window on a workspace that's never active simply isn't
  # rendered, and isn't a "pinned window off its monitor" as far as
  # Hyprland's clamp logic is concerned, so nothing pulls it back —
  # confirmed via a hands-off polling test cycling through same-monitor AND
  # cross-monitor workspace switches repeatedly, no movement at all. When
  # shown again: move it onto whatever the currently-focused monitor's
  # active workspace actually is (not a fixed one — you may have switched
  # workspaces while it was hidden), re-pin it, then position it on-screen.
  # Both is_pinned/client_workspace checks before dispatching a change are
  # deliberate, not just tidiness — apply() also runs from toggle-sides/
  # toggle-mode/toggle-size/position while ALREADY hidden or ALREADY shown,
  # and hl.dsp.window.pin is a TOGGLE, not a set-to-value — calling it
  # unconditionally on every apply() would flip pin state the wrong way on
  # every second call.
  if [ "$hidden" = "yes" ]; then
    [ "$(is_pinned "$name")" = "yes" ] && hyprctl dispatch "hl.dsp.window.pin({window=\"class:$name\"})" >/dev/null
    [ "$(client_workspace "$name")" = "$HIDDEN_WS" ] || hyprctl dispatch "hl.dsp.window.move({window=\"class:$name\", workspace=$HIDDEN_WS, follow=false})" >/dev/null
  else
    cur_ws=$(active_workspace)
    [ "$(client_workspace "$name")" = "$cur_ws" ] || hyprctl dispatch "hl.dsp.window.move({window=\"class:$name\", workspace=$cur_ws, follow=false})" >/dev/null
    [ "$(is_pinned "$name")" = "yes" ] || hyprctl dispatch "hl.dsp.window.pin({window=\"class:$name\"})" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({window=\"class:$name\", x=$rx, y=$ry})" >/dev/null
  fi
}

case "$1" in
  apply)
    apply "$2"
    ;;
  position)
    name=$(require_sidebar)
    printf '%s' "$2" > "$STATE_DIR/${name}.pos"
    apply "$name"
    ;;
  toggle-sides)
    name=$(require_sidebar)
    pos=$(current_pos "$name")
    case "$pos" in
      left)   new=right ;;
      right)  new=left ;;
      top)    new=bottom ;;
      bottom) new=top ;;
    esac
    printf '%s' "$new" > "$STATE_DIR/${name}.pos"
    apply "$name"
    ;;
  toggle-mode)
    name=$(require_sidebar)
    pos=$(current_pos "$name")
    case "$pos" in
      left|right) new=top ;;
      top|bottom) new=left ;;
    esac
    printf '%s' "$new" > "$STATE_DIR/${name}.pos"
    apply "$name"
    ;;
  toggle-size)
    name=$(require_sidebar)
    stage=$(cat "$STATE_DIR/${name}.stage" 2>/dev/null || echo default)
    case "$stage" in
      default) stage=half ;;
      half)    stage=full ;;
      full)    stage=default ;;
    esac
    printf '%s' "$stage" > "$STATE_DIR/${name}.stage"
    apply "$name"
    ;;
  *) exit 1 ;;
esac
