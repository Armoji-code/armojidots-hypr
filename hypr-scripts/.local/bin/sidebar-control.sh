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

apply() {
  name="$1"

  # hidden = moved just past the edge it's docked to, not a workspace change
  # (see sidebar.sh for why) — this is the single source of truth for "where
  # is this sidebar right now", shown or not. Computed from the same
  # geometry as the shown position below (not a single far-off-screen
  # coordinate) so the move animation is a short, normal-looking slide off
  # the relevant edge instead of a comically long cross-screen jump.
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

  if [ "$hidden" = "yes" ]; then
    # always up, off the top of whichever monitor it's actually on —
    # regardless of dock side. Going left/right off this output's own edge
    # can land inside a horizontally-adjacent monitor instead of actually
    # being hidden (side-by-side layout), and going all the way past the
    # true combined virtual-desktop edge turns a docked-on-the-right-hand-
    # monitor sidebar into a slide across the entire desktop width. Up is
    # short (bounded by this monitor's own height, using the window's own
    # height $h so it clears fully regardless of dock orientation) and
    # never crosses into a neighboring monitor either way.
    hyprctl dispatch "hl.dsp.window.move({window=\"class:$name\", x=$rx, y=$((oy - h - 50))})" >/dev/null
  else
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
