import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// home backdrop, a separate window on the background layer: dot grid, halftone orb, wallpaper. The home itself (clock, bento) -- on a layer
// above, transparent: it redraws often (colon, rings, spinning cover), while the wallpaper is a fullscreen shader,
// and in one window they would be computed on every one of its frames. Here a frame -- only on a wave, view change and orb breathing.
// The image covers everything -- we do not draw the grid and orb, the orb does not breathe: the window stands still
PanelWindow {
    id: root

    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.bg
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "glyph-back"

    readonly property bool home: (Hyprland.focusedWorkspace?.toplevels.values.length ?? 0) === 0
    property real phase: 0
    Timer { running: root.home && orb.visible; interval: 100; repeat: true; onTriggered: root.phase += 0.1 }

    Stage {
        id: stage
        Image {
            visible: Theme.state.grid && !wall.opaque
            anchors.fill: parent
            fillMode: Image.Tile
            source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="1.5" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
        }
        Orb { id: orb; visible: Theme.state.orb && !wall.opaque; x: stage.width - 720; y: stage.height - 580; phase: root.phase }
        Wall { id: wall; anchors.fill: parent; path: Theme.wallSrc(Theme.state.wall); animate: !Sys.wallOpen }
    }
}
