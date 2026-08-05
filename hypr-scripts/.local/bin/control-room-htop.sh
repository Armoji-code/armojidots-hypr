#!/bin/sh
# Live htop of debianlab (the home server) for the control-room TV.
# Auto-reconnects if SSH drops (server reboot, network blip, etc).
# -t forces a remote pty (ssh skips this by default when a command is
# given, leaving $TERM=dumb remotely — that's what actually broke htop,
# not a terminfo issue). TERM is also overridden to xterm-256color since
# debianlab doesn't have kitty's own xterm-kitty terminfo entry installed.
while :; do
  TERM=xterm-256color ssh -t -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 debianlab htop
  sleep 3
done
