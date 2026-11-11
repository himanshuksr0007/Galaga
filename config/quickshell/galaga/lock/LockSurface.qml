import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

// the session-lock surface: a thin shell around LockFace -- the face itself is shared
// with the greeter (greet.qml), which draws the same pixels over a Greetd backend
WlSessionLockSurface {
    id: root

    required property var auth // { buffer, fail, busy, leaving, submit() } from lock.qml
    property string layout: "en"

    color: Theme.bg

    // one screen (prefs LOOK): the screen in focus at lock time gets the face, the others a plain
    // cover (SenulMapa's idea, AMM021's port). Once, not a binding: moving the cursor mustn't swap
    // them. Typing works from any screen, the buffer is shared through auth
    property string mainName: ""
    readonly property bool primary: !Theme.state.lockOneScreen || !mainName || screen?.name === mainName
    Component.onCompleted: mainName = Hyprland.focusedMonitor?.name ?? ""

    LockFace {
        anchors.fill: parent
        auth: root.auth
        layout: root.layout
        session: true // the session lock: media controls + notification summary (the greeter leaves this off)
        photo: Theme.state.avatar ? "file://" + Theme.state.avatar : ""
        wallPath: Theme.scr(root.screen?.name, "wall") // each screen locks over its own wallpaper
    }

    Rectangle { anchors.fill: parent; color: Theme.bg; visible: !root.primary }
}
