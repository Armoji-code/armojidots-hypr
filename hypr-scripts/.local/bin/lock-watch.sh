#!/bin/sh
# Caps Lock / Num Lock toggle notifications. Watches the kernel's LED sysfs
# brightness files via inotify — portable, no libinput/input-group
# permission dance needed. (Fn Lock has no such sysfs attribute on this
# ThinkPad's thinkpad_acpi driver, so it can't be watched the same way.)

CAPS=$(ls /sys/class/leds/*::capslock/brightness 2>/dev/null | head -n1)
NUM=$(ls /sys/class/leds/*::numlock/brightness 2>/dev/null | head -n1)

[ -n "$CAPS" ] || [ -n "$NUM" ] || exit 0

notify_state() {
  name="$1"; path="$2"
  state=$(cat "$path" 2>/dev/null)
  case "$state" in
    0) on="off" ;;
    *) on="on" ;;
  esac
  notify-send -t 1500 -h string:x-canonical-private-synchronous:lock "$name" "$name is now $on"
}

inotifywait -m -e modify $CAPS $NUM 2>/dev/null | while read -r path _ _; do
  case "$path" in
    "$CAPS") notify_state "Caps Lock" "$CAPS" ;;
    "$NUM")  notify_state "Num Lock" "$NUM" ;;
  esac
done
