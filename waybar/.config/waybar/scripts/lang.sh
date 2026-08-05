#!/bin/sh
# Keyboard layout module: EN/LT set via hyprland.lua's kb_layout "us,lt" +
# kb_options "grp:alt_shift_toggle" (native Shift+Alt chord). This script
# reacts to the resulting Hyprland IPC event:
#   watch  → waybar's persistent exec: streams JSON text + fires a
#            notify-send toast on every layout change, from any trigger
#            (Shift+Alt, or the waybar button below)
#   toggle → waybar on-click: switches layout, which fires the same IPC
#            event watch() reacts to (single source of truth for the toast)
#
# Ported from armojidots (SwayFX): swaymsg's `input type:keyboard
# xkb_switch_layout next` + `-t subscribe -m '["input"]'` become
# `hyprctl switchxkblayout <device> next` + the Hyprland socket2 event
# stream's `activelayout>>` events. Hyprland reports several "keyboard"
# devices on this machine too (a wireless receiver's consumer-control/
# system-control sub-devices, video-bus, power buttons) — pin to whichever
# one `hyprctl devices -j` marks `main: true`, same idea as sway's
# "first xkb_active_layout_name-bearing device" pin.

label() {
  case "$1" in
    *US*|*us*|*English*) echo "EN" ;;
    *Lithuania*|*lt*|*LT*) echo "LT" ;;
    *) echo "$1" ;;
  esac
}

main_keyboard() {
  hyprctl devices -j | python3 -c '
import json, sys
d = json.load(sys.stdin)
for kb in d.get("keyboards", []):
    if kb.get("main"):
        print(kb["name"]); break
'
}

case "$1" in
  toggle)
    dev=$(main_keyboard)
    [ -n "$dev" ] && hyprctl switchxkblayout "$dev" next >/dev/null
    ;;
  watch|"")
    dev=$(main_keyboard)
    [ -n "$dev" ] || exit 0

    hyprctl devices -j | python3 -c "
import json, sys
dev = '$dev'
d = json.load(sys.stdin)
for kb in d.get('keyboards', []):
    if kb.get('name') == dev:
        print(kb.get('active_keymap', '')); break
" | while IFS= read -r name; do
      l=$(label "$name")
      printf '{"text":"󰌌 %s","tooltip":"%s"}\n' "$l" "$name"
    done

    SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    python3 -u -c "
import socket, sys
target = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[2])
buf = ''
while True:
    chunk = s.recv(4096).decode(errors='replace')
    if not chunk:
        break
    buf += chunk
    while '\n' in buf:
        line, buf = buf.split('\n', 1)
        if not line.startswith('activelayout>>'):
            continue
        data = line[len('activelayout>>'):]
        parts = data.split(',', 1)
        if len(parts) != 2:
            continue
        kbname, layout = parts
        if kbname != target:
            continue
        print(layout, flush=True)
" "$dev" "$SOCK" | while IFS= read -r name; do
      [ -z "$name" ] && continue
      l=$(label "$name")
      printf '{"text":"󰌌 %s","tooltip":"%s"}\n' "$l" "$name"
      notify-send -t 1500 -h string:x-canonical-private-synchronous:lang "󰌌 Keyboard layout" "Switched to $name"
    done
    ;;
esac
