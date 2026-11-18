pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// the pairing agent (bt-agent.py, beside shell.qml): quickshell
// registers no agent with bluez, and bluez completes no bond
// without an agent somewhere -- an unpaired device then connects
// as a bare radio link, no audio profile, nothing stored. The
// shell runs the agent for its whole life and restarts it when it
// exits, so pairing lives exactly as long as the shell does. The
// agent itself re-registers whenever bluetoothd restarts.
Singleton {
    id: root

    readonly property bool on: true

    Process {
        id: proc
        command: ["python3", Quickshell.configDir + "/bt-agent.py"]
        running: true
        onExited: backoff.restart()
    }
    Timer { id: backoff; interval: 3000; onTriggered: proc.running = true }
}
