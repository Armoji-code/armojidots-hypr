#!/bin/sh
# ── armojidots-hypr theme engine ────────────────────
# Ported from armojidots (SwayFX) — identical color math (wallpaper
# extraction + HSV-derived palette family), now at full parity: waybar,
# kitty, GTK, swaync, armoji-dock/osd/spotlight, walker, hyprland window
# borders, hyprlock, and icon folder recoloring.
#   theme.sh apply <palette>   palettes: wallpaper (extracted from current
#                              wallpaper), ruby, orange, dandelion, emerald,
#                              cobalt, bubblegum, purpur, b&w
#   theme.sh pick              walker picker (used by /set color)
#   theme.sh startup           re-apply saved palette (for autostart)
#   theme.sh tone <light|heavy|loud>
#   theme.sh tone-pick         walker picker (used by /set tone)

STATE_DIR="$HOME/.local/state/armojidots-hypr"
WALL="$HOME/dotfiles/wallpapers/current"
mkdir -p "$STATE_DIR"

PALETTES="wallpaper
ruby
orange
dandelion
emerald
cobalt
bubblegum
purpur
b&w"

extract_from_wallpaper() {
  python3 - "$WALL" <<'PYEOF'
import sys, colorsys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB").resize((64, 64))
best, best_score = None, 0
for count, (r, g, b) in img.getcolors(64 * 64):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    score = count * (s ** 1.5) * v
    if v > 0.25 and score > best_score:
        best, best_score = (r, g, b), score
if best is None:
    best = (120, 140, 200)

h, s, v = colorsys.rgb_to_hsv(*[c / 255 for c in best])
s = min(1.0, s * 1.2 + 0.1)  # derive_family() applies the 40% reduction
v = min(1.0, max(v, 0.75))
acc = colorsys.hsv_to_rgb(h, s, v)
dim = colorsys.hsv_to_rgb(h, s, v * 0.68)
print("#%02x%02x%02x" % tuple(int(c * 255) for c in acc),
      "#%02x%02x%02x" % tuple(int(c * 255) for c in dim))
PYEOF
}

derive_family() {
  python3 - "$1" "$2" <<'PYEOF'
import sys, colorsys

def hx(rgb): return "#%02x%02x%02x" % tuple(int(c * 255) for c in rgb)
r, g, b = (int(sys.argv[1][i:i+2], 16) / 255 for i in (1, 3, 5))
h, s, v = colorsys.rgb_to_hsv(r, g, b)

tone = sys.argv[2] if len(sys.argv) > 2 else "heavy"
T = {
    "light": dict(bg_s=0.35, bg_v=0.11, bg2_s=0.28, bg2_v=0.22, fg_s=0.06, mut_s=0.18, ansi=0.75),
    "heavy": dict(bg_s=0.80, bg_v=0.13, bg2_s=0.65, bg2_v=0.25, fg_s=0.18, mut_s=0.40, ansi=1.00),
    "loud":  dict(bg_s=1.00, bg_v=0.17, bg2_s=0.90, bg2_v=0.30, fg_s=0.30, mut_s=0.55, ansi=1.15),
}.get(tone, None) or {
    "bg_s": 0.80, "bg_v": 0.13, "bg2_s": 0.65, "bg2_v": 0.25,
    "fg_s": 0.18, "mut_s": 0.40, "ansi": 1.00}

s_acc = s * 0.6  # confirmed-good: 40% less saturated than the raw seed
acc   = colorsys.hsv_to_rgb(h, s_acc, v)
dim   = colorsys.hsv_to_rgb(h, s_acc, v * 0.68)
bg    = colorsys.hsv_to_rgb(h, min(1.0, s * T["bg_s"]), T["bg_v"])
bg2   = colorsys.hsv_to_rgb(h, min(1.0, s * T["bg2_s"]), T["bg2_v"])
fg    = colorsys.hsv_to_rgb(h, min(1.0, s * T["fg_s"]), 0.94)
muted = colorsys.hsv_to_rgb(h, min(1.0, s * T["mut_s"]), 0.62)

spec = [(-0.09, 1.00, 0.80), (0.00, 1.00, 0.88), (0.05, 0.90, 0.85),
        (-0.04, 0.75, 0.90), (0.09, 0.95, 0.82), (-0.13, 0.90, 0.86)]
regs, brights = [], []
for dh, ds, dv in spec:
    # s_acc (already 40% lighter than raw seed saturation) instead of raw s —
    # dark theme means the whole terminal palette should read light, not
    # just the accent
    regs.append(colorsys.hsv_to_rgb((h + dh) % 1.0, min(1.0, s_acc * ds * T["ansi"]), dv))
    brights.append(colorsys.hsv_to_rgb((h + dh) % 1.0, min(1.0, s_acc * ds * T["ansi"] * 0.9), min(1.0, dv + 0.12)))
out = [acc, dim, bg, bg2, fg, muted] + regs + brights
print(" ".join(hx(c) for c in out))
PYEOF
}

