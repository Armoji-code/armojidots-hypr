#!/bin/sh
# Waybar media modules driven by playerctl, targeting a SELECTED player so
# multiple simultaneous players (e.g. Spotify + a browser tab) don't fight
# over which one's shown — click the cover art to cycle between them.
#   cover      → writes a circle-cropped cover-art PNG for the image#cover
#                module (waybar's "image" module just polls a file path).
#                Loops so it self-heals if cava/playerctl aren't ready yet
#                at waybar startup (a real timing race, not hypothetical).
#   cava       → block-char visualizer, looped for the same reason
#   playpause  → JSON: play/pause icon reflecting player status
#   info       → JSON: "Title\n<small>Artist</small>" (pango, escaped)
#   cycle      → advance the selected player (bound to cover art on-click)
#   play-pause / prev / next → act on the selected player specifically

CACHE="$HOME/.cache/armojidots-waybar"
COVER="$CACHE/cover.png"
SEL="$CACHE/selected-player"
mkdir -p "$CACHE"

trap 'pkill -P $$ 2>/dev/null' EXIT INT TERM

emit_pp() {
  case "$1" in
    Playing) printf '{"text":"󰏤","alt":"playing"}\n' ;;
    Paused)  printf '{"text":"󰐊","alt":"paused"}\n' ;;
    *)       printf '{"text":"󰐊","alt":"stopped"}\n' ;;
  esac
}

players() { playerctl -l 2>/dev/null; }

current_player() {
  sel=$(cat "$SEL" 2>/dev/null)
  list=$(players)
  if [ -n "$sel" ] && printf '%s\n' "$list" | grep -qx "$sel"; then
    printf '%s' "$sel"
  else
    printf '%s\n' "$list" | head -n1
  fi
}

placeholder_cover() {
  css="$HOME/.config/waybar/colors.css"
  accent=$(grep -m1 '@define-color accent ' "$css" 2>/dev/null | awk '{print $3}' | tr -d ';')
  dim=$(grep -m1 '@define-color accent-dim ' "$css" 2>/dev/null | awk '{print $3}' | tr -d ';')
  [ -z "$accent" ] && accent="#537ff2"
  [ -z "$dim" ] && dim="#3957a4"
  python3 -c '
import sys
from PIL import Image, ImageDraw, ImageFont
out, dim_hex, accent_hex = sys.argv[1], sys.argv[2], sys.argv[3]
size = 22 * 3
im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.ellipse((0, 0, size, size), fill=dim_hex)
font = ImageFont.truetype("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf", int(size * 0.5))
glyph = ""
bbox = d.textbbox((0, 0), glyph, font=font)
gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text(((size - gw) / 2 - bbox[0], (size - gh) / 2 - bbox[1]), glyph, font=font, fill=accent_hex)
im.save(out)
' "$COVER" "$dim" "$accent" 2>/dev/null
}

case "$1" in
  cycle)
    list=$(players)
    n=$(printf '%s\n' "$list" | grep -c .)
    [ "$n" -le 1 ] && exit 0
    cur=$(current_player)
    printf '%s\n' "$list" | awk -v cur="$cur" '
      { a[NR]=$0; if ($0==cur) idx=NR }
      END { print (idx=="") ? a[1] : a[(idx % NR) + 1] }
    ' > "$SEL"
    ;;
  play-pause) playerctl -p "$(current_player)" play-pause 2>/dev/null ;;
  prev)       playerctl -p "$(current_player)" previous 2>/dev/null ;;
  next)       playerctl -p "$(current_player)" next 2>/dev/null ;;

  cover)
    last=""
    while :; do
      p=$(current_player)
      url=$(playerctl -p "$p" metadata mpris:artUrl 2>/dev/null)
      if [ "$url|$p" != "$last" ]; then
        last="$url|$p"
        if [ -z "$url" ]; then
          placeholder_cover
        else
          src="$url"
          case "$url" in
            file://*) src="${url#file://}" ;;
            http://*|https://*)
              src="$CACHE/art-src"
              curl -fsSL "$url" -o "$src" 2>/dev/null || src=""
              ;;
          esac
          [ -n "$src" ] && [ -f "$src" ] && python3 -c '
import sys
from PIL import Image, ImageDraw
src, out, size = sys.argv[1], sys.argv[2], 22 * 3
im = Image.open(src).convert("RGBA")
w, h = im.size; s = min(w, h)
im = im.crop(((w-s)//2, (h-s)//2, (w-s)//2+s, (h-s)//2+s)).resize((size, size), Image.LANCZOS)
mask = Image.new("L", (size, size), 0)
ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
im.putalpha(mask)
im.save(out)
' "$src" "$COVER" 2>/dev/null || placeholder_cover
        fi
      fi
      sleep 1
    done
    ;;
  cava)
    cfg=$(mktemp)
    printf '[general]\nframerate=30\nbars=10\nsensitivity=120\n[output]\nmethod=raw\nraw_target=/dev/stdout\ndata_format=ascii\nascii_max_range=7\n[input]\nmethod=pulse\nsource=auto\n' > "$cfg"
    while :; do
      cava -p "$cfg" | python3 -u -c '
import sys
bars = "▁▂▃▄▅▆▇█"
for line in sys.stdin:
    vals = [v for v in line.strip().strip(";").split(";") if v != ""]
    print("".join(bars[min(int(v), 7)] for v in vals), flush=True)
'
      sleep 2
    done
    ;;
  playpause)
    last=""
    while :; do
      p=$(current_player)
      s=$(playerctl -p "$p" status 2>/dev/null)
      if [ "$s|$p" != "$last" ]; then
        last="$s|$p"
        emit_pp "$s"
      fi
      sleep 1
    done
    ;;
  info)
    last=""
    while :; do
      p=$(current_player)
      line=$(playerctl -p "$p" metadata --format '{{title}}||{{artist}}' 2>/dev/null)
      if [ "$line|$p" != "$last" ]; then
        last="$line|$p"
        printf '%s\n' "$line" | python3 -c '
import sys, json, html
line = sys.stdin.readline().rstrip("\n")
title, _, artist = line.partition("||")
if not title:
    print(json.dumps({"text": ""})); sys.exit()
t, a = html.escape(title), html.escape(artist)
text = f"{t}\n<small>{a}</small>" if artist else t
tip = f"{title} — {artist}" if artist else title
print(json.dumps({"text": text, "tooltip": tip}))
'
      fi
      sleep 1
    done
    ;;
esac
