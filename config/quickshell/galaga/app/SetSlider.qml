import QtQuick
import qs
import qs.components

// a settings row with a dot-track slider: label left, value right, drag or click the
// track. Like Dial it speaks once -- on release, or after 200 ms of stillness --
// so a drag doesn't fire a hyprctl eval per step.
Item {
    id: root

    property string label: ""
    property real from: 0
    property real to: 100
    property real step: 1
    property real value: 0
    property string unit: ""
    property bool divider: true
    property real v: value
    signal moved(real v)

    width: parent ? parent.width : 0
    height: 48
    onValueChanged: if (!drag.pressed) v = value

    readonly property real frac: (v - from) / (to - from)

    function put(x) {
        const w = track.width;
        let nv = from + Math.max(0, Math.min(1, x / w)) * (to - from);
        nv = from + Math.round((nv - from) / step) * step;
        nv = Math.max(from, Math.min(to, nv));
        if (nv === v) return;
        v = nv;
        wait.restart();
    }

    Timer { id: wait; interval: 200; onTriggered: root.moved(root.v) }

    Text {
        id: lab
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 150
        text: root.label
        font { family: Theme.ui; pixelSize: 15 }
        color: Theme.fg
        elide: Text.ElideRight
    }
    Item {
        id: trackBox
        anchors { left: lab.right; leftMargin: 14; right: val.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        height: 24
        Rectangle {
            id: track
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 6
            radius: 3
            color: Theme.s3
            Rectangle {
                width: parent.width * root.frac
                height: parent.height
                radius: 3
                color: Theme.fg
            }
        }
        Rectangle {
            width: 18
            height: 18
            radius: 9
            x: root.frac * track.width - 9
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            border { width: 2; color: Theme.bg }
        }
        MouseArea {
            id: drag
            anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
            cursorShape: Qt.PointingHandCursor
            onPressed: m => root.put(m.x)
            onPositionChanged: m => { if (pressed) root.put(m.x); }
            onReleased: { wait.stop(); root.moved(root.v); }
        }
    }
    Text {
        id: val
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 58
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.v) + (root.unit ? " " + root.unit : "")
        font { family: Theme.mono; pixelSize: 12 }
        color: Theme.grey
    }
    Rectangle {
        visible: root.divider
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.s2
    }
}