resolve() {
  case "$1" in
    ruby)      seed="#e35d6a" ;;
    orange)    seed="#f28744" ;;
    dandelion) seed="#f2c94c" ;;
    emerald)   seed="#3ecf82" ;;
    cobalt)    seed="#5480f2" ;;
    bubblegum) seed="#f06ec3" ;;
    purpur)    seed="#a06ef0" ;;
    bw|"b&w")  seed="#e8eaef" ;;
    wallpaper) seed=$(extract_from_wallpaper | cut -d' ' -f1) ;;
    *) return 1 ;;
  esac
  TONE=$(cat "$STATE_DIR/tone" 2>/dev/null || echo heavy)
  set -- $(derive_family "$seed" "$TONE")
  ACC="$1" DIM="$2" BG="$3" BG2="$4" FG="$5" MUTED="$6"
  R1="$7" R2="$8" R3="$9"
  shift 9
  R4="$1" R5="$2" R6="$3" B1="$4" B2="$5" B3="$6" B4="$7" B5="$8" B6="$9"
}

# same 21:00-05:00 window as waybar/scripts/bluelight.sh's AUTO mode — kept
# as a separate check here rather than shared, matches this codebase's
# existing pattern of small self-contained scripts over cross-file helpers
is_rgb_night() {
  h=$(date +%H)
  [ "$h" -ge 21 ] || [ "$h" -lt 5 ]
}

