import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// power menu: Super+Esc, the bar's power button, and alt+f4 on the desktop (scripts/altf4.sh, over ipc below). Screen almost black, on the left a column of Doto words: selected large with a red dot, the rest Mute.
// up/down -- the word smoothly grows and shrinks. On the right a ring of 60 dots: uptime (fraction of a six-hour shift)
PanelWindow {
    id: root

    property int sel: 2
    readonly property var items: [
        ["LOCK", () => Quickshell.execDetached([Quickshell.env("HOME") + "/.config/quickshell/rice/rice", "lock"])],
        ["SLEEP", () => Quickshell.execDetached(["systemctl", "suspend"])],
        ["SHUT DOWN", () => Quickshell.execDetached(["systemctl", "poweroff"])],
        ["REBOOT", () => Quickshell.execDetached(["systemctl", "reboot"])],
        ["LOG OUT", () => Hyprland.dispatch("hl.dsp.exit()")]
    ]

    // entrance like the other surfaces (launcher, charms): scrim fades in,
    // content rises a little and fades with it -- instead of popping in whole
    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function open() {
        sel = 2;
        SysStats.sample(); // fresh uptime
        shown = true;
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }

    // scripts/altf4.sh: shown -- so the script can close the menu instead of the
    // window under it; toggle -- the desktop branch, the same as Super+Esc
    IpcHandler {
        target: "power"
        function toggle(): string { root.toggle(); return root.shown ? "open" : "shut"; }
        function shown(): bool { return root.shown; }
    }
    function accept() {
        close();
        items[sel][1]();
    }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-power"

    Rectangle {
        anchors.fill: parent
        color: Theme.fade(Theme.bg, 0.96)
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.sel = (root.sel + 4) % 5;
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Tab) root.sel = (root.sel + 1) % 5;
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.accept();
            else if (e.key === Qt.Key_Escape) root.close();
            else return;
            e.accepted = true;
        }

        Column {
            x: 240
            anchors.verticalCenter: parent.verticalCenter
            spacing: 26
            opacity: root.t
            transform: Translate { y: 24 * (1 - root.t) }
            Repeater {
                model: root.items
                Row {
                    id: it
                    required property var modelData
                    required property int index
                    readonly property bool on: root.sel === index
                    spacing: 30
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: it.on
                        width: 30
                        height: 30
                        radius: 15
                        color: Theme.red
                    }
                    Num {
                        text: it.modelData[0]
                        font.pixelSize: it.on ? 168 : 66
                        color: it.on ? Theme.fg : Theme.mute
                        Behavior on font.pixelSize { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                    }
                    HoverHandler { onHoveredChanged: if (hovered) root.sel = it.index }
                    TapHandler { onTapped: { root.sel = it.index; root.accept(); } }
                }
            }
        }

        Item {
            x: stage.width - 200 - 460
            anchors.verticalCenter: parent.verticalCenter
            width: 460
            height: 460
            opacity: root.t
            Ring { anchors.fill: parent; n: 60; dot: 10; f: SysStats.uptime / (6 * 3600) }
            Column {
                anchors.centerIn: parent
                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: "uptime" }
                Num {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: lead + 10
                    bottomPadding: lead + 10
                    text: `${Math.floor(SysStats.uptime / 3600)}:${String(Math.floor(SysStats.uptime / 60) % 60).padStart(2, "0")}`
                    font.pixelSize: 110
                }
                Lb {
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property int n: Hyprland.toplevels.values.length
                    text: `${n} window${n === 1 ? "" : "s"} open`
                }
            }
        }

        Row {
            x: 240
            anchors { bottom: parent.bottom; bottomMargin: 70 }
            spacing: 34
            opacity: root.t
            Lb { text: "↑↓ select" }
            Lb { text: "↵ confirm" }
            Lb { text: "esc cancel" }
        }
    }
}
