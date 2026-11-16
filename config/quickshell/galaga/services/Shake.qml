pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs

// aero shake (settings -> features): shake a window you are dragging --
// quick back-and-forth -- and every other window on its workspace parks;
// shake again (any later drag) and they come back. Like windows, it fires
// mid-drag, while the shaken window is still in hand.
//
// Detection rides DragWatch's motion events only: each one carries the
// cursor, and a shake is read off the cursor's x -- a leg is a run of at
// least 30 px in one direction, a reversal a run of 30 px back, and three
// reversals inside 900 ms of each other are a shake. In the sampling
// world (no hyprdrag plugin) there is no motion stream, so the feature
// is simply inert -- the same terms as Snap's live follow, which reads
// the same events.
//
// Park and restore go through the ordinary minimise machinery, so a
// shaken-away window is a minimised window in every other respect: it
// parks through Snap.minimise (minimise.sh, the genie snapshot and all),
// sits in the deck's minimised section, and restores the deck's way --
// the genie gets first refusal when it kept a snapshot, the plain move
// otherwise, back to the workspace it was shaken from. `parked` is
// runtime state: a shell restart forgets the list, and the windows just
// stay minimised windows, restorable from the deck like any other.
Singleton {
    id: root

    readonly property bool on: Theme.state.featShake // shell.qml reads this to start the service

    // ---- the shake's memory: what the last shake put away ----
    property var parked: [] // [{ addr, ws }], bare addresses, in park order

    // ---- detection state, one move drag at a time ----
    property string dragAddr: "" // the window in hand, bare hex; "" -- no move drag
    property int dir: 0          // the current leg: 1 right, -1 left, 0 not committed yet
    property var anchor: null    // the current leg's extreme cursor x; null until the drag's first sample
    property int reversals: 0
    property real lastRevT: 0    // Date.now() of the last reversal
    property bool fired: false   // one shake per drag, however long it goes on

    function bare(a) {
        return a.startsWith("0x") ? a.slice(2) : a;
    }
    function top(addr) {
        const ts = Hyprland.toplevels.values;
        for (let i = 0; i < ts.length; i++)
            if (ts[i].address === addr) return ts[i];
        return null;
    }
    function reset() {
        dragAddr = "";
        dir = 0;
        anchor = null;
        reversals = 0;
        lastRevT = 0;
        fired = false;
    }

    Connections {
        target: DragWatch
        function onDragStarted(kind, addr) {
            root.reset();
            if (kind === "move") root.dragAddr = root.bare(addr);
        }
        function onDragMotion(kind, addr, rect, cur) {
            if (kind !== "move" || !Theme.state.featShake || !DragWatch.motionAlive) return;
            if (!root.dragAddr || root.bare(addr) !== root.dragAddr) return;
            root.track(cur.x);
        }
        function onDragStopped(kind, addr) {
            root.reset();
        }
    }

    // one cursor sample. The anchor holds the leg's extreme: the leg
    // extends while the cursor runs past it, and only a 30 px run back
    // off it counts as a reversal -- small hand jitter never reaches 30.
    function track(x) {
        if (fired) return;
        if (anchor === null) { anchor = x; return; }
        if (dir === 0) {
            // no leg yet: the first 30 px run either way commits one
            if (Math.abs(x - anchor) >= 30) { dir = x > anchor ? 1 : -1; anchor = x; }
            return;
        }
        if (dir === 1) {
            if (x > anchor) anchor = x;
            else if (anchor - x >= 30) { dir = -1; anchor = x; countRev(); }
        } else {
            if (x < anchor) anchor = x;
            else if (x - anchor >= 30) { dir = 1; anchor = x; countRev(); }
        }
    }
    function countRev() {
        const now = Date.now();
        // a leg that took its time is a new shake starting, not this one
        // continuing: the count restarts at 1
        reversals = now - lastRevT <= 900 ? reversals + 1 : 1;
        lastRevT = now;
        if (reversals >= 3) { fired = true; shake(); }
    }

    function shake() {
        if (!Theme.state.featShake) return;
        if (parked.length) {
            // back they come, each to the workspace it was shaken from.
            // Gone meanwhile -- the entry goes with it; already back by
            // another path (the deck) -- nothing to do. The list clears
            // either way.
            const list = parked;
            parked = [];
            for (const e of list) {
                const t = top(e.addr);
                if (!t) continue;
                if (t.workspace?.name !== "special:minimized") continue;
                if (Theme.state.featGenieBack && GenieLink.handler && GenieLink.handler(e.addr, e.ws)) continue;
                Hyprland.dispatch(`hl.dsp.window.move({ window = "address:0x${e.addr}", workspace = "${e.ws}", follow = false })`);
            }
            return;
        }
        const dt = top(dragAddr);
        if (!dt || !dt.workspace) return;
        const wsId = dt.workspace.id;
        if (wsId === undefined || wsId < 0) return; // a special workspace: nothing to clear
        const others = Hyprland.toplevels.values.filter(t => t.address !== dragAddr && t.workspace && t.workspace.id === wsId);
        if (!others.length) return;
        parked = others.map(t => ({ addr: t.address, ws: wsId }));
        for (const e of parked) Snap.minimise("0x" + e.addr);
    }
}
