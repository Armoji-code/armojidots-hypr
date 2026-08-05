#!/bin/sh
# /set monitors: reuse an already-open nwg-displays window instead of opening
# a second one (nwg-displays supports Hyprland natively, same as sway).
# A fresh launch is floated/centered by the nwg-displays window rule in
# hyprland.lua, right at map time.
if hyprctl clients -j | grep -q '"class": *"nwg-displays"'; then
  hyprctl dispatch 'hl.dsp.focus({window="class:nwg-displays"})' >/dev/null
  exit 0
fi
exec nwg-displays
