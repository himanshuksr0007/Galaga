import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// hot corners: flick the pointer into a screen corner and hold a beat -- the corner's action fires
// (settings -> desktop & deck). Each corner is its own 14x14 window with the hot edges' dwell and
// drag gate (quick/Hot.qml): a window dragged or resized across a corner must not fire it -- corner
// drags are snap gestures too. A corner set to off has no window at all.
Scope {
    id: root

    signal fired(string action)
    required property var screen

    component CornerWin: PanelWindow {
        required property string corner
        readonly property bool isLeft: corner === "tl" || corner === "bl"
        readonly property bool isTop: corner === "tl" || corner === "tr"
        readonly property string act: Theme.state.hotCorners?.[corner] ?? "off"

        // DragWatch sample from when this hover began; the dwell decides with it
        property var s1: null

        visible: act !== "off"
        anchors { left: isLeft; right: !isLeft; top: isTop; bottom: !isTop }
        implicitWidth: 14
        implicitHeight: 14
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "galaga-corners"

        HoverHandler {
            id: hov
            onHoveredChanged: {
                if (hovered) {
                    s1 = null;
                    if (!DragWatch.alive) DragWatch.sample(s => { s1 = s; }); // the event world needs no sample
                    dwell.restart();
                } else dwell.stop();
            }
        }
        // the dwell decides with DragWatch: a window being dragged or resized
        // across the corner must not fire it (services/DragWatch). The action
        // is read as it fires, not as the hover began.
        Timer { id: dwell; interval: 150; onTriggered: DragWatch.mayOpen(s1, ok => { if (hov.hovered && ok) root.fired(act); }) }
    }

    CornerWin { corner: "tl"; screen: root.screen }
    CornerWin { corner: "tr"; screen: root.screen }
    CornerWin { corner: "bl"; screen: root.screen }
    CornerWin { corner: "br"; screen: root.screen }
}
