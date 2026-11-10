local vars = require("variables")

hl.config({
    input = {
        kb_layout          = "us",
        numlock_by_default = true, -- the lock's password is a numpad PIN half the time; greetd's compositor does the same (config/greetd/hyprland.lua)
        repeat_delay       = 250,
        repeat_rate        = 35,
        focus_on_close     = 1,

        touchpad           = {
            natural_scroll       = true,
            disable_while_typing = vars.touchpadDisableTyping,
            scroll_factor        = vars.touchpadScrollFactor,
        },
    },

    binds = {
        scroll_event_delay = 0,
    },

    cursor = {
        hotspot_padding = 1,
    },
})
