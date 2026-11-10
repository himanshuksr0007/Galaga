local vars = require("variables")

----------------------
---- Window rules ----
----------------------

hl.window_rule({ match = { fullscreen = false }, opacity = vars.windowOpacity .. " override" })

-- Apps that draw their own window buttons (GTK headerbars, Electron, ...). The list
-- drives two rules: these apps get no hyprbars bar (the no_bar rule at the bottom of
-- this file), and they are
-- the one exception to the maximise suppression below, so a click on their own
-- maximise button actually maximises. There is no protocol way to detect "draws
-- its own buttons", so the list is curated by hand: ONE CLASS PER LINE. Find an
-- app's class with `hyprctl activewindow` (or `hyprctl clients`), add a line here,
-- and both rules follow -- see README "Window buttons".
local ownButtons = {
    "org\\.gnome\\..*", -- GNOME apps: headerbars (Nautilus, Settings, Text Editor, Loupe, ...)
    "gnome-control-center",
    "Code", "VSCodium", "codium", -- VS Code: own titlebar, see README "Window buttons"
    "steam", -- own titlebar; the games themselves are fullscreen anyway
    "discord", "vesktop", "equibop", -- own titlebars
    "firefox", "org\\.mozilla\\.firefox", "firefox-esr", -- Firefox: own titlebar buttons (see README "Window buttons")
    "zen", "app\\.zen_browser\\.zen", "io\\.github\\.zen_browser\\.zen", -- Zen: same engine, same buttons
    "org\\.quickshell", -- the shell's own windows (Rice switcher)
}

-- The two rules build their patterns from the list SEPARATELY, on purpose -- they
-- must never share one pattern string. When they did (a single joined local feeding
-- both), the no_bar rule silently stopped matching the listed classes: Calculator
-- grew a hyprbar over its headerbar while the suppression exemption on the very
-- same list kept working. The matched set is identical either way; only the shape
-- differs. Suppression joins the list into one negative group:
local ownButtonsJoined = table.concat(ownButtons, "|")
-- ...and no_bar (bottom of this file) anchors every entry on its own:
local ownButtonsEach = {}
for i, class in ipairs(ownButtons) do ownButtonsEach[i] = "^(" .. class .. ")$" end
local ownButtonsNoBar = table.concat(ownButtonsEach, "|")

-- apps (kitty) request maximize on open -- ignore it, tiling decides by itself.
-- The own-buttons apps above are exempt (negative: match): for them the same
-- request is a user clicking their maximise button, not an app presuming.
-- Suppression is a per-window set that matching rules only ever add to -- no
-- later rule can take an event back out -- so the exception has to live in this
-- rule's own match.
hl.window_rule({ match = { class = "negative:^(" .. ownButtonsJoined .. ")$" }, suppress_event = "maximize" })

hl.window_rule({ match = { float = true, xwayland = false }, center = true }) -- Center all floating windows (not xwayland cause popups)

-- Floating Applications
hl.window_rule({
    match = {
        class =
        "guifetch|yad|zenity|wev|org.gnome.FileRoller|file-roller|blueman-manager|com.github.GradienceTeam.Gradience|feh|imv|system-config-printer|org.quickshell",
    },
    tag   = "+float",
})
hl.window_rule({
    match = {
        title =
        "(Select|Open)( a)? (File|Folder)(s)?|File (Operation|Upload)( Progress)?|.* Properties|Export Image as PNG|GIMP Crash Debug|Save As|Library",
    },
    tag   = "+float",
})
hl.window_rule({ match = { class = "steam", title = "Friends List" }, tag = "+float" })
hl.window_rule({ match = { class = "com-atlauncher-App", title = "ATLauncher Console" }, tag = "+float" })
hl.window_rule({ match = { class = "PandoraLauncher", title = "Minecraft Game Output" }, tag = "+float" })

hl.window_rule({ match = { tag = "float" }, float = true })

