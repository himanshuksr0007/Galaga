-- Window title bars with mac-style traffic-light buttons, drawn by the hyprbars plugin
-- (hyprland-plugins, installed and enabled by install.sh through hyprpm).
--
-- Loading: hyprpm loads the plugin from execs.lua (`hyprpm reload`), and the plugin's init
-- reloads this config -- so on the very first pass hl.plugin.hyprbars does not exist yet.
-- The pcall below keeps that pass silent; the reload right after registers the buttons.
-- After a Hyprland upgrade the plugin is stale until rebuilt: `hyprpm update`.
--
-- Apps that draw their own headerbar buttons (GTK apps, VS Code, ...) are excluded
-- in rules.lua (hyprbars:no_bar) and themed by term/gtk-3.0 + term/gtk-4.0 instead.
-- Browsers get this bar like everyone else: their built-in buttons are switched off
-- on their side first (config/browser/user.js for Firefox/Zen, a setting in
-- Chromium) -- see README: "Window buttons".
--
-- Colours: bone bar and ash inactive discs from the scheme, the rice's one red and its
-- white/black from Theme.qml (the same values as term/gtk.css). hyprbars draws each
-- button as a plain disc -- there is no per-button border -- so the white disc gets its
-- edge from the dark glyph on it and the bar being a warm step darker than the disc.
local scheme = require("scheme.demonshot")

hl.config({
    plugin = {
        hyprbars = {
            bar_height                 = 32,
            bar_color                  = "rgb(" .. scheme.bone .. ")",
            ["col.text"]               = "rgb(" .. scheme.crypt .. ")",
            bar_text_font              = "Space Grotesk",
            bar_text_size              = 11,
            bar_text_align             = "left", -- the plugin starts the title right after the buttons
            bar_buttons_alignment      = "left",
            bar_padding                = 10,
            bar_button_padding         = 8,
            bar_part_of_window         = true,
            bar_precedence_over_border = true, -- the window border wraps the bar too: one frame
            bar_blur                   = false, -- the bar is opaque bone
            -- unfocused windows: all three discs go ash, like macOS greying its traffic lights
            inactive_button_color      = "rgb(" .. scheme.ash .. ")",
            -- double-clicking the bar toggles fullscreen, like a titlebar double-click should
            on_double_click            = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })']],
        },
    },
})

-- Left to right: close, minimise, fullscreen. With bar_buttons_alignment = "left" the
-- plugin lays the buttons out in the order they are added here.
-- A click focuses the window first and only then runs the action (hyprbars barDeco.cpp),
-- so the actions use the plain active-window dispatchers, exactly like the keybinds --
-- and with them the existing animations: close rides windowsOut, fullscreen and the
-- minimise move ride windowsMove (animations.lua; the tree has no fullscreen leaf).
-- Minimise does not exist in Hyprland: the window is parked on special:minimized with
-- follow = false (we stay here). Restore: Super+Alt+Shift+M, see functions.lua.
pcall(function()
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(D71921)", -- close: the one red
        fg_color = "rgb(000000)",
        size     = 15,
        icon     = "✕",
        action   = "hyprctl dispatch 'hl.dsp.window.close()'",
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(F2F2F2)", -- minimise: white
        fg_color = "rgb(000000)",
        size     = 15,
        icon     = "−",
        action   = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", follow = false })']],
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(000000)", -- fullscreen: black
        fg_color = "rgb(F2F2F2)",
        size     = 15,
        icon     = "⤢",
        action   = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })']],
    })
end)
