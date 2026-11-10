import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "lock"

// lock -- a separate process, as in demonshot: qs -p .../glyph/lock.qml (called by `rice lock`). Unlocked -- we exit.
// Shell crashed -- the lock lives; lock crashed -- Hyprland keeps the screen covered, SUPER+ALT+L starts it again
ShellRoot {
    id: shell
    // hot-reload recreates WlSessionLock: the old one dies, the process hangs without a screen
    settings.watchFiles: false

    QtObject {
        id: gate
        property string buffer: ""
        property bool fail: false
        property string msg: "" // the greeter fills this from pam; the lock's PamContext reports only a result
        property bool leaving: false // password accepted: the surface finishes the exit, then unlockT releases the lock
        readonly property bool busy: pam.active
        function submit() {
            if (!buffer || pam.active || leaving) return;
            pam.start();
        }
    }

    PamContext {
        id: pam
        config: "lock"
        configDirectory: Quickshell.shellPath("pam")
        onResponseRequiredChanged: if (responseRequired) respond(gate.buffer)
        onCompleted: res => {
            gate.buffer = "";
            if (res === PamResult.Success) {
                gate.leaving = true;
                unlockT.start();
            } else gate.fail = true;
        }
    }
    Timer { id: unlockT; interval: 470; onTriggered: lock.locked = false }

    property string layout: "en"
    function short(name) { return name.slice(0, 2).toLowerCase(); }
    Process {
        running: true
        command: ["sh", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .active_keymap'"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) shell.layout = shell.short(text.trim()) }
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "activelayout") shell.layout = shell.short(e.data.split(",").pop()); }
    }

    WlSessionLock {
        id: lock
        locked: true
        // ponytail: lockedChanged does not arrive after locked = false (quickshell 0.3.2), and secure crashes -- we exit on it
        onSecureChanged: if (!secure) Qt.quit()

        LockSurface { auth: gate; layout: shell.layout }
    }
}