-- Opaque Apps (Terminal, Image Viewers, Creative Software, Games) as they prefer native transparency as required
hl.window_rule({
    match = {
        class =
        "kitty|equibop|org.quickshell|com.t3tools.T3Code|imv|swappy|krita|gimp|inkscape|darktable|resolve|kdenlive|shotcut|blender|godot|(steam_app_(default|[0-9]+))|gamescope",
    },
    tag   = "+opaque_app",
})

hl.window_rule({ match = { tag = "opaque_app" }, opaque = true })

-- Sized & Centered Floaters
hl.window_rule({ match = { class = "org.quickshell", title = "Rice" }, float = true, center = true }) -- shell switcher
hl.window_rule({ match = { class = "kitty", title = "nmtui" }, tag = "+float_60_70" })
hl.window_rule({ match = { class = "org.pulseaudio.pavucontrol|yad-icon-browser" }, tag = "+float_60_70" })
hl.window_rule({ match = { class = "org.gnome.Settings" }, tag = "+float_70_80" })
hl.window_rule({ match = { class = "nwg-look" }, tag = "+float_50_60" })

hl.window_rule({
    match  = { tag = "float_60_70" },
    float  = true,
    size   = "(monitor_w*0.6) (monitor_h*0.7)",
    center = true,
})
hl.window_rule({
    match  = { tag = "float_70_80" },
    float  = true,
    size   = "(monitor_w*0.7) (monitor_h*0.8)",
    center = true,
})
hl.window_rule({
    match  = { tag = "float_50_60" },
    float  = true,
    size   = "(monitor_w*0.5) (monitor_h*0.6)",
    center = true,
})

-- Games (Steam, Lutris/Wine, Gamescope)
hl.window_rule({
    match        = { class = "(steam_app_(default|[0-9]+))|gamescope" },
    immediate    = true,
    idle_inhibit = "always",
})

-- Picture in picture (resize and move done via script)
hl.window_rule({
    match             = { title = "Picture(-| )in(-| )[Pp]icture" },
    move              = "(monitor_w*0.98-window_w) (monitor_h*0.97-window_h)",
    pin               = true,
    float             = true,
    keep_aspect_ratio = true,
})

-- Ueberzugpp
hl.window_rule({ match = { class = "^(ueberzugpp_.*)$" }, float = true, no_initial_focus = true })

-- Autodesk Fusion 360
hl.window_rule({ match = { class = "fusion360.exe", title = "Fusion360|(Marking Menu)" }, no_blur = true })

-- Ugh xwayland popups
hl.window_rule({ match = { xwayland = true, title = "win[0-9]+" }, tag = "+xwl_popup" })
hl.window_rule({
    match = { xwayland = true, title = "", class = "", initial_title = "", initial_class = "" },
    tag   = "+xwl_popup",
})
hl.window_rule({
    match     = { tag = "xwl_popup" },
    no_dim    = true,
    no_shadow = true,
    no_blur   = true,
    opaque    = true,
})

-- Special workspaces
hl.window_rule({ match = { class = "btop" }, workspace = "special:sysmon" })
hl.window_rule({
    match     = {
        class = "feishin|Spotify|Supersonic|Cider|com.github.th_ch.youtube_music|Plexamp|com-maxrave-simpmusic-MainKt",
    },
    workspace = "special:music",
})
hl.window_rule({ match = { initial_title = "Spotify( \\(?Free\\)?)?" }, workspace = "special:music" }) -- Spotify wayland, it has no class for some reason; regex (re2), not a lua pattern
hl.window_rule({ match = { class = "discord|equibop|vesktop|whatsapp|org\\.telegram\\.desktop|TelegramDesktop" }, workspace = "special:communication" })
hl.window_rule({ match = { class = "Todoist|io\\.github\\.alainm23\\.planify" }, workspace = "special:todo" })

