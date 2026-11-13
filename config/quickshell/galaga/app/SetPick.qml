import QtQuick
import qs
import qs.components
import qs.services

// a settings row with a segmented pick on the right: the white segment slides to the
// current option, the shape Prefs' Pick uses at row size.
Item {
    id: root

    property string label: ""
    property var opts: []
    property int cur: 0
    property real seg: 78
    property bool divider: true
    signal picked(int i)

    width: parent ? parent.width : 0
    height: 48

    Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: root.label
        font { family: Theme.ui; pixelSize: 15 }
        color: Theme.fg
    }
    Rectangle {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: root.seg * root.opts.length
        height: 34
        radius: Theme.corner(17)
        color: Theme.s2
        Rectangle {
            x: 3 + root.cur * root.seg
            y: 3
            width: root.seg - 6
            height: parent.height - 6
            radius: Theme.corner(14)
            color: Theme.fg
            Behavior on x { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
        }
        Row {
            anchors.fill: parent
            Repeater {
                model: root.opts
                Item {
                    required property var modelData
                    required property int index
                    width: root.seg
                    height: parent.height
                    Lb {
                        anchors.centerIn: parent
                        text: modelData
                        px: 11
                        color: root.cur === index ? Theme.ink : Theme.grey
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                    }
                    TapHandler {
                        onTapped: {
                            if (root.cur !== index) Sounds.play("tick");
                            root.picked(index);
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }
    }
    Rectangle {
        visible: root.divider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.s2
    }
}
