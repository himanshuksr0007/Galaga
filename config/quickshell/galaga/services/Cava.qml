pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// cava in the background while someone is watching: consumers register by name (home's
// Glyph Matrix, the galaga edges' VU) and one process serves them all -- it runs only
// while at least one is registered. 8 mono bands 0...1, from bass to highs (cava.conf)
Singleton {
    id: root

    property var users: ({})
    // a fullscreen game (services/Game) stops cava too: no FFT to pay for mid-game
    readonly property bool active: Object.keys(users).length > 0 && !Game.playing
    function use(name, on) {
        if (!!users[name] === on) return;
        const u = Object.assign({}, users);
        if (on) u[name] = true; else delete u[name];
        users = u;
    }
    property var bars: Array(8).fill(0)

    Process {
        running: root.active
        command: ["cava", "-p", Qt.resolvedUrl("cava.conf").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(s => s !== "").map(s => Number(s) / 100);
                // a cava that can't open its input (PipeWire not up yet at login) prints only its title
                // escape "\e]0;cava\a": NaN bars would stick in consumers' running averages for good and
                // paint derived levels black (Isaqdn03's find) -- such a frame is skipped, bars stay
                if (!v.length || v.some(x => !isFinite(x))) return;
                root.bars = v;
            }
        }
        onRunningChanged: if (!running) root.bars = Array(8).fill(0)
    }
}
