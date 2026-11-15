import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// hot edge: the cursor lingered at the right edge -- quick settings slide out (Quick.peek). A 2px strip over the bottom 80%:
// it barely touches the top corner and scrollbars at the edge
PanelWindow {
    id: root

    signal triggered

    // DragWatch sample from when this hover began; the dwell decides with it
    property var s1: null

    visible: Theme.state.quickHover
    anchors { right: true; bottom: true }
    implicitWidth: 2
    implicitHeight: Math.round(screen.height * 0.8)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "galaga-hot"

    HoverHandler {
        id: hov
        onHoveredChanged: {
            if (hovered) {
                root.s1 = null;
                DragWatch.sample(s => { root.s1 = s; });
                dwell.restart();
            } else dwell.stop();
        }
    }
    // the dwell decides with two DragWatch samples: a window being dragged or
    // resized across the edge must not peek the panel (services/DragWatch)
    Timer { id: dwell; interval: 150; onTriggered: DragWatch.sample(s2 => { if (hov.hovered && !DragWatch.busyBetween(root.s1, s2)) root.triggered(); }) }
}
