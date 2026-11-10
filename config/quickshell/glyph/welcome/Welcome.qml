import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.components

// first-login card: the keys to know (AMM021's welcome card; the list below is this fork's
// own bindings). Once "got it" is pressed it stays away (Theme.state.welcomed);
// settings -> FEATURES brings it back
PanelWindow {
    id: root

    readonly property var keys: [
        ["Super", "launcher"], ["Super + Space", "deck · the bottom dashboard"],
        ["Super + T", "terminal"], ["Super + W", "browser"],
        ["Super + E", "files"], ["Super + I", "settings"],
        ["Super + A", "quick settings"], ["Super + Tab", "desktops overview"],
        ["Super + `", "exposé · this desktop's windows"], ["Super + Shift + W", "wallpapers"],
        ["Super + V", "clipboard"], ["Super + Period", "emoji and symbols"],
        ["Super + Shift + S", "screenshot"], ["Super + Q", "close a window"],
        ["Super + Alt + M", "minimise · back from the deck"], ["Super + 1…9", "go to a desktop"],
        ["3-finger swipe", "desktops · overview · desktop"], ["Super + L", "lock"],
        ["Super + Esc", "power menu"]
    ]

    property bool ready: false
    property bool leaving: false // dismissed: the card glides out first, welcomed lands when it has
    Timer { running: true; interval: 1500; onTriggered: root.ready = true } // after the login settles
    property real t: ready && !leaving ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    function done() {
        if (leaving) return;
        leaving = true;
        bye.restart();
    }
    // welcomed unloads this window (shell.qml's LazyLoader), so it is only set
    // once the fade has run -- setting it in done() cut the card off mid-air
    Timer { id: bye; interval: 380; onTriggered: Theme.state.welcomed = true }

    visible: ready
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "glyph-welcome"

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: root.t }

    Stage {
        id: stage
        focus: true
        Keys.onPressed: e => {
            if (e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter) return;
            root.done();
            e.accepted = true;
        }

        Rectangle {
            x: (stage.width - width) / 2
            y: (stage.height - height) / 2 + 24 * (1 - root.t)
            width: 1120
            height: body.height + 96
            radius: Theme.corner(44)
            opacity: root.t
            color: Theme.s1
            border { width: 1; color: Theme.s2 }

            Column {
                id: body
                x: 56
                y: 48
                width: parent.width - 112
                spacing: 28

                Row {
                    spacing: 24
                    Ring { width: 64; height: 64; n: 16; dot: 4; f: 1 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Num { text: "glyph"; font.pixelSize: 44 }
                        Lb { text: "the keys to know" }
                    }
                }

                Grid {
                    columns: 2
                    columnSpacing: 40
                    rowSpacing: 12
                    Repeater {
                        model: root.keys
                        Item {
                            required property var modelData
                            width: 484
                            height: 34
                            Rectangle {
                                id: cap
                                anchors.verticalCenter: parent.verticalCenter
                                width: capL.implicitWidth + 24
                                height: 32
                                radius: Theme.corner(16)
                                color: Theme.s2
                                Lb { id: capL; anchors.centerIn: parent; text: parent.parent.modelData[0]; px: 11; color: Theme.fg }
                            }
                            Text {
                                anchors { left: cap.right; leftMargin: 16; right: parent.right; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: parent.modelData[1]
                                font { family: Theme.ui; pixelSize: 17 }
                                color: Theme.grey
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 64
                    Lb { anchors.verticalCenter: parent.verticalCenter; text: "this card again: super + i → features" }
                    // the got-it pill (AMM021's Act, inlined -- prefs has no Act here)
                    Rectangle {
                        anchors.right: parent.right
                        width: gotL.implicitWidth + 88
                        height: 64
                        radius: Theme.corner(32)
                        color: Theme.s2
                        Rectangle {
                            x: 6
                            y: 6
                            width: 52
                            height: 52
                            radius: 26
                            color: Theme.s3
                            Icon { anchors.centerIn: parent; text: "\u{F012C}"; font.pixelSize: 22 }
                        }
                        Lb { id: gotL; x: 70; anchors.verticalCenter: parent.verticalCenter; text: "got it"; color: Theme.fg }
                        MouseArea { anchors.fill: parent; onClicked: root.done() }
                    }
                }
            }
        }
    }
}
