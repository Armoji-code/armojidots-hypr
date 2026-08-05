#!/bin/sh
# Set the wallpaper and persist it via the `current` symlink that hyprpaper
# and theme.sh both read. Wallpapers live in ~/Pictures/Wallpapers.
#   wallpaper-pick.sh "<path>"   set that image directly
#                                (used by spotlight's /set wallpaper thumbnails)
#   wallpaper-pick.sh            no arg → dmenu picker (fallback)
WALLDIR="$HOME/Pictures/Wallpapers"
LINK="$HOME/dotfiles/wallpapers/current"

if [ -n "$1" ]; then
  pick="$1"
else
  name=$(find "$WALLDIR" -maxdepth 1 -type f \
           \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
           -printf '%f\n' | sort | walker --dmenu -p "wallpaper ❯")
  [ -z "$name" ] && exit 0
  pick="$WALLDIR/$name"
fi
[ -f "$pick" ] || { notify-send "wallpaper" "not found: $pick"; exit 1; }

ln -sf "$pick" "$LINK"
# hyprpaper 0.8.4's IPC is much simpler than the preload/reload/unload API
# newer versions have — the only request it accepts is `wallpaper
# <mon>,<path>` (confirmed live: preload/reload/unload/listloaded all come
# back "invalid hyprpaper request"). It also resolves the path once at
# request time rather than watching the symlink, so it has to be re-issued
# per monitor on every change, not just relinked.
for mon in $(hyprctl monitors -j | python3 -c '
import json, sys
for m in json.load(sys.stdin):
    print(m["name"])
'); do
  hyprctl hyprpaper wallpaper "$mon,$LINK" >/dev/null
done

# the wallpaper-driven palette follows the new wallpaper
if [ "$(cat "$HOME/.local/state/armojidots-hypr/theme" 2>/dev/null)" = "wallpaper" ]; then
  "$HOME/.local/bin/theme.sh" apply wallpaper
fi
