#!/bin/sh
# Quick-access sidebar terminals — pinned (sticky, sway's "sticky enable")
# floating windows while SHOWN. NOT Hyprland special workspaces: that looked
# right at first but broke badly in real use — while a special workspace is
# the active/shown one on a monitor, any NEW window opened while it's
# visible silently joins it too (so hiding the sidebar hid whatever you'd
# just opened right along with it), and focus wouldn't reliably move to
# regular windows either (special workspaces are a modal overlay, not a
# peer to normal ones).
#
# Hide/show is now pin + workspace, not on/off-screen positioning — see the
# big comment in sidebar-control.sh's apply() for why: a permanently-pinned
# window merely moved off-screen looked right in every manual test, but
# switching workspaces ON THE SAME MONITOR turned out to yank any pinned
# window that's off its monitor's visible box right back into view, no
# matter how far off-screen it was. Hidden now means unpinned + parked on
# workspace 999 (a plain regular workspace nobody's Win+N bind can reach and
# no monitor ever makes active — NOT a special workspace, so none of the
# problems above apply), which Hyprland leaves alone across every workspace
# switch since it's simply not rendered anywhere.
#
# Position/size are controlled separately (sidebar-control.sh, Win+Shift+
# Arrows / Win+Arrows) and persisted per-sidebar.
# usage: sidebar.sh term | claude

name="sidebar-$1"
case "$1" in
  term)   cmd="kitty --app-id=$name -o env=SIDEBAR=1 fish" ;;
  claude) cmd="kitty --app-id=$name claude" ;;
  *)      exit 1 ;;
esac

STATE_DIR="$HOME/.local/state/armojidots-hypr"
mkdir -p "$STATE_DIR"

exists() {
  hyprctl clients -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('yes' if any(c.get('class') == sys.argv[1] for c in data) else 'no')
" "$name"
}

if [ "$(exists)" = "yes" ]; then
  hidden=$(cat "$STATE_DIR/${name}.hidden" 2>/dev/null || echo yes)
  if [ "$hidden" = "yes" ]; then
    printf 'no' > "$STATE_DIR/${name}.hidden"
  else
    printf 'yes' > "$STATE_DIR/${name}.hidden"
  fi
else
  # float + pin come from hyprland.lua's "sidebar-term"/"sidebar-claude"
  # window rules, applied automatically at map time
  $cmd &
  sleep 0.3   # let the window map before positioning it
  printf 'no' > "$STATE_DIR/${name}.hidden"
fi

# Win+Shift+Arrows / Win+Arrows act on whichever sidebar was shown/toggled
# most recently — recorded here since "currently focused window" is
# unreliable (the sidebar doesn't always hold keyboard focus after summon)
printf '%s' "$name" > "$STATE_DIR/last-sidebar"
~/.local/bin/sidebar-control.sh apply "$name"
