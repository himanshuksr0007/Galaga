import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// features: one persisted switch per feature of the programme; off -- the
// feature is fully inert. The detailed controls live with their feature:
// theme and its times on appearance, desktop names and walls on desktop &
// deck, the profile photo on lock, essential notifications on notifications.
// The shell's own identity sits on top: its name from rice.json (the same one
// the Rice app draws), the switcher when there is something to switch to,
// reload, and do not disturb.
Item {
    id: pg

    property bool active: false
    signal closeRequested

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    // name and tagline of the current shell -- from its rice.json
    property var meta: ({})
    FileView { path: Quickshell.shellPath("rice.json"); onLoaded: try { pg.meta = JSON.parse(text()); } catch (e) {} }
    // "switch shell" -- only when there is something to choose from: other
    // shells, folders with rice.json nearby (Demon's Shot...)
    property int shells: 1
    Process {
        running: pg.active
        command: [Quickshell.env("HOME") + "/.config/quickshell/rice/rice", "list"]
        stdout: StdioCollector { onStreamFinished: pg.shells = text.trim().split("\n").length }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 22

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "shell" }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 18
                        Item {
                            width: 64
                            height: 64
                            Ring { anchors.fill: parent; n: 16; dot: 6; f: 1 }
                            Rectangle { anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: Theme.fg }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Lb { text: "running now"; px: 10.5 }
                            Num { text: pg.meta.name ?? "GALAGA"; font.pixelSize: 34 }
                            Lb { visible: !!pg.meta.tagline; text: pg.meta.tagline ?? ""; px: 10.5 }
                        }
                    }
                    SetToggle {
                        label: "do not disturb"
                        on: Theme.state.dnd
                        onFlip: want => Theme.state.dnd = want
                    }
                    Item { width: 1; height: 14 }
                    Row {
                        spacing: 10
                        SetButton {
                            visible: pg.shells > 1
                            label: "switch shell"
                            onHit: {
                                pg.closeRequested();
                                Quickshell.execDetached(["qs", "-c", "rice"]);
                            }
                        }
                        SetButton { label: "reload"; onHit: Quickshell.reload(false) }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "genie" }
                SetCard {
                    SetToggle { label: "genie · minimise"; on: Theme.state.genie; onFlip: want => Theme.state.genie = want }
                    SetToggle { label: "genie · restore"; on: Theme.state.featGenieBack; divider: false; onFlip: want => Theme.state.featGenieBack = want }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "interface" }
                SetCard {
                    SetToggle { label: "reactive edges"; on: Theme.state.featEdges; onFlip: want => Theme.state.featEdges = want }
                    SetToggle { label: "exposé"; on: Theme.state.featExpose; onFlip: want => Theme.state.featExpose = want }
                    SetToggle { label: "launcher smarts"; on: Theme.state.featLauncher; onFlip: want => Theme.state.featLauncher = want }
                    SetToggle { label: "focus in bar"; on: Theme.state.featFocus; onFlip: want => Theme.state.featFocus = want }
                    SetToggle { label: "named desktops"; on: Theme.state.featDesktops; divider: false; onFlip: want => Theme.state.featDesktops = want }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "system" }
                SetCard {
                    SetToggle { label: "shot text + qr"; on: Theme.state.featShot; onFlip: want => Theme.state.featShot = want }
                    SetToggle { label: "auto game mode"; on: Theme.state.featGameAuto; onFlip: want => Theme.state.featGameAuto = want }
                    SetToggle {
                        label: "sounds"
                        on: Theme.state.sounds
                        divider: false
                        onFlip: want => { Theme.state.sounds = want; if (want) Sounds.play("pop"); }
                    }
                }
            }

            // the first-login card (welcome/Welcome.qml): bring it back
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "welcome card" }
                SetCard {
                    SetRow {
                        label: "welcome card"
                        sub: "the keys, once more"
                        divider: false
                        SetButton {
                            label: "show"
                            onHit: {
                                Theme.state.welcomed = false;
                                pg.closeRequested();
                            }
                        }
                    }
                }
            }
        }
    }
}
