pragma Singleton

import QtQuick
import Quickshell

// the bridge between the deck and the genie. Genie.qml registers its handlers here at
// startup; the deck's minimised rows offer restores to the genie first (it kept the
// park-time snapshot and can expand it back) and fall back to the plain move when the
// handler is absent or answers false. drop: the deck closed a parked window -- its
// kept snapshot can go.
Singleton {
    property var handler: null // (address, workspaceId) -> bool: true -- the genie took the restore
    property var drop: null    // (address) -> void: forget a kept snapshot
}
