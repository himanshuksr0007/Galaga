import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

// genie: the minimise warp -- the magic lamp, aimed at the deck.
// Hyprland's animations cannot vertex-warp a real window, so the shell does it
// with the window's own pixels. scripts/minimise.sh -- the one entry point
// every park path runs (white title-bar button, Super+Alt+M, show-desktop) --
// hands the window here BEFORE parking it. We snapshot its rect with grim
// (the shot module's capture: a frozen file; a live ScreencopyView of a
// toplevel that is about to unmap cannot promise to hold its last frame),
// show the snapshot as a ghost over the still-live window, park the real
// window, and warp the ghost down into the deck's minimised section: 30
// horizontal slices follow the lamp curve -- the far edge narrows first, the
// edge nearest the deck stays widest longest, everything funnels into one
// point on the bottom edge, at the section's centre.
// The target is computed from the CURRENT section order (Theme.state.deck)
// on every park -- move the minimised section in Prefs and the windows
// follow it. The deck itself is always bottom-centre in this shell.
// Safety: the shell owns the park only after answering "go"; inside, a
// fallback timer parks the window even if grim hangs or fails, so a minimise
// can never be lost to the effect. Off: Prefs -> DECK -> genie (the IPC then
// answers "plain" and minimise.sh parks directly, as before).
// Restore has no reverse warp, deliberately: a parked window is unmapped, so
// there are no fresh pixels to un-warp -- only the stale snapshot from park
// time, and animating stale content would be a fake. Restore stays instant.
Scope {
    id: root

    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    property var ghosts: []
    property var scr: null
    property double lastAt: 0 // last enqueue (ms): parks close together form a burst
    property int burst: 0

    // deck section widths, from deck/Deck.qml (each section component's fixed
    // width). If a section is ever resized there, change it here too.
    readonly property var widths: ({ clock: 216, weather: 188, perf: 300, net: 176, media: 240, min: 184 })
    // the deck's own section rule (Deck.ids): the configured order minus
    // unknown ids, "min" appended when a state file predates it
    readonly property var ids: { const l = Theme.state.deck.filter(id => Theme.decks.includes(id)); if (!l.includes("min")) l.push("min"); return l; }

    // the suck target's x, in overlay layout px: the minimised section's
    // centre. The panel is centred on screen; inside it the sections sit in
    // `ids` order (row x = 26, cells are section + 20 for the dotted separator
    // and cell spacing past the first, 16 of row spacing between cells).
    // y is the bottom edge itself -- where the closed deck hides.
    function targetX(stageW) {
        const ids = root.ids, mi = ids.indexOf("min");
        let rowW = 0, before = 0;
        for (let i = 0; i < ids.length; i++) {
            const cell = root.widths[ids[i]] + (i > 0 ? 20 : 0);
            if (i < mi) before += cell + 16;
            rowW += cell + (i > 0 ? 16 : 0);
        }
        return (stageW - (rowW + 52)) / 2 + 26 + before + (mi > 0 ? 20 : 0) + root.widths.min / 2;
    }

    function enqueue(r) {
        // a warp for this window is already running: its park is owned, and a
        // second ghost of the same pixels would only double the show
        if (root.ghosts.some(g => g.addr === r.address)) return true;
        const now = Date.now();
        root.burst = now - root.lastAt < 300 ? Math.min(root.burst + 1, 6) : 0;
        root.lastAt = now;
        if (root.ghosts.length === 0)
            root.scr = Quickshell.screens.find(s => s.name === r.monitor)
                ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
                ?? Quickshell.screens[0];
        const s = Theme.s, sx = root.scr?.x ?? 0, sy = root.scr?.y ?? 0;
        const g = ghostC.createObject(stage, {
            addr: r.address,
            file: `${root.run}/glyph-genie-${now}-${r.address.slice(2)}.ppm`,
            raw: `${r.at[0]},${r.at[1]} ${r.size[0]}x${r.size[1]}`, // global logical px -- grim's own space
            gx: (r.at[0] - sx) / s,
            gy: (r.at[1] - sy) / s,
            gw: r.size[0] / s,
            gh: r.size[1] / s,
            stagger: root.burst * 40,
            tx: root.targetX(stage.width)
        });
        if (!g) return false; // no ghost, no ownership: the script parks directly
        root.ghosts = root.ghosts.concat(g);
        return true;
    }

    IpcHandler {
        target: "genie"
        // scripts/minimise.sh. "go" = the shell owns this park now (snapshot,
        // ghost, park dispatch, fallback included); anything else and the
        // script parks the window directly, exactly as the rice always did.
        function minimise(req: string): string {
            if (!Theme.state.genie) return "plain";
            let r;
            try { r = JSON.parse(req); } catch (e) { return "plain"; }
            if (!r || !r.address || !r.at || !r.size || !(r.size[0] > 0) || !(r.size[1] > 0)) return "plain";
            return root.enqueue(r) ? "go" : "plain";
        }
    }

    PanelWindow {
        id: win
        screen: root.scr
        visible: root.ghosts.length > 0
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { } // no region anywhere: the warp never eats a click
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "glyph-genie"

        Stage { id: stage }
    }

    Component {
        id: ghostC

        Item {
            id: ghost
            anchors.fill: parent
            visible: ready
            // the last sliver fades as it collapses into the point
            opacity: p > 0.9 ? 1 - (p - 0.9) * 8.1 : 1

            property string addr: ""
            property string file: ""
            property string raw: "" // "x,y wxh" for grim, global logical px
            property real gx: 0
            property real gy: 0
            property real gw: 0
            property real gh: 0
            property real tx: 0 // target x, layout px; the target y is the stage's bottom edge
            property int stagger: 0
            property real p: 0
            property bool ready: false
            property bool parked: false
            property bool gone: false

            // the lamp curve. Vertically the ghost is a homothety about the
            // target point: every row's distance to the bottom edge scales by
            // (1 - p), so rows compress toward the deck in order -- they can
            // bunch but never pass each other, for any window geometry.
            // Horizontally each row follows q(v): v = 0 at the far (top) edge,
            // 1 at the deck edge, and a row starts narrowing at p = v * spread
            // -- the far edge funnels first, the deck edge stays widest
            // longest, and every row's centre drifts to the target x.
            readonly property real spread: 0.45
            function q(v) { return Math.max(0, Math.min(1, (p - v * spread) / (1 - spread))); }
            function edgeY(u) { return parent.height - (parent.height - (gy + u * gh)) * (1 - p); }

            Repeater {
                model: 30
                Item {
                    id: slice
                    required property int index
                    readonly property real u0: index / 30
                    readonly property real u1: (index + 1) / 30
                    readonly property real v: (index + 0.5) / 30
                    readonly property real qv: ghost.q(v)
                    readonly property real cx: ghost.gx + ghost.gw / 2 + (ghost.tx - ghost.gx - ghost.gw / 2) * Math.pow(qv, 1.7)
                    readonly property real hw: ghost.gw / 2 * (1 - 0.97 * Math.pow(qv, 1.35))
                    x: cx - hw
                    y: ghost.edgeY(u0)
                    width: Math.max(0.75, hw * 2)
                    height: Math.max(1, ghost.edgeY(u1) - ghost.edgeY(u0)) + 0.8 // a hair of overlap: no seams mid-warp
                    clip: true
                    Image {
                        // the slice's band of the snapshot, squashed with it:
                        // the full frame scaled to 30 slice-heights, shifted so
                        // this band fills the slice
                        width: slice.width
                        height: slice.height * 30
                        y: -slice.index * slice.height
                        source: ghost.ready ? "file://" + ghost.file : ""
                    }
                }
            }

            Process {
                id: cap
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (text.trim() === "ok") ghost.ready = true;
                        else { ghost.doPark(); ghost.finish(); } // no snapshot: plain park, no ghost
                    }
                }
            }
            Component.onCompleted: cap.exec(["sh", "-c", 'grim -t ppm -g "$1" "$2" && echo ok', "sh", raw, file])

            // the ghost is up at p = 0, pixel-identical over the live window:
            // one beat for the overlay to present, then park + warp together
            Timer {
                id: parkDelay
                interval: ghost.stagger + 30
                onTriggered: { ghost.doPark(); anim.start(); }
            }
            onReadyChanged: if (ready) parkDelay.start()

            // whatever happened above -- a hung grim, a lost process -- the
            // park lands. Minimising never depends on the effect.
            Timer {
                running: true
                interval: ghost.stagger + 650
                onTriggered: { ghost.doPark(); if (!ghost.ready) ghost.finish(); }
            }

            NumberAnimation {
                id: anim
                target: ghost
                property: "p"
                from: 0
                to: 1
                duration: 350
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.glide
                onFinished: ghost.finish()
            }

            function doPark() {
                if (parked) return;
                parked = true;
                Hyprland.dispatch(`hl.dsp.window.move({ window = "address:${addr}", workspace = "special:minimized", follow = false })`);
            }
            function finish() {
                if (gone) return;
                gone = true;
                Quickshell.execDetached(["rm", "-f", file]);
                root.ghosts = root.ghosts.filter(g => g !== ghost);
                destroy(50);
            }
        }
    }
}
