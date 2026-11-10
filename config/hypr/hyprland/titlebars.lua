-- Window title bars with mac-style traffic-light buttons, drawn by the hyprbars plugin
-- (hyprland-plugins, installed and enabled by install.sh through hyprpm).
--
-- Loading: the plugin is loaded HERE, during config evaluation -- hl.plugin.load
-- registers hyprbars (and with it the plugin.hyprbars.* keys) before the hl.config
-- block below runs. The load is then VERIFIED (the wiki's own pattern,
-- hl.get_loaded_plugins): the keys and buttons are registered only when the
-- plugin is actually in. Configuring an absent plugin is what painted the red
-- unknown-key errors at login until the exec'd `hyprpm reload` landed it --
-- the bare pcall could fail quietly and the config below could not tell
-- (reported twice, last on 2026-11-11). When the plugin is not in yet, this
-- file registers nothing plugin-shaped at all, and execs.lua's start pass
-- (hyprpm reload, then a config reload right behind it) re-runs this file
-- with the check green, so the bars arrive whole and error-free. A plugin
-- that is genuinely stale or missing still fails loudly -- in hyprpm's own
-- reload notification and in this file's log line -- never as a wall of
-- unknown-key errors for what is only a load-order problem.
-- The .so is the one hyprpm built (install.sh: hyprpm add hyprland-plugins,
-- enable hyprbars); hyprpm keeps it under ~/.local/share/hyprpm/<repo>/hyprbars/.
-- The known repo path is tried first, then any other repo dir there.
--
-- Apps that draw their own headerbar buttons (GTK apps, VS Code, ...) are excluded
-- in rules.lua (hyprbars:no_bar) and themed by term/gtk-3.0 + term/gtk-4.0 instead.
-- Chromium-family browsers get this bar too, once their "Use system title bar and
-- borders" setting switches their built-in buttons off; Firefox and Zen instead
-- keep their own buttons and are excluded in rules.lua like the other
-- own-buttons apps -- see README: "Window buttons".
--
-- The title is centred in Doto, the rice's dot-matrix font (config/fonts), bold --
-- hyprbars centres the title texture between the buttons on both sides.
-- The button glyphs appear only while the cursor hovers any of the buttons
-- (icon_on_hover), like macOS; otherwise the three discs sit plain. The plugin passes
-- no font weight to the icon rendering, so the glyphs themselves are the heaviest
-- forms: ✖ ━ ▢.
--
-- Colours: bone bar and ash inactive discs from the scheme, the rice's one red and its
-- white/black from Theme.qml (the same values as term/gtk.css). hyprbars draws each
-- button as a plain disc -- there is no per-button border -- so the white disc gets its
-- edge from the dark glyph on it and the bar being a warm step darker than the disc.
local function hyprbars_so()
    local home = os.getenv("HOME")
    local known = home .. "/.local/share/hyprpm/hyprland-plugins/hyprbars/hyprbars.so"
    local f = io.open(known)
    if f then
        f:close()
        return known
    end
    -- pcall'd: this fallback must never be able to break the rest of the file
    local ok, line = pcall(function()
        local ls = io.popen("ls " .. home .. "/.local/share/hyprpm/*/hyprbars/hyprbars.so 2>/dev/null")
        if not ls then return nil end
        local l = ls:read("*l")
        ls:close()
        return l
    end)
    if ok and line and line ~= "" then return line end
    return nil
end

-- hyprpm is an external process: the config must grant it the plugin
-- permission, or its loads stall on a prompt nobody can see at login
-- (Hyprland wiki, "Using plugins"). The config's own load below needs no
-- grant; this one covers execs.lua's `hyprpm reload` fallback.
hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

local function is_plugin_loaded(name)
    for _, v in pairs(hl.get_loaded_plugins()) do
        if v.name == name then return true end
    end
    return false
end

local so = hyprbars_so()
if so then pcall(hl.plugin.load, so) end -- already loaded (a re-parse) or stale: either way, not fatal here

local loaded = is_plugin_loaded("hyprbars")
_G.GLYPH_HYPRBARS = loaded -- rules.lua gates its hyprbars:no_bar props on this, the same check
if not loaded then
    print("glyph: hyprbars is not loaded at config time -- its keys and buttons wait for the hyprpm reload pass")
end

local scheme = require("scheme.demonshot")

if loaded then hl.config({
    plugin = {
        hyprbars = {
            bar_height                 = 32,
            bar_color                  = "rgb(" .. scheme.bone .. ")",
            ["col.text"]               = "rgb(" .. scheme.crypt .. ")",
            bar_text_font              = "Doto",
            bar_text_size              = 13,
            bar_text_weight            = "bold",
            bar_text_align             = "center",
            bar_buttons_alignment      = "left",
            bar_padding                = 10,
            bar_button_padding         = 8,
            bar_part_of_window         = true,
            bar_precedence_over_border = true, -- the window border wraps the bar too: one frame
            bar_blur                   = false, -- the bar is opaque bone
            icon_on_hover              = true, -- glyphs only while hovering a button, plain discs otherwise
            -- unfocused windows: all three discs go ash, like macOS greying its traffic lights
            inactive_button_color      = "rgb(" .. scheme.ash .. ")",
            -- double-clicking the bar toggles true fullscreen, like a titlebar double-click should
            on_double_click            = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })']],
        },
    },
})
end

-- Left to right: close, minimise, maximise. With bar_buttons_alignment = "left" the
-- plugin lays the buttons out in the order they are added here.
-- A click focuses the window first and only then runs the action (hyprbars barDeco.cpp),
-- so the actions use the plain active-window dispatchers, exactly like the keybinds --
-- and with them the existing animations: close rides windowsOut, maximise and the
-- minimise move ride windowsMove (animations.lua; the tree has no fullscreen leaf).
-- The black button maximises (fullscreen mode "maximized": the window fills the
-- workspace, bar and gaps stay) -- true fullscreen is the bar double-click above.
-- Minimise does not exist in Hyprland: the window is parked on special:minimized.
-- The white button runs scripts/minimise.sh -- the one entry point every park
-- path uses (Super+Alt+M runs it too, via functions.minimise_active): it offers
-- the window to the glyph shell for the genie warp into the deck's minimised
-- section, and parks directly if the shell does not take it. A click focuses
-- the window first (barDeco), so the script's active window is this one.
-- Restore: Super+Alt+Shift+M, see functions.lua.
-- Same gate as the config above: the buttons register only when the plugin
-- verified in. The pcall still guards the call itself.
if loaded then pcall(function()
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(D71921)", -- close: the one red
        fg_color = "rgb(000000)",
        size     = 16,
        icon     = "✖",
        action   = "hyprctl dispatch 'hl.dsp.window.close()'",
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(F2F2F2)", -- minimise: white
        fg_color = "rgb(000000)",
        size     = 16,
        icon     = "━",
        action   = [[bash $HOME/.config/hypr/scripts/minimise.sh]],
    })
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(000000)", -- maximise: black
        fg_color = "rgb(F2F2F2)",
        size     = 16,
        icon     = "▢",
        action   = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    })
end)
end
