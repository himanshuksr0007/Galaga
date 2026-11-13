import QtQuick
import qs
import qs.components
import qs.services

// a settings row with the house switch on the right (DeviceSettings' Switch shape).
// Controlled: the owner binds on and writes its store in onFlip.
Item {
    id: root

    property string label: ""
    property string sub: ""
    property bool on: false
    property bool divider: true
    signal flip(bool want)

    width: parent ? parent.width : 0
    height: sub ? 62 : 48

    Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: parent.width - 70
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
    Rectangle {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 46
        height: 26
        radius: 13
        color: root.on ? Theme.fg : Theme.s3
        Behavior on color { ColorAnimation { duration: Theme.t } }
        Rectangle {
            width: 20
            height: 20
            radius: 10
            y: 3
            x: root.on ? parent.width - width - 3 : 3
            color: root.on ? Theme.ink : Theme.grey
            Behavior on x { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
            Behavior on color { ColorAnimation { duration: Theme.t } }
        }
    }
    Rectangle {
        visible: root.divider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.s2
    }
    TapHandler {
        onTapped: {
            Sounds.play("tick");
            root.flip(!root.on);
        }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
