import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// processes: everything running, grouped the way windows groups it -- a
// process belongs to the app that started it: the highest ancestor
// below the session's own infrastructure (init, the user manager, the
// compositor, the bus), so a browser and its helpers sit under one row
// until it is expanded, and the infrastructure itself stays in small
// rows of its own instead of swallowing the whole list. ps does the
// walking (quickshell has no process model): pid, parent, resident
// memory, cumulative cpu seconds and state, every two seconds and only
// while the page is up. cpu% is the delta between two snapshots over
// the machine's cores; the first snapshot has nothing to diff against
// and reads 0. end task is sigterm first -- a group still there on the
// next snapshot offers force kill (sigkill) instead. the shell's own
// group is protected: this window lives inside the shell, and ending
// it would end the desktop.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    readonly property int cpuW: 70
    readonly property int memW: 90
    readonly property int btnW: 124

    property int cores: 1
    property bool coresAsked: false
    property var prevTimes: ({}) // pid -> cumulative cpu seconds at the last snapshot
    property real lastStamp: 0
    property var groups: []       // group objects, in display order
    property var groupByRoot: ({})
    property var display: []      // flattened rows for the repeater
    property var openGroups: new Set() // rootPids the user expanded; survives rebuilds
    property var termed: ({})     // "g<rootPid>" / "p<pid>" -> when sigterm was sent
    property bool hovering: false

    onActiveChanged: {
        if (active) {
            if (!coresAsked) { coresAsked = true; coreProc.running = true; }
        } else {
            // a snapshot after a while away would average its cpu over
            // the whole gap; start the diffing fresh instead
            prevTimes = ({});
            lastStamp = 0;
        }
    }

    function fmtMem(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + " GB";
        if (kb >= 1024) return Math.round(kb / 1024) + " MB";
        return kb + " KB";
    }

    // the session's infrastructure: a process whose parent is one of
    // these is an app root, and the infrastructure processes group as
    // themselves
    readonly property var boundary: new Set(["systemd", "hyprland", "dbus-daemon", "uwsm", "init"])
    function rootOf(r, byPid) {
        let cur = r;
        const seen = new Set();
        while (!seen.has(cur.pid)) {
            seen.add(cur.pid);
            if (cur.ppid === cur.pid) break;
            const p = byPid[cur.ppid];
            if (!p || p.pid === 1 || boundary.has(p.comm)) break;
            cur = p;
        }
        return cur;
    }

    function snapshot(text) {
        const now = Date.now();
        const elapsed = lastStamp ? (now - lastStamp) / 1000 : 0;
        const rows = [];
        const byPid = {};
        const newPrev = {};
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(.+?)\s*$/);
            if (!m) continue;
            const r = { pid: +m[1], ppid: +m[2], rss: +m[3], times: +m[4], stat: m[5], comm: m[6], cpu: 0 };
            if (r.pid === 2 || (r.ppid === 2 && r.rss === 0)) continue; // kernel threads
            const prev = prevTimes[r.pid];
            if (prev !== undefined && elapsed > 0)
                r.cpu = Math.round(Math.max(0, r.times - prev) / (elapsed * cores) * 1000) / 10;
            rows.push(r);
            byPid[r.pid] = r;
            newPrev[r.pid] = r.times;
        }
        prevTimes = newPrev;
        lastStamp = now;

        const gmap = {};
        const glist = [];
        for (const r of rows) {
            const root = rootOf(r, byPid);
            let g = gmap[root.pid];
            if (!g) {
                const e = DesktopEntries.heuristicLookup(root.comm);
                g = {
                    rootPid: root.pid, comm: root.comm,
                    name: e?.name || root.comm,
                    icon: Quickshell.iconPath(e?.icon || "application-x-executable", "application-x-executable"),
                    pids: [], cpu: 0, memKb: 0, children: [],
                    prot: root.pid === 1 || root.comm === "quickshell" || root.comm === "qs"
                };
                gmap[root.pid] = g;
                glist.push(g);
            }
            g.pids.push(r.pid);
            g.cpu += r.cpu;
            g.memKb += r.rss;
            g.children.push(r);
        }
        for (const g of glist) g.children.sort((a, b) => b.cpu - a.cpu);

        // busiest first -- but rows must not move under the pointer:
        // while it hovers the list, groups keep their previous order
        // and only new ones append, sorted among themselves
        let ordered;
        if (hovering && groups.length) {
            const fresh = {};
            for (const g of glist) fresh[g.rootPid] = g;
            ordered = [];
            for (const old of groups)
                if (fresh[old.rootPid]) { ordered.push(fresh[old.rootPid]); delete fresh[old.rootPid]; }
            ordered = ordered.concat(Object.values(fresh).sort((a, b) => b.cpu - a.cpu));
        } else {
            ordered = glist.sort((a, b) => b.cpu - a.cpu);
        }

        const y = flick.contentY;
        groups = ordered;
        groupByRoot = gmap;
        // forget the term marks of things that are gone now
        for (const k of Object.keys(termed)) {
            if (k[0] === "g") { if (!gmap[+k.slice(1)]) delete termed[k]; }
            else if (!byPid[+k.slice(1)]) delete termed[k];
        }
        refreshDisplay();
        Qt.callLater(() => { flick.contentY = y; });
    }

    function refreshDisplay() {
        const out = [];
        for (const g of groups) {
            const exp = openGroups.has(g.rootPid);
            out.push({
                isGroup: true, rootPid: g.rootPid, name: g.name, icon: g.icon,
                sub: (g.children.length > 1 ? g.children.length + " processes · " : "") + "pid " + g.rootPid + (g.prot ? " · protected" : ""),
                cpu: g.cpu, mem: g.memKb, prot: g.prot, expanded: exp,
                btn: termed["g" + g.rootPid] ? "force kill" : "end task"
            });
            if (exp) for (const r of g.children) out.push({
                isGroup: false, rootPid: g.rootPid, pid: r.pid, name: r.comm,
                sub: "pid " + r.pid + " · " + r.stat,
                cpu: r.cpu, mem: r.rss, prot: g.prot,
                btn: termed["p" + r.pid] ? "force" : "kill"
            });
        }
        display = out;
    }

    function toggleGroup(rootPid) {
        if (openGroups.has(rootPid)) openGroups.delete(rootPid); else openGroups.add(rootPid);
        refreshDisplay();
    }

    // sigterm every pid in the group, the root last; a group that was
    // already termed and is still here gets sigkill
    function endGroup(rootPid) {
        const g = groupByRoot[rootPid];
        if (!g || g.prot) return;
        const key = "g" + rootPid;
        const list = g.pids.filter(p => p !== rootPid);
        list.push(rootPid);
        if (termed[key]) {
            Quickshell.execDetached(["kill", "-9"].concat(list.map(String)));
            delete termed[key];
        } else {
            Quickshell.execDetached(["kill"].concat(list.map(String)));
            termed[key] = Date.now();
        }
        refreshDisplay();
    }

    function endChild(pid) {
        const key = "p" + pid;
        if (termed[key]) {
            Quickshell.execDetached(["kill", "-9", String(pid)]);
            delete termed[key];
        } else {
            Quickshell.execDetached(["kill", String(pid)]);
            termed[key] = Date.now();
        }
        refreshDisplay();
    }

    Process {
        id: coreProc
        command: ["nproc"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim());
                if (n > 0) pg.cores = n;
            }
        }
    }
    Process {
        id: psProc
        command: ["ps", "-eo", "pid=,ppid=,rss=,times=,stat=,comm="]
        stdout: StdioCollector { onStreamFinished: pg.snapshot(text) }
    }
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: pg.active
        onTriggered: if (!psProc.running) psProc.running = true
    }

    Column {
        anchors.fill: parent
        spacing: 10

        // ---- column labels ----
        Item {
            width: parent.width
            height: 26
            Lb { x: 88; anchors.verticalCenter: parent.verticalCenter; text: "name"; px: 10.5; color: Theme.mute }
            Row {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 10
                Lb { width: pg.cpuW; horizontalAlignment: Text.AlignRight; text: "cpu"; px: 10.5; color: Theme.mute }
                Lb { width: pg.memW; horizontalAlignment: Text.AlignRight; text: "memory"; px: 10.5; color: Theme.mute }
                Item { width: pg.btnW; height: 1 }
            }
        }

        Flickable {
            id: flick
            width: parent.width
            height: parent.height - 36
            clip: true
            contentWidth: width
            contentHeight: col.height
            boundsBehavior: Flickable.StopAtBounds

            HoverHandler { id: listHov; onHoveredChanged: pg.hovering = hovered }

            Column {
                id: col
                width: parent.width
                spacing: 2

                Repeater {
                    model: pg.display
                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property var o: modelData
                        width: col.width
                        height: o.isGroup ? 56 : 48
                        radius: Theme.corner(o.isGroup ? 28 : 24)
                        color: hov.hovered ? Theme.s3 : "transparent"

                        // the left stretch toggles the group open
                        Item {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: colsRow.left }
                            TapHandler { enabled: row.o.isGroup; onTapped: pg.toggleGroup(row.o.rootPid) }
                            Icon {
                                visible: row.o.isGroup
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.o.expanded ? "\u{F0140}" : "\u{F0142}"
                                font.pixelSize: 15
                                color: Theme.grey
                            }
                            Rectangle {
                                visible: row.o.isGroup
                                x: 32
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                height: 44
                                radius: 22
                                color: Theme.s3
                                Image {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    source: row.o.icon ?? ""
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                            Column {
                                anchors { left: parent.left; leftMargin: 88; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: row.o.name
                                    font { family: Theme.ui; pixelSize: row.o.isGroup ? 14 : 13; weight: row.o.isGroup ? Font.DemiBold : Font.Normal }
                                    color: Theme.fg
                                }
                                Lb { px: 10; text: row.o.sub }
                            }
                        }

                        Row {
                            id: colsRow
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Text {
                                width: pg.cpuW
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: row.o.cpu.toFixed(1) + "%"
                                font { family: Theme.ui; pixelSize: 13 }
                                color: Theme.fg
                            }
                            Text {
                                width: pg.memW
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: pg.fmtMem(row.o.mem)
                                font { family: Theme.ui; pixelSize: 13 }
                                color: Theme.fg
                            }
                            Item {
                                width: pg.btnW
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                SetButton {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    visible: !row.o.prot
                                    label: row.o.btn
                                    danger: row.o.btn === "force kill" || row.o.btn === "force"
                                    onHit: row.o.isGroup ? pg.endGroup(row.o.rootPid) : pg.endChild(row.o.pid)
                                }
                            }
                        }
                        HoverHandler { id: hov }
                    }
                }

                Lb {
                    visible: pg.display.length === 0
                    x: 88
                    topPadding: 8
                    text: "nothing to show"
                    color: Theme.mute
                }
            }
        }
    }
}
