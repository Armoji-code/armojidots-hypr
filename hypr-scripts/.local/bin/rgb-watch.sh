#!/bin/sh
# Re-checks the RGB night schedule periodically so it actually crosses the
# 21:00/05:00 boundary while running, not just at theme-pick time — same
# pattern as bluelight-watch.sh.
while :; do
  ~/.local/bin/theme.sh rgb-recheck
  sleep 300
done
