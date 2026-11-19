import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// performance: the task manager's live system page -- windows' performance
// tab in nothing clothes. Everything live is read from services/SysStats
// (itself /proc and sysfs); the page only demands sampling while it is on
// screen (the perf binding, the deck's way) and keeps the last 60
// one-second samples per metric for the history graph. Specs (machine,
// processor, gpu, os, kernel, hostname) are fetched once, on first
// activation, the about page's way -- a row whose source failed stays
// hidden. Where the machine offers no gpu telemetry the page says so
// instead of graphing zeros, and the disk has no rate worth graphing:
// its mounts take the graph's place. Nothing here is estimated.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    property string sel: "cpu"
    property var specs: ({})
    property bool specsDone: false
    property var hist: ({ cpu: [], mem: [], gpu: [], rx: [], tx: [] })

    // sampling on demand only: SysStats' perf leg (frequency, processes)
    // runs while this page is the one on screen
    Binding { target: SysStats; property: "perf"; value: pg.active }

    readonly property var devices: [
        { id: "cpu", name: "cpu", icon: "\u{F061A}" },
        { id: "memory", name: "memory", icon: "\u{F035B}" },
        { id: "gpu", name: "gpu", icon: "\u{F08AE}" },
        { id: "network", name: "network", icon: "\u{F05A9}" },
        { id: "disk", name: "disk", icon: "\u{F02CA}" }
    ]

    // the rail's one-line live stat per device
    function stat(id) {
        if (id === "cpu") return `${Math.round(SysStats.cpu * 100)}% · ${SysStats.cpuFreq.toFixed(2)} ghz`;
        if (id === "memory") return SysStats.memTotal > 0 ? `${SysStats.memUsed.toFixed(1)} / ${SysStats.memTotal.toFixed(1)} gb` : "";
        if (id === "gpu") return SysStats.gpuType === "" ? "no telemetry" : `${Math.round(SysStats.gpu * 100)}%` + (SysStats.gpuTemp > 0 ? ` · ${Math.round(SysStats.gpuTemp)}°c` : "");
        if (id === "network") return `↓ ${SysStats.rate(SysStats.rx)} ↑ ${SysStats.rate(SysStats.tx)}`;
        if (id === "disk") { const r = SysStats.disks.find(d => d.mount === "root"); return r ? `${Math.round(r.used * 100)}% used` : ""; }
        return "";
    }
    // the big number over the graph
    function headVal() {
        if (pg.sel === "cpu") return `${Math.round(SysStats.cpu * 100)}%`;
        if (pg.sel === "memory") return `${Math.round(SysStats.mem * 100)}%`;
        if (pg.sel === "gpu") return SysStats.gpuType === "" ? "" : `${Math.round(SysStats.gpu * 100)}%`;
        if (pg.sel === "network") return `↓ ${SysStats.rate(SysStats.rx)} · ↑ ${SysStats.rate(SysStats.tx)}`;
        if (pg.sel === "disk") { const r = SysStats.disks.find(d => d.mount === "root"); return r ? `${Math.round(r.used * 100)}%` : ""; }
        return "";
    }
    function select(id) {
        if (pg.sel === id) return;
        pg.sel = id;
        Sounds.play("tick");
        graph.requestPaint();
    }
    function upText(s) {
        if (!s) return "";
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d ? `${d} d ${h} h` : h ? `${h} h ${m} min` : `${m} min`;
    }
    function sizeGb(bytes) {
        const g = bytes / 1000000000;
        return (g >= 100 ? Math.round(g) : Math.round(g * 10) / 10) + " gb";
    }
    function pushHist() {
        const h = pg.hist;
        const add = (a, v) => { a.push(v); if (a.length > 60) a.shift(); };
        add(h.cpu, SysStats.cpu);
        add(h.mem, SysStats.mem);
        add(h.gpu, SysStats.gpu);
        add(h.rx, SysStats.rx);
        add(h.tx, SysStats.tx);
        graph.requestPaint();
    }

    onActiveChanged: if (active && !specsDone) { specsDone = true; specProc.running = true; }

    // one sample a second for the graph, only while the page is up
    Timer { interval: 1000; running: pg.active; repeat: true; triggeredOnStart: true; onTriggered: pg.pushHist() }

    // the specs, once: dmi, /proc, lspci, /etc -- the about page's fetch
    Process {
        id: specProc
        command: ["sh", "-c", "model=$(dmidecode -s system-product-name 2>/dev/null || cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null); cpu=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1); gpu=$(lspci 2>/dev/null | sed -n -e 's/.*VGA[^:]*: //p' -e 's/.*3D[^:]*: //p' | head -n 1); os=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release); kern=$(uname -r); host=$(hostname); printf 'model=%s\\ncpu=%s\\ngpu=%s\\nos=%s\\nkern=%s\\nhost=%s\\n' \"$model\" \"$cpu\" \"$gpu\" \"$os\" \"$kern\" \"$host\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const ln of text.split("\n")) {
                    const i = ln.indexOf("=");
                    if (i > 0) m[ln.slice(0, i)] = ln.slice(i + 1).trim();
                }
                if (m.os) m.os = m.os.replace(/^"|"$/g, "");
                pg.specs = m;
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: 24

        // ---- the device rail ----
        Column {
            id: rail
            width: 250
            spacing: 6

            Repeater {
                model: pg.devices
                RailRow { }
            }
        }

        // ---- the selected device ----
        Flickable {
            width: parent.width - rail.width - 24
            height: parent.height
            contentWidth: width
            contentHeight: detCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: detCol
                width: parent.width
                spacing: 22

                Item {
                    width: parent.width
                    height: 26
                    SetHead { anchors.verticalCenter: parent.verticalCenter; text: pg.sel }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: pg.headVal()
                        font { family: Theme.mono; pixelSize: 13 }
                        color: Theme.grey
                    }
                }

                // the history graph -- every device but the disk, and not
                // for a gpu the machine cannot report on
                Rectangle {
                    visible: pg.sel !== "disk" && !(pg.sel === "gpu" && SysStats.gpuType === "")
                    width: parent.width
                    height: 220
                    radius: Theme.corner(22)
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }

                    Canvas {
                        id: graph
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            const ox = 12, oy = 8, w = width - ox * 2, h = height - oy * 2;
                            ctx.clearRect(0, 0, width, height);
                            // the dot grid
                            ctx.fillStyle = Theme.s3;
                            for (let x = ox + 4; x < ox + w; x += 18)
                                for (let y = oy + 4; y < oy + h; y += 18)
                                    ctx.fillRect(x, y, 2, 2);
                            const series = (vals, max, color, fill) => {
                                if (!vals.length) return;
                                const dx = w / 59, n = vals.length;
                                const px = i => ox + w - (n - 1 - i) * dx;
                                const py = v => oy + h - 2 - Math.max(0, Math.min(1, v / max)) * (h - 4);
                                if (fill) {
                                    ctx.beginPath();
                                    ctx.moveTo(px(0), py(vals[0]));
                                    for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(vals[i]));
                                    ctx.lineTo(px(n - 1), oy + h);
                                    ctx.lineTo(px(0), oy + h);
                                    ctx.closePath();
                                    ctx.globalAlpha = 0.10;
                                    ctx.fillStyle = color;
                                    ctx.fill();
                                    ctx.globalAlpha = 1;
                                }
                                ctx.beginPath();
                                ctx.moveTo(px(0), py(vals[0]));
                                for (let i = 1; i < n; i++) ctx.lineTo(px(i), py(vals[i]));
                                ctx.strokeStyle = color;
                                ctx.lineWidth = 2;
                                ctx.stroke();
                            };
                            if (pg.sel === "network") {
                                let mx = 1;
                                for (const v of pg.hist.rx) mx = Math.max(mx, v);
                                for (const v of pg.hist.tx) mx = Math.max(mx, v);
                                series(pg.hist.rx, mx, Theme.fg, true);
                                series(pg.hist.tx, mx, Theme.grey, false);
                            } else {
                                series(pg.sel === "cpu" ? pg.hist.cpu : pg.sel === "memory" ? pg.hist.mem : pg.hist.gpu, 1, Theme.fg, true);
                            }
                        }
                    }
                }

                // a gpu with no sensor: the honest line takes the graph's
                // place (the fetched name still shows in the details below)
                Lb {
                    visible: pg.sel === "gpu" && SysStats.gpuType === ""
                    text: "no gpu telemetry on this machine"
                    px: 12
                    color: Theme.mute
                }

                // the disk's mounts take the graph's place: a bar per mount
                Column {
                    visible: pg.sel === "disk"
                    width: parent.width
                    spacing: 14

                    Repeater {
                        model: SysStats.disks
                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: 6
                            Item {
                                width: parent.width
                                height: 18
                                Lb { anchors.verticalCenter: parent.verticalCenter; text: modelData.mount === "root" ? "/" : "/" + modelData.mount; px: 12; color: Theme.fg }
                                Text {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    text: `${Math.round(modelData.used * 100)}% · ${pg.sizeGb(modelData.size)}`
                                    font { family: Theme.mono; pixelSize: 12 }
                                    color: Theme.grey
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 8
                                radius: 4
                                color: Theme.s2
                                Rectangle { width: parent.width * modelData.used; height: parent.height; radius: 4; color: Theme.fg }
                            }
                        }
                    }
                    Lb { visible: SysStats.disks.length === 0; text: "no mounts read yet"; px: 11; color: Theme.mute }
                }

                // ---- cpu details ----
                Column {
                    visible: pg.sel === "cpu"
                    width: parent.width
                    spacing: 22

                    Column {
                        width: parent.width
                        spacing: 10
                        SetHead { text: "processor" }
                        SetCard {
                            SetRow { label: "model"; value: pg.specs.cpu || ""; visible: !!pg.specs.cpu }
                            SetRow { label: "speed"; value: SysStats.cpuFreq > 0 ? `${SysStats.cpuFreq.toFixed(2)} ghz` : ""; visible: SysStats.cpuFreq > 0 }
                            SetRow { label: "processors"; value: SysStats.cores.length > 0 ? String(SysStats.cores.length) : ""; visible: SysStats.cores.length > 0 }
                            SetRow { label: "temperature"; value: SysStats.cpuTemp > 0 ? `${Math.round(SysStats.cpuTemp)}°c` : ""; visible: SysStats.cpuTemp > 0 }
                            SetRow { label: "load average"; value: SysStats.load; visible: SysStats.load !== "" }
                            SetRow { label: "uptime"; value: pg.upText(SysStats.uptime); visible: SysStats.uptime > 0; divider: false }
                        }
                    }
                    Column {
                        visible: SysStats.cores.length > 0
                        width: parent.width
                        spacing: 10
                        SetHead { text: "per core" }
                        SetCard {
                            Row {
                                spacing: 6
                                Repeater {
                                    model: SysStats.cores
                                    Item {
                                        required property var modelData
                                        width: 14
                                        height: 46
                                        Rectangle { anchors.fill: parent; radius: 3; color: Theme.s2 }
                                        Rectangle { width: parent.width; height: Math.max(2, parent.height * modelData); anchors.bottom: parent.bottom; radius: 3; color: Theme.fg }
                                    }
                                }
                            }
                        }
                    }
                    Column {
                        visible: !!pg.specs.model || !!pg.specs.os || !!pg.specs.kern || !!pg.specs.host
                        width: parent.width
                        spacing: 10
                        SetHead { text: "machine" }
                        SetCard {
                            SetRow { label: "model"; value: pg.specs.model || ""; visible: !!pg.specs.model }
                            SetRow { label: "os"; value: pg.specs.os || ""; visible: !!pg.specs.os }
                            SetRow { label: "kernel"; value: pg.specs.kern || ""; visible: !!pg.specs.kern }
                            SetRow { label: "hostname"; value: pg.specs.host || ""; visible: !!pg.specs.host; divider: false }
                        }
                    }
                }

                // ---- memory details ----
                Column {
                    visible: pg.sel === "memory"
                    width: parent.width
                    spacing: 10
                    SetHead { text: "memory" }
                    SetCard {
                        SetRow { label: "used"; value: SysStats.memTotal > 0 ? `${SysStats.memUsed.toFixed(1)} gb` : ""; visible: SysStats.memTotal > 0 }
                        SetRow { label: "total"; value: SysStats.memTotal > 0 ? `${SysStats.memTotal.toFixed(1)} gb` : ""; visible: SysStats.memTotal > 0 }
                        SetRow { label: "usage"; value: SysStats.memTotal > 0 ? `${Math.round(SysStats.mem * 100)}%` : ""; visible: SysStats.memTotal > 0 }
                        SetRow { label: "swap used"; value: SysStats.memTotal > 0 ? `${SysStats.swapUsed.toFixed(1)} gb` : ""; visible: SysStats.memTotal > 0 }
                        SetRow { label: "cached"; value: SysStats.memTotal > 0 ? `${SysStats.cache.toFixed(1)} gb` : ""; visible: SysStats.memTotal > 0; divider: false }
                    }
                }

                // ---- gpu details ----
                Column {
                    visible: pg.sel === "gpu"
                    width: parent.width
                    spacing: 10
                    SetHead { text: "graphics" }
                    SetCard {
                        SetRow { label: "model"; value: pg.specs.gpu || ""; visible: !!pg.specs.gpu }
                        SetRow { label: "usage"; value: `${Math.round(SysStats.gpu * 100)}%`; visible: SysStats.gpuType !== "" }
                        SetRow { label: "temperature"; value: SysStats.gpuTemp > 0 ? `${Math.round(SysStats.gpuTemp)}°c` : ""; visible: SysStats.gpuTemp > 0 }
                        SetRow { label: "vram"; value: SysStats.vramTotal > 0 ? `${SysStats.vramUsed.toFixed(1)} / ${SysStats.vramTotal.toFixed(1)} gb` : ""; visible: SysStats.vramTotal > 0 }
                        SetRow { label: "driver"; value: SysStats.gpuType; visible: SysStats.gpuType !== ""; divider: false }
                    }
                }

                // ---- network details ----
                Column {
                    visible: pg.sel === "network"
                    width: parent.width
                    spacing: 10
                    SetHead { text: "network" }
                    SetCard {
                        SetRow { label: "interface"; value: SysStats.iface; visible: SysStats.iface !== "" }
                        SetRow { label: "download"; value: SysStats.rate(SysStats.rx); visible: SysStats.iface !== "" }
                        SetRow { label: "upload"; value: SysStats.rate(SysStats.tx); visible: SysStats.iface !== ""; divider: false }
                    }
                    Lb { visible: SysStats.iface === ""; text: "no default route right now"; px: 11; color: Theme.mute }
                }

                // ---- disk details ----
                Column {
                    visible: pg.sel === "disk" && SysStats.disks.length > 0
                    width: parent.width
                    spacing: 10
                    SetHead { text: "volumes" }
                    SetCard {
                        Repeater {
                            model: SysStats.disks
                            SetRow {
                                required property var modelData
                                required property int index
                                label: modelData.mount === "root" ? "/" : "/" + modelData.mount
                                value: `${pg.sizeGb(modelData.used * modelData.size)} of ${pg.sizeGb(modelData.size)} used`
                                divider: index < SysStats.disks.length - 1
                            }
                        }
                    }
                }
            }
        }
    }

    // one rail row: the settings device rows' shape -- a disc that fills
    // when its device is the one on show, the name, the live stat under it
    component RailRow: Rectangle {
        id: rrow
        required property var modelData
        readonly property var d: modelData
        readonly property bool on: pg.sel === d.id
        width: rail.width
        height: 56
        radius: Theme.corner(28)
        color: on ? Theme.s3 : hov.hovered ? Theme.s2 : "transparent"

        Rectangle {
            id: dic
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: rrow.on ? Theme.fg : Theme.s3
            Icon { anchors.centerIn: parent; text: rrow.d.icon; font.pixelSize: 19; color: rrow.on ? Theme.ink : Theme.fg }
        }
        Column {
            anchors { left: dic.right; leftMargin: 14; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: rrow.d.name; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
            Lb { px: 10; color: Theme.mute; text: pg.stat(rrow.d.id) }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pg.select(rrow.d.id) }
    }
}
