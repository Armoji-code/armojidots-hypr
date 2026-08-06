#!/usr/bin/env python3
# Reimplements sway's activation-watch.sh for Hyprland via the socket2 event
# stream (Hyprland has no "focus_on_window_activation: except this app"
# per-app override either, same as sway) — jump straight to a window that
# requests attention (urgent hint), with a per-app exception list.
#
# Viber pings urgent on every incoming message; auto-teleporting to it each
# time would be constantly disruptive, so it's excluded here. It still gets
# the normal urgent-border flash. This also auto-closes Viber's separate
# "new message" toast window on open — Hyprland's windowrule engine has no
# declarative "close on match" action (unlike sway's for_window ... kill).
#
# sidebar-term/sidebar-claude are also excluded for the same reason, found
# live: sidebar-claude runs an actual `claude` CLI session, which raises an
# urgent hint on its own when it finishes responding — auto-focusing (and,
# per Hyprland's own focus-on-a-floating-window behavior, effectively
# un-hiding) a sidebar the user had deliberately hidden via its own toggle
# is exactly the same "constantly disruptive" problem Viber has, just
# triggered by Claude finishing a reply instead of an incoming message.
# See [[control-room-tv]]/[[armojidots-hypr-port]] memory notes.

import json
import os
import socket
import subprocess

EXCEPTED_URGENT_CLASSES = {"viber", "sidebar-term", "sidebar-claude"}


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    return f"{runtime}/hypr/{sig}/.socket2.sock"


def clients():
    out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except ValueError:
        return []


def dispatch(expr):
    subprocess.run(["hyprctl", "dispatch", expr], capture_output=True)


def focus(address):
    dispatch(f'hl.dsp.focus({{window="address:{address}"}})')


def close(address):
    dispatch(f'hl.dsp.window.close({{window="address:{address}"}})')


def handle(line):
    if ">>" not in line:
        return
    kind, data = line.split(">>", 1)

    if kind == "urgent":
        address = "0x" + data
        c = next((c for c in clients() if c.get("address") == address), None)
        if c and c.get("class", "").lower() not in EXCEPTED_URGENT_CLASSES:
            focus(address)

    elif kind == "openwindow":
        # openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE
        parts = data.split(",", 3)
        if len(parts) == 4:
            address, _ws, cls, title = parts
            if cls == "viber" and title == "ViberPC":
                close("0x" + address)


def main():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(socket_path())
    buf = ""
    while True:
        chunk = s.recv(4096).decode(errors="replace")
        if not chunk:
            break
        buf += chunk
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            handle(line.strip())


if __name__ == "__main__":
    main()
