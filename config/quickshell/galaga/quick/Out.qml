import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.components
import qs.services

// audio outputs under the volume slider (right-click it). Tap makes one the default; the slider and
// playing apps follow it. Same rows as Picker. From Isaqdn03/glyph-rice.
// Picks go through Eq: a device with its system eq on is picked with the chain in front of it, and the
// chain's own sink never appears as a row. inspectable (the sound menu) adds a chevron per row that
// asks for the device's page instead of picking it
Rectangle {
    id: root
    signal touched // any click inside pins the panel
    signal inspect(var node)
    property bool inspectable: false

    // unfolds like the Picker and Rec beside it in Quick: grows and fades on t
    // instead of snapping in -- Quick's column rides the height binding, so the
    // whole panel glides with it
    property bool open: false
    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    // [label, icon, order]
    function kind(n) {
        return /^raop_sink/.test(n.name) ? ["airplay", "\u{F0118}", 3]
            : /^bluez_output/.test(n.name) ? ["bluetooth", "\u{F02CB}", 2]
            : /\.usb-/.test(n.name) ? ["usb", "\u{F02CB}", 2]
            : /HDMI/.test(n.name) ? ["hdmi", "\u{F0379}", 1]
            : ["built-in", "\u{F04C3}", 0];
    }
    // "Ryzen HD Audio Controller Speaker" → Speaker; HDMI goes by the monitor's name
    function name(n) {
        if (/HDMI/.test(n.name) && n.nickname) return n.nickname;
        return n.description.replace(/^.*Controller /, "").replace(/ \(.*\)$/, "") || n.nickname || n.name;
    }
    // unplugged HDMI ports stay as sinks; only a connected one carries the monitor's name (ELD) as its nick.
    // ponytail: a monitor that reports no name hides as unplugged
    readonly property var outs: Pipewire.nodes.values
        .filter(n => n.isSink && n.audio && !n.isStream && n.name !== "galaga-eq" && !/^HDMI \d+$/.test(n.nickname))
        .sort((a, b) => kind(a)[2] - kind(b)[2] || name(a).localeCompare(name(b)))

    visible: t > 0
    height: (list.height + 32) * t
    opacity: t
    clip: true
    radius: Theme.corner(30)
    color: Theme.s2

    Column {
        id: list
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 4

        Item {
            width: parent.width
            height: 24
            Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: `outputs · ${root.outs.length}` }
        }

        Repeater {
            model: root.outs
            Rectangle {
                id: row
                required property var modelData
                readonly property var o: modelData
                readonly property bool on: Pipewire.defaultAudioSink === o || Eq.engaged === o
                readonly property var k: root.kind(o)
                width: list.width
                height: 56
                radius: Theme.corner(28)
                color: hov.hovered ? Theme.s3 : "transparent"

                Rectangle {
                    id: ic
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: 22
                    color: row.on ? Theme.fg : Theme.s3
                    Behavior on color { ColorAnimation { duration: Theme.t } }
                    Icon { anchors.centerIn: parent; text: row.k[1]; font.pixelSize: 19; color: row.on ? Theme.ink : Theme.fg }
                }
                Column {
                    anchors { left: ic.right; leftMargin: 14; right: parent.right; rightMargin: root.inspectable ? 44 : 16; verticalCenter: parent.verticalCenter }
                    Text { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: root.name(row.o); font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
                    Lb { px: 10; text: (row.on ? `default · ${row.k[0]}` : row.k[0]) + (Eq.engaged === row.o ? " · eq" : "") }
                }
                Item {
                    visible: root.inspectable
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 32
                    height: 32
                    Icon { anchors.centerIn: parent; text: "\u{F0142}"; font.pixelSize: 18; color: Theme.grey }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.touched(); root.inspect(row.o); } }
                }
                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.touched(); Eq.pick(row.o); } }
            }
        }
    }
}
