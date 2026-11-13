import QtQuick
import qs

// a small pill button (the PillBtn shape the device pages used). danger paints the label red.
Rectangle {
    id: root

    property string label: ""
    property bool danger: false
    signal hit

    implicitWidth: lbl.implicitWidth + 32
    implicitHeight: 32
    width: implicitWidth
    height: implicitHeight
    radius: Theme.corner(16)
    color: hov.hovered ? Theme.fg : Theme.s2
    Behavior on color { ColorAnimation { duration: 150 } }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: root.label
        font { family: Theme.ui; pixelSize: 13; weight: Font.DemiBold }
        color: root.danger && !hov.hovered ? Theme.red : (hov.hovered ? Theme.ink : Theme.fg)
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.hit() }
}
