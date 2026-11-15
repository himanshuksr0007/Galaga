pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// drag watch: tells a hover strip whether the focused window is being
// dragged or resized right now, so the deck and the quick panel stay down
// while a window is carried across their edges. Compositor drags keep
// feeding hover to layer surfaces, so a plain dwell cannot tell a
// deliberate linger from a window passing through -- two samples can:
// one when the hover begins, one when the strip's dwell fires. Between
// them a hand drag moves the window at one size with the cursor holding
// the same point of it; a resize changes the size with the cursor at the
// window. Anything else (or no reading at all) is not a drag, and the
// strips fail open -- a panel must never get stuck shut. Samples run on
// demand only, when a strip asks: no polling.
Singleton {
    id: root

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
