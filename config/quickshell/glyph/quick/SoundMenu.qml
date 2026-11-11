import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// the sound menu: the bar's speaker gets its own small dropdown instead of
// opening all of quick settings. macOS puts a volume slider and the output
// list behind its menu-bar speaker; here it is the same two things in the
// glyph skin -- the house dotted slider, and the outputs list Quick keeps
// behind a right-click on its slider (Out), unfolded for good. A mute toggle
// sits in the header. Click the speaker again, click anywhere else, or press
// Esc to close it; the wheel over the bar icon still rides the volume, and
// opening quick settings (any other tray icon) puts this away, as it puts
// quick away when this opens -- shell.qml wires the two against each other.
PanelWindow {
    id: root

    property bool open: false
    function toggle() { open = !open; }
    function close() { open = false; }
    onOpenChanged: if (open) Sounds.play("pop")

    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-sound"

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: panel
        readonly property bool barTop: Theme.state.barAt === "top"
        width: 360
        height: col.height + 44
        x: parent.width - width - 14
        y: barTop ? Math.ceil(86 * Theme.s) : parent.height - height - Math.ceil(86 * Theme.s)
        opacity: root.t
        transform: Translate { y: (1 - root.t) * (panel.barTop ? -8 : 8) }
        radius: Theme.corner(36)
        color: Theme.s1
        border { width: 1; color: Theme.s2 }
        focus: true
        Keys.onEscapePressed: root.close()
        MouseArea { anchors.fill: parent } // clicking the panel does not close it

        Column {
            id: col
            x: 22
            y: 22
            width: parent.width - 44
            spacing: 16

            Item {
                width: parent.width
                height: 24
                Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "sound" }
                Icon {
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: Sys.muted ? "\u{F075F}" : "\u{F057E}"
                    color: Sys.muted ? Theme.red : Theme.grey
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (Sys.sink?.audio) Sys.sink.audio.muted = !Sys.sink.audio.muted; } }
                }
            }

            VolSlider { }

            Out { width: parent.width; open: true }
        }
    }

    // the house slider, as in Quick: filled -- a white pill with the icon,
    // empty -- a row of dots, the level in a chip at the right. No right-click
    // menu here -- the outputs it would unfold are already below it
    component VolSlider: Rectangle {
        id: sl
        readonly property real value: Sys.muted ? 0 : Sys.vol
        readonly property real shown: area.pressed ? area.v : value
        width: col.width
        height: 54
        radius: Theme.corner(27)
        color: Theme.s2
        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11 - 2.8
            Repeater {
                model: Math.max(0, Math.floor((sl.width - 20) / 11) + 1)
                Rectangle { width: 2.8; height: 2.8; radius: 1.4; color: Theme.mute }
            }
        }
        Rectangle {
            width: Math.max(height, sl.width * sl.shown)
            height: parent.height
            radius: Theme.corner(27)
            color: Theme.fg
            Behavior on width { enabled: !area.pressed; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; text: Sys.muted ? "\u{F075F}" : "\u{F057E}"; font.pixelSize: 21; color: Theme.ink }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: val.width + 16
            height: val.height + 8
            radius: Theme.corner(10)
            color: Theme.s2
            Lb { id: val; anchors.centerIn: parent; text: Math.round(sl.shown * 100); color: Theme.grey }
        }
        MouseArea {
            id: area
            property real v
            property real wacc: 0
            anchors.fill: parent
            preventStealing: true
            function set(x) { v = Math.max(0, Math.min(1, x / width)); Sys.setVol(v); }
            onPressed: e => set(e.x)
            onPositionChanged: e => set(e.x)
            // wheel, same recipe as Quick's sliders: a notch is 5%, a touchpad
            // four times slower, steps accumulate to 2% before they land
            onWheel: e => {
                wacc += (e.inverted ? -1 : 1) * (e.angleDelta.y || -e.angleDelta.x) / 120 * 0.05 * (e.phase === Qt.NoScrollPhase ? 1 : 0.25);
                if (Math.abs(wacc) < 0.02)
                    return;
                Sys.setVol(Math.max(0, Math.min(1, sl.shown + wacc)));
                wacc = 0;
            }
        }
    }
}
