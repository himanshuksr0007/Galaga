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

    // this screen's own workspace: the orb breathes and the wallpaper follows it, not the focused screen's
    readonly property var ownWs: Hyprland.monitorFor(screen)?.activeWorkspace
    readonly property bool home: (ownWs?.toplevels.values.length ?? 0) === 0
    property real phase: 0
    // the breathing drives a fullscreen-window redraw ten times a second: shell performance trim
    // breathes at half rate, lite holds the orb still (Theme.perf)
    Timer { running: root.home && orb.visible && !Theme.perfLite; interval: Theme.state.perf === 1 ? 200 : 100; repeat: true; onTriggered: root.phase += 0.1 }

    Stage {
        id: stage
        Image {
            visible: Theme.state.grid && !wall.opaque
            anchors.fill: parent
            fillMode: Image.Tile
            source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="1.5" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
        }
        Orb { id: orb; visible: Theme.state.orb && !wall.opaque; x: stage.width - 720; y: stage.height - 580; phase: root.phase }
        Wall {
            id: wall
            anchors.fill: parent
            // two axes, one winner: a per-desktop wallpaper (prefs DESKTOPS) for THIS screen's active
            // desktop wins; unset -- this screen's own wallpaper (prefs DISPLAY), else the shared one.
            // Same Wall, same wave: the crossfade on switch is the path change itself
            path: Theme.wallSrc((Theme.state.featDesktops ? Theme.state.wsWalls[String(root.ownWs?.id ?? "")] : "") || Theme.scr(root.screen?.name, "wall"))
            animate: !Sys.wallOpen
        }
    }
}
