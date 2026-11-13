import QtQuick
import qs
import qs.components

// one settings row: label (and a small caps sub-line) on the left; a mono value, a tail
// slot for a control (button, marker) and an optional chevron on the right. clickable
// rows light up on hover and fire hit.
Item {
    id: root

    property string label: ""
    property string sub: ""
    property string value: ""
    property bool chevron: false
    property bool divider: true
    property bool clickable: false
    default property alias tail: tailRow.data
    signal hit

    width: parent ? parent.width : 0
    height: sub ? 62 : 48

    Rectangle {
        anchors { fill: parent; leftMargin: -10; rightMargin: -10 }
        radius: Theme.corner(12)
        color: Theme.s2
        opacity: root.clickable && hov.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: parent.width - tailBox.width - 16
        spacing: 3
        Text {
            text: root.label
            font { family: Theme.ui; pixelSize: 15 }
            color: Theme.fg
            elide: Text.ElideRight
            width: parent.width
        }
        Lb { visible: root.sub !== ""; text: root.sub; px: 10; color: Theme.mute }
    }
    Row {
        id: tailBox
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 12
        Text {
            visible: root.value !== ""
            text: root.value
            font { family: Theme.mono; pixelSize: 12 }
            color: Theme.grey
            anchors.verticalCenter: parent.verticalCenter
        }
        Row {
            id: tailRow
            spacing: 10
            anchors.verticalCenter: parent.verticalCenter
        }
        Icon {
            visible: root.chevron
            text: "\u{F0142}"
            font.pixelSize: 18
            color: Theme.mute
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Rectangle {
        visible: root.divider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.s2
    }
    HoverHandler { id: hov; enabled: root.clickable; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: root.clickable; onTapped: root.hit() }
}
