pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs

// interface sounds: short synthesized blips (assets/sounds, tools/make_sounds.py)
// for the moments that deserve a whisper of feedback -- panels opening, the
// volume keys, a screenshot landing, the charger, a notification, the lock.
// play(name) is the only door. It answers to Theme.state: the master switch
// (sounds), a category per sound (soundUi / soundAlerts / soundSys), and it
// stays quiet over a fullscreen game -- except the lock pair: locking is
// never gameplay. Each sound also has a minimum gap, so a dragged slider
// ticks like a ratchet instead of a machine gun.
// Playback itself lives in SoundFx.qml behind a Loader: QtMultimedia is a
// separate package, and if it is missing the Loader fails and every play()
// is a silent no-op -- the shell never breaks over a sound.
Singleton {
    id: root

    // shell.qml binds this to Game.playing. The lock process never binds it
    // (and the lock pair is exempt anyway): each process has its own Sounds
    property bool gameQuiet: false
    readonly property bool ready: fx.status === Loader.Ready && !!fx.item

    Loader { id: fx; source: "SoundFx.qml" }

    readonly property var cats: ({ pop: "soundUi", tick: "soundUi", notify: "soundAlerts",
                                   lock: "soundSys", unlock: "soundSys", shot: "soundSys", charge: "soundSys",
                                   close: "soundUi", briup: "soundUi", bridown: "soundUi" })
    readonly property var gaps: ({ pop: 150, tick: 90, notify: 400, lock: 250, unlock: 250, shot: 250, charge: 500,
                                   close: 300, briup: 90, bridown: 90 })
    property var last: ({})

    function play(name) {
        if (!ready || !Theme.state.sounds) return;
        const cat = cats[name];
        if (!cat || !Theme.state[cat]) return;
        if (gameQuiet && name !== "lock" && name !== "unlock") return;
        const now = Date.now();
        if (now - (last[name] ?? 0) < gaps[name]) return;
        last = Object.assign({}, last, { [name]: now });
        fx.item.play(name);
    }

    // the window-close edge, watched here because every close path (the bar's
    // red disc, a keybind, the deck's menu, the app quitting itself) ends at
    // the same place: a toplevel that was here is gone. The map keeps each
    // window's class so the shell's own windows and classless X popups (menus,
    // tooltips) close silently. Parking a window keeps its toplevel -- a
    // minimise never sounds like a close.
    readonly property var tlNow: Hyprland.toplevels.values
    property var tlPrev: ({})
    onTlNowChanged: {
        const cur = {};
        for (const t of tlNow) cur[t.address] = t.lastIpcObject?.class ?? "";
        let gone = false;
        for (const a in tlPrev)
            if (!(a in cur) && tlPrev[a] && tlPrev[a] !== "org.quickshell") gone = true;
        tlPrev = cur;
        if (gone) play("close");
    }
}
