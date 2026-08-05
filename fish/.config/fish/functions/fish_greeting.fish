function fish_greeting
    # tiered fetch (mini / stacked / wide) that follows terminal width and
    # re-renders on resize — logic + WINCH handler live in
    # conf.d/armoji_greeting.fish
    set -g __armoji_greeting_fresh 1
    set -g __armoji_greeting_tier (__armoji_tier)
    __armoji_fetch
end
