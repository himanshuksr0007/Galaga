import QtQuick
import qs
import qs.components

Rectangle {
    id: button
    required property string label
    property bool danger: false
    signal hit

    width: parent.width
    height: Math.max(40, caption.implicitHeight + 12)
    radius: Theme.corner(height / 2)
    color: hover.hovered ? Theme.s3 : Theme.s2

    Lb {
        id: caption
        anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        px: 11
        font.bold: true
        color: button.danger ? Theme.red : Theme.fg
        text: button.label
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: button.hit() }
}
