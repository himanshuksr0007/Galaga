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
                if (!DragWatch.alive) DragWatch.sample(s => { root.s1 = s; }); // the event world needs no sample
                dwell.restart();
            } else dwell.stop();
        }
    }
    // the dwell decides with DragWatch: a window being dragged or resized
    // across the edge must not peek the panel (services/DragWatch)
    Timer { id: dwell; interval: 150; onTriggered: DragWatch.mayOpen(root.s1, ok => { if (hov.hovered && ok) root.triggered(); }) }
}
