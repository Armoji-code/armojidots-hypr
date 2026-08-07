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
#

label() {
  case "$1" in
    *US*|*us*|*English*) echo "EN" ;;
    *Lithuania*|*lt*|*LT*) echo "LT" ;;
    *) echo "$1" ;;
  esac
}

# Get main keyboard device with retry mechanism for startup race conditions.
# A single hyprctl call per attempt is reused for both lookups below to
# avoid doubling IPC traffic under contention. Each python parse is
# wrapped in try/except so a malformed/empty response degrades to "no
# device found this attempt" instead of a crash-noise traceback.
main_keyboard() {
  tries=0
  while [ "$tries" -lt 10 ]; do
    devices_json=$(hyprctl devices -j)
    if [ -n "$devices_json" ]; then
      dev=$(echo "$devices_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for kb in d.get("keyboards", []):
    if kb.get("main"):
        print(kb["name"]); break
')
      if [ -z "$dev" ]; then
        dev=$(echo "$devices_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for kb in d.get("keyboards", []):
    if "keyboard" in kb.get("name", "").lower():
        print(kb["name"]); break
')
      fi
      [ -n "$dev" ] && break
    fi
    tries=$((tries + 1))
    sleep 0.3
  done

  echo "$dev"
}

case "$1" in
  toggle)
    dev=$(main_keyboard)
    [ -n "$dev" ] && hyprctl switchxkblayout "$dev" next >/dev/null
    ;;
  watch|"")
    # This is the persistent exec loop that handles live notifications
    
    dev=$(main_keyboard)
    
    # If we found a device, show current layout; otherwise use fallback
    if [ -n "$dev" ]; then
      # Initial display
      current_layout=$(hyprctl devices -j | python3 -c "
import json, sys
dev = '$dev'
d = json.load(sys.stdin)
for kb in d.get('keyboards', []):
    if kb.get('name') == dev:
        print(kb.get('active_keymap', '')); break
")
      l=$(label "$current_layout")
      printf '{"text":"󰌌 %s","tooltip":"%s"}\n' "$l" "$current_layout"
    else
      # Show fallback if no device found yet (but don't exit)
      printf '{"text":"󰌌 EN","tooltip":"English"}\n'
    fi

    # Monitor for layout changes
    SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    # Same startup-race concern as main_keyboard(): don't give up on one check.
    sock_tries=0
    while [ ! -S "$SOCK" ] && [ "$sock_tries" -lt 10 ]; do
      sock_tries=$((sock_tries + 1))
      sleep 0.3
    done

    # If socket exists, monitor for real-time updates
    if [ -S "$SOCK" ]; then
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
    fi
    
    # If we can't reach the socket (which happens during startup/race conditions) 
    # we silently continue instead of freezing
    ;;
esac