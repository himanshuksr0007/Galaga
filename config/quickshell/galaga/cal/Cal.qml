import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// Calendar and focus timer: click the bar clock. The top card expands from that clock.
// Month as a 7x6 grid (today -- white circle), arrows and left/right scroll, click on the month -- back to today. Below the timer:
// ring of dots fills clockwise, minute presets, start/pause (and space), reset. While running -- Galaga fills the bottom strip.
// Esc or click outside -- close
PanelWindow {
    id: root

    property bool open: false
    function toggle() { open = !open; }
    function close() { open = false; }
    property int shift: 0 // months from the current one
    onOpenChanged: if (open) shift = 0

    property PanelWindow triggerBar
    property alias popoverOrigin: entrance.origin
    readonly property alias t: entrance.progress
    PopoverMotion { id: entrance; opened: root.open }

    visible: open || t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
        : entrance.continuous ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "galaga-cal"
    mask: Region {
        item: root.open && entrance.continuous ? panel : null
        width: root.open && !entrance.continuous ? root.width : 0
        height: root.open && !entrance.continuous ? root.height : 0
    }
    HyprlandFocusGrab {
        windows: root.triggerBar ? [root, root.triggerBar] : [root]
        active: entrance.continuous && root.open && root.visible
        onCleared: if (root.open) root.close()
    }

    SystemClock { id: clock; precision: SystemClock.Hours }
    readonly property var en: Qt.locale("en_US")
    readonly property var month: new Date(clock.date.getFullYear(), clock.date.getMonth() + shift, 1)
    readonly property int lead: (month.getDay() + 6) % 7 // days of the previous month before Monday

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: entrance.continuous ? root.triggerBar?.exclusiveZone ?? 0 : 0
        color: "#000000"
        opacity: 0.35 * (entrance.continuous ? entrance.content : root.t)
        MouseArea { anchors.fill: parent; enabled: root.open && !entrance.continuous; onClicked: root.close() }
    }

    Stage {
        PopoverCard {
            id: panel
            motion: entrance
            unit: Theme.s
            readonly property real off: entrance.continuous ? 92 : 92 - 24 * (1 - root.t)
            readonly property bool onTop: Theme.state.barAt === "top"
            x: onTop ? (parent.width - width) / 2 : off
            y: onTop ? off : (parent.height - height) / 2
            width: 440
            height: col.height + 52
            focus: true
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_Left) root.shift--;
                else if (e.key === Qt.Key_Right) root.shift++;
                else if (e.key === Qt.Key_Space) Focus.toggle();
                else return;
                e.accepted = true;
            }
            MouseArea { anchors.fill: parent } // clicking the panel does not close it

            Column {
                id: col
                x: 26
                y: 26
                width: parent.width - 52
                spacing: 18

                Item {
                    width: parent.width
                    height: 44
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Num { anchors.verticalCenter: parent.verticalCenter; text: root.en.standaloneMonthName(root.month.getMonth(), Locale.ShortFormat); font.pixelSize: 44 }
                        Lb { anchors.verticalCenter: parent.verticalCenter; text: root.month.getFullYear() }
                        TapHandler { onTapped: root.shift = 0 }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Round { icon: "\u{F0141}"; onClicked: root.shift-- }
                        Round { icon: "\u{F0142}"; onClicked: root.shift++ }
                    }
                }

                Grid {
                    width: parent.width
                    columns: 7
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        Text {
                            required property string modelData
                            width: col.width / 7
                            height: 28
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font { family: Theme.mono; pixelSize: 11 }
                            color: Theme.grey
                        }
                    }
                    Repeater {
                        model: 42
                        Item {
                            id: day
                            required property int index
                            readonly property var d: new Date(root.month.getFullYear(), root.month.getMonth(), index - root.lead + 1)
                            readonly property bool own: d.getMonth() === root.month.getMonth()
                            readonly property bool today: d.toDateString() === clock.date.toDateString()
                            width: col.width / 7
                            height: 46
                            Rectangle { anchors.centerIn: parent; visible: day.today; width: 38; height: 38; radius: 19; color: Theme.fg }
                            Text {
                                anchors.centerIn: parent
                                text: day.d.getDate()
                                font { family: Theme.mono; pixelSize: 14 }
                                color: day.today ? Theme.ink : !day.own ? Theme.mute : day.index % 7 > 4 ? Theme.grey : Theme.fg
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.s2 }

                Row {
                    spacing: 24
                    Item {
                        width: 164
                        height: 164
                        Ring { anchors.fill: parent; n: 44; dot: 5; f: Focus.f }
                        Column {
                            anchors.centerIn: parent
                            Num { anchors.horizontalCenter: parent.horizontalCenter; text: Focus.mmss(Focus.left); font.pixelSize: 38 }
                            Lb {
                                anchors.horizontalCenter: parent.horizontalCenter
                                topPadding: 10
                                text: Focus.running ? "focus" : Focus.paused ? "paused" : "ready"
                                color: Focus.running ? Theme.fg : Theme.grey
                                px: 10
                            }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 16
                        Lb { text: "focus · min" }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [15, 25, 45, 60]
                                Rectangle {
                                    id: chip
                                    required property int modelData
                                    readonly property bool on: Focus.minutes === modelData
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: on ? Theme.fg : chipHov.hovered ? Theme.s3 : Theme.s2
                                    Text { anchors.centerIn: parent; text: chip.modelData; font { family: Theme.mono; pixelSize: 13 } color: chip.on ? Theme.ink : Theme.fg }
                                    HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Focus.set(chip.modelData) }
                                }
                            }
                        }
                        Row {
                            spacing: 10
                            Rectangle {
                                width: 146
                                height: 44
                                radius: Theme.corner(22)
                                color: Focus.running ? Theme.s2 : Theme.fg
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Icon { anchors.verticalCenter: parent.verticalCenter; text: Focus.running ? "\u{F03E4}" : "\u{F040A}"; color: Focus.running ? Theme.fg : Theme.ink }
                                    Lb {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Focus.running ? "pause" : Focus.paused ? "resume" : "start"
                                        color: Focus.running ? Theme.fg : Theme.ink
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Focus.toggle() }
                            }
                            Round { icon: "\u{F0450}"; opacity: Focus.running || Focus.paused ? 1 : 0.4; onClicked: Focus.reset() }
                        }
                    }
                }
            }
        }
    }

    component Round: Rectangle {
        property string icon
        signal clicked
        width: 44
        height: 44
        radius: 22
        color: Theme.s2
        Icon { anchors.centerIn: parent; text: parent.icon }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
    }
}
