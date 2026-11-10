pragma Singleton

import QtQuick
import Quickshell
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
                                   lock: "soundSys", unlock: "soundSys", shot: "soundSys", charge: "soundSys" })
    readonly property var gaps: ({ pop: 150, tick: 90, notify: 400, lock: 250, unlock: 250, shot: 250, charge: 500 })
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
}
