#!/bin/sh
# /set hdr: reuse an already-open armoji-hdr window instead of opening a
# second one. A fresh launch is floated/centered by the armoji-hdr window
# rule in hyprland.lua, right at map time.
if hyprctl clients -j | grep -q '"class": *"armoji-hdr"'; then
  hyprctl dispatch 'hl.dsp.focus({window="class:armoji-hdr"})' >/dev/null
  exit 0
fi
exec ~/.local/bin/armoji-hdr
