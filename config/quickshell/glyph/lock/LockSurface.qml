import QtQuick
import Quickshell.Wayland
import qs

// the session-lock surface: a thin shell around LockFace -- the face itself is shared
// with the greeter (greet.qml), which draws the same pixels over a Greetd backend
WlSessionLockSurface {
    id: root

    required property var auth // { buffer, fail, busy, leaving, submit() } from lock.qml
    property string layout: "en"

    color: Theme.bg

    LockFace {
        anchors.fill: parent
        auth: root.auth
        layout: root.layout
        photo: Theme.state.avatar ? "file://" + Theme.state.avatar : ""
    }
}
