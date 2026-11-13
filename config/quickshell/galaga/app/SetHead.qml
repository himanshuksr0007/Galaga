import QtQuick
import qs
import qs.components

// section head: the red dot + a caps label, the shape Prefs' FeatHead uses
Row {
    property string text: ""

    spacing: 10
    Rectangle {
        width: 8
        height: 8
        radius: 4
        color: Theme.accent
        anchors.verticalCenter: parent.verticalCenter
    }
    Lb { text: parent.text; px: 12; color: Theme.grey }
}
