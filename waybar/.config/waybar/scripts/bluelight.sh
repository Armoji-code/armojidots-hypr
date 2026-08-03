#!/bin/sh
# Waybar blue-light filter pill: ON (always warm) -> OFF (never) -> AUTO
# (warm 21:00-05:00) -> ... via hyprsunset (Hyprland's own tool, controlled
# live over hyprctl — no killing/relaunching a process per state like
# wlsunset needed). hyprsunset itself must already be running (autostart);
# this script only ever sends it commands. State persists across reboots.

STATE_FILE="$HOME/.local/state/armojidots-hypr/bluelight"
mkdir -p "$(dirname "$STATE_FILE")"
cur=$(cat "$STATE_FILE" 2>/dev/null || echo auto)

is_night() {
  h=$(date +%H)
  [ "$h" -ge 21 ] || [ "$h" -lt 5 ]
}

apply() {
  case "$1" in
    on)   hyprctl hyprsunset temperature 3000 >/dev/null ;;
    off)  hyprctl hyprsunset identity >/dev/null ;;
    auto) if is_night; then hyprctl hyprsunset temperature 3000 >/dev/null; else hyprctl hyprsunset identity >/dev/null; fi ;;
  esac
}

case "$1" in
  status)
    case "$cur" in
      on)   icon="󰛨"; tip="blue light: ON (always)" ;;
      off)  icon="󰃟"; tip="blue light: OFF" ;;
      *)    icon="󰥔"; tip="blue light: AUTO (21:00-05:00)" ;;
    esac
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$icon" "$tip" "$cur"
    ;;
  toggle)
    case "$cur" in
      on)   next=off ;;
      off)  next=auto ;;
      *)    next=on ;;
    esac
    printf '%s\n' "$next" > "$STATE_FILE"
    apply "$next"
    pkill -SIGRTMIN+9 waybar 2>/dev/null
    ;;
  startup)
    apply "$cur"
    ;;
  recheck)
    # called periodically by bluelight-watch.sh; only matters in auto mode,
    # a plain re-apply is a harmless no-op otherwise
    [ "$cur" = "auto" ] && apply auto
    ;;
esac
