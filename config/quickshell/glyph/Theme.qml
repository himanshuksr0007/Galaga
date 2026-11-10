pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings

// glyph: black, white dots, one red. Palette, fonts, motion, state (theme, do-not-disturb) and the look of hypr/kitty -- all here
Singleton {
    id: root

    // state survives a restart, and the lock reads it too (separate process)
    readonly property alias state: st
    readonly property bool light: st.light

    // light theme -- same layout, greys inverted; red does not change
    readonly property color bg: light ? "#E9E9E9" : "#000000"   // background, wallpapers
    readonly property color s1: light ? "#FFFFFF" : "#0E0E0E"   // bar, panels
    readonly property color s2: light ? "#F1F1F1" : "#1A1A1A"   // tiles, off
    readonly property color s3: light ? "#D9D9D9" : "#2A2A2A"   // lines, dimmed dots
    readonly property color mute: light ? "#B8B8B8" : "#4A4A4A" // inactive
    readonly property color grey: light ? "#6E6E6E" : "#8C8C8C" // labels, secondary
    readonly property color fg: light ? "#0B0B0B" : "#F2F2F2"   // text, on, focus
    readonly property color ink: light ? "#FFFFFF" : "#000000"  // text on a white tile
    readonly property color red: "#D71921"                      // at most one thing on screen, and only "live"
    readonly property color glow: light ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color scrim: light ? Qt.rgba(0.91, 0.91, 0.91, 0.8) : Qt.rgba(0, 0, 0, 0.74)

    readonly property string dot: "Doto"                   // digits and short words, not smaller than 26px
    readonly property string ui: "Space Grotesk"
    readonly property string mono: "Space Mono"            // labels in caps
    readonly property string nf: "JetBrainsMono Nerd Font" // icons

    // 1920x1080 layout canvas -> screen. ponytail: based on the first screen; on a second screen the layout is the same
    // (hypr's scale does the sizing), only the home bento hugs the right edge there
    readonly property real s: {
        const sc = Quickshell.screens[0];
        return sc ? Math.min(sc.width / 1920, sc.height / 1080) : 1;
    }

    // a screen's own settings live in state.screens under the monitor's MODEL: it is the monitor, not the port --
    // the same monitor through another port or a dock keeps its own. Two identical monitors, or one without a
    // model, go by port name. The model is the same one hyprctl reports (Rules.key)
    function sid(name) {
        const m = Quickshell.screens.find(s => s.name === name)?.model.trim();
        return m && Quickshell.screens.filter(s => s.model.trim() === m).length === 1 ? m : name;
    }
    // by name -- an old entry (from before models) or a twin that is currently alone
    function own(name) { return st.screens[sid(name)] ?? st.screens[name]; }
    // a screen's setting by output name: its own, else the shared one; bar and home default to on
    function scr(name, key) { return own(name)?.[key] ?? { wall: st.wall, widgets: st.widgets }[key] ?? true; }
    // undefined -- drop the screen's own value, it takes the shared one. An entry under a port name is copied under
    // the model but stays: if a twin appears, that screen is looked up by port again
    function setScr(name, key, v) {
        const o = Object.assign({}, own(name)), all = Object.assign({}, st.screens);
        if (v === undefined) delete o[key];
        else o[key] = v;
        all[sid(name)] = o;
        st.screens = all;
    }
    // the first screen's wallpaper, its own or the shared one -- the colour source reads this one
    readonly property string wall: scr(Quickshell.screens[0]?.name, "wall")

    // glide: ease-out-quart, no overshoot -- like the bezier glide in hypr
    readonly property var glide: [0.25, 1, 0.5, 1, 1, 1]
    readonly property int t: 350

    // wallpapers are drawn from a copy sized for the screen (the picker makes it, magick): the original can be a 40 MB png and would take seconds to load.
    // ponytail: no copy (cache wiped, path typed by hand) -- empty, grid and orb, until the picker is opened
    readonly property string wallCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/glyph/walls"
    function wallSrc(p) { return p ? `${wallCache}/${p.slice(p.lastIndexOf("/") + 1)}.jpg` : ""; }
    function url(p) { return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : ""; }

    function fade(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    // clock per 12/24 setting: "09" or "9"
    function hh(d) { const h = d.getHours(); return st.clock24 ? String(h).padStart(2, "0") : String(h % 12 || 12); }
    function hex(c) { return c.toString().slice(1, 7).toUpperCase(); }

    // as in Rules: apply() at startup must see glyph.json, not the defaults
    Component.onCompleted: stateFile.waitForJob()

    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/glyph.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        // write -- once at the end of the turn: writeAdapter() on every field in a row mixes up neighbors
        onAdapterUpdated: Qt.callLater(stateFile.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: st
            property bool light: false
            property bool dnd: false  // new ones are not shown, critical ones always
            property int unread: 0    // for the lock
            // ---- what the settings (prefs) change ----
            property var widgets: ["weather", "calendar", "cpu", "player", "buds", "system"] // home bento in order, see kinds
            property bool clock24: true
            property bool blink: true      // clock colon blinks
            property string name: ""       // in the greeting; empty -- $USER
            property bool grid: true       // dot grid on the wallpaper
            property bool orb: true        // halftone orb
            // wallpaper (picker wall/Walls, drawn by components/Wall): path to the image; empty -- grid and orb. The picker folder can be changed here
            property string wall: ""
            property string wallDir: ""    // empty -- ~/Pictures/Wallpapers
            property int wallLook: 0       // 0 dots, 1 grey photo, 2 color
            property int wallPitch: 10     // dot pitch, px
            property int wallBright: 85    // %, from background to image
            property int rounding: 20      // hypr windows
            property bool edges: true      // Glyph strips at the edges (volume/brightness, flashes, progress)
            property int briSteps: 20      // brightness from the keys: divisions per scale, 40/20/10 -- step 2.5/5/10 %
            property bool quickHover: true // quick settings on hover at the right edge
            property bool deckHover: true  // deck -- bottom-center panel, slides out on hovering the edge
            property bool genie: true      // minimise warps the window into the deck's minimised section (genie/Genie.qml); off -- a plain park
            // ---- the feature programme: one persisted toggle per feature (prefs FEATURES). Off -- the feature is fully inert ----
            property bool featGenieBack: true  // restore expands the park-time snapshot back out of the minimised section (genie/Genie.qml)
            property bool featEdges: true      // reactive glyph edges: music VU, charging fill, focus drain (glyph/Glyph.qml)
            property bool featExpose: true     // all-windows exposé of the current desktop (expose/Expose.qml)
            property bool featLockMedia: true  // media controls + notification summary on the session lock (lock/LockFace.qml)
            property bool featEssential: false // essential notifications: only the picked apps light the edges (Notes.qml); off by default -- it changes notification behaviour
            property var essentialApps: []     // desktop entry ids picked in prefs FEATURES
            property var peek: []              // latest notifications [{ app, summary }] -- written by Notes, read by the lock face
            property bool featLauncher: true   // launcher smarts in apps mode: maths, conversions, kill, files (launcher/Launcher.qml)
            property bool featFocus: true      // focus timer as a bar tray widget (bar/Bar.qml); the timer itself also lives in cal/Cal.qml
            property int themeMode: 0          // 0 -- manual (the light field above decides), 1 -- auto on the schedule below
            property int lightAt: 420          // auto: light from 07:00 -- minutes after midnight, edited in prefs LOOK
            property int darkAt: 1140          // auto: dark from 19:00
            property bool featDesktops: true   // per-desktop names + wallpapers (prefs DESKTOPS)
            property var wsNames: ({})         // desktop id (as string) -> name; missing -- just the number
            property var wsWalls: ({})         // desktop id (as string) -> wallpaper path; missing/"" -- the global wall above
            property bool featShot: true       // shot: grab text (OCR) and scan QR modes (shot/Shot.qml)
            property string avatar: ""         // profile photo: the copy in the state dir; "" -- the dotted face (lock/LockFace.qml)
            property var deck: ["clock", "weather", "perf", "net", "media", "min"] // its sections in order, see decks
            property var bar: ["layout", "wifi", "bluetooth", "sound", "notes", "focus", "battery", "mode", "power"] // bar tray from top to bottom, see bars
            property bool barTitle: true   // window title stacked in the bar
            // recording (quick/Rec, Sys.recArgs)
            property int recArea: 0        // 0 whole monitor, 1 region (slurp)
            property int recAudio: 0       // 0 no sound, 1 system, 2 microphone, 3 both on one track
            property int recFps: 60
            property int recQuality: 2     // medium, high, very_high, ultra
            property bool recCursor: true
            property bool vpnPortal: false // tunnel taken down for a captive portal, restore it in the open (vpn/Vpn)
            property bool audioMeter: false // AUDIO page level meter: PwNodePeakMonitor crashes quickshell 0.3.0, so it is opt-in for 0.3.1+
            property var screens: ({})     // per-screen own settings by monitor model (Theme.sid): { bar, home, widgets, wall }
        }
    }

    // bento widgets: id -> width in cells (3-column x 3-row grid, 220 each). Does not fit -- not shown
    readonly property var kinds: ({ weather: 1, calendar: 1, cpu: 1, ram: 1, gpu: 1, disk: 1, battery: 1, buds: 1, player: 2, system: 3, cat: 1, cava: 1 })
    // deck sections
    readonly property var decks: ["clock", "weather", "perf", "net", "media", "min"]
    // bar tray
    readonly property var bars: ["layout", "wifi", "bluetooth", "sound", "notes", "focus", "battery", "mode", "power"]

    // ---- the look of everything outside the shell. Called only by shell.qml: at startup and on theme change ----
    // hypr inherits from demonshot: monitor, input, idle, night light and motion are set by its Rules (shell.qml), animations -- from the
    // hypr config. From here -- gaps/border/blur/shadows from its rules.json, while glyph's own -- border colors, shadows, groups, background and
    // rounding 20 (without them the red glow and demonshot groups from hypr/variables.lua would remain).
    // Back to demonshot: `rice switch` runs hyprctl reload, its applyAll repaints
    function hypr(lua) { Quickshell.execDetached(["hyprctl", "eval", lua]); }

    // kitty includes this file after its own colors (include in kitty.conf); demonshot writes its palette there too
    FileView { id: kitty; path: Quickshell.env("HOME") + "/.config/demonshot/kitty.conf"; printErrors: false }
    // 16 ANSI from the concept: pastel only for the terminal. In the light theme 0<->15 and 7<->8, so white is not lost on white
    readonly property var ansi: ["#0E0E0E", "#D71921", "#9BB59A", "#D9C38A", "#8EA3C2", "#B79BC2", "#8FB8B8", "#C9C9C9",
                                 "#4A4A4A", "#F0434B", "#B5CCB4", "#E8D6A8", "#AABBD4", "#CDB6D6", "#ABCDCD", "#F2F2F2"]

    function apply() {
        // game mode (Rules.store.game) -- on top of the settings, like ultra: border 1, no gaps or rounding, tearing for
        // windows with immediate (games, hyprland/rules.lua). Exit -- your values return, allow_tearing -- false, as in general.lua
        const r = Rules.store, g = r.game;
        const c = x => `"rgb(${hex(x)})"`;
        // shadow: in dark -- a barely visible white glow, in light -- a soft black
        const shadow = light ? "rgba(0000002E)" : `rgba(${hex(fg)}1A)`;
        hypr(`hl.config({ general = { gaps_in = ${g ? 0 : r.gapsIn}, gaps_out = ${g ? 0 : r.gapsOut}, border_size = ${g ? 1 : r.border}, allow_tearing = ${g}, `
           + `col = { active_border = ${c(fg)}, inactive_border = ${c(s3)} } }, `
           + `decoration = { rounding = ${g ? 0 : st.rounding}, blur = { enabled = ${Rules.blurOn} }, shadow = { enabled = ${Rules.shadowOn}, color = "${shadow}" } }, `
           + `group = { col = { border_active = ${c(fg)}, border_inactive = ${c(s3)}, border_locked_active = ${c(fg)}, border_locked_inactive = ${c(mute)} }, `
           + `groupbar = { font_family = "${mono}", text_color = ${c(fg)}, col = { active = ${c(s3)}, inactive = ${c(s1)}, locked_active = ${c(s3)}, locked_inactive = ${c(s1)} } } }, `
           + `misc = { background_color = ${c(bg)} } })`);

        const a = light ? [15, 1, 2, 3, 4, 5, 6, 8, 7, 9, 10, 11, 12, 13, 14, 0].map(i => ansi[i]) : ansi;
        kitty.setText("# glyph: written by Theme.apply(), do not edit by hand\n" + [
            ["font_family", "Space Mono"], ["window_padding_width", "26 30"], ["cursor_trail", "0"],
            ["foreground", fg], ["background", s1], ["cursor", fg], ["cursor_text_color", s1],
            ["selection_foreground", fg], ["selection_background", s3], ["url_color", grey],
            ["active_border_color", fg], ["inactive_border_color", s3],
            ["active_tab_foreground", ink], ["active_tab_background", fg],
            ["inactive_tab_foreground", grey], ["inactive_tab_background", s1], ["tab_bar_background", bg]
        ].concat(a.map((c, i) => ["color" + i, c])).map(([k, v]) => `${k} ${typeof v === "string" ? v : v.toString().slice(0, 7).toUpperCase()}`).join("\n") + "\n");
        Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"]);
    }
}
