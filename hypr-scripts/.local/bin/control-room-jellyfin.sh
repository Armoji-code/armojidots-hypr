#!/bin/sh
# Live Jellyfin library dashboard (debianlab) for the control-room TV.
# Polls the REST API directly with an API key — no local Jellyfin
# client/session needed. Refreshes every $REFRESH seconds.
#
# JF_URL/JF_KEY live in ~/.config/control-room/jellyfin.env (gitignored,
# not this repo — it's public) rather than hardcoded here.
ENV_FILE="$HOME/.config/control-room/jellyfin.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "missing $ENV_FILE (needs JF_URL + JF_KEY) — see control-room-tv memory notes"
  exit 1
fi
. "$ENV_FILE"
REFRESH=30

while :; do
  # raw ANSI clear+home instead of `clear` — tput/terminfo lookups can
  # race on a brand-new kitty window (see control-room-cava.sh), this
  # doesn't depend on terminfo at all.
  printf '\033[2J\033[H'
  python3 - "$JF_URL" "$JF_KEY" <<'PY'
import sys, json, urllib.request, datetime

url, key = sys.argv[1], sys.argv[2]

def get(path):
    req = urllib.request.Request(url + path, headers={"X-Emby-Token": key})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.load(r)

CYAN, YELLOW, GREEN, DIM, BOLD, RESET = "\033[36m", "\033[33m", "\033[32m", "\033[2m", "\033[1m", "\033[0m"

try:
    counts = get("/Items/Counts")
    recent = get(
        "/Items?IncludeItemTypes=Movie,Series&Recursive=true"
        "&SortBy=DateCreated&SortOrder=Descending&Limit=16"
        "&Fields=DateCreated,ProductionYear"
    )
except Exception as e:
    print(f"{DIM}jellyfin (debianlab) unreachable: {e}{RESET}")
    sys.exit(0)

now = datetime.datetime.now().strftime("%H:%M:%S")
print(f"{BOLD}{CYAN}debianlab — Jellyfin{RESET}")
print(f"{DIM}{counts.get('MovieCount', 0)} movies   {counts.get('SeriesCount', 0)} shows   updated {now}{RESET}\n")
print(f"{BOLD}Recently added{RESET}")
for it in recent.get("Items", []):
    is_movie = it.get("Type") == "Movie"
    tag = "" if is_movie else " (show)"
    year = it.get("ProductionYear", "")
    color = GREEN if is_movie else YELLOW
    print(f"  {color}{it['Name']}{RESET} {DIM}{year}{tag}{RESET}")
PY
  sleep "$REFRESH"
done
