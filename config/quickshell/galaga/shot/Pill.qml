import QtQuick
import qs

// pill over the frame: Surface with a Raised outline, content centered next to it. A click on it does not reach the frame beneath
Rectangle {
    default property alias content: row.data
    property alias spacing: row.spacing
    property real pad: 10

    width: row.width + pad * 2
    height: 56
    radius: height / 2
    color: Theme.s1
    border { width: 1; color: Theme.s2 }

    MouseArea { anchors.fill: parent }
    Row { id: row; anchors.centerIn: parent }
}
