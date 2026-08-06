#!/usr/bin/env python3
# ── armojidots-hypr · Hyprland IPC compat proxy for waybar ──────────────
#
# This build's Hyprland (0.56.1, Lua config) dropped the classic IPC dispatch
# protocol entirely: the command socket evaluates everything after "dispatch "
# as a raw Lua expression via hl.dispatch(...) — confirmed live, sending the
# textbook "dispatch workspace 12" errors with a Lua syntax error ("workspace
# 12" isn't valid Lua). Only hl.dsp.*(...) calls work now (see hyprland.lua's
# own binds for the pattern). Every other IPC verb (queries like "j/workspaces",
# "j/monitors", the event socket) is untouched — only "dispatch" changed.
#
# waybar 0.15.0 (stock, from the repos) has "dispatch workspace {id}" and
# "dispatch workspace name:{name}" hardcoded into its hyprland/workspaces
# module (confirmed via `strings` on the binary) — it talks directly to
# Hyprland's IPC unix sockets, not through hyprctl, so there's no CLI to
# patch and no waybar-side config option for this (the module has no
# on-click override). Clicking a workspace button in the bar silently no-ops
# because the compositor rejects the command it sends.
#
# Fix: sit a tiny transparent proxy in front of the real sockets. waybar is
# launched (see hyprland.lua) with HYPRLAND_INSTANCE_SIGNATURE overridden to
# a fixed value ("waybar-proxy") just for that one process, so it connects to
# OUR sockets under $XDG_RUNTIME_DIR/hypr/waybar-proxy/ instead of the real
# ones. Everything is relayed byte-for-byte to the real sockets except
# "dispatch workspace ..." commands, which get rewritten into the
# hl.dsp.focus({workspace=...}) form the compositor actually accepts. This
# only needs to handle what waybar itself sends — see the grep above; if a
# future waybar version starts sending other classic dispatchers through
# this same socket, add them to translate_dispatch() below.

import asyncio
import os
import re
import sys

PROXY_SIG = "waybar-proxy"
WORKSPACE_RE = re.compile(r"^workspace\s+(.+)$")


def real_socket_dir():
    runtime = os.environ["XDG_RUNTIME_DIR"]
    sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    return f"{runtime}/hypr/{sig}"


def proxy_socket_dir():
    return f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{PROXY_SIG}"


def translate_dispatch(rest: str) -> str:
    """rest is everything after "dispatch " in an incoming request. Already
    hl.dsp.*-style expressions (anything real Hyprland clients would send,
    including our own scripts if they ever go through this proxy) pass
    through untouched — only the classic "workspace <id|name:x>" form waybar
    sends needs rewriting."""
    m = WORKSPACE_RE.match(rest.strip())
    if not m:
        return rest
    arg = m.group(1).strip()
    if arg.startswith("name:"):
        name = arg[len("name:"):]
        try:
            ws = str(int(name))
        except ValueError:
            ws = f'"{name}"'
    else:
        ws = arg
    return f"hl.dsp.focus({{workspace={ws}}})"


async def relay(src: asyncio.StreamReader, dst: asyncio.StreamWriter):
    try:
        while True:
            chunk = await src.read(65536)
            if not chunk:
                break
            dst.write(chunk)
            await dst.drain()
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        dst.close()


async def handle_event_client(reader, writer, real_path):
    # .socket2.sock is push-only from Hyprland's side — open our own
    # connection to the real event socket and relay it straight through.
    try:
        real_reader, real_writer = await asyncio.open_unix_connection(real_path)
    except OSError:
        writer.close()
        return
    await relay(real_reader, writer)
    real_writer.close()


async def handle_command_client(reader, writer, real_path):
    request = await reader.read(65536)
    if not request:
        writer.close()
        return
    text = request.decode("utf-8", "replace")
    if text.startswith("dispatch "):
        rest = text[len("dispatch "):]
        text = "dispatch " + translate_dispatch(rest)
    try:
        real_reader, real_writer = await asyncio.open_unix_connection(real_path)
    except OSError as e:
        writer.write(f"error: proxy could not reach real socket: {e}".encode())
        await writer.drain()
        writer.close()
        return
    real_writer.write(text.encode("utf-8"))
    await real_writer.drain()
    real_writer.write_eof() if real_writer.can_write_eof() else None
    response = await real_reader.read(-1)
    writer.write(response)
    await writer.drain()
    writer.close()
    real_writer.close()


async def main():
    real_dir = real_socket_dir()
    pdir = proxy_socket_dir()
    os.makedirs(pdir, exist_ok=True)

    cmd_sock = f"{pdir}/.socket.sock"
    evt_sock = f"{pdir}/.socket2.sock"
    for p in (cmd_sock, evt_sock):
        try:
            os.unlink(p)
        except FileNotFoundError:
            pass

    real_cmd = f"{real_dir}/.socket.sock"
    real_evt = f"{real_dir}/.socket2.sock"

    cmd_server = await asyncio.start_unix_server(
        lambda r, w: handle_command_client(r, w, real_cmd), path=cmd_sock)
    evt_server = await asyncio.start_unix_server(
        lambda r, w: handle_event_client(r, w, real_evt), path=evt_sock)

    async with cmd_server, evt_server:
        await asyncio.gather(cmd_server.serve_forever(), evt_server.serve_forever())


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
