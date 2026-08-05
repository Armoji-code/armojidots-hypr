# ── armojidots · responsive greeting ────────────────
# The fetch layout follows the terminal width, and re-renders when the
# window is resized — until the first command is run. This also fixes the
# spawn race: the tiler resizes a new window right after it opens, so the
# width at shell-start is often wrong; the resize fires WINCH and we redraw.

function __armoji_tier
    set -l cols (tput cols 2>/dev/null; or echo 80)
    if set -q SIDEBAR; or test "$cols" -lt 38
        echo mini
    else if test "$cols" -lt 90
        echo stacked
    else
        echo wide
    end
end

function __armoji_fetch
    switch (__armoji_tier)
        case mini
            set_color green
            echo "HI ARMOJI ▪"
            set_color normal
        case stacked
            # cramped: logo on top, specs below so they don't collide
            fastfetch --logo-position top
        case '*'
            fastfetch
    end
end

# Redraw the greeting at the new size on resize, but only while the prompt
# is still fresh (no command run) and empty, and only if the tier changed.
function __armoji_greeting_winch --on-signal WINCH
    test "$__armoji_greeting_fresh" = 1; or return
    test -z (commandline); or return
    set -l t (__armoji_tier)
    test "$t" = "$__armoji_greeting_tier"; and return
    set -g __armoji_greeting_tier $t
    printf '\033[2J\033[H'
    __armoji_fetch
    commandline -f repaint
end

# Stop redrawing once the user actually runs something.
function __armoji_greeting_done --on-event fish_preexec
    set -g __armoji_greeting_fresh 0
end
