import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// drop deck: while a window is being dragged (the hyprdrag plugin's move
// drag -- services/DragWatch), a strip of workspaces rises at the bottom
// of every screen; let go over one and the window moves there. It is a
// pure overlay: click-through, no keyboard, gone the moment the drag ends.
// Without the plugin there are no drag events and this never appears --
// the feature simply does not exist in the sampling world, it does not
// degrade into something half-working.
//
// Hit-testing is the shell's own arithmetic, because the strip cannot
// take the pointer (the dragged window holds it): while shown, the root
// samples hyprctl cursorpos every 100 ms -- a cost bounded by the drag
// itself -- and each screen's cells register their global rectangles.
// A cell's global rect is its position inside its window (mapToItem to
// the window's surface item -- pure scene math) plus the window's own
// origin on the desktop: the window is full-width and bottom-anchored,
// so that origin is (screen.x, screen.y + screen.height - window height).
Scope {
    id: root

    readonly property bool shown: DragWatch.alive && DragWatch.moveActive && Theme.state.snapDrop
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    // the dragged window's home workspace: the cell it sits on is marked,
    // and dropping there is not a move
    readonly property var dragTl: Hyprland.toplevels.values.find(tp => "0x" + tp.address === DragWatch.addr) ?? null
    readonly property int homeWs: dragTl?.workspace?.id ?? -1

    // the cells on offer: every real workspace in id order, plus one fresh
    // (the lowest unused positive id) to drop a window onto a new desktop
    readonly property var cells: {
        const ws = Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id);
        const list = ws.map(w => ({ id: w.id, name: w.name ?? "", count: w.toplevels.values.length, fresh: false }));
        let nid = 1;
        while (ws.some(w => w.id === nid)) nid++;
        list.push({ id: nid, name: "", count: 0, fresh: true });
        return list;
    }

    // cell key -> { ws, x, y, w, h } in global coordinates, and the outcome
    property var rects: ({})
    property int hoverWs: -1 // the workspace under the cursor (-1: none)
    property var cur: null // the last cursor sample, global { x, y }

    function regRect(key, ws, r) {
        const n = Object.assign({}, rects);
        n[key] = { ws: ws, x: r.x, y: r.y, w: r.w, h: r.h };
        rects = n;
    }
    function unregRect(key) {
        if (!(key in rects)) return;
        const n = Object.assign({}, rects);
        delete n[key];
        rects = n;
    }
    function pickHover() {
        if (!cur) { hoverWs = -1; return; }
        for (const k in rects) {
            const r = rects[k];
            if (cur.x >= r.x && cur.x < r.x + r.w && cur.y >= r.y && cur.y < r.y + r.h) { hoverWs = r.ws; return; }
        }
        hoverWs = -1;
    }

    // the cursor, sampled only while the strip is up
    Timer { interval: 100; repeat: true; running: root.shown; onTriggered: if (!cpos.running) cpos.running = true }
    Process {
        id: cpos
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                const x = parseInt(p[0]), y = parseInt(p[1]);
                root.cur = isNaN(x) || isNaN(y) ? null : { x: x, y: y };
                root.pickHover();
            }
        }
    }

    // the drop: the drag ended -- if a cell is hovered and it is not the
    // window's home, the window goes there. The addressable move is the
    // deck's own form (deck/Deck.qml, the minimised section's restore);
    // follow = false: the window is thrown, the user stays.
    Connections {
        target: DragWatch
        function onDragStopped(kind, addr) {
            if (kind !== "move") return;
            if (root.hoverWs < 0) root.pickHover(); // the last sample may not have been picked yet
            const target = root.hoverWs, home = root.homeWs;
            root.hoverWs = -1;
            root.cur = null;
            if (target > 0 && addr && target !== home)
                Hyprland.dispatch(`hl.dsp.window.move({ window = "address:${addr}", workspace = "${target}", follow = false })`);
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData
            visible: root.t > 0
            anchors { left: true; right: true; bottom: true }
            implicitHeight: Math.ceil(96 * Theme.s)
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "galaga-dropdeck"
            mask: Region { } // no region anywhere: the strip never eats a click

            Item {
                id: surface
                anchors.fill: parent

                Rectangle {
                    // the pill behind the cells; it carries the motion
                    // (fade + a small settle) so the cells themselves never
                    // move and their registered rects stay true
                    anchors.centerIn: rowBox
                    width: rowBox.width + 36
                    height: 68
                    radius: Theme.corner(24)
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }
                    opacity: root.t
                    scale: 0.96 + 0.04 * root.t
                }

                Item {
                    id: rowBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: row.width
                    height: 68
                    opacity: root.t

                    Row {
                        id: row
                        anchors.centerIn: parent
                        spacing: 10

                        Repeater {
                            model: root.cells

                            Rectangle {
                                id: cell

                                required property var modelData
                                readonly property string key: win.modelData.name + ":" + modelData.id
                                readonly property bool hov: root.hoverWs === modelData.id
                                readonly property bool home: root.homeWs === modelData.id

                                function report() {
                                    const p = mapToItem(surface, 0, 0);
                                    root.regRect(key, modelData.id, {
                                        x: win.modelData.x + p.x,
                                        y: win.modelData.y + win.modelData.height - win.height + p.y,
                                        w: width, h: height });
                                }
                                Component.onCompleted: report()
                                Component.onDestruction: root.unregRect(key)
                                // the first registration happens while the
                                // strip has never been shown and its window
                                // may not have its real geometry yet -- so
                                // register again the moment it rises, when
                                // the layout is the one on screen
                                Connections {
                                    target: root
                                    function onShownChanged() { if (root.shown) Qt.callLater(cell.report); }
                                }
                                onXChanged: report()
                                onYChanged: report()
                                onWidthChanged: report()
                                onHeightChanged: report()

                                width: 80
                                height: 52
                                radius: Theme.corner(16)
                                color: hov ? Theme.fg : Theme.s2
                                border { width: home ? 1 : 0; color: Theme.fade(Theme.fg, 0.55) }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Lb {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cell.modelData.fresh || !cell.modelData.name || cell.modelData.name === String(cell.modelData.id)
                                            ? String(cell.modelData.id) : cell.modelData.name
                                        px: 15
                                        color: cell.hov ? Theme.ink : Theme.fg
                                    }
                                    Lb {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cell.modelData.fresh ? "new"
                                            : cell.home ? "here"
                                            : cell.modelData.count === 1 ? "1 window" : cell.modelData.count + " windows"
                                        px: 9
                                        color: cell.hov ? Theme.ink : Theme.mute
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
