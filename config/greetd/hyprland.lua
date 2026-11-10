-- the greeter's compositor: a stripped Hyprland whose only job is the glyph face.
-- Deployed to /etc/greetd/hyprland.lua by ./install.sh --greeter; greetd starts it
-- as the "greeter" user. Deliberately NOT the session config: no plugins, no
-- keybinds, no daemons -- but the input section mirrors the session's, so the
-- keyboard (layout, numlock) behaves exactly like after login.

hl.monitor({ output = "", mode = "highres", position = "auto", scale = "auto" })

hl.config({
    input = {
        kb_layout          = "us", -- keep in step with hypr/hyprland/input.lua
        numlock_by_default = true, -- a 4-digit PIN is typed on the numpad, cold, at boot
        repeat_delay       = 250,
        repeat_rate        = 35,
    },

    misc = {
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0, -- no wallpaper: the face draws its own background
        background_color        = "rgb(000000)",
        key_press_enables_dpms  = true,
        mouse_move_enables_dpms = true,
    },

    animations = { enabled = false }, -- the face animates itself (LockFace), the compositor stays still
})

hl.on("hyprland.start", function()
    -- the face, then the compositor exits: greetd starts the user session only
    -- once this greeter session has ended (see glyph-greeter)
    hl.exec_cmd("/etc/greetd/glyph-greeter")
end)
