pragma Singleton

import Quickshell
import Quickshell.Services.UPower
import QtQuick
import qs
import qs.settings

// battery saver on battery, by itself (prefs -> POWER -> auto saver on battery; Rules.store.powerAuto). Unplug --
// the mode you had is kept in Theme.state.powerHold and battery saver (Rules.setMode 0) takes over; plug back
// in -- the kept mode returns. Same discipline as services/Game: the hold lives in Theme.state, so a
// shell restart mid-hold still puts the mode back (the settle below), and taking a mode by hand while
// on battery clears the hold -- you took over, nothing overrides you at plug-in. Switching the pref
// off while it holds restores your mode at once; switching it on while already unplugged engages now.
// No laptop battery (a desktop, a UPS) -- never engages. The mode itself is all Rules: the daemon's
// profile persists in the daemon, the saver flag in rules.json, so what this adds is only the edges.
Singleton {
    id: root

    readonly property bool on: Theme.state.powerHold !== null && Theme.state.powerHold !== undefined
    readonly property bool laptop: UPower.displayDevice?.isLaptopBattery ?? false

    // startup, once things have settled (UPower's device and the daemon's profile need a moment to
    // be the real ones -- the mode recorded now is the mode restored later): a hold left over from
    // before a restart on the charger is put back; a fresh boot on battery engages
    Timer {
        id: settle
        interval: 2000
        running: true
        onTriggered: root.on ? (UPower.onBattery || root.restore()) : root.engage()
    }

    Connections {
        target: UPower
        function onOnBatteryChanged() { UPower.onBattery ? root.engage() : root.restore(); }
    }
    // you picked another mode on battery -- yours now, the plug-in restore is off. Ultra itself
    // (mode 0, what engage sets) doesn't count; an outside change (powerprofilesctl in a terminal)
    // is a pick like any other
    Connections {
        target: Rules
        function onModeChanged() { if (root.on && UPower.onBattery && Rules.mode !== 0) Theme.state.powerHold = null; }
    }
    Connections {
        target: Rules.store
        function onPowerAutoChanged() {
            if (Rules.store.powerAuto) root.engage();
            else if (root.on) UPower.onBattery ? root.restore() : Theme.state.powerHold = null;
        }
    }

    function engage() {
        settle.stop();
        if (!Rules.store.powerAuto || root.on || !root.laptop || !UPower.onBattery) return;
        Theme.state.powerHold = { mode: Rules.mode };
        Rules.setMode(0);
    }
    function restore() {
        settle.stop();
        const was = Theme.state.powerHold;
        if (!was) return;
        Theme.state.powerHold = null;
        Rules.setMode(was.mode);
    }
}
