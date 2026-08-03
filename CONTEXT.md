# armojidots-hypr — session context (Hyprland build, from VM detour to now)

Paste this into a new conversation (or point Claude at this file path) to
resume exactly where this one left off.

## What this is
A Hyprland companion desktop-environment project to **armojidots** (the
SwayFX build on Armin's ThinkPad laptop). Built on Armin's **gaming PC**
(hostname `cachyosmain`, user `armoji`), reached entirely over SSH from the
laptop — Claude has no local/physical access to this machine.

## Machine access — read this before doing anything
- `ssh armoji@<LAN IP>` — passwordless, key already in `authorized_keys`.
  IP can change (DHCP) — if SSH stops connecting, ask Armin to run `ip a` on
  the gaming PC and get the current address.
- **Remote shell is `fish`, not bash.** Fish chokes on lots of ordinary
  bash syntax (`$?`, `$|`, heredocs, `VAR=val cmd`, etc.) with confusing
  errors. Rule: route almost everything through
  `ssh armoji@<ip> bash -s <<'EOF' ... EOF` instead of a raw one-line
  `ssh armoji@<ip> 'command'` string. This was the single biggest source of
  wasted turns this session — don't repeat it.
- **`hyprctl` needs env vars that a bare SSH session doesn't have.** Before
  any `hyprctl` call over SSH, first find and export the live instance:
  ```sh
  ls /run/user/1000/hypr/          # find the instance signature dir
  export HYPRLAND_INSTANCE_SIGNATURE=<that dir name>
  export WAYLAND_DISPLAY=wayland-1
  export XDG_RUNTIME_DIR=/run/user/1000
  ```
  This signature **changes on every reboot** — never hardcode an old one.
- Waybar restarts: `pkill -x waybar` then relaunch (`nohup waybar >/tmp/waybar.log 2>&1 & disown`)
  with the env vars above. **SIGUSR2 does NOT reliably reload waybar's CSS
  on this machine** (unlike the laptop) — always do a full restart.
  After restarting, always also `pkill -9 -f '[m]edia.sh cover'`,
  `pkill -9 -f '[m]edia.sh cava'`, `pkill -9 -f '^cava '` first, or repeated
  test-restarts leak duplicate processes (this happened — 16 of each at one
  point).
- Screenshots: `grim /tmp/x.png` (with the env vars exported) on the
  remote box, then `scp armoji@<ip>:/tmp/x.png ~/Downloads/` and Read it
  locally. There's no other way to see the gaming PC's screen.
- `gh auth login`'s browser device-flow **silently fails** on this machine
  (terminal shows "Exiting due to channel error" even though the browser
  side reports success) — go straight to "paste an authentication token"
  instead, don't waste time retrying the browser flow.

## Repo
[Armoji-code/armojidots-hypr](https://github.com/Armoji-code/armojidots-hypr),
public. Local clone at `~/dotfiles` on the gaming PC, GNU Stow-managed
(same convention as armojidots: one top-level dir per package, mirrors
`$HOME`). **There is a large pile of uncommitted work right now** — commit
only when Armin explicitly says to (standing rule, same as armojidots).

## Design rules Armin set for this project (apply everywhere, don't re-ask)
- Pill shapes — fully rounded (`border-radius: 999px`, clamps automatically)
- Frosty glass — but just Hyprland's **normal global blur** (already
  `blur.enabled = true` in the base config); don't add custom per-layer
  `layer_rule` blur overrides, that was tried and explicitly rejected
- No borders anywhere — blur alone carries the visual separation
- For differently-sized elements: radius should scale *additively*
  (`big_radius = small_radius + own_padding`), not proportionally — not
  yet exercised since everything built so far is uniformly pill-sized
- A real multi-palette color engine, not one hardcoded accent
- Same transparency value reused consistently across a given layer of
  glass elements
- **Dark mode only**, no light variant, ever
- **This is Hyprland, not Sway/SwayFX** — don't blindly port sway-isms.
  BUT: when in doubt, the instruction later in the session became **port
  armojidots' actual files directly** rather than reinventing from the
  design rules above — see "the CSS incident" below.

## What's actually been built, in order

### 1. VM detour (abandoned/irrelevant)
Early on, a QEMU/libvirt VM was set up to test CachyOS+Hyprland
(`cachyos-test` domain, `~/vms` on the laptop). **This was a false start** —
Armin clarified he'd installed CachyOS on his actual physical gaming PC,
not the VM. The VM still exists on the laptop but is unrelated to
everything below; ignore it unless Armin brings it up again.

### 2. Stripping Noctalia
CachyOS's Hyprland installer option now bundles **Noctalia** (a
quickshell-based shell, CachyOS's default since their June 2026 snapshot)
by default. Armin wanted bare Hyprland instead, matching how armojidots
started from scratch. Fully removed:
- Packages `noctalia` + `cachyos-hypr-noctalia` (plain `-R`, not `-Rs` —
  recursive removal would have swept `hyprland`, `kitty`, `dolphin` too
  since they were pulled in as deps of the Noctalia bundle)
- `~/.config/hypr` and `~/.config/noctalia` backed up (not deleted) to
  `hypr.noctalia-bak` / `noctalia.bak`
- Scattered leftover theme fragments Noctalia had dropped into other
  apps' configs (btop, gtk-3.0/4.0, alacritty, kitty, qt5ct/qt6ct, kdeglobals)
  — found and cleaned these up **twice**: once right after removal, and
  again later when a Firefox GTK warning surfaced a `gtk-3.0/gtk.css`
  file that still `@import`ed the deleted `noctalia.css` (same pattern
  existed in `gtk-4.0/gtk.css` too — check for this class of dangling
  reference if anything Noctalia-flavored still misbehaves)
- Confirmed the actual Hyprland session launch (SDDM autologin →
  `/usr/bin/start-hyprland`, and the fallback config at
  `/usr/share/hypr/hyprland.lua`) are owned by the **`hyprland` package
  itself**, not Noctalia — so removal didn't risk breaking login. That
  fallback config is a genuine, complete, working upstream example
  (Super+Q terminal, Super+E file manager, workspace switching, etc.),
  confirmed by testing.

### 3. User Hyprland config layering pattern
Since `/usr/share/hypr/hyprland.lua` is root-owned (can't edit directly),
and a user `~/.config/hypr/hyprland.lua` would otherwise *replace* it
entirely (losing all the bare defaults), the pattern settled on is:
```lua
dofile("/usr/share/hypr/hyprland.lua")
-- then user overrides (hl.monitor, hl.window_rule, hl.on("hyprland.start", ...)) below
```
This works — verified all 48 base binds (including Super+Q) survive a
`hyprctl reload` alongside the overrides. This is the **only** file to
edit for monitor/window-rule/autostart config:
`~/.config/hypr/hyprland.lua` on the gaming PC.

Gotchas hit while editing this file:
- `hyprctl keyword ...` doesn't work on this Lua-config build ("keyword
  can't work with non-legacy parsers, use eval") — use
  `hyprctl eval "hl.monitor({...})"` (or `hl.window_rule`, `hl.layer_rule`)
  for **live/runtime** testing before writing to the file.
- `hyprctl dispatch exec "..."` also doesn't work with the old string
  syntax on this build — just export the real session env vars and run
  the command directly instead of fighting dispatch syntax.
- `hl.window_rule({ ..., size = "900x620", ... })` — the `x` separator
  syntax from the (apparently outdated) doc site is wrong; this build
  wants a **space**: `size = "900 620"`.

### 4. Monitor setup (now permanent, in hyprland.lua)
Two monitors, physically: a portrait secondary on the left, a landscape
240Hz main on the right.
```lua
hl.monitor({ output = "HDMI-A-2", mode = "preferred", position = "0x0", scale = 1, transform = 1 })
hl.monitor({ output = "DP-2", mode = "2560x1440@240", position = "1080x0", scale = 1 })
```
- `HDMI-A-2` = side monitor, 1920x1080@60, portrait (transform=1), pinned left
- `DP-2` = main monitor, MSI MAG 273QP QD-OLED, 2560x1440 @ **240Hz** (was
  defaulting to ~60Hz "preferred" — had to set the mode explicitly)

**HDR**: DP-2 supports HDR (real spec: True Black 400 mode = ~450 nit
ceiling, not the Peak 1000 mode — Armin confirmed he uses True Black 400).
Tried enabling it with proper values (researched via an actual Hyprland
GitHub discussion about correct HDR luminance config, since Hyprland's own
defaults are documented as "completely wrong"):
```lua
-- add to the DP-2 hl.monitor() block if re-enabling:
bitdepth = 10, cm = "hdr", max_luminance = 450, min_luminance = 0,
sdr_max_luminance = 250, sdr_min_luminance = 0, sdrbrightness = 1.0, sdrsaturation = 1.0,
```
**Found and confirmed a real, reproducible bug**: with HDR on, SDR content
(waybar's dark glass pill, specifically) renders visibly washed-out/lighter
on the HDR monitor vs the identical CSS on the SDR side monitor — confirmed
by direct side-by-side screenshot comparison with matched zoom, toggling
HDR off and back on to verify causation. This is a real SDR-in-HDR
tone-mapping artifact (PQ curve vs sRGB gamma curve mismatch, most visible
on translucent/alpha-blended elements), not something misconfigured — it's
a known, still-imperfect problem across HDR desktop compositing generally
(Windows/macOS/Linux), not unique to this setup. **Current state: HDR is
OFF** (last explicit action was reverting to the plain `DP-2` block above
after confirming the washout was real) — Armin said "we will think of
fixes" for this, no resolution yet. Re-check `hyprctl monitors -j` →
`colorManagementPreset` field to see current live state, don't trust this
doc if time has passed.

### 5. Wallpapers
All 11 images copied from the laptop's `~/Pictures/Wallpapers/` via
`rsync` into `~/dotfiles/wallpapers/Pictures/Wallpapers/` (new stow
package on the gaming PC — note this is a *different* internal structure
than armojidots' own ad-hoc `wallpapers/current` symlink-to-absolute-path
setup on the laptop). A `~/dotfiles/wallpapers/current` symlink was added
pointing at `Pictures/Wallpapers/pixel_bliss.png`, matching the convention
`theme.sh`'s wallpaper-extraction mode expects. `hyprpaper` installed and
configured as a systemd `--user` service (`hyprpaper.service`, enabled) —
note its config needs the **modern block syntax** with explicit monitor
names (`wallpaper { monitor = DP-2; path = ...; }` x2), the legacy
`wallpaper = ,/path` "all monitors" comma-syntax silently produced "no
target" for both outputs on this hyprpaper version.

### 6. Waybar — the big rebuild, several false starts
Installed: `waybar playerctl cava ttf-jetbrains-mono-nerd swaync pulsemixer
network-manager-applet blueman python-pillow` (python-pillow was missed
initially — caused the cover-art placeholder to silently fail with zero
output, no error visible without manually invoking the python snippet).

**"CSS incident"**: First pass redesigned waybar's structure from
first-principles based on the design rules above (custom `group/left` +
`group/right` wrapper modules, per-module pills). Armin was very unhappy
with this — the instruction became **stop reinventing, port the actual
armojidots config.jsonc/style.css directly, only substituting what
genuinely must differ for Hyprland**. Concretely:
- waybar's CSS wraps `modules-left`/`modules-center`/`modules-right` in
  classes `.modules-left` etc. **natively, automatically, with no
  wrapper module needed** — the custom `group/left`/`group/right` modules
  were unnecessary and their CSS id is `#left`/`#right` (group modules
  strip the `group/` prefix entirely, not hyphenate it like `custom/`
  modules do — this is a real, documented waybar gotcha, cost real time
  to discover) — this whole approach was removed once the real
  armojidots CSS was ported over
- Real armojidots `.modules-left/-center/-right` get an outer glass pill
  (`@bg`), individual modules inside ALSO get their own smaller nested
  pill (`rgba(255,255,255,0.07)`) — a two-level nested-pill look, not
  flat. Ported verbatim.
- Substitutions actually needed: `hyprland/workspaces` (not
  `sway/workspaces`), dropped `backlight`/`battery`/`custom/power`
  (desktop, no battery — confirmed `/sys/class/power_supply/` is empty),
  `kitty --app-id=float-tui` instead of `foot --app-id=float-tui`
  (foot isn't installed there, kitty is the terminal), cache dir renamed
  `armojidots-waybar` instead of `armoji-waybar`.
- `custom/language` (lang.sh) module was **left out for now** — deferred
  to a later "buttons" pass, never actually built. The real armojidots
  `lang.sh` is 100% `swaymsg`-based (subscribes to sway IPC input events)
  and needs a genuine Hyprland rewrite, not a port: `hyprctl
  switchxkblayout <device> next` for toggling, Hyprland's own
  `.socket2.sock` event stream (plain text lines, `activelayout>>...`)
  for watching changes instead of `swaymsg -t subscribe`. Research was
  done (`hyprctl devices -j` shows a `main: true` field to identify the
  real physical keyboard among several virtual ones) but **nothing was
  implemented yet**.
- Per-monitor difference: Armin asked to **remove the media pill from
  the side/portrait monitor's bar** (keep it only on the main monitor) —
  this was acknowledged but **not yet done**. Needs waybar's
  multi-bar-config-array feature (an array of bar objects in
  `config.jsonc`, one per output) or an `output` exclusion list.
- Self-healing `cover`/`cava` loops ported verbatim from armojidots'
  proven version (restart-on-death `while :; do ...; sleep N; done`
  pattern) — this is why full waybar restarts are safe to do liberally
  during testing/theme changes, unlike the original non-self-healing
  design that motivated using SIGUSR2 on the laptop.

Notification module (`custom/notifications`) and `idle_inhibitor` were
ported to match armojidots' exact icons/format-icons/tooltips, but not
deeply tested yet (just visually present, clicking not verified).

### 7. Theme engine (`theme.sh`) — ported, then heavily tuned
Faithfully ported armojidots' actual `theme.sh` (wallpaper dominant-color
extraction via PIL + HSV-derived full palette family via `derive_family()`
+ 8 named presets: ruby/orange/dandelion/emerald/cobalt/bubblegum/purpur/
b&w). Lives at `~/dotfiles/theme/.local/bin/theme.sh` on the gaming PC
(new stow package — armojidots keeps theme.sh under the `sway` package,
doesn't make sense here, so it got its own `theme` package instead).
Applies to whatever actually exists on this machine: **waybar, kitty,
swaync, gtk-3.0/gtk-4.0** — deliberately does NOT try to theme
armoji-dock/armoji-osd/spotlight/walker/foot/swaylock since none of those
are built on this box.

State dir: `~/.local/state/armojidots-hypr/` (theme name + tone
persisted here, mirrors laptop's `~/.local/state/armojidots/`).

**Reload mechanism differs from the laptop on purpose**: SIGUSR2 doesn't
reliably reload waybar's CSS here (see machine-access notes above), so
`theme.sh`'s `apply()` does a full `pkill -x waybar` + relaunch instead
of `pkill -SIGUSR2 waybar` — confirmed safe given the self-healing
cover/cava loops.

**Saturation tuning saga** (this took many iterations, read carefully
before touching color math again):
1. Original ported formula: full/vivid saturation (matches armojidots
   exactly) — Armin found this "very dark"/too saturated for this
   monitor setup and asked for "more pastel."
2. First pastel attempt (clamped S~0.40-0.55, V~0.78-0.85): too washed
   out, "looks white."
3. Recalibrated against real Catppuccin-style pastel reference points:
   too grey.
4. Recalibrated against actual **baby blue** (#89CFF0 → H199° S43% V94%,
   computed precisely): close, but Armin then gave an **exact literal
   hex** (`#8480FD`) to just set directly, bypassing the algorithm
   entirely for a moment.
5. Then: **"change it back to how it was first"** — full revert of all
   pastel math, back to the exact original ported formula (verified
   byte-identical output to the very first test: `#0062f4` twice).
6. Then: manual, incremental, explicitly-directed steps on top of the
   *reverted* (fully-saturated) formula: "slowly make it less deep blue"
   → single small saturation nudge (~15% reduction, tested) → **"make it
   40 percent"** → confirmed-good result at exactly 40% saturation
   reduction from the raw/original value (`s_acc = s * 0.6"`).
7. **"apply the theme engine everywhere"** — baked the confirmed 40%
   reduction into `derive_family()`'s `s_acc` permanently. **Found and
   fixed a real bug here**: the wallpaper-extraction path
   (`extract_from_wallpaper()`) also had its own copy of the same `*0.6`
   factor, but `resolve()` *always* re-derives extraction's seed output
   through `derive_family()` a second time regardless of palette source
   — so wallpaper mode was compounding the reduction twice (0.6×0.6=0.36
   effective, not 0.6). Fixed by removing the factor from
   `extract_from_wallpaper()`, keeping it only in `derive_family()` (the
   single final stage everything funnels through, preset or wallpaper).
   Verified fix reproduces the confirmed-good manual hex almost exactly.

**Current formula state** (as of last edit): `derive_family()`'s
`acc`/`dim` computation uses `s_acc = s * 0.6` (40% reduction, confirmed
good by Armin). **In progress / just discovered, not yet verified**:
the ANSI terminal color family (`regs`/`brights`, i.e. kitty's
color1-color14 — what fastfetch's swatch row actually displays) was
**still using the raw un-reduced `s`**, only the single accent/dim pair
had gotten the 40% treatement. Armin caught this directly ("the palette
is fucked, full of deep colors... this is a dark theme, colors have to
be lighter") after the kitty include-line fix (below) finally let a
fresh kitty window show real theme colors for the first time. A fix was
written (change `s * ds * T["ansi"]` → `s_acc * ds * T["ansi"]` in the
`regs`/`brights` loop, both instances) and **passed a syntax check, but
was never applied+tested** — this is the very next thing to do:
```sh
export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=<current>
ssh armoji@<ip> '<export the above>; ~/.local/bin/theme.sh apply wallpaper'
# then open a NEW kitty window (existing ones won't hot-reload) and screenshot
```

### 8. kitty — the include-line bug
`theme.sh` was faithfully writing `~/.config/kitty/theme-colors.conf` from
the very start, but **`kitty.conf` itself never had `include
theme-colors.conf`** — it wasn't even under stow management (a leftover
plain file from the Noctalia skel, containing only
`background_opacity 0.6`, `cursor_trail 1`, `window_padding_width 25`).
This meant *no amount of reopening kitty* would ever show the theme —
confirmed by Armin directly ("has not changed even after reopening
terminal"). Fixed: created a proper `~/dotfiles/kitty/.config/kitty/kitty.conf`
stow package with `include theme-colors.conf` prepended, keeping the
existing 3 settings, removed the old unmanaged file, stowed it. **Verified
working for new windows** — a freshly-launched `kitty --hold -e fastfetch`
showed correct theme colors; the already-open old window did not (expected,
kitty doesn't hot-reload a running instance's config).

Also note: `kitty -e fastfetch` alone closes instantly (fastfetch exits,
kitty closes with it) — use `kitty --hold -e fastfetch` for any
screenshot-verification purposes.

## Immediate next steps (in order)
1. **Apply + verify the ANSI-palette fix** (ready to go, described above)
   — open a fresh kitty window after, screenshot, confirm the swatch row
   and labels read light/soft instead of deep/saturated.
2. Decide on HDR (currently off) — Armin wants to "think of fixes" for
   the SDR-washout issue before re-enabling, no plan yet.
3. Remove the media pill from the side/portrait monitor's waybar (asked
   for, not done — needs multi-bar config or per-output module list).
4. Build `lang.sh` for Hyprland (keyboard layout EN/LT switcher +
   waybar module) — research done, nothing implemented.
5. Commit the substantial pile of uncommitted work once Armin says to —
   `theme` package, `waybar` package, `kitty` package, `wallpapers`
   package, `hyprland.lua` changes, `hypr-scripts` (bluelight-watch.sh)
   are all sitting uncommitted in `~/dotfiles` on the gaming PC.

## Also present, working, not covered in detail above
- `hyprsunset` (Hyprland's native blue-light filter, controlled live via
  `hyprctl hyprsunset temperature <N>` / `identity`) + a ported
  `bluelight.sh` waybar module (ON/OFF/AUTO 21:00-05:00, matches
  armojidots' UX) + a `bluelight-watch.sh` re-check loop for AUTO mode —
  all wired into `hl.on("hyprland.start", ...)` autostart, confirmed
  working.
- `float-tui` window rule (`hl.window_rule`) for nmtui/pulsemixer/
  bluetuith-style floating terminal tools — `bluetuith` itself isn't
  available as a package on this system (target not found), so the
  bluetooth waybar button currently launches `blueman-manager` (GTK GUI)
  instead of a TUI, unlike the laptop.
