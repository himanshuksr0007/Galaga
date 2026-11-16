pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs
import qs.settings

// windows-style snapping (settings -> windows -> snapping). Super+arrows snap the
// focused window into halves, corners and the full work area; Super+Z opens the
// layouts popup (snap/SnapPop.qml), which fills a layout's spaces one pick at a
// time (snap assist). The layout engine is dwindle, so a snapped window FLOATS at
// an exact size; unsnapping gives back whatever it was before the first snap --
// tiled, or floating at its old geometry, kept per window in recs.
//
// Groups: windows placed by one action (an arrow snap plus its assist picks, a
// layout plus its picks) share a group -- and so does any set of records whose
// placed rects share a full edge. regroup() rebuilds the groups per workspace
// from the stored rects after every placement, so the rule is one and the same
// however the windows got there. A group never spans workspaces, and holds at
// most four windows (the grid is the largest layout). Grouped windows resize
// together: resize one and the watcher moves the shared boundary for its
// neighbours (linkedResize below; settings -> windows -> resize neighbours).
//
// Geometry has no hyprland event and a toplevel's lastIpcObject is a snapshot
// from the last full fetch, so actions and the group watcher both read fresh
// `hyprctl clients -j` / `monitors -j` (the Game service's Process shape). The
// watcher polls while a group exists -- every 200 ms, and every 100 ms on a
// clients-only fetch while a drag is on, so a linked resize follows the
// pointer instead of trailing it. Our own dispatch
// batches are fenced by a 150 ms guard so the poll never mistakes one of our
// placements for the user dragging a window away.
//
// Dragging is the third way in, and the drag tracker at the bottom is its
// watcher: it samples the focused window and the cursor on its own small
// fetch. A window that moves at one size, held by one point of it, is a hand
// drag; the zone under the cursor previews (snap/SnapZone.qml), and letting
// go on an edge or a corner places the window there. With the hyprdrag
// plugin (DragWatch alive) the tracker idles between drags: the events
// start it -- the first sample is the pre-drag baseline -- and stop it, and
// the release is the stop event rather than a still-tick guess; without the
// plugin the 250 ms cycle runs whenever drag-snapping is on, as it did.
Singleton {
    id: root

    // addr (hyprctl form, with 0x) -> { zone, rect, lastZone, pre { floating, x, y, w, h }, ws }
    property var recs: ({})
    // group id -> [addr]
    property var groups: ({})
    property int gidSeq: 0
    property double guardUntil: 0

    // the layouts popup's state -- snap/SnapPop.qml only renders this
    property bool popOpen: false
    property string popMode: ""    // "layouts" | "assist"
    property var assistZones: []   // [{ zone, frac, rect, label }] still to fill, in order
    property var assistCands: []   // [{ addr, title, cls }] the other windows on assistWs
    property int assistWs: -1

    // canonical zones as fractions of the gap-inset work area
    readonly property var zf: ({
        L: [0, 0, 0.5, 1], R: [0.5, 0, 0.5, 1], T: [0, 0, 1, 0.5], B: [0, 0.5, 1, 0.5],
        TL: [0, 0, 0.5, 0.5], TR: [0.5, 0, 0.5, 0.5], BL: [0, 0.5, 0.5, 0.5], BR: [0.5, 0.5, 0.5, 0.5],
        MAX: [0, 0, 1, 1]
    })
    readonly property var zlabel: ({ L: "left half", R: "right half", T: "top half", B: "bottom half",
        TL: "top left", TR: "top right", BL: "bottom left", BR: "bottom right", MAX: "the whole screen" })
    // the popup's six layouts: zone 1 takes the focused window, the rest are assist picks
    readonly property var layouts: [
        { name: "side by side", zones: [
            { f: [0, 0, 0.5, 1], zone: "L", label: "left half" },
            { f: [0.5, 0, 0.5, 1], zone: "R", label: "right half" }] },
        { name: "stacked", zones: [
            { f: [0, 0, 1, 0.5], zone: "T", label: "top half" },
            { f: [0, 0.5, 1, 0.5], zone: "B", label: "bottom half" }] },
        { name: "three columns", zones: [
            { f: [0, 0, 1 / 3, 1], zone: "lay", label: "left column" },
            { f: [1 / 3, 0, 1 / 3, 1], zone: "lay", label: "middle column" },
            { f: [2 / 3, 0, 1 / 3, 1], zone: "lay", label: "right column" }] },
        { name: "grid", zones: [
            { f: [0, 0, 0.5, 0.5], zone: "TL", label: "top left" },
            { f: [0.5, 0, 0.5, 0.5], zone: "TR", label: "top right" },
            { f: [0, 0.5, 0.5, 0.5], zone: "BL", label: "bottom left" },
            { f: [0.5, 0.5, 0.5, 0.5], zone: "BR", label: "bottom right" }] },
        { name: "main + side", zones: [
            { f: [0, 0, 0.6, 1], zone: "lay", label: "main" },
            { f: [0.6, 0, 0.4, 1], zone: "lay", label: "side" }] },
        { name: "side + main", zones: [
            { f: [0, 0, 0.4, 1], zone: "lay", label: "side" },
            { f: [0.4, 0, 0.6, 1], zone: "lay", label: "main" }] }
    ]

    // ---- fresh state: one fetch feeds one action, or one watcher tick ----

    property var snapC: null // last clients list
    property var snapM: null // last monitors list
    property var snapA: null // last activewindow object ({} when nothing is focused)
    property bool fetching: false
    property bool haveC: false
    property bool haveM: false
    property bool haveA: false
    property var pendingAct: null
    // arrange-on-open bookkeeping: when each address was first seen, and
    // which addresses the current observe pass is seeing for the first time
    property var seenAt: ({})
    property var freshNow: []

    Process {
        id: pc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.snapC = JSON.parse(text); } catch (e) { root.snapC = null; }
                root.haveC = true;
                root.fetched();
            }
        }
    }
    Process {
        id: pm
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.snapM = JSON.parse(text); } catch (e) { root.snapM = null; }
                root.haveM = true;
                root.fetched();
            }
        }
    }
    Process {
        id: pa
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.snapA = JSON.parse(text); } catch (e) { root.snapA = null; }
                root.haveA = true;
                root.fetched();
            }
        }
    }
    // act runs once all three are in; with no act the fetch feeds the watcher
    function fetch(act) {
        if (act) pendingAct = act;
        if (fetching) return;
        fetching = true;
        haveC = false;
        haveM = false;
        haveA = false;
        pc.running = true;
        pm.running = true;
        pa.running = true;
    }
    function fetched() {
        if (!haveC || !haveM || !haveA) return;
        fetching = false;
        const act = pendingAct;
        pendingAct = null;
        if (act) act();
        else observe();
    }
    // the watcher's hot path while a drag is on: clients only (observe()
    // needs nothing else), one process instead of three, so a tick lands
    // fast enough for a linked resize to follow the pointer. Skipped while
    // a full fetch is in flight -- its observe() covers the tick.
    property bool wFetching: false
    Process {
        id: pw
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wFetching = false;
                try { root.snapC = JSON.parse(text); root.observe(); } catch (e) { }
            }
        }
    }
    function watchFetch() {
        if (wFetching || fetching) return;
        wFetching = true;
        pw.running = true;
    }
    Timer {
        // while a drag is on the watcher runs hot (the 100 ms clients-only
        // fetch above); the rest of the time it idles at 200 ms on the
        // full fetch
        interval: DragWatch.dragging ? 100 : 200
        repeat: true
        // legacy (no hyprdrag): while a group exists. Event mode: only
        // while a drag is on and for a second after it ends (settleT),
        // plus the slow sweep below and one fetch on every drag stop --
        // a grouped window resized or moved from the keyboard is picked
        // up by the sweep (within 2 s) instead of the next 200 ms tick.
        running: Object.keys(root.groups).length > 0
                 && (!DragWatch.alive || DragWatch.dragging || settleT.running)
        onTriggered: {
            if (root.fetching || root.pendingAct) return;
            if (DragWatch.dragging) root.watchFetch();
            else root.fetch(null);
        }
    }
    // the event-mode settle window after a drag stops (see above)
    Timer { id: settleT; interval: 1000 }
    Timer {
        interval: 2000
        repeat: true
        running: DragWatch.alive && Object.keys(root.groups).length > 0
        onTriggered: if (!root.fetching && !root.pendingAct) root.fetch(null)
    }
    Timer {
        // no setup is known yet: a slow look every 5 s, and one at
        // startup, so an arrangement already sitting on a workspace --
        // placed by hand, or left there by a shell restart, records
        // being memory-only -- is adopted without waiting for a snap
        // action. Once a group forms the watchers above own the cadence
        // and this stops.
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: Theme.state.snap && Object.keys(root.groups).length === 0
        onTriggered: if (!root.fetching && !root.pendingAct) root.fetch(null)
    }
    // a window that might pair on open gets one more look once it has had
    // a moment to settle into its first geometry (see openArrange)
    Timer {
        id: openT
        interval: 650
        onTriggered: if (!root.fetching && !root.pendingAct) root.fetch(null)
    }

    // ---- snapshot helpers ----

    function client(addr) {
        return (snapC ?? []).find(c => c.address === addr) ?? null;
    }
    function focusedAddr() {
        // the focused window comes from the same hyprctl fetch as everything
        // else, so its address is already in the client list's 0x form and
        // client() finds it. (The toplevel manager's address never matched
        // the list, and every entry point silently found no window at all.)
        return snapA?.address ?? "";
    }
    function monOf(c) {
        return (snapM ?? []).find(m => m.id === c.monitor) ?? (snapM ?? []).find(m => m.focused) ?? null;
    }
    // the work area in logical px: the monitor's rect minus what the layers reserve
    function workarea(m) {
        const w = Math.round(m.width / m.scale), h = Math.round(m.height / m.scale);
        const r = m.reserved ?? [0, 0, 0, 0];
        return { x: m.x + r[0], y: m.y + r[1], w: w - r[0] - r[2], h: h - r[1] - r[3] };
    }
    // a zone rect: the fraction of the work area, inset by gaps out at the edges
    // and by half of gaps in on every shared edge -- two snapped halves sit
    // exactly gaps-in apart, like the tiler's own windows
    function zoneRect(f, wa) {
        const go = Rules.store.gapsOut, gi = Rules.store.gapsIn;
        const x0 = wa.x + go, y0 = wa.y + go, w = wa.w - 2 * go, h = wa.h - 2 * go;
        let x = x0 + f[0] * w, y = y0 + f[1] * h, zw = f[2] * w, zh = f[3] * h;
        if (f[0] > 0) { x += gi / 2; zw -= gi / 2; }
        if (f[1] > 0) { y += gi / 2; zh -= gi / 2; }
        if (f[0] + f[2] < 1) zw -= gi / 2;
        if (f[1] + f[3] < 1) zh -= gi / 2;
        return { x: Math.round(x), y: Math.round(y), w: Math.round(zw), h: Math.round(zh) };
    }
    // the apps that draw their own window buttons, and so get no hyprbars
    // bar -- the same classes as the ownButtons list in rules.lua, which
    // the no_bar rule is built from (keep the two in step). Every other
    // window carries the 32-tall bar at its top.
    readonly property var ownButtons: [/^org\.gnome\..*$/, /^gnome-control-center$/, /^Code$/, /^VSCodium$/, /^codium$/,
        /^steam$/, /^discord$/, /^vesktop$/, /^equibop$/, /^firefox$/, /^org\.mozilla\.firefox$/, /^firefox-esr$/,
        /^zen$/, /^app\.zen_browser\.zen$/, /^io\.github\.zen_browser\.zen$/, /^org\.quickshell$/]
    function hasBar(cls) { return !!cls && !ownButtons.some(r => r.test(cls)); }
    // the rect a window is actually placed with: a window carrying the bar,
    // set into a zone that touches the top, starts 32 lower -- its whole
    // bar sits below the pill, not just its client area. The MAX zone is
    // exempt (a maximised window hugs the strip, like the tiler's own lone
    // window), and so are the own-buttons apps: no bar, no clearance.
    function placedRect(addr, f, wa) {
        const r = zoneRect(f, wa);
        const c = client(addr);
        if (c && Theme.state.barAt === "top" && f[1] === 0 && !(f[0] === 0 && f[2] === 1 && f[3] === 1) && hasBar(c.class))
            return { x: r.x, y: r.y + 32, w: r.w, h: r.h - 32 };
        return r;
    }
    function rectOf(c) {
        return { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] };
    }
    function rectEq(a, b, tol) {
        return a && b && Math.abs(a.x - b.x) <= tol && Math.abs(a.y - b.y) <= tol
            && Math.abs(a.w - b.w) <= tol && Math.abs(a.h - b.h) <= tol;
    }

    // ---- dispatchers (hyprland's lua api, addressed like the deck addresses windows) ----

    function dsp(s) { Hyprland.dispatch(s); }
    function moveStr(a, r) { return `hl.dsp.window.move({ x = ${r.x}, y = ${r.y}, relative = false, window = "address:${a}" })`; }
    function resizeStr(a, r) { return `hl.dsp.window.resize({ x = ${r.w}, y = ${r.h}, window = "address:${a}" })`; }
    function floatStr(a, on) { return `hl.dsp.window.float({ action = "${on ? "on" : "off"}", window = "address:${a}" })`; }
    function guard() { guardUntil = Date.now() + 150; }

    // ---- records ----

    function saveRec(addr, rec) {
        const n = Object.assign({}, recs);
        n[addr] = rec;
        recs = n;
    }
    function dropRec(addr) {
        if (!(addr in recs)) return;
        const n = Object.assign({}, recs);
        delete n[addr];
        recs = n;
    }
    function groupOf(addr) {
        for (const g in groups) if (groups[g].includes(addr)) return g;
        return "";
    }
    // full-edge sharing between two placed rects: the edges face each
    // other across the inner gap and both windows run its whole length.
    // Placed rects never touch -- zoneRect keeps gapsIn between
    // neighbours -- so the test has to expect the gap, not coincidence:
    // with gaps_in at 6, a coincidence test leaves every placed pair
    // ungrouped and linked resize with nothing to link.
    // side by side: the inner edges touch, the bottoms sit on one line and
    // the spans overlap. The tops may differ -- a window with the bar
    // starts 32 lower than an own-buttons one in the same pair of zones.
    function shareV(a, b) { return Math.abs(a.x + a.w + Rules.store.gapsIn - b.x) <= 2 && Math.abs((a.y + a.h) - (b.y + b.h)) <= 2 && spansOverlap(a.y, a.h, b.y, b.h); }
    function shareH(a, b) { return Math.abs(a.y + a.h + Rules.store.gapsIn - b.y) <= 2 && Math.abs(a.x - b.x) <= 2 && Math.abs(a.w - b.w) <= 2; }
    function linked(a, b) { return shareV(a, b) || shareV(b, a) || shareH(a, b) || shareH(b, a); }
    function regroupWs(ws) {
        const mine = Object.keys(recs).filter(a => recs[a].ws === ws);
        const old = groups, ng = {};
        for (const g in old)
            if (!old[g].some(a => recs[a] && recs[a].ws === ws)) ng[g] = old[g];
        const seen = {};
        for (const a of mine) {
            if (seen[a]) continue;
            const comp = [], stack = [a];
            seen[a] = true;
            while (stack.length) {
                const x = stack.pop();
                comp.push(x);
                for (const b of mine)
                    if (!seen[b] && linked(recs[x].rect, recs[b].rect)) { seen[b] = true; stack.push(b); }
            }
            if (comp.length < 2) continue;
            const key = comp.slice().sort().join(",");
            const keep = Object.keys(old).find(g => old[g].slice().sort().join(",") === key);
            ng[keep ?? ("g" + (++gidSeq))] = comp;
        }
        groups = ng;
    }

    // ---- placing and restoring ----

    // snap one window into a rect. The first snap of a window captures what it
    // was (tiled, or floating where) -- that is what restore gives back.
    // (preOver: a caller that saw the window before it moved -- the drag
    // tracker -- hands that state over; a window with a record keeps its own.)
    function place(addr, rect, zone, preOver) {
        const c = client(addr);
        if (!c) return;
        let rec = recs[addr];
        if (!rec) {
            rec = { zone: "", rect: null, lastZone: "", ws: c.workspace.id,
                    pre: preOver ?? { floating: !!c.floating, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] } };
        }
        if (rec.zone && rec.zone !== zone) rec.lastZone = rec.zone;
        if ((c.fullscreen ?? 0) > 0)
            dsp(`hl.dsp.window.fullscreen({ mode = "fullscreen", action = "off", window = "address:${addr}" })`);
        if (!c.floating) dsp(floatStr(addr, true));
        dsp(resizeStr(addr, rect));
        dsp(moveStr(addr, rect));
        rec.zone = zone;
        rec.rect = rect;
        rec.ws = c.workspace.id;
        saveRec(addr, rec);
        guard();
        Sounds.play("tick");
    }
    function restore(addr) {
        const rec = recs[addr];
        if (!rec) return;
        const ws = rec.ws, pre = rec.pre;
        dropRec(addr);
        if (pre.floating) {
            dsp(resizeStr(addr, pre));
            dsp(moveStr(addr, pre));
        } else {
            dsp(floatStr(addr, false)); // the tiler takes it back
        }
        guard();
        Sounds.play("tick");
        regroupWs(ws);
    }
    function minimise(addr) {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/minimise.sh", addr]);
    }

    // ---- super+arrows ----

    function snapDir(dir) {
        if (!Theme.state.snap) { // off: the arrows are focus keys again, as they were
            Hyprland.dispatch(`hl.dsp.focus({ direction = "${dir}" })`);
            return;
        }
        fetch(() => snapDirNow(dir));
    }
    function snapDirNow(dir) {
        const addr = focusedAddr();
        if (!addr) return;
        const c = client(addr);
        if (!c || c.workspace.id < 0) return; // parked or nowhere: nothing to snap
        const mon = monOf(c);
        if (!mon) return;
        const wa = workarea(mon), rec = recs[addr], zone = rec?.zone ?? "";
        let target = "", frac = null;
        if (dir === "left") {
            if (zone === "L") return;
            target = "L"; frac = zf.L;
        } else if (dir === "right") {
            if (zone === "R") return;
            target = "R"; frac = zf.R;
        } else if (dir === "up") {
            if (zone === "MAX") return;
            if (zone === "L") { target = "TL"; frac = zf.TL; }
            else if (zone === "R") { target = "TR"; frac = zf.TR; }
            else if (zone === "BL") { target = "L"; frac = zf.L; }
            else if (zone === "BR") { target = "R"; frac = zf.R; }
            else if (zone === "B") {
                const left = c.at[0] + c.size[0] / 2 < wa.x + wa.w / 2;
                target = left ? "BL" : "BR"; frac = left ? zf.BL : zf.BR;
            } else { target = "MAX"; frac = zf.MAX; } // free, T, TL, TR, a layout space
        } else { // down
            if (!rec) { minimise(addr); return; }
            if (zone === "TL" || zone === "BL") { target = "L"; frac = zf.L; }
            else if (zone === "TR" || zone === "BR") { target = "R"; frac = zf.R; }
            else if (zone === "MAX" && rec.lastZone && zf[rec.lastZone]) { target = rec.lastZone; frac = zf[rec.lastZone]; }
            else { restore(addr); return; } // a half, a layout space, or MAX with nowhere to go back to
        }
        place(addr, placedRect(addr, frac, wa), target);
        regroupWs(c.workspace.id);
        maybeAssist(addr, target, wa, c.workspace.id);
    }

    // ---- snap assist ----

    function complements(zone) {
        return ({ L: ["R"], R: ["L"], T: ["B"], B: ["T"],
                  TL: ["TR", "BL", "BR"], TR: ["TL", "BR", "BL"],
                  BL: ["TL", "BR", "TR"], BR: ["TR", "BL", "TL"] })[zone] ?? [];
    }
    function candidates(ws, exclude) {
        return (snapC ?? [])
            .filter(c => c.workspace.id === ws && c.address !== exclude)
            .map(c => ({ addr: c.address, title: c.title || c.class || "", cls: c.class ?? "" }));
    }
    // after an arrow snap: if the rest of the shape is empty and there is
    // anything to fill it with, the popup offers those windows one at a time
    function maybeAssist(addr, zone, wa, ws) {
        if (!Theme.state.snapAssist) return;
        const comp = complements(zone);
        if (!comp.length) return;
        const empty = comp
            .map(z => ({ zone: z, frac: zf[z], rect: zoneRect(zf[z], wa), label: zlabel[z] }))
            .filter(z => !Object.keys(recs).some(a => recs[a].ws === ws && (recs[a].zone === z.zone || rectEq(recs[a].rect, z.rect, 6)))
                      && !(snapC ?? []).some(c => c.address !== addr && c.workspace.id === ws && rectEq(rectOf(c), z.rect, 6)));
        if (!empty.length) return;
        const cands = candidates(ws, addr);
        if (!cands.length) return;
        assistZones = empty;
        assistWs = ws;
        assistCands = cands;
        popMode = "assist";
        popOpen = true;
    }
    function chooseAssist(addr) {
        if (popMode !== "assist" || !assistZones.length) return;
        const z = assistZones[0];
        fetch(() => {
            const c = client(addr);
            if (!c) { popCancel(); return; }
            const mon = monOf(c);
            if (!mon) { popCancel(); return; }
            place(addr, placedRect(addr, z.frac, workarea(mon)), z.zone);
            regroupWs(assistWs);
            assistZones = assistZones.slice(1);
            assistCands = candidates(assistWs, "");
            if (!assistZones.length || !assistCands.length) popClose();
        });
    }

    // ---- the layouts popup (super+z) ----

    function toggleLayouts() {
        if (popOpen) { popCancel(); return; }
        if (!Theme.state.snap) return;
        popMode = "layouts";
        popOpen = true;
        Sounds.play("pop");
    }
    function chooseLayout(i) {
        const lay = layouts[i];
        if (!lay || popMode !== "layouts") return;
        fetch(() => {
            const addr = focusedAddr(), c = addr ? client(addr) : null;
            if (!c || c.workspace.id < 0) { popCancel(); return; }
            const mon = monOf(c);
            if (!mon) { popCancel(); return; }
            const wa = workarea(mon), z0 = lay.zones[0];
            place(addr, placedRect(addr, z0.f, wa), z0.zone);
            regroupWs(c.workspace.id);
            const rest = lay.zones.slice(1).map(z => ({ zone: z.zone, frac: z.f, rect: zoneRect(z.f, wa), label: z.label }));
            const cands = candidates(c.workspace.id, addr);
            if (Theme.state.snapAssist && rest.length && cands.length) {
                assistZones = rest;
                assistWs = c.workspace.id;
                assistCands = cands;
                popMode = "assist"; // the popup stays up and turns into the picker
            } else popClose();
        });
    }
    // a whole layout at once: windows[k] takes zones[k], no picking
    function applyLayout(i, addrs) {
        const lay = layouts[i];
        if (!lay) return;
        fetch(() => {
            const first = addrs.length ? client(addrs[0]) : null;
            if (!first) return;
            const mon = monOf(first);
            if (!mon) return;
            const wa = workarea(mon);
            addrs.slice(0, lay.zones.length).forEach((a, k) => place(a, placedRect(a, lay.zones[k].f, wa), lay.zones[k].zone));
            regroupWs(first.workspace.id);
        });
    }
    function popClose() {
        popOpen = false;
        popMode = "";
        assistZones = [];
        assistCands = [];
    }
    function popCancel() { popClose(); } // esc / super+z again: placed windows keep their group

    // ---- the watcher: membership and geometry, while any group exists ----

    function observe() {
        if (!snapC) return;
        // who is new: stamp first sightings, forget the closed. A window
        // first seen in this same pass can be arranged but can never be
        // the lone window it pairs with, so a shell start -- where every
        // window is new at once -- rearranges nothing.
        const nowMs = Date.now();
        const aliveNow = {};
        freshNow = [];
        for (const c of snapC) {
            aliveNow[c.address] = true;
            if (!(c.address in seenAt)) { seenAt[c.address] = nowMs; freshNow.push(c.address); }
        }
        for (const a in seenAt) if (!aliveNow[a]) delete seenAt[a];
        const touched = {};
        // the pass reads the records as they were when it started:
        // linkedResize writes a mate's new rect into the live records
        // mid-pass, while the mate's entry in this fetch still shows its
        // old rect -- judging the mate by the live record would learn
        // the stale rect straight back over the resize's target, and the
        // next pass would mistake the landed resize for a fresh one
        const passRecs = recs;
        for (const addr of Object.keys(passRecs)) {
            const rec = passRecs[addr], c = client(addr);
            // closed, moved to another desktop, fullscreen, or back in the
            // tiler's hands: the record is done, the window is left as it is
            if (!c || c.workspace.id !== rec.ws || (c.fullscreen ?? 0) > 0 || !c.floating) {
                touched[rec.ws] = true;
                dropRec(addr);
                continue;
            }
            if (dragT && addr === dragT.addr) continue; // in a hand drag: its fate is decided at release
            const cur = rectOf(c);
            if (rectEq(cur, rec.rect, 0)) continue;
            if (Date.now() < guardUntil) { // our own placement landing: just learn it
                rec.rect = cur;
                saveRec(addr, rec);
                continue;
            }
            const sizeSame = cur.w === rec.rect.w && cur.h === rec.rect.h;
            if (sizeSame) {
                // dragged away whole: a free window again -- record cleared,
                // left floating exactly where it was dropped
                touched[rec.ws] = true;
                dropRec(addr);
                continue;
            }
            // resized. In a group, with linked resize on, the neighbours'
            // shared edges follow and the record learns the new rect; anywhere
            // else the window has left its space, and the record ends with it.
            const gid = groupOf(addr);
            if (Theme.state.snapLinked && gid) {
                linkedResize(addr, rec.rect, cur, gid);
                rec.rect = cur;
                saveRec(addr, rec);
            } else {
                touched[rec.ws] = true;
                dropRec(addr);
            }
        }
        for (const ws in touched) regroupWs(Number(ws));
        openArrange();
        adopt();
    }

    // ---- arrange on open: a window that opens beside a lone window
    // filling the screen does not land on top of it or behind it -- the
    // two are placed side by side and grouped, the arrangement a person
    // would otherwise make by hand. The tiler's own splits are left
    // alone: there the first window stops filling the screen the moment
    // the second one lands, so the test below simply never matches.
    // Dialogs and tools stay out: a small floating window is doing what
    // it was told, and a fullscreen window is left to its fullscreen.
    function openArrange() {
        if (!Theme.state.snap || !Theme.state.snapOpen || popOpen || DragWatch.dragging || dragT) return;
        for (const addr of freshNow) {
            const n = client(addr);
            if (!n || recs[addr] || (n.fullscreen ?? 0) > 0 || n.workspace.id < 0) continue;
            if ((n.class ?? "") === "org.quickshell") continue; // the shell's own windows float by rule
            const ws = n.workspace.id;
            const others = (snapC ?? []).filter(c => c.workspace.id === ws && c.address !== addr);
            if (others.length !== 1) continue;
            const o = others[0];
            if (freshNow.includes(o.address) || groupOf(o.address)) continue;
            if ((o.fullscreen ?? 0) > 0 || (o.class ?? "") === "org.quickshell") continue;
            const mon = monOf(o);
            if (!mon) continue;
            const wa = workarea(mon);
            // the lone window fills the screen -- a snap maximise, a hand
            // maximise, the tiler's single tile. Anything less is a
            // deliberate float and stays exactly as it is.
            if (!rectEq(rectOf(o), zoneRect(zf.MAX, wa), 10)) continue;
            const nr = rectOf(n);
            if (n.floating && nr.w * nr.h < 0.8 * wa.w * wa.h) continue;
            // a new window's first geometry is not always its settled one
            // (a browser restoring its size, a slow first map): give it a
            // moment, then look again with a fresh fetch
            if (Date.now() - (seenAt[addr] ?? 0) < 600) { openT.restart(); continue; }
            place(o.address, placedRect(o.address, zf.L, wa), "L");
            place(addr, placedRect(addr, zf.R, wa), "R");
            regroupWs(ws);
            return; // one pair per pass; another new window gets the next
        }
    }

    // ---- adoption: a setup is understood from its geometry, not from
    // how it was made. Floating windows that sit in a tiling arrangement
    // -- full edges shared across the inner gap, the same test groups are
    // built with -- are taken in as records, so linked resize, the fill
    // and the rest of the pair manners apply without anyone pressing
    // Super+Z first: a pair arranged by hand, or left sitting on the
    // workspace by a shell restart (records live in memory), is a setup
    // the moment it is seen. Nothing is moved; the record just learns
    // where the window already is. Tiled windows are left alone -- the
    // layout already understands them.
    function adopt() {
        if (!Theme.state.snap || DragWatch.dragging || dragT) return;
        const byWs = {};
        for (const c of (snapC ?? [])) {
            if (recs[c.address] || !c.floating || (c.fullscreen ?? 0) > 0 || c.workspace.id < 0) continue;
            if (!byWs[c.workspace.id]) byWs[c.workspace.id] = [];
            byWs[c.workspace.id].push(c);
        }
        for (const ws in byWs) {
            const placed = Object.keys(recs).filter(a => recs[a].ws === Number(ws))
                                 .map(a => ({ address: a, rect: recs[a].rect }));
            const all = placed.concat(byWs[ws].map(c => ({ address: c.address, rect: rectOf(c) })));
            const seen = {};
            for (const n of all) {
                if (seen[n.address]) continue;
                const comp = [], stack = [n];
                seen[n.address] = true;
                while (stack.length) {
                    const x = stack.pop();
                    comp.push(x);
                    for (const b of all)
                        if (!seen[b.address] && linked(x.rect, b.rect)) { seen[b.address] = true; stack.push(b); }
                }
                if (comp.length < 2) continue;
                for (const m of comp) {
                    if (recs[m.address]) continue;
                    const c = client(m.address);
                    if (!c) continue;
                    saveRec(m.address, { zone: zoneOfRect(m.rect, c), rect: m.rect, lastZone: "", ws: Number(ws),
                                         pre: { floating: true, x: m.rect.x, y: m.rect.y, w: m.rect.w, h: m.rect.h } });
                }
            }
            regroupWs(Number(ws));
        }
    }
    // the zone a rect already matches, if any (an adopted window keeps
    // its Super+arrow stepping when its space is a named zone)
    function zoneOfRect(r, c) {
        const mon = monOf(c);
        if (!mon) return "";
        const wa = workarea(mon);
        for (const z in zf) if (rectEq(r, zoneRect(zf[z], wa), 4)) return z;
        return "";
    }

    function spansOverlap(p1, l1, p2, l2) { return p1 < p2 + l2 && p2 < p1 + l1; }
    // M was resized from oldR to newR: every group mate sharing an edge with
    // M's old rect has that boundary moved to M's new edge, the inner gap
    // preserved -- its far edge stays, so it grows or shrinks into the space. In a 2x2 group a corner
    // window shares one vertical and one horizontal edge, so both mates move
    // and the cross follows. A mate that would end up under 240x160 is left.
    function linkedResize(addr, oldR, newR, gid) {
        let applied = false;
        const gi = Rules.store.gapsIn; // the shared boundary sits across the inner gap, and keeps it
        for (const n of (groups[gid] ?? [])) {
            if (n === addr) continue;
            const nr = recs[n];
            if (!nr) continue;
            const r = nr.rect;
            let nx = r.x, ny = r.y, nw = r.w, nh = r.h, adj = false;
            if (Math.abs(oldR.x + oldR.w + gi - r.x) <= 3 && spansOverlap(oldR.y, oldR.h, r.y, r.h)) {
                const b = newR.x + newR.w + gi; nx = b; nw = r.x + r.w - b; adj = true;
            } else if (Math.abs(oldR.x - gi - (r.x + r.w)) <= 3 && spansOverlap(oldR.y, oldR.h, r.y, r.h)) {
                nw = newR.x - gi - r.x; adj = true;
            }
            if (Math.abs(oldR.y + oldR.h + gi - r.y) <= 3 && spansOverlap(oldR.x, oldR.w, r.x, r.w)) {
                const b = newR.y + newR.h + gi; ny = b; nh = r.y + r.h - b; adj = true;
            } else if (Math.abs(oldR.y - gi - (r.y + r.h)) <= 3 && spansOverlap(oldR.x, oldR.w, r.x, r.w)) {
                nh = newR.y - gi - r.y; adj = true;
            }
            if (!adj || nw < 240 || nh < 160) continue;
            const nrect = { x: nx, y: ny, w: nw, h: nh };
            dsp(resizeStr(n, nrect));
            dsp(moveStr(n, nrect));
            nr.rect = nrect;
            saveRec(n, nr);
            applied = true;
        }
        if (applied) guard();
    }

    // ---- hyprdrag events: the tracker's start/stop, the watcher's pulse ----

    Connections {
        target: DragWatch
        function onDragStarted(kind, addr) {
            if (kind !== "move") return;
            if (!Theme.state.snap || !Theme.state.snapDrag || root.popOpen) return;
            root.evDrag = true;
            root.evSeed = true;
            root.evBase = null;
            root.dragPrev = null;
            root.livePrev = null;
            root.dragFetch(); // the baseline sample: the window has not moved yet
        }
        function onDragMotion(kind, addr, rect, cur) {
            // the drag at its own rate, geometry included: a resize of a
            // grouped window is followed live (liveFollow), a move feeds
            // the drag tracker's begin/track rules directly (motionTrack)
            // -- neither path polls, so neither can trail the pointer
            if (kind === "resize") { root.liveFollow(addr, rect); return; }
            if (!Theme.state.snap || !Theme.state.snapDrag || root.popOpen) return;
            root.motionTrack(addr, rect, cur);
        }
        function onDragStopped(kind, addr) {
            if (kind === "move" && root.dragT) {
                if (DragWatch.motionAlive) {
                    root.dragRelease(); // the last motion set the zone, a mouse-move ago
                } else {
                    // land on one last sample, taken now: the legacy tracker's
                    // still-tick release always read the cursor's final resting
                    // place, but the stop event fires the instant the button
                    // lifts -- with the zone from the last mid-drag tick, a
                    // quick flick to an edge lets go before the preview caught
                    // up and the snap is missed. dFetched() lands it below.
                    root.pendingLand = true;
                    root.dragFetch();
                }
            }
            root.liveBase = null;
            root.livePrev = null;
            root.evDrag = false;
            root.evSeed = false;
            root.evBase = null;
            settleT.restart();
            // one fetch on every drag stop, grouped or not: a setup
            // arranged by hand is adopted by the observe() it feeds
            if (!root.fetching && !root.pendingAct) root.fetch(null);
        }
    }

    // ---- live drags: the plugin's motion events, followed directly ----

    // liveBase: a resize follow in progress -- the dragged window's rect
    // when the drag began, and each group mate's rect then. Every motion
    // recomputes the mates from those bases and the live rect, so the
    // follow is exact at any rate. (linkedResize cannot do this: its edge
    // tests read the mates' current records, which the first step of the
    // follow itself has already moved.) The dragged window's own record
    // stays at the base for the whole drag; the watcher reconciles it
    // when the drag ends.
    property var liveBase: null // { addr, gid, rect, mates: { addr: rect } }
    function liveFollow(addr, r) {
        if (!Theme.state.snap || !Theme.state.snapLinked) return;
        const rec = recs[addr];
        if (!rec) return;
        if (!liveBase || liveBase.addr !== addr) {
            const gid = groupOf(addr);
            if (!gid) return;
            const mates = {};
            for (const n of (groups[gid] ?? [])) if (n !== addr && recs[n]) mates[n] = recs[n].rect;
            if (!Object.keys(mates).length) return;
            liveBase = { addr: addr, gid: gid, rect: rec.rect, mates: mates };
        }
        const base = liveBase.rect, gi = Rules.store.gapsIn;
        let applied = false;
        for (const n in liveBase.mates) {
            const m = liveBase.mates[n], nr = recs[n];
            if (!nr) continue;
            let nx = m.x, ny = m.y, nw = m.w, nh = m.h, adj = false;
            if (Math.abs(base.x + base.w + gi - m.x) <= 3 && spansOverlap(base.y, base.h, m.y, m.h)) {
                const b = r.x + r.w + gi; nx = b; nw = m.x + m.w - b; adj = true;
            } else if (Math.abs(base.x - gi - (m.x + m.w)) <= 3 && spansOverlap(base.y, base.h, m.y, m.h)) {
                nw = r.x - gi - m.x; adj = true;
            }
            if (Math.abs(base.y + base.h + gi - m.y) <= 3 && spansOverlap(base.x, base.w, m.x, m.w)) {
                const b = r.y + r.h + gi; ny = b; nh = m.y + m.h - b; adj = true;
            } else if (Math.abs(base.y - gi - (m.y + m.h)) <= 3 && spansOverlap(base.x, base.w, m.x, m.w)) {
                nh = r.y - gi - m.y; adj = true;
            }
            if (!adj || nw < 240 || nh < 160) continue;
            const nrect = { x: nx, y: ny, w: nw, h: nh };
            if (rectEq(nrect, nr.rect, 0)) continue; // this motion changed the other axis only
            dsp(resizeStr(n, nrect));
            dsp(moveStr(n, nrect));
            nr.rect = nrect;
            saveRec(n, nr);
            applied = true;
        }
        if (applied) guard();
    }

    // livePrev: the last motion sample of a move drag. motionTrack runs
    // the sampling tracker's begin/track rules on the event's sample
    // instead of a fetched one -- the preview follows the cursor at the
    // drag's own rate, and the release lands with the final motion's zone.
    property var livePrev: null // { addr, x, y, w, h, cx, cy }
    function motionTrack(addr, r, cur) {
        if (!snapM) { fetch(null); return; } // zones need the monitors first
        const cl = (dsnapC ?? []).find(x => x.address === addr) ?? null;
        if (!cl || cl.workspace.id < 0) return; // the seed fetch has not landed, or the window is parked
        const offX = cur.x - r.x, offY = cur.y - r.y;
        if (dragT) {
            if (dragT.addr !== addr) return;
            if (r.w !== dragT.lastW || r.h !== dragT.lastH
                || Math.abs(offX - dragT.offX) > 12 || Math.abs(offY - dragT.offY) > 12) { dragAbort(); return; }
            dragT.lastX = r.x;
            dragT.lastY = r.y;
            const z = dragZoneAt(cl, cur);
            dragZone = z?.zone ?? "";
            dragRect = z?.rect ?? null;
            return;
        }
        const p = livePrev;
        if (p && p.addr === addr && r.w === p.w && r.h === p.h && (r.x !== p.x || r.y !== p.y)
            && Math.abs(offX - (p.cx - p.x)) <= 12 && Math.abs(offY - (p.cy - p.y)) <= 12) {
            const rec = recs[addr];
            const base = (evBase && evBase.addr === addr) ? evBase : p;
            dragT = { addr: addr, offX: offX, offY: offY,
                      lastX: r.x, lastY: r.y, lastW: r.w, lastH: r.h, still: 0,
                      pre: rec ? rec.pre : { floating: base.floating ?? true, x: base.x, y: base.y, w: base.w, h: base.h } };
            const z = dragZoneAt(cl, cur);
            dragZone = z?.zone ?? "";
            dragRect = z?.rect ?? null;
            root.beginFill(addr);
            DragWatch.fxSuspend();
        }
        livePrev = { addr: addr, x: r.x, y: r.y, w: r.w, h: r.h, cx: cur.x, cy: cur.y };
    }

    // ---- drag snapping: drag a window to an edge or corner, let go ----

    // the drag cycle's own small fetch: clients, the active window, the
    // cursor. (The main fetch's monitors give the work areas; if they are
    // not in yet, dragTick starts that fetch and skips the tick.)
    property var dsnapC: null
    property var dsnapA: null
    property var dsnapPos: null
    property bool dFetching: false
    property bool haveDC: false
    property bool haveDA: false
    property bool haveDP: false

    Process {
        id: dc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dsnapC = JSON.parse(text); } catch (e) { root.dsnapC = null; }
                root.haveDC = true;
                root.dFetched();
            }
        }
    }
    Process {
        id: da
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dsnapA = JSON.parse(text); } catch (e) { root.dsnapA = null; }
                root.haveDA = true;
                root.dFetched();
            }
        }
    }
    Process {
        id: dpos
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                const x = parseInt(p[0]), y = parseInt(p[1]);
                root.dsnapPos = isNaN(x) || isNaN(y) ? null : { x: x, y: y };
                root.haveDP = true;
                root.dFetched();
            }
        }
    }
    function dragFetch() {
        if (dFetching) return;
        dFetching = true;
        haveDC = false;
        haveDA = false;
        haveDP = false;
        dc.running = true;
        da.running = true;
        dpos.running = true;
    }
    function dFetched() {
        if (!haveDC || !haveDA || !haveDP) return;
        dFetching = false;
        const wasT = root.dragT; // the tick below may abort it; the landing still needs it
        dragTick();
        if (root.pendingLand) {
            // the drag stopped: land with the zone under the cursor NOW,
            // from this final sample (see onDragStopped)
            root.pendingLand = false;
            if (!root.dragT && wasT) root.dragT = wasT;
            if (root.dragT) {
                const c = (root.dsnapC ?? []).find(x => x.address === root.dragT.addr) ?? null;
                if (c && root.dsnapPos) {
                    const z = root.dragZoneAt(c, root.dsnapPos);
                    root.dragZone = z?.zone ?? "";
                    root.dragRect = z?.rect ?? null;
                }
                root.dragRelease();
            }
        }
    }
    Timer {
        interval: 250
        repeat: true
        // legacy: whenever drag-snapping is on. Event mode: only while a
        // move drag is actually on -- between drags the tracker costs
        // nothing at all (DragWatch says when one starts and ends). When
        // the plugin reports motion, motionTrack drives the tracker from
        // the events and this timer stands down entirely.
        running: Theme.state.snap && Theme.state.snapDrag && !root.popOpen
                 && (!DragWatch.alive || (DragWatch.moveActive && !DragWatch.motionAlive))
        onTriggered: root.dragFetch()
    }

    // dragPrev: the last sample of the focused window. dragT: a drag being
    // tracked. dragZone / dragRect: the preview snap/SnapZone.qml draws.
    property var dragPrev: null // { addr, x, y, w, h, floating, cx, cy }
    property var dragT: null    // { addr, offX, offY, lastX, lastY, lastW, lastH, still, pre }
    property bool pendingLand: false // a move drag stopped: land on the final sample (dFetched)
    // event mode (DragWatch alive): evDrag while a move drag is on, evSeed
    // until its first sample has been taken, evBase that first sample --
    // the window before the drag touched it, kept apart from dragPrev:
    // the begin test below compares consecutive samples (a grabbed tiled
    // window is re-seated by the compositor as the drag takes hold, so a
    // frozen baseline never matches it again), while `pre` -- what a
    // restore must give back -- is the baseline's state
    property bool evDrag: false
    property bool evSeed: false
    property var evBase: null
    property string dragZone: ""
    property var dragRect: null

    function dragSample(c, cur) {
        return { addr: c.address, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1],
                 floating: !!c.floating, cx: cur.x, cy: cur.y };
    }
    function dragAbort() {
        endFill();
        DragWatch.fxRestore();
        dragT = null;
        dragZone = "";
        dragRect = null;
    }

    // the tiling gesture, lent to a snapped pair: when one of two windows
    // that tile a rectangle together is dragged away, the other fills the
    // whole space for the length of the drag. A tiled pair does this by
    // itself -- the layout reflows around the dragged window and takes it
    // back on release -- but a snapped pair floats outside the layout, so
    // the service lends it the same manners. endFill (from dragAbort, so
    // every way a drag can end is covered) puts the mate back in its own
    // space before the landing proceeds: dropped home, the pair is
    // exactly restored; dropped elsewhere, the landing's own rules
    // (accommodate, regroup) take it from there.
    property var dragFill: null // { mate, rect, zone }
    function beginFill(addr) {
        if (!Theme.state.snapLinked || dragFill) return;
        const rec = recs[addr];
        if (!rec) return;
        const gid = groupOf(addr);
        const members = gid ? (groups[gid] ?? []) : [];
        if (members.length !== 2) return;
        const mate = members.find(m => m !== addr);
        const mr = recs[mate];
        if (!mr) return;
        const a = rec.rect, b = mr.rect;
        if (!shareV(a, b) && !shareV(b, a) && !shareH(a, b) && !shareH(b, a)) return;
        // the space the pair tiles is the two rects' own union -- never one
        // window's top and height: in a mixed pair the bar window starts 32
        // lower, and a mate filling the space must not inherit that offset
        // (a dragged kitty left Firefox maximised under a 32 gap)
        const ux = Math.min(a.x, b.x), uy = Math.min(a.y, b.y);
        const union = { x: ux, y: uy, w: Math.max(a.x + a.w, b.x + b.w) - ux, h: Math.max(a.y + a.h, b.y + b.h) - uy };
        dragFill = { mate: mate, rect: { x: b.x, y: b.y, w: b.w, h: b.h }, zone: mr.zone };
        place(mate, union, mr.zone);
    }
    function endFill() {
        if (!dragFill) return;
        const f = dragFill;
        dragFill = null;
        if (recs[f.mate]) place(f.mate, f.rect, f.zone);
    }
    // the zone the cursor is on: within 6 px of the work area's edges. The
    // bottom alone is not a zone -- windows maximises at the top, not there.
    function dragZoneAt(c, cur) {
        const mon = monOf(c);
        if (!mon) return null;
        const wa = workarea(mon);
        const l = cur.x <= wa.x + 6, r = cur.x >= wa.x + wa.w - 6;
        const t = cur.y <= wa.y + 6, b = cur.y >= wa.y + wa.h - 6;
        let zone = "";
        if (l && t) zone = "TL"; else if (r && t) zone = "TR";
        else if (l && b) zone = "BL"; else if (r && b) zone = "BR";
        else if (t) zone = "MAX"; else if (l) zone = "L"; else if (r) zone = "R";
        return zone ? { zone: zone, rect: placedRect(c.address, zf[zone], wa) } : null;
    }

    function dragTick() {
        const a = dsnapA?.address ?? "", cur = dsnapPos;
        // nothing focused, no cursor, or the popup is up: no drag can be on
        if (!a || !cur || popOpen) { dragAbort(); dragPrev = null; return; }
        const c = (dsnapC ?? []).find(x => x.address === a) ?? null;
        if (!c || c.workspace.id < 0) { dragAbort(); dragPrev = null; return; } // closed, or parked away
        if (!snapM) { fetch(null); dragPrev = dragSample(c, cur); return; } // zones need the monitors first
        if (evSeed) { // event mode: this drag's first sample is its baseline
            evSeed = false;
            evBase = dragSample(c, cur);
            dragPrev = evBase;
            return;
        }
        const r = rectOf(c);
        const offX = cur.x - r.x, offY = cur.y - r.y; // where the cursor holds the window

        if (dragT) {
            if (dragT.addr !== a) dragAbort(); // focus went elsewhere mid-drag
            else if (r.w !== dragT.lastW || r.h !== dragT.lastH
                     || Math.abs(offX - dragT.offX) > 12 || Math.abs(offY - dragT.offY) > 12) {
                dragAbort(); // resized, or moved by the keys: not a hand drag any more
            } else if (r.x !== dragT.lastX || r.y !== dragT.lastY) {
                dragT.still = 0;
                dragT.lastX = r.x;
                dragT.lastY = r.y;
                const z = dragZoneAt(c, cur);
                dragZone = z?.zone ?? "";
                dragRect = z?.rect ?? null;
                dragPrev = dragSample(c, cur);
                return;
            } else if (++dragT.still >= 2) {
                // legacy: the position held for two ticks means let go.
                // Event mode knows better -- the plugin's stop ends it.
                if (DragWatch.alive) { dragPrev = dragSample(c, cur); return; }
                dragRelease();
                dragPrev = null;
                return;
            } else {
                dragPrev = dragSample(c, cur);
                return;
            }
        }

        // begin: the window is floating in the fresh data, it moved since the
        // last sample at the same size, and the cursor still holds it by the
        // same point (±12 px) -- a hand drag. A grabbed tiled window is
        // floating by now (hyprland floats it as the drag starts). The state
        // a restore must give back is the record's own if it has one, else
        // the pre-drag baseline's (event mode) or the previous sample's.
        const p = dragPrev;
        if (p && p.addr === a && c.floating
                && r.w === p.w && r.h === p.h && (r.x !== p.x || r.y !== p.y)
                && Math.abs(offX - (p.cx - p.x)) <= 12 && Math.abs(offY - (p.cy - p.y)) <= 12) {
            const rec = recs[a];
            const base = (evDrag && evBase && evBase.addr === a) ? evBase : p;
            dragT = { addr: a, offX: offX, offY: offY,
                      lastX: r.x, lastY: r.y, lastW: r.w, lastH: r.h, still: 0,
                      pre: rec ? rec.pre : { floating: base.floating, x: base.x, y: base.y, w: base.w, h: base.h } };
            const z = dragZoneAt(c, cur);
            dragZone = z?.zone ?? "";
            dragRect = z?.rect ?? null;
            beginFill(a);
            DragWatch.fxSuspend();
        }
        dragPrev = dragSample(c, cur);
    }

    function dragRelease() {
        const d = dragT, zone = dragZone;
        dragAbort();
        evDrag = false;
        evSeed = false;
        evBase = null;
        if (!d) return;
        fetch(() => dragLand(d, zone)); // land on fresh lists, so client() is true
    }
    // with a zone: place it (the tick sound is place()'s). With none: a
    // record whose window was carried somewhere else ends, and the window
    // stays a free floating window where it was dropped.
    function dragLand(d, zone) {
        const c = client(d.addr);
        if (!c || c.workspace.id < 0) return;
        if (zone) {
            const mon = monOf(c);
            if (!mon) return;
            const wa = workarea(mon), target = zoneRect(zf[zone], wa);
            // accommodate: a snapped window already sits in this space --
            // it yields instead of being stacked under the dropped one:
            // to the dropped window's own old space when it had one (the
            // two trade places), else to this space's complement, so the
            // pair ends up side by side
            const occ = Object.keys(recs).find(a => a !== d.addr && recs[a].ws === c.workspace.id && (recs[a].zone === zone || rectEq(recs[a].rect, target, 6)));
            if (occ) {
                const mine = recs[d.addr];
                if (mine && mine.zone && zf[mine.zone]) place(occ, placedRect(occ, zf[mine.zone], wa), mine.zone);
                else {
                    const free = complements(zone).filter(z => !Object.keys(recs).some(a => a !== occ && a !== d.addr
                        && recs[a].ws === c.workspace.id && (recs[a].zone === z || rectEq(recs[a].rect, zoneRect(zf[z], wa), 6))));
                    if (free.length) place(occ, placedRect(occ, zf[free[0]], wa), free[0]);
                }
            }
            place(d.addr, placedRect(d.addr, zf[zone], wa), zone, d.pre);
            regroupWs(c.workspace.id);
        } else {
            const rec = recs[d.addr];
            if (rec && !rectEq(rectOf(c), rec.rect, 0)) {
                const ws = rec.ws;
                dropRec(d.addr);
                regroupWs(ws);
            }
        }
    }

    // ---- deck drops: a window let go over a workspace cell lands there ----

    // the drop deck's drop, followed through (deck/DropDeck.qml calls this
    // when a drag ends over a cell): the window moves to that workspace and
    // the view goes with it, and then the workspace's windows -- the ones
    // already there plus this one -- are laid out together: one takes the
    // whole space, two sit side by side, three in columns, four in a grid
    // (the layouts popup's shapes, capped like groups are). Laid out
    // together they share edges, so they form a group and resize together
    // from then on.
    function dropTo(addr, ws) {
        dsp(`hl.dsp.window.move({ window = "address:${addr}", workspace = "${ws}", follow = true })`);
        guard();
        fetch(() => dropArrange(addr, ws, false));
    }
    function dropArrange(addr, ws, retried) {
        const c = client(addr);
        if (!c || c.workspace.id !== ws) {
            // the move may not be in the fresh lists yet: one second look
            if (!retried) fetch(() => dropArrange(addr, ws, true));
            return;
        }
        const mon = monOf(c);
        if (!mon) return;
        const wa = workarea(mon);
        const others = (snapC ?? [])
            .filter(x => x.workspace.id === ws && x.address !== addr && (x.fullscreen ?? 0) === 0)
            .sort((p, q) => (p.at[0] - q.at[0]) || (p.at[1] - q.at[1]));
        const set = others.slice(0, 3).map(x => x.address).concat([addr]);
        const zones = set.length === 1 ? [{ f: zf.MAX, zone: "MAX" }]
            : set.length === 2 ? layouts[0].zones
            : set.length === 3 ? layouts[2].zones
            : layouts[3].zones;
        set.forEach((a, k) => place(a, placedRect(a, zones[k].f, wa), zones[k].zone));
        regroupWs(ws);
    }
}
