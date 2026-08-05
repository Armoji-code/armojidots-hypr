#!/bin/sh
# Low battery notifications at 20/10/5%, only while actually discharging —
# each threshold fires once per discharge cycle, then resets once you're
# back above it (plugged in / charging), so it doesn't spam every poll.

BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
[ -n "$BAT" ] || exit 0

n20=0; n10=0; n5=0

while :; do
  cap=$(cat "$BAT/capacity" 2>/dev/null)
  status=$(cat "$BAT/status" 2>/dev/null)

  if [ "$status" = "Discharging" ] && [ -n "$cap" ]; then
    if [ "$cap" -le 5 ] && [ "$n5" -eq 0 ]; then
      notify-send -u critical -t 0 "󰂎 Battery: ${cap}%" "YO BRO PLUG IT IN!!!"
      n5=1; n10=1; n20=1
    elif [ "$cap" -le 10 ] && [ "$n10" -eq 0 ]; then
      notify-send -u critical "󰂎 Battery: ${cap}%" "Yo bro you heard me the first time right?"
      n10=1; n20=1
    elif [ "$cap" -le 20 ] && [ "$n20" -eq 0 ]; then
      notify-send -u normal "󰂎 Battery: ${cap}%" "Yo bro heads up its pretty low"
      n20=1
    fi
  else
    n20=0; n10=0; n5=0
  fi

  sleep 30
done
