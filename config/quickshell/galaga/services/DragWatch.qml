pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// drag watch: the shell's one answer to "is a window being dragged or
// resized right now, and which one". The deck and the quick panel ask
// before they open (a compositor drag keeps feeding hover to their edge
// strips, so a plain dwell cannot tell a deliberate linger from a window
// passing through); Snap's drag tracker and the deck's drop targets run
// on the start/stop signals.
//
// Two worlds, one interface. With the hyprdrag plugin loaded
// (config/hypr/hyprland/drag.lua) the compositor's own drag state arrives
// as socket2 events -- movestart/movestop, resizestart/resizestop, each
// with the window's address -- and `dragging` is simply true between a
// start and its stop. `alive` turns true at the session's first hyprdrag
// event and stays true: that is the plugin proving itself. Without the
// plugin (not installed, stale after a Hyprland upgrade) the events never
// arrive, alive stays false, and every consumer falls back to the
// sampling path below: two samples of the focused window and the cursor,
// one when a hover begins and one when the strip's dwell fires -- a hand
// drag moves the window at one size with the cursor holding the same
// point of it, a resize changes the size with the cursor at the window,
// and anything else (or no reading at all) is not a drag. Either way the
// strips fail open -- a panel must never get stuck shut.
Singleton {
    id: root

    // ---- the event core (hyprdrag) ----
    property bool alive: false // a hyprdrag event has arrived this session
    property bool moveActive: false
    property bool resizeActive: false
    property string addr: "" // the dragged window, 0x form, while a drag is on
    readonly property bool dragging: moveActive || resizeActive
    readonly property string kind: moveActive ? "move" : (resizeActive ? "resize" : "")

    signal dragStarted(string kind, string addr)
    signal dragStopped(string kind, string addr)

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            const data = String(e.data ?? "").trim();
            switch (e.name) {
            case "hyprdrag-movestart":
                root.alive = true;
                root.addr = data;
                root.moveActive = true;
                root.dragStarted("move", data);
                break;
            case "hyprdrag-resizestart":
                root.alive = true;
                root.addr = data;
                root.resizeActive = true;
                root.dragStarted("resize", data);
                break;
            case "hyprdrag-movestop":
                root.alive = true;
                if (!root.moveActive) break;
                root.moveActive = false;
                { const stopped = data || root.addr; if (!root.dragging) root.addr = ""; root.dragStopped("move", stopped); }
                break;
            case "hyprdrag-resizestop":
                root.alive = true;
                if (!root.resizeActive) break;
                root.resizeActive = false;
                { const stopped = data || root.addr; if (!root.dragging) root.addr = ""; root.dragStopped("resize", stopped); }
                break;
            }
        }
    }

    // may a hover strip open its panel? cb(true/false). Event world: the
    // answer is just "no drag is on". Sampling world: the second sample is
    // taken now and busyBetween decides (s1 is the hover-start sample the
    // strip took, possibly null -- that fails open, as before).
    function mayOpen(s1, cb) {
        if (alive) { cb(!dragging); return; }
        sample(s2 => cb(!busyBetween(s1, s2)));
    }

    // ---- the sampling fallback (no plugin) ----

    // one sample: the focused window's rect and the cursor, from the same
    // hyprctl pair Snap samples. cb gets { addr, x, y, w, h, cx, cy }, or
    // null when either read fails or nothing is focused. Calls queue: a
    // strip asking mid-sample gets the next fresh run, never a stale one.
    function sample(cb) {
        queue = queue.concat([cb]);
        pump();
    }

    // is the window in s1 being dragged or resized by s2? Pure: the two
    // samples and nothing else -- no settings, no snap state.
    function busyBetween(s1, s2) {
        if (!s1 || !s2 || !s1.addr || s1.addr !== s2.addr) return false;
        if (s1.w === s2.w && s1.h === s2.h) {
            // moved at one size, the cursor still holding it by the same
            // point (±12 px): a hand drag. Stood still: not busy.
            if (s1.x === s2.x && s1.y === s2.y) return false;
            return Math.abs((s2.cx - s2.x) - (s1.cx - s1.x)) <= 12
                && Math.abs((s2.cy - s2.y) - (s1.cy - s1.y)) <= 12;
        }
        // size changed, and the cursor sits at the window (40 px of slack
        // for the border grab area): a resize
        return s2.cx >= s2.x - 40 && s2.cx <= s2.x + s2.w + 40
            && s2.cy >= s2.y - 40 && s2.cy <= s2.y + s2.h + 40;
    }

    property var queue: []
    property bool running: false
    property var winObj: null
    property var curPos: null
    property bool haveWin: false
    property bool haveCur: false

    function pump() {
        if (running || !queue.length) return;
        running = true;
        haveWin = false;
        haveCur = false;
        winObj = null;
        curPos = null;
        pw.running = true;
        pc.running = true;
    }
    function got() {
        if (!haveWin || !haveCur) return;
        running = false;
        const cb = queue[0];
        queue = queue.slice(1);
        if (cb) cb(combined());
        pump();
    }
    function combined() {
        const o = winObj, c = curPos;
        if (!o || !c || !o.address || !o.at || !o.size) return null;
        return { addr: o.address, x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1], cx: c.x, cy: c.y };
    }

    Process {
        id: pw
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.winObj = JSON.parse(text); } catch (e) { root.winObj = null; }
                root.haveWin = true;
                root.got();
            }
        }
    }
    Process {
        id: pc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",");
                const x = parseInt(p[0]), y = parseInt(p[1]);
                root.curPos = isNaN(x) || isNaN(y) ? null : { x: x, y: y };
                root.haveCur = true;
                root.got();
            }
        }
    }
}
