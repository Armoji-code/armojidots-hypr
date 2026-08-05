#!/bin/sh
# Installs Slot-Multicolor-Dark-Icons to ~/.local/share/icons (user-writable,
# no sudo). Not packaged anywhere (not AUR/pacman) — the archive is bundled
# here so the setup is reproducible straight from this repo.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/share/icons"
tar -xf "$HERE/Slot-Multicolor-Dark-Icons.tar.xz" -C "$HOME/.local/share/icons"
echo "Installed Slot-Multicolor-Dark-Icons to ~/.local/share/icons"
echo "Run: theme.sh apply <palette>  (or 'startup') to select it + recolor generic folders"
