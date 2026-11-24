import QtQuick
import Quickshell
import qs

Item {
    id: c
    property bool newest: true
    property bool interactive: true
    signal tapped()
    signal exited()
    required property string app
    required property string summary
    required property string body
    required property string icon
    required property string glyph
    required property bool crit
    required property bool leaving
    property bool presented: true

    // p 0...1 linear, each phase has its own ease-out-quart (like glide)
    property real p: 0
    Component.onCompleted: p = Qt.binding(() => presented && !leaving ? 1 : 0)
    Behavior on p { NumberAnimation { duration: c.leaving ? 450 : 700 } }
    onPChanged: if (leaving && p <= 0) exited()
    function ph(a, b) { const x = Math.max(0, Math.min(1, (p - a) / (b - a))); return 1 - Math.pow(1 - x, 4); }
    readonly property real drop: ph(0, 0.3)   // pill falls
    readonly property real grow: ph(0.25, 0.8) // and spreads into a tile
    readonly property real full: Math.max(86, txt.height + 32)

    width: 600
    height: (40 + (full - 40) * grow + 12) * drop // place in the stack grows and collapses with the tile

    Rectangle {
        width: 140 + (600 - 140) * c.grow
        height: 40 + (c.full - 40) * c.grow
        x: (600 - width) / 2
        y: -24 * (1 - c.drop)
        opacity: c.drop
        radius: Theme.corner(Math.min(34, height / 2))
        clip: true
        color: Theme.s1
        border { width: 1; color: c.crit ? Theme.red : Theme.fg }

        // content -- at full size in the center: text width does not change while the tile grows
        Item {
            anchors.centerIn: parent
            width: 600
            height: c.full
            opacity: c.ph(0.7, 1)

            Rectangle {
                id: ic
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 54
                height: 54
                radius: 27
                color: Theme.s2
                Icon { anchors.centerIn: parent; visible: !img.visible; text: c.glyph || "\u{F009A}"; font.pixelSize: 24 }
                Image {
                    id: img
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    visible: status === Image.Ready
                    source: c.icon ? Quickshell.iconPath(c.icon, true) : ""
                    sourceSize: Qt.size(28, 28)
                    layer.enabled: true
                    layer.effect: Dm { step: 2 }
                }
            }
            Column {
                id: txt
                anchors { left: ic.right; leftMargin: 16; right: dot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                Lb { width: parent.width; elide: Text.ElideRight; text: `${c.app} · now` }
                Text {
                    width: parent.width
                    topPadding: 2
                    elide: Text.ElideRight
                    text: c.summary
                    textFormat: Text.PlainText
                    font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                    color: Theme.fg
                }
                Text {
                    width: parent.width
                    visible: !!c.body
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: c.body
                    font { family: Theme.ui; pixelSize: 14 }
                    color: Theme.grey
                }
            }
            // red dot -- only on the newest one: one red on screen
            Rectangle { id: dot; visible: c.newest; anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter } width: 12; height: 12; radius: 6; color: Theme.red }
        }

        TapHandler {
            enabled: c.interactive
            onTapped: c.tapped()
        }
    }
}
