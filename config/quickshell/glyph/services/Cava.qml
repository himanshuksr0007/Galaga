pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// cava in the background while someone is watching: consumers register by name (home's
// Glyph Matrix, the glyph edges' VU) and one process serves them all -- it runs only
// while at least one is registered. 8 mono bands 0...1, from bass to highs (cava.conf)
Singleton {
    id: root

    property var users: ({})
    readonly property bool active: Object.keys(users).length > 0
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
            onRead: line => root.bars = line.split(";").filter(s => s !== "").map(v => v / 100)
        }
        onRunningChanged: if (!running) root.bars = Array(8).fill(0)
    }
}
