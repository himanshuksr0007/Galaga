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
// window, and warp the ghost down into the deck's minimised section: thin
// horizontal slices (~6 px each) follow the lamp curve -- the edge nearest
// the deck narrows first and most (the neck forms at the target, as on
// macOS), the far edge follows last, everything funnels into one point on
// the bottom edge, at the section's centre.
// The target is computed from the CURRENT section order (Theme.state.deck)
// on every park -- move the minimised section in Prefs and the windows
// follow it. The deck itself is always bottom-centre in this shell.
// Safety: the shell owns the park only after answering "go"; inside, a
// fallback timer parks the window even if grim hangs or fails, so a minimise
// can never be lost to the effect. Off: Prefs -> FEATURES -> genie · minimise
// (the IPC then answers "plain" and minimise.sh parks directly, as before).
// Restore (FEATURES -> genie · restore): the reverse lamp, honestly labelled --
// a parked window is unmapped, so there are no fresh pixels to un-warp. What
// expands is the park-time snapshot, kept per parked window
// (galaga-genie-keep-*.ppm in the runtime dir, at most 12, swept when a window
// leaves special:minimized any other way or the shell restarts). The real
// window is moved back FIRST, underneath the ghost, and the ghost's last
// frames crossfade into it: the end state is the live window, not the picture.
// The deck offers restores through GenieLink; no snapshot (feature off at park
// time, evicted, swept) -- the plain instant restore, exactly as before.
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
            file: `${root.run}/galaga-genie-${now}-${r.address.slice(2)}.ppm`,
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

    // ---- restore: snapshots kept per parked window, and the reverse warp ----
    property var kept: ({}) // address -> { file, gx, gy, gw, gh, tx, scr } (layout px + screen name)
    property var keepOrder: [] // park order, for eviction past the cap
    property var backPending: null

    Component.onCompleted: {
        GenieLink.handler = (addr, ws) => root.restore(addr, ws);
        GenieLink.drop = addr => root.dropKept(addr);
        // snapshots from a previous shell run are orphans -- their windows have new addresses
        Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/galaga-genie-keep-*.ppm', "sh", run]);
    }

    function keep(addr, file, gx, gy, gw, gh, tx) {
        dropKept(addr); // an older snapshot of the same window, if any
        const kf = `${run}/galaga-genie-keep-${addr.slice(2)}.ppm`;
        Quickshell.execDetached(["mv", "-f", file, kf]);
        const k = Object.assign({}, kept);
        k[addr] = { file: kf, gx: gx, gy: gy, gw: gw, gh: gh, tx: tx, scr: scr?.name ?? "" };
        kept = k;
        keepOrder = keepOrder.concat(addr);
        while (keepOrder.length > 12) dropKept(keepOrder[0]); // the cap: oldest first
    }
    function dropKept(addr) {
        if (!kept[addr] && kept["0x" + addr]) addr = "0x" + addr; // callers hold either address form
        if (kept[addr]) Quickshell.execDetached(["rm", "-f", kept[addr].file]);
        const k = Object.assign({}, kept);
        delete k[addr];
        kept = k;
        keepOrder = keepOrder.filter(a => a !== addr);
    }
    function unkeep(addr) { // registry only -- the file changes owner (a restore ghost)
        const k = Object.assign({}, kept);
        delete k[addr];
        kept = k;
        keepOrder = keepOrder.filter(a => a !== addr);
    }
    // a window that left special:minimized any other way (closed, moved by hand)
    // takes its snapshot with it; checked on a slow beat, and the deck's close
    // calls GenieLink.drop directly
    Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: {
            for (const addr of Object.keys(root.kept)) {
                const t = Hyprland.toplevels.values.find(t => t.address === addr.replace(/^0x/, ""));
                if (!t || t.workspace?.name !== "special:minimized") root.dropKept(addr);
            }
        }
    }

    function restore(addr, wsId) {
        // the deck hands over Quickshell's bare address; the registry is keyed by
        // the IPC form (0x...) the park arrived in -- resolve the key first, or the
        // lookup misses and every restore silently declines to the plain move
        const key = kept[addr] ? addr : "0x" + addr;
        const k = kept[key];
        if (!k) return false;
        unkeep(key);
        // the real window comes back FIRST, underneath: it maps at its resting place
        // while the snapshot expands over it, and the ghost's last frames crossfade
        // into it -- the end state is the live window, not the picture
        Hyprland.dispatch(`hl.dsp.window.move({ window = "address:${key}", workspace = "${wsId}", follow = true })`);
        Hyprland.refreshToplevels();
        backPending = { k: k, addr: key };
        backT.restart();
        return true;
    }
    Timer { id: backT; interval: 45; onTriggered: root.spawnBack() } // a beat for the fresh geometry
    function spawnBack() {
        const bp = backPending;
        backPending = null;
        if (!bp) return;
        if (root.ghosts.length === 0)
            root.scr = Quickshell.screens.find(s => s.name === bp.k.scr) ?? Quickshell.screens[0];
        let gx = bp.k.gx, gy = bp.k.gy, gw = bp.k.gw, gh = bp.k.gh;
        const t = Hyprland.toplevels.values.find(t => t.address === bp.addr.replace(/^0x/, ""));
        const o = t?.lastIpcObject;
        if (o?.at && o?.size) { // fresher than park time: the rect the window actually landed in
            const s = Theme.s, sx = root.scr?.x ?? 0, sy = root.scr?.y ?? 0;
            gx = (o.at[0] - sx) / s;
            gy = (o.at[1] - sy) / s;
            gw = o.size[0] / s;
            gh = o.size[1] / s;
        }
        const g = ghostC.createObject(stage, {
            addr: bp.addr, file: bp.k.file, gx: gx, gy: gy, gw: gw, gh: gh,
            tx: stage.width > 0 ? root.targetX(stage.width) : bp.k.tx, back: true, p: 1
        });
        if (!g) { Quickshell.execDetached(["rm", "-f", bp.k.file]); return; }
        root.ghosts = root.ghosts.concat(g);
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
        WlrLayershell.namespace: "galaga-genie"

        Stage { id: stage }
    }

    Component {
        id: ghostC

        Item {
            id: ghost
            anchors.fill: parent
            visible: ready
            // forward: the last sliver fades as it collapses into the point. Back: the
            // same fade on the way out of the point, and another at p -> 0, where the
            // picture crossfades into the live window already mapped beneath it
            opacity: back && p < 0.15 ? p / 0.15 : p > 0.9 ? 1 - (p - 0.9) * 8.1 : 1

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
            property bool back: false // restore ghost: p runs 1 -> 0 over the kept snapshot
            property bool ready: false
            property bool parked: false
            property bool gone: false

            // the lamp curve. The shape is macOS's: the window is sucked
            // INTO the deck, so the neck forms at the target -- the rows
            // nearest the deck narrow first and most, and the narrowing
            // travels up the window as it drains. (The first build had the
            // phase the other way round -- the deck edge stayed widest
            // longest -- which read as the window stretching like taffy
            // with a blob at the bottom, not a lamp. The user's verdict,
            // 2026-11-11.)
            // -- slices are ~6 px tall (48..140 of them), so the funnel's
            // silhouette is a curve, not a staircase;
            // -- horizontally each row follows q(v): v = 0 at the far (top)
            // edge, 1 at the deck edge. The phase runs on w = 1 - v, the
            // row's distance from the deck: a row starts narrowing at
            // p = w * spread and is SMOOTHSTEPPED through it, so the deck
            // row is fully narrow almost at once and the far row last;
            // the squeeze itself is pow(q, 2.2) -- gentle while a row is
            // still travelling, near-total as it reaches the point -- and
            // every row's centre drifts to the target x on a lagging
            // power, which is the lamp's bend;
            // -- vertically a row's distance to the bottom edge scales by
            // (1 - p) ^ (1 + 0.5 * p * u): a homothety with a taffy stretch --
            // the rows nearer the deck give way a touch faster, the far rows
            // linger, and because both factors shrink monotonically with u
            // the rows can bunch but never pass each other, for any geometry;
            // -- the texture is mapped exactly: the whole snapshot is scaled
            // to the ghost's current total height and shifted by the rows
            // above, never derived from a slice's own height, so bands cannot
            // drift against each other mid-warp.
            readonly property real spread: 0.45
            readonly property int slices: Math.max(48, Math.min(140, Math.round(gh / 6)))
            readonly property real spanY: edgeY(1) - edgeY(0) // the ghost's current total height
            function q(v) {
                const w = 1 - v; // distance from the deck edge: the neck starts there
                const t = Math.max(0, Math.min(1, (p - w * spread) / (1 - spread)));
                return t * t * (3 - 2 * t);
            }
            function edgeY(u) {
                const d = parent.height - (gy + u * gh);
                return parent.height - d * Math.pow(1 - p, 1 + 0.5 * p * u);
            }

            Repeater {
                model: ghost.slices
                Item {
                    id: slice
                    required property int index
                    readonly property real u0: index / ghost.slices
                    readonly property real u1: (index + 1) / ghost.slices
                    readonly property real v: (index + 0.5) / ghost.slices
                    readonly property real qv: ghost.q(v)
                    readonly property real cx: ghost.gx + ghost.gw / 2 + (ghost.tx - ghost.gx - ghost.gw / 2) * Math.pow(qv, 1.7)
                    readonly property real hw: ghost.gw / 2 * (1 - 0.985 * Math.pow(qv, 2.2))
                    x: cx - hw
                    y: ghost.edgeY(u0)
                    width: Math.max(0.75, hw * 2)
                    height: Math.max(1, ghost.edgeY(u1) - ghost.edgeY(u0)) + 0.8 // a hair of overlap: no seams mid-warp
                    clip: true
                    Image {
                        // this slice's band of the snapshot, squashed with it:
                        // the full frame at the ghost's current total height,
                        // shifted up by the rendered height of the rows above
                        width: slice.width
                        height: ghost.spanY
                        y: -(ghost.edgeY(slice.u0) - ghost.edgeY(0))
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
            Component.onCompleted: {
                if (back) { ready = true; backAnim.start(); } // the file already exists -- it is the kept snapshot
                else cap.exec(["sh", "-c", 'grim -t ppm -g "$1" "$2" && echo ok', "sh", raw, file]);
            }

            // the ghost is up at p = 0, pixel-identical over the live window:
            // one beat for the overlay to present, then park + warp together
            Timer {
                id: parkDelay
                interval: ghost.stagger + 30
                onTriggered: { ghost.doPark(); anim.start(); }
            }
            onReadyChanged: if (ready && !back) parkDelay.start()

            // whatever happened above -- a hung grim, a lost process -- the
            // park lands. Minimising never depends on the effect. The interval
            // stays clear of the warp itself (560 ms + the park beat)
            Timer {
                running: true
                interval: ghost.stagger + 950
                onTriggered: {
                    if (ghost.back) { ghost.finish(); return; } // the window is already back; only a stuck ghost can be lost
                    ghost.doPark();
                    if (!ghost.ready) ghost.finish();
                }
            }

            // the lamp's own timing, not the house glide: a held breath, an
            // accelerating suck, a soft landing -- easeInOut over 560 ms
            NumberAnimation {
                id: anim
                target: ghost
                property: "p"
                from: 0
                to: 1
                duration: 560
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.42, 0.0, 0.58, 1.0]
                onFinished: ghost.finish()
            }
            NumberAnimation {
                id: backAnim
                target: ghost
                property: "p"
                from: 1
                to: 0
                duration: 520
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.42, 0.0, 0.58, 1.0]
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
                // a forward ghost that actually parked hands its snapshot to the kept
                // registry when genie restore is on -- that file is the reverse warp's
                // pixels. Everything else: the file goes, as before
                if (!back && parked && Theme.state.featGenieBack) root.keep(addr, file, gx, gy, gw, gh, tx);
                else Quickshell.execDetached(["rm", "-f", file]);
                root.ghosts = root.ghosts.filter(g => g !== ghost);
                destroy(50);
            }
        }
    }
}
