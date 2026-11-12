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
    hl.exec_cmd("wl-paste --type text --watch cliphist -max-items 100 store")
    hl.exec_cmd("wl-paste --type image --watch cliphist -max-items 100 store")

    -- Drives mount by themselves (udiskie on udisks2). A shell restart can leave the last one
    -- running -- kill our own first (AMM021's dedupe)
    hl.exec_cmd([[sh -c 'command -v udiskie >/dev/null || exit 0; pkill -x -u "$(id -u)" udiskie; exec udiskie -a -n -T']])

    -- Cloudflare WARP's tray applet, when the warp extra installed the client
    -- (install.sh; the warp-svc daemon is enabled there). Same guard and dedupe
    -- as udiskie: no binary -- no-op; a restart must not stack two tray icons.
    -- This start is the only one: install.sh masks the package's own user
    -- service (its Restart kept resurrecting the window after it was closed)
    -- and hides its xdg autostart, so a killed client stays dead for the session.
    -- It waits for the shell's tray first (up to 10 s): started before a
    -- StatusNotifier host exists, the applet opens its main window on the
    -- desktop instead of sitting in the tray (seen at login, 2026-11-11).
    -- xcb is the platform the user verified this Qt app runs on here
    hl.exec_cmd([[sh -c 'command -v warp-taskbar >/dev/null || exit 0; pkill -x -u "$(id -u)" warp-taskbar; for i in $(seq 1 50); do busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && break; sleep 0.2; done; exec env QT_QPA_PLATFORM=xcb warp-taskbar']])

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
