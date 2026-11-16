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
// start and its stop. While a drag runs the plugin also posts a motion
// event per mouse move carrying the dragged window's live geometry and
// the cursor (dragMotion below), so a follower never has to poll to keep
// up with a drag. `alive` means the plugin is loaded NOW: an event
// proves it the moment one arrives, and a slow plugin-list check (the
// presence check below) notices when it goes away, so disabling or
// unloading the plugin mid-session hands the shell back to the sampling
// world within seconds instead of stranding it between the two. Without
// the plugin (not installed, stale after a Hyprland upgrade) the events never
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
    property bool motionAlive: false // a motion event has arrived: the plugin reports geometry live
    property bool moveActive: false
    property bool resizeActive: false
    property string addr: "" // the dragged window, 0x form, while a drag is on
    readonly property bool dragging: moveActive || resizeActive

    signal dragStarted(string kind, string addr)
    signal dragStopped(string kind, string addr)
    // a drag in motion: kind, the window, its live rect, the cursor
    signal dragMotion(string kind, string addr, var rect, var cur)

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            const data = String(e.data ?? "").trim();
            switch (e.name) {
            case "hyprdrag-movestart":
                root.alive = true;
                root.addr = data;
                root.moveActive = true;
                root.fxSuspend();
                root.dragStarted("move", data);
                break;
            case "hyprdrag-resizestart":
                root.alive = true;
                root.addr = data;
                root.resizeActive = true;
                root.fxSuspend();
                root.dragStarted("resize", data);
                break;
            case "hyprdrag-movestop":
                root.alive = true;
                if (!root.moveActive) break;
                root.moveActive = false;
                if (!root.dragging) root.fxRestore();
                { const stopped = data || root.addr; if (!root.dragging) root.addr = ""; root.dragStopped("move", stopped); }
                break;
            case "hyprdrag-resizestop":
                root.alive = true;
                if (!root.resizeActive) break;
                root.resizeActive = false;
                if (!root.dragging) root.fxRestore();
                { const stopped = data || root.addr; if (!root.dragging) root.addr = ""; root.dragStopped("resize", stopped); }
                break;
            case "hyprdrag-movemotion":
            case "hyprdrag-resizemotion": {
                root.alive = true;
                root.motionAlive = true;
                const p = data.split(",");
                if (p.length < 7) break;
                root.dragMotion(e.name === "hyprdrag-movemotion" ? "move" : "resize", p[0],
                                { x: +p[1], y: +p[2], w: +p[3], h: +p[4] }, { x: +p[5], y: +p[6] });
                break;
            }
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

    // the presence check: an event proves the plugin is there the moment
    // one arrives, but only a look at the plugin list notices it going
    // AWAY (disabled or unloaded mid-session, crashed). Without this,
    // `alive` latches on for the whole session and every consumer waits
    // on events that are never coming -- the fallback never engages and
    // the shell is stranded between the two worlds. One hyprctl call
    // every 15 s keeps `alive` meaning "loaded now"; when the plugin
    // vanishes, any latched drag state goes with it (its stop event is
    // never coming either), and the sampling world picks up from there.
    Process {
        id: plist
        command: ["hyprctl", "plugin", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.alive = text.includes("hyprdrag");
                if (!root.alive) {
                    root.motionAlive = false;
                    root.moveActive = false;
                    root.resizeActive = false;
                    root.addr = "";
                    root.fxRestore(); // a drag cut off mid-flight leaves no stop to restore by
                }
            }
        }
    }
    Timer {
        // the presence check only has something to prove while the plugin is
        // believed present: if it is unloaded, one check clears alive and the
        // timer stops with it; if it is loaded later, its first event is what
        // latches alive (and restarts this) -- the sampling world runs either way
        interval: 15000
        repeat: true
        running: root.alive
        onTriggered: if (!plist.running) plist.running = true
    }

    // ---- drag-time effects suspension ----
    // Blur and shadows are the compositor's per-frame tax: while a window
    // is dragged or resized the desktop re-renders continuously, and the
    // shadow pass and the blur passes run on every one of those frames.
    // For the length of a drag they buy nothing -- the window is in
    // motion under the cursor -- so a drag switches them off and the
    // drop switches back exactly what was on. The user's own settings
    // are read once at startup and are what gets restored; if they were
    // never read (or nothing is on), suspension simply does not happen.
    // Snap calls these too, for the sampling world's drags.
    property var fxBlur: null // the user's decoration:blur:enabled
    property var fxShadow: null // the user's decoration:shadow:enabled
    property bool fxOff: false
    function fxSuspend() {
        if (fxOff || fxBlur === null || fxShadow === null) return;
        if (!fxBlur && !fxShadow) return;
        fxOff = true;
        // through hyprctl eval, the channel Rules uses: Hyprland.dispatch wraps
        // its string in hl.dispatch(...), and hl.config is not a dispatcher --
        // sent that way these calls failed on every drag and the suspension
        // silently never happened
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ decoration = { blur = { enabled = false }, shadow = { enabled = false } } })"]);
    }
    function fxRestore() {
        if (!fxOff) return;
        fxOff = false;
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ decoration = { blur = { enabled = ${fxBlur} }, shadow = { enabled = ${fxShadow} } } })`]);
    }
    Process {
        id: fxB
        command: ["hyprctl", "getoption", "decoration:blur:enabled"]
        stdout: StdioCollector { onStreamFinished: root.fxBlur = text.includes("true") }
    }
    Process {
        id: fxS
        command: ["hyprctl", "getoption", "decoration:shadow:enabled"]
        stdout: StdioCollector { onStreamFinished: root.fxShadow = text.includes("true") }
    }
    Component.onCompleted: { fxB.running = true; fxS.running = true; }

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
