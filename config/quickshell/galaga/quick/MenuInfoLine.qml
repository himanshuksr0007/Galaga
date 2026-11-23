import QtQuick
import qs
import qs.components

Item {
    id: row
    required property string k
    required property string v

    width: parent.width
    height: Math.max(20, value.implicitHeight, key.implicitHeight)

    Lb {
        id: key
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        px: 11
        text: row.k
    }
    Text {
        id: value
        anchors { left: key.right; leftMargin: 12; right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font { family: Theme.mono; pixelSize: 11 }
        color: Theme.fg
        text: row.v
    }
}