# Pushes case RGB to match either the current theme (day) or off (21:00-
# 05:00, see is_rgb_night). Self-contained — reads the saved palette/tone
# itself, so it can be called standalone (rgb-watch.sh's periodic recheck)
# as well as from apply() right after a theme pick, without redoing the
# heavier waybar/GTK/QT/kitty file regeneration for a plain day/night flip.
#
# Devices: 2x "ENE DRAM" (RAM, one "DRAM" zone each). "...Radeon..." (GPU:
# Right fan/Left fan/Center fan/Side). "...AORUS ELITE..." (B850
# motherboard: ARGB_V2_1/2/3 headers + Chipset Accent + LED_C). Confirmed
# live: a whole-device `--device N --color` only reliably reaches one zone
# (the GPU logo/Side), the rest silently no-op — every zone needs its own
# explicit --zone.
#
# The keyboard (LEOBOG Hi75C Pro) is deliberately NOT targeted here, and
# its "Sinowealth Keyboard" detector is disabled in OpenRGB.json entirely
# — confirmed live that OpenRGB holding a HID handle to it while wired
# causes intermittent dropped keystrokes (fine over its 2.4GHz dongle,
# which OpenRGB doesn't see/touch at all). Not a write-frequency thing —
# stopping openrgb.service outright fixed it, just re-detecting it did not.
#
# Target by NAME SUBSTRING, not numeric index — index order is NOT stable
# (confirmed live: OpenRGB detecting the keyboard once shifted the
# motherboard from index 3 to 4, so a hardcoded --device 3 silently
# recolored the keyboard instead of the fan headers). openrgb's --device
# flag substring-matches every device whose name contains the given
# string, not just the first (confirmed live: one --device "DRAM" selector
# lit both RAM sticks), so this stays correct regardless of what other RGB
# devices come and go.
# Goes through the persistent `openrgb --server` (openrgb.service) via
# --client, not direct hardware access — direct mode re-enumerates every
# device from scratch on each call, the server keeps them open.
apply_rgb() {
  command -v openrgb >/dev/null 2>&1 || return 0

  if is_rgb_night; then
    c=000000
  else
    resolve "$(cat "$STATE_DIR/theme" 2>/dev/null || echo wallpaper)" || return 0
    # $ACC already carries derive_family()'s 40% saturation reduction (tuned
    # for on-screen UI) — confirmed too washed-out on actual LEDs, so re-
    # saturate just for RGB output without touching the UI-facing colors.
    # This hardware's blue channel also reads visibly stronger than red/green
    # at the same value (confirmed live: emerald green came out looking
    # blueish-mint) — dial blue back specifically for LEDs to compensate.
    # A flat multiply is wrong though: confirmed live it crushes genuinely
    # blue-dominant palettes (cobalt) into grey. Use a gamma curve on blue
    # instead — it cuts moderate blue (the false-tint case) hard while
    # leaving strong/near-pure blue (cobalt) mostly intact, since x**1.8
    # shrinks small-to-mid values proportionally more than values near 1.0.
    c=$(python3 - "$ACC" <<'PYEOF'
import sys, colorsys
r, g, b = (int(sys.argv[1][i:i+2], 16) / 255 for i in (1, 3, 5))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
s = min(1.0, s * 2.0)
r, g, b = colorsys.hsv_to_rgb(h, s, v)
b = b ** 1.8
r, g, b = (min(1.0, x) for x in (r, g, b))
print("%02x%02x%02x" % tuple(int(c * 255) for c in (r, g, b)))
PYEOF
)
  fi

  # theme.sh's `startup` invocation races openrgb.service at boot: the SDK
  # server registers devices progressively as it enumerates them, and the
  # motherboard's HID controller (the fan-header ARGB zones) shows up
  # noticeably later than the RAM/GPU's fast I2C devices. Confirmed live:
  # on a fresh boot GPU+RAM took the new color but the fans silently
  # didn't, because the motherboard hadn't been enumerated by the server
  # yet at the moment this ran. Wait (bounded) for it to actually be
  # present by name before sending any color commands — a no-op almost
  # instantly on every non-boot invocation (theme picker etc.), the
  # server's already warm by then.
  tries=0
  while [ "$tries" -lt 15 ]; do
    openrgb --client 127.0.0.1:6742 --list-devices 2>/dev/null | grep -q "AORUS ELITE" && break
    tries=$((tries + 1))
    sleep 1
  done

  openrgb --client 127.0.0.1:6742 \
    --device "DRAM" --zone 0 --mode static --color "$c" \
    --device "Radeon" --zone 0 --mode static --color "$c" \
    --device "Radeon" --zone 1 --mode static --color "$c" \
    --device "Radeon" --zone 2 --mode static --color "$c" \
    --device "Radeon" --zone 3 --mode static --color "$c" \
    --device "AORUS ELITE" --zone 0 --mode static --color "$c" \
    --device "AORUS ELITE" --zone 1 --mode static --color "$c" \
    --device "AORUS ELITE" --zone 2 --mode static --color "$c" \
    --device "AORUS ELITE" --zone 3 --mode static --color "$c" \
    --device "AORUS ELITE" --zone 4 --mode static --color "$c" \
    >/dev/null 2>&1
}

