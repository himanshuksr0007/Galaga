import QtQuick
import qs

// a settings card: one rounded surface holding a column of rows. Rows draw their own
// bottom hairline (SetRow.divider); the last row in a card leaves it off.
Rectangle {
    default property alias body: col.data
    property real pad: 20

    width: parent ? parent.width : 0
    height: col.height + pad * 2
    radius: Theme.corner(22)
    color: Theme.s1
    border { width: 1; color: Theme.s2 }

    Column {
        id: col
        x: parent.pad
        y: parent.pad
        width: parent.width - parent.pad * 2
        spacing: 0
    }
}