-- Window buttons (hyprbars, hyprland/titlebars.lua): the own-buttons apps (the
-- ownButtons list at the top of this file) keep theirs -- GTK apps' are themed by
-- term/gtk.css -- and get no second bar here; fullscreen, PiP and XWayland popups
-- lose the bar too. Firefox and Zen are in the list: they keep their built-in
-- buttons, whose box follows the decoration layout this rice ships (close and
-- maximise -- no minimise, whose click could not work here), and the exemption
-- above makes their maximise land. Chromium, Chrome and Brave are NOT in the
-- list: with their "Use system title bar and borders" setting on they draw no
-- buttons of their own and take the hyprbar instead -- see README "Window buttons".
-- The no_bar prop itself is gated on _G.GLYPH_HYPRBARS, which titlebars.lua
-- (required before this file) sets from its verified plugin check: while the
-- plugin is not in, the value is nil and Lua drops the key from the table, so
-- the rule registers without it -- an unknown plugin prop here errors exactly
-- like an unknown config key did at login. The start-time reload pass
-- (execs.lua) re-registers the full form once hyprbars is in.
hl.window_rule({ match = { fullscreen = true }, ["hyprbars:no_bar"] = _G.GLYPH_HYPRBARS or nil })
hl.window_rule({ match = { tag = "xwl_popup" }, ["hyprbars:no_bar"] = _G.GLYPH_HYPRBARS or nil })
hl.window_rule({ match = { title = "Picture(-| )in(-| )[Pp]icture" }, ["hyprbars:no_bar"] = _G.GLYPH_HYPRBARS or nil })
-- The own-buttons exclusion rides a TAG, the same two-step the float and opaque
-- rules above use -- not the class match alone. The class rule by itself held
-- only until the window changed state: maximise an own-buttons app with its own
-- button, unmaximise it, and our bar appeared over its headerbar and stayed
-- (reported 2026-11-11, Firefox first, then every own-buttons app). A tag, once
-- set at map time, stays on the window for its whole life, and tag-matched rules
-- are the ones re-run on every state change -- so the exclusion is re-asserted
-- exactly when the class-matched prop was being lost. Both rules stay: the
-- direct class rule covers map time, the tag rule covers every change after.
hl.window_rule({ match = { class = ownButtonsNoBar }, tag = "+own_buttons" })
hl.window_rule({ match = { tag = "own_buttons" }, ["hyprbars:no_bar"] = _G.GLYPH_HYPRBARS or nil })
hl.window_rule({
    match = { class = ownButtonsNoBar }, -- every entry anchored on its own -- see the note at the list
    ["hyprbars:no_bar"] = _G.GLYPH_HYPRBARS or nil,
})

---------------------
---- Layer rules ----
---------------------

hl.layer_rule({ match = { namespace = "hyprpicker" }, animation = "fade" })                 -- Colour picker out animation
hl.layer_rule({ match = { namespace = "logout_dialog" }, animation = "fade" })              -- wlogout
hl.layer_rule({ match = { namespace = "selection" }, animation = "fade" })                  -- slurp
hl.layer_rule({ match = { namespace = "wayfreeze" }, animation = "fade" })                  -- wayfreeze
hl.layer_rule({ match = { namespace = "launcher" }, animation = "popin 80%", blur = true }) -- Fuzzel

-- Shell: all demonshot windows animate themselves (slam), the compositor stays out of it
hl.layer_rule({ match = { namespace = "demonshot-.*" }, no_anim = true })
-- glyph: OSD strips, island, quick settings and its own modules draw their own appearance -- the compositor stays out of it (and does not slow the OSD);
-- the power menu has no animation of its own -- a soft fade
hl.layer_rule({ match = { namespace = "glyph-power" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "glyph-(launcher|edge|island|buds|quick|home|bar|caffeine|shot|clip|charms|vpn|deck|prefs|hot|cal|wall|back)" }, no_anim = true })
