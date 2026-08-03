#!/bin/sh
# Re-checks the blue-light AUTO schedule periodically so it actually
# crosses the 21:00/05:00 boundary while running, not just at toggle-time.
while :; do
  ~/.config/waybar/scripts/bluelight.sh recheck
  sleep 300
done
