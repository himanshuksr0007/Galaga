import QtQuick
import Quickshell
import Quickshell.Hyprland
import "bar"
import "buds"
import "cal"
import "charms"
import "clip"
import "deck"
import "desktops"
import "expose"
import "genie"
import "glyph"
import "home"
import "launcher"
import "power"
import "prefs"
import "quick"
import "settings"
import "shot"
import "vpn"
import "wall"

// glyph: rice in the spirit of nothing os. Home on the wallpaper, bar, launcher, quick settings,
// Glyph strips at the edges instead of OSD, notification island, power menu, settings, deck (bottom dashboard), clipboard, charms (emoji and symbols), screenshots, vpn, wallpapers. Lock -- a separate process (lock.qml).
// Switches from demonshot via `rice switch` / the Rice app -- hypr keybinds are shared (shell:*), each shell takes its own
ShellRoot {
    id: shell

    Launcher { id: launcher }
    Quick { id: quick; onPowerRequested: power.open(); onSettingsRequested: prefs.open() }
    Power { id: power }
    Prefs { id: prefs; onWallRequested: walls.open() }
    Glyph {}
    Buds {}
    Cal { id: cal }
    Clip { id: clip }
    Charms { id: charms }
    Deck { id: deck }
    Desktops { id: desktops }
    Expose { id: expose }
    Genie {}
    Shot { id: shot }
    Vpn { id: vpn }
    Walls { id: walls }

    Variants {
        model: Quickshell.screens
        Scope {
            id: s
            required property var modelData
            Back { screen: s.modelData }
            Home { screen: s.modelData }
            Hot { screen: s.modelData; onTriggered: quick.peek() }
            Bar {
                screen: s.modelData
                onMarkClicked: launcher.toggle()
                onTrayClicked: quick.toggle()
                onPowerClicked: power.toggle()
                onClockClicked: cal.toggle()
            }
        }
    }

    // hypr like demonshot: its Rules (settings/Rules.qml, the same ~/.config/demonshot/rules.json) sets the monitor, input,
    // motion, night light and hypridle; on top Theme.apply -- its own border colors, rounding and kitty. We call it on theme change too
    Component.onCompleted: {
        hypr();
        Rules.night();
        Rules.idle();
        autoTheme();
    }
    // theme auto (prefs LOOK / FEATURES): light between lightAt and darkAt (minutes after
    // midnight; lightAt past darkAt reads as an overnight span, equal -- no switch). It
    // applies through the one machinery everything uses -- state.light, which Theme.apply
    // and the GTK/kitty writers follow. A manual flip (prefs LOOK, quick's dark tile)
    // sets themeMode back to 0, and that choice holds until auto is picked again. The
    // 30 s tick also catches up after suspend or a late login: the first tick that sees
    // the wrong side fixes it.
    function autoTheme() {
        if (Theme.state.themeMode !== 1) return;
        const d = new Date(), m = d.getHours() * 60 + d.getMinutes();
        const L = Theme.state.lightAt, D = Theme.state.darkAt;
        const want = L === D ? Theme.state.light : L < D ? (m >= L && m < D) : (m >= L || m < D);
        if (want !== Theme.state.light) Theme.state.light = want;
    }
    Timer { interval: 30000; repeat: true; running: true; onTriggered: shell.autoTheme() }
    // what lives in the hypr config. It re-reads it itself: save any hypr file (the links are live -- both git pull and branch
    // switch), hyprctl reload -- and it returns the variables.lua defaults: demonshot borders, monitor, input, animations. We apply
    // ours again. hyprctl eval does not send configreloaded -- no loop. Night light and hypridle -- their own processes, reload does not touch them
    function hypr() {
        Rules.monitor();
        Rules.input();
        Rules.motion();
        Theme.apply();
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "configreloaded") shell.hypr(); }
    }
    Connections {
        target: Theme
        function onLightChanged() { Theme.apply(); }
    }
    Connections {
        target: Theme.state
        function onRoundingChanged() { Theme.apply(); }
        function onThemeModeChanged() { shell.autoTheme(); }
        function onLightAtChanged() { shell.autoTheme(); }
        function onDarkAtChanged() { shell.autoTheme(); }
    }
    // ultra mode enables/disables blur and shadows on top of the settings -- repaint windows (refresh rate and motion are set by Rules.setMode itself).
    // Game -- the same plus animations
    Connections {
        target: Rules.store
        function onUltraChanged() { Theme.apply(); }
        function onGameChanged() { Rules.motion(); Theme.apply(); }
    }

    // tap Super -- launcher. Super+<key> swallows and decides when to open, hyprland/keybinds.lua (key polling):
    // the global only gives pressed, without released, so the release is handled on the hypr side
    Shortcut {
        name: "launcher"
        description: "launcher (tap Super)"
        onPressed: launcher.toggle()
    }
    // Super+Space (altar in demonshot) -- deck, bottom dashboard: the launcher is already on tapping Super
    Shortcut { name: "altar"; description: "deck: bottom dashboard"; onPressed: deck.toggle() }
    Shortcut { name: "desktops"; description: "desktops overview"; onPressed: desktops.toggle() }
    Shortcut { name: "expose"; description: "exposé: windows on this desktop"; onPressed: { if (Theme.state.featExpose) expose.toggle(); } }
    Shortcut { name: "quick"; description: "quick settings"; onPressed: quick.toggle() }
    Shortcut { name: "ward"; description: "quick settings"; onPressed: quick.toggle() } // Super+N in demonshot -- same toggles
    Shortcut { name: "settings"; description: "settings"; onPressed: prefs.toggle() }
    Shortcut { name: "power"; description: "power menu"; onPressed: power.toggle() }
    Shortcut { name: "shot"; description: "screenshot"; onPressed: shot.open() }
    Shortcut { name: "pact"; description: "vpn: clash verge"; onPressed: vpn.toggle() }
    Shortcut { name: "clip"; description: "clipboard"; onPressed: clip.toggle() }
    Shortcut { name: "charms"; description: "emoji, kaomoji, symbols"; onPressed: charms.toggle() }
    Shortcut { name: "wall"; description: "wallpapers"; onPressed: walls.toggle() }
    Shortcut { name: "game"; description: "game mode"; onPressed: Rules.store.game = !Rules.store.game }

    component Shortcut: GlobalShortcut { appid: "shell" }
}