apply() {
  name="$1"
  resolve "$name" || { notify-send "theme" "unknown palette: $name"; exit 1; }

  bg_r=$((0x${BG#\#} >> 16 & 255)); bg_g=$((0x${BG#\#} >> 8 & 255)); bg_b=$((0x${BG#\#} & 255))

  # ── waybar ──
  mkdir -p "$HOME/.config/waybar"
  cat > "$HOME/.config/waybar/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color accent $ACC;
@define-color accent-dim $DIM;
@define-color bg rgba($bg_r, $bg_g, $bg_b, 0.58);
@define-color fg $FG;
@define-color muted $MUTED;
EOF

  # ── kitty ──
  mkdir -p "$HOME/.config/kitty"
  cat > "$HOME/.config/kitty/theme-colors.conf" <<EOF
# generated by theme.sh — palette: $name
foreground $FG
background $BG
selection_foreground $BG
selection_background $ACC
cursor $ACC
url_color $ACC
color0  $BG2
color1  $R1
color2  $R2
color3  $R3
color4  $R4
color5  $R5
color6  $R6
color7  $FG
color8  $MUTED
color9  $B1
color10 $B2
color11 $B3
color12 $B4
color13 $B5
color14 $B6
color15 #ffffff
EOF

  # ── swaync ──
  mkdir -p "$HOME/.config/swaync"
  cat > "$HOME/.config/swaync/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color cc-bg rgba($bg_r, $bg_g, $bg_b, 0.72);
@define-color notif-bg rgba($bg_r, $bg_g, $bg_b, 0.78);
@define-color accent $ACC;
@define-color fg $FG;
@define-color muted $MUTED;
EOF

  # ── GTK apps (adw-gtk3 + libadwaita accent overrides) ──
  for gtkdir in gtk-3.0 gtk-4.0; do
    mkdir -p "$HOME/.config/$gtkdir"
    cat > "$HOME/.config/$gtkdir/gtk.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color accent_bg_color $ACC;
@define-color accent_fg_color #ffffff;
@define-color accent_color $ACC;
@define-color theme_selected_bg_color $ACC;
@define-color theme_selected_fg_color #ffffff;
@define-color success_bg_color $ACC;
@define-color success_color $ACC;
@define-color success_fg_color #ffffff;
@define-color window_bg_color $BG2;
@define-color window_fg_color $FG;
@define-color view_bg_color $BG;
@define-color view_fg_color $FG;
@define-color headerbar_bg_color $BG;
@define-color headerbar_fg_color $FG;
@define-color sidebar_bg_color $BG;
@define-color sidebar_fg_color $FG;
@define-color secondary_sidebar_bg_color $BG;
@define-color secondary_sidebar_fg_color $FG;
@define-color card_bg_color $BG2;
@define-color card_fg_color $FG;
@define-color dialog_bg_color $BG2;
@define-color dialog_fg_color $FG;
@define-color popover_bg_color $BG2;
@define-color popover_fg_color $FG;
EOF
  done

  # ── QT apps (qt5ct/qt6ct) ──
  # QT_QPA_PLATFORMTHEME points QT apps at qt5ct/qt6ct instead of a bare
  # native style with no theming at all; qt6ct is confirmed installed, qt5ct
  # isn't yet (write its config too — harmless, just unused until installed).
  # qt5ct/qt6ct's color scheme format is QPalette::ColorRole order — a fixed
  # 21-slot sequence (WindowText, Button, Light, Midlight, Dark, Mid, Text,
  # BrightText, ButtonText, Base, Window, Shadow, Highlight, HighlightedText,
  # Link, LinkVisited, AlternateBase, NoRole, ToolTipBase, ToolTipText,
  # PlaceholderText), each #AARRGGBB — confirmed against qt6ct's own shipped
  # presets (/usr/share/qt6ct/colors/*.conf), not guessed from memory.
  qt_scheme() {
    # backgrounds (Base/Window/AlternateBase/ToolTipBase all draw from
    # bg/bg2) get real alpha for the same glass look GTK/waybar/etc. get —
    # text/accent stay fully opaque so nothing reads mushy
    fg="ff${FG#\#}"; bg="e6${BG#\#}"; bg2="e6${BG2#\#}"
    acc="ff${ACC#\#}"; dim="ff${DIM#\#}"; muted="ff${MUTED#\#}"
    active="#$fg, #$bg2, #$fg, #$bg2, #$bg, #$bg2, #$fg, #$fg, #$fg, #$bg, #$bg2, #ff000000, #$acc, #ffffffff, #$acc, #$dim, #$bg2, #$bg2, #$bg2, #$fg, #$muted"
    disabled="#$muted, #$bg2, #$fg, #$bg2, #$bg, #$bg2, #$muted, #$fg, #$muted, #$bg, #$bg2, #ff000000, #$acc, #$muted, #$acc, #$dim, #$bg2, #$bg2, #$bg2, #$muted, #$muted"
    cat <<EOF
[ColorScheme]
active_colors=$active
disabled_colors=$disabled
inactive_colors=$active
EOF
  }
  for qtdir in qt5ct qt6ct; do
    mkdir -p "$HOME/.config/$qtdir/colors"
    qt_scheme > "$HOME/.config/$qtdir/colors/armoji.conf"
    cat > "$HOME/.config/$qtdir/$qtdir.conf" <<EOF
[Appearance]
color_scheme_path=$HOME/.config/$qtdir/colors/armoji.conf
custom_palette=true
icon_theme=Slot-Multicolor-Dark-Icons
standard_dialogs=default
style=Fusion
EOF
  done

  # ── armoji-dock ──
  mkdir -p "$HOME/.config/armoji-dock"
  cat > "$HOME/.config/armoji-dock/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color accent $ACC;
@define-color bg rgba($bg_r, $bg_g, $bg_b, 0.58);
@define-color fg $FG;
@define-color muted $MUTED;
EOF

  # ── armoji-osd ──
  mkdir -p "$HOME/.config/armoji-osd"
  cat > "$HOME/.config/armoji-osd/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color accent $ACC;
@define-color bg rgba($bg_r, $bg_g, $bg_b, 0.58);
@define-color fg $FG;
@define-color muted $MUTED;
EOF

  # ── armoji-spotlight ──
  mkdir -p "$HOME/.config/armoji-spotlight"
  cat > "$HOME/.config/armoji-spotlight/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color accent $ACC;
@define-color bg rgba($bg_r, $bg_g, $bg_b, 0.58);
@define-color fg $FG;
@define-color muted $MUTED;
EOF

  # ── armoji-hdr ──
  mkdir -p "$HOME/.config/armoji-hdr"
  cat > "$HOME/.config/armoji-hdr/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color accent $ACC;
@define-color bg rgba($bg_r, $bg_g, $bg_b, 0.58);
@define-color fg $FG;
@define-color muted $MUTED;
EOF

  # ── walker ──
  mkdir -p "$HOME/.config/walker/themes/armoji"
  cat > "$HOME/.config/walker/themes/armoji/colors.css" <<EOF
/* generated by theme.sh — palette: $name */
@define-color window_bg_color rgba($bg_r, $bg_g, $bg_b, 0.58);
@define-color accent_bg_color $ACC;
@define-color theme_fg_color $FG;
@define-color error_bg_color #C34043;
@define-color error_fg_color #DCD7BA;
EOF

  # ── hyprland window borders (mirrors sway's colors.conf) ──
  # borders are already paper-thin (1px) — full-opacity accent still read as
  # a loud, saturated line at that weight, so both get real alpha too: the
  # hint should come from the border being *there*, not from how vivid it is
  mkdir -p "$HOME/.config/hypr"
  cat > "$HOME/.config/hypr/colors.lua" <<EOF
-- generated by theme.sh — palette: $name
-- window border colors (mirrors sway colors.conf)
hl.config({
    general = {
        col = {
            active_border   = "rgba(${ACC#\#}80)",
            inactive_border = "rgba(${BG2#\#}4d)",
        },
    },
})
EOF

  # ── hyprlock (whole config is generated; edit here, not there) ──
  cat > "$HOME/.config/hypr/hyprlock.conf" <<EOF
# generated by theme.sh — palette: $name
general {
    ignore_empty_input = true
    hide_cursor = false
}

background {
    monitor =
    path = ~/dotfiles/wallpapers/current
    blur_passes = 2
    blur_size = 8
    noise = 0.02
    contrast = 0.9
    brightness = 0.65
}

label {
    monitor =
    text = cmd[update:1000] echo "\$(date +'%H:%M')"
    color = rgba(${FG#\#}ff)
    font_size = 64
    font_family = JetBrainsMono Nerd Font
    position = 0, 220
    halign = center
    valign = center
}

label {
    monitor =
    text = cmd[update:60000] echo "\$(date +'%A, %B %e')"
    color = rgba(${FG#\#}ff)
    font_size = 20
    font_family = JetBrainsMono Nerd Font
    position = 0, 160
    halign = center
    valign = center
}

input-field {
    monitor =
    size = 250, 60
    outline_thickness = 3
    dots_size = 0.25
    dots_spacing = 0.3
    dots_center = true
    outer_color = rgba(${ACC#\#}ff)
    inner_color = rgba(${BG#\#}cc)
    font_color = rgba(${FG#\#}ff)
    fade_on_empty = false
    placeholder_text = <i>Password...</i>
    hide_input = false
    check_color = rgba(${ACC#\#}ff)
    fail_color = rgba(e06c75ff)
    position = 0, -60
    halign = center
    valign = center
}
EOF

  # ── Slot-Multicolor-Dark-Icons: selective folder recolor ──
  # Only the "default" XDG folders (Documents, Downloads, Music, Pictures,
  # Videos, Desktop, Public, Templates, home/root, and the bare "folder"
  # icon) get tinted to the accent — every folder with its own branded icon
  # (git, docker, steam, blender, …) keeps the pack's original artwork, so
  # those stay visually distinct on purpose.
  SLOT_DIR="$HOME/.local/share/icons/Slot-Multicolor-Dark-Icons"
  slot_color=$(python3 - "$ACC" <<'PYEOF'
import sys, colorsys
r, g, b = (int(sys.argv[1][i:i+2], 16) / 255 for i in (1, 3, 5))
h, s, v = colorsys.rgb_to_hsv(r, g, b)
deg = h * 360
if s < 0.10:
    print("grey")
elif deg < 15 or deg >= 345:
    print("red")
elif deg < 40:
    print("orange")
elif deg < 65:
    print("yellow")
elif deg < 170:
    print("green")
elif deg < 220:
    print("cyan")
elif deg < 260:
    print("blue")
elif deg < 300:
    print("violet")
else:
    print("magenta")
PYEOF
)

  # ── GTK accent color (the actual fix for "gtk recoloring doesn't work") ──
  # Modern adw-gtk3 and libadwaita (GTK4) don't read the old @define-color
  # accent_color hook from gtk.css at all — they read this org.gnome.desktop
  # .interface accent-color enum instead, which was stuck on the GNOME
  # default ('blue') regardless of palette. gtk.css's overrides are left in
  # place too (still used for surface colors like window/view/card bg — just
  # not accent), same hue buckets as the icon-pack mapping above, renamed to
  # GNOME's fixed 9-color accent enum.
  gnome_accent=$(case "$slot_color" in
    grey)    echo slate ;;
    cyan)    echo teal ;;
    violet)  echo purple ;;
    magenta) echo pink ;;
    *)       echo "$slot_color" ;;   # red/orange/yellow/green/blue map 1:1
  esac)
  gsettings set org.gnome.desktop.interface accent-color "$gnome_accent" 2>/dev/null

  if [ -d "$SLOT_DIR" ]; then
    generic_folders="folder folder-open"
    for size_dir in "$SLOT_DIR"/places/*/; do
      target="${size_dir}folder-$slot_color.svg"
      [ -f "$target" ] || continue
      for fname in $generic_folders; do
        dest="${size_dir}${fname}.svg"
        { [ -f "$dest" ] || [ -L "$dest" ]; } || continue
        ln -sf "folder-$slot_color.svg" "$dest"
      done
    done
    gtk-update-icon-cache -qf "$SLOT_DIR" >/dev/null 2>&1
  fi

  printf '%s\n' "$name" > "$STATE_DIR/theme"

  # ── case RGB (OpenRGB) ──
  apply_rgb

  # ── reload the world ──
  # hyprland.lua's colors.lua include picks up the new border colors on
  # reload; harmless no-op for everything else already applied via files
  hyprctl reload >/dev/null 2>&1
  # SIGUSR2 doesn't reliably reload waybar's CSS on this machine — full
  # restart instead. media.sh's cover/cava/playpause/info modules are all
  # self-healing "while :; do …; sleep N; done" loops (by design, so a dead
  # cava/playerctl child gets relaunched instead of staying dead) — but that
  # also means a plain `pkill -x waybar` orphans every one of them instead of
  # taking them down, so each restart leaked more copies (confirmed: 100+
  # accumulated leaked media.sh loops found and cleared while wiring this
  # up). Kill all four self-healing loop kinds before relaunching.
  pkill -x waybar 2>/dev/null
  pkill -9 -f '[m]edia.sh cover' 2>/dev/null
  pkill -9 -f '[m]edia.sh cava' 2>/dev/null
  pkill -9 -f '[m]edia.sh playpause' 2>/dev/null
  pkill -9 -f '[m]edia.sh info' 2>/dev/null
  pkill -9 -f '^cava ' 2>/dev/null
  sleep 0.3
  setsid -f waybar >/dev/null 2>&1
  swaync-client --reload-css >/dev/null 2>&1
  # armoji-dock/osd/spotlight (resident daemons) re-read their colors.css on
  # SIGUSR1 — no restart needed
  pkill -USR1 -f 'armoji-dock --daemon' >/dev/null 2>&1
  pkill -USR1 -f 'armoji-osd' >/dev/null 2>&1
  pkill -USR1 -f 'armoji-spotlight --daemon' >/dev/null 2>&1
  # walker caches its theme CSS at startup — restart it (resident systemd
  # service, comes back instantly)
  systemctl --user restart walker.service >/dev/null 2>&1
  # already-open kitty terminals: push new colors via OSC escapes (pywal trick)
  _seq=$(
    printf '\033]10;#%s\033\\' "${FG#\#}"
    printf '\033]11;#%s\033\\' "${BG#\#}"
    printf '\033]12;#%s\033\\' "${ACC#\#}"
    _i=0
    for _c in "$BG2" "$R1" "$R2" "$R3" "$R4" "$R5" "$R6" "$FG" \
              "$MUTED" "$B1" "$B2" "$B3" "$B4" "$B5" "$B6" ffffff; do
      printf '\033]4;%d;#%s\033\\' "$_i" "${_c#\#}"
      _i=$((_i + 1))
    done
  )
  for _pts in /dev/pts/[0-9]*; do
    [ -w "$_pts" ] && printf '%s' "$_seq" > "$_pts" 2>/dev/null
  done
  # theme flip-flop forces running GTK apps to re-read gtk.css; the sleep keeps
  # GTK from coalescing the two sets into a no-op when the end value is unchanged
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3' 2>/dev/null
  sleep 0.3
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null
  # toggle through a dummy value first so apps that only react to a change
  # event actually refresh, then land on Slot-Multicolor-Dark-Icons
  gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' 2>/dev/null
  gsettings set org.gnome.desktop.interface icon-theme 'Slot-Multicolor-Dark-Icons' 2>/dev/null
  notify-send -t 3000 "󰏘 Theme" "palette: $name ($ACC)"
}

case "$1" in
  apply)   apply "$2" ;;
  startup) apply "$(cat "$STATE_DIR/theme" 2>/dev/null || echo wallpaper)" ;;
  pick)
    choice=$(printf '%s\n' "$PALETTES" | walker --dmenu -p "color ❯")
    [ -n "$choice" ] && apply "$choice"
    ;;
  tone)
    case "$2" in light|heavy|loud) ;; *) echo "tone: light|heavy|loud" >&2; exit 1 ;; esac
    printf '%s\n' "$2" > "$STATE_DIR/tone"
    apply "$(cat "$STATE_DIR/theme" 2>/dev/null || echo wallpaper)"
    ;;
  tone-pick)
    choice=$(printf 'light\nheavy\nloud\n' | walker --dmenu -p "tone ❯")
    [ -n "$choice" ] && "$0" tone "$choice"
    ;;
  rgb-recheck)
    # called periodically by rgb-watch.sh to cross the 21:00/05:00 boundary
    # while running — cheap, only touches OpenRGB, not the rest of the theme
    apply_rgb
    ;;
  *) echo "usage: theme.sh apply <palette> | pick | tone <light|heavy|loud> | tone-pick | startup | rgb-recheck" >&2; exit 1 ;;
esac
