import QtQuick
import Quickshell
import qs
import qs.settings

// screen in 16:10 miniature: wallpaper (dot grid, if enabled) and bar.
// k -- logical screen px in layout px
Rectangle {
    readonly property real k: width / (Rules.mon.w ? Rules.mon.w / Rules.scale : Quickshell.screens[0]?.width ?? 1920)
    width: 760
    height: 475
    radius: 24
    color: Theme.bg
    border { width: 1; color: Theme.s3 }
    Image {
        visible: Theme.state.grid
        anchors { fill: parent; margins: 12 }
        fillMode: Image.Tile
        source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="1" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
    }
    // the bar at its own edge: the offset 14 and thickness 64 are layout px, on screen they are Theme.s logical ones
    Rectangle {
        readonly property real u: Theme.s * parent.k
        readonly property bool onTop: Theme.state.barAt === "top"
        x: 14 * u
        y: 14 * u
        width: onTop ? parent.width - 28 * u : 64 * u
        height: onTop ? 64 * u : parent.height - 28 * u
        radius: Theme.corner(Math.min(width, height) / 2)
        color: Theme.s1
        border { width: 1; color: Theme.s2 }
    }
}
