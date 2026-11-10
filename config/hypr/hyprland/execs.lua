local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()
    -- Plugins first (hyprpm): titlebars.lua loads hyprbars in-config during
    -- evaluation and verifies it; when that check fails (the load refused at
    -- evaluation time), titlebars and rules register NOTHING plugin-shaped,
    -- so this pass is what brings the bars in: hyprpm loads the plugin, and
    -- the config reload right behind it -- same exec, so the order is
    -- guaranteed -- re-runs the config with the plugin in and every key,
    -- button and no_bar rule lands, error-free. It is also the recovery
    -- path after a Hyprland upgrade, once `hyprpm update` has rebuilt the
    -- .so. First, so even the fallback lands before anything visual.
    hl.exec_cmd("sh -c 'hyprpm reload -n; hyprctl reload'")

    -- Shell: whichever one is selected in rice
    hl.exec_cmd(vars.rice .. " start")

    -- in a nested session the system daemons are already running outside
    if vars.nested then return end

    -- Keyring and auth
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Auto delete trash 30 days old
    hl.exec_cmd("trash-empty 30")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- Location provider
    hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")

    -- Forward bluetooth media commands to MPRIS
    hl.exec_cmd("mpris-proxy")

    -- 4-finger tap -> quick settings: the one gesture Hyprland's engine has no
    -- shape for. libinput-gestures only reads the pad (no grab), so the native
    -- swipes in gestures.lua are unaffected; its whole config is that one line
    hl.exec_cmd("libinput-gestures")

    -- hypridle starts the shell (Rules.idle): timings from house rules -> ~/.config/demonshot/hypridle.conf
end)

-- Resizer listener
hl.on("window.title", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)

hl.on("window.open", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)
