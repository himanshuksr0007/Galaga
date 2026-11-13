import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components

// about this machine: every row is read live from the system (dmi, /proc, /etc,
// uname, df) when the page shows; a row whose source fails stays hidden.
Item {
    id: pg

    property bool active: false
    property string model: ""
    property string cpu: ""
    property string os: ""
    property string kern: ""
    property string host: ""
    property string disk: ""
    property string screen: ""
    property real memKb: 0
    property real upSec: 0

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    function refresh() {
        if (!info.running) info.running = true;
        const s = Quickshell.screens.length ? Quickshell.screens[0] : null;
        screen = s ? `${s.name} · ${s.width} × ${s.height}` + (s.refreshRate ? ` · ${Math.round(s.refreshRate)} hz` : "") : "";
    }
    function memText() {
        if (!memKb) return "";
        const g = memKb / 1048576;
        return (g >= 100 ? Math.round(g) : Math.round(g * 10) / 10) + " gb";
    }
    function upText() {
        if (!upSec) return "";
        const d = Math.floor(upSec / 86400), h = Math.floor(upSec % 86400 / 3600), m = Math.floor(upSec % 3600 / 60);
        return d ? `${d} d ${h} h` : h ? `${h} h ${m} min` : `${m} min`;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: info
        command: ["sh", "-c", "model=$(dmidecode -s system-product-name 2>/dev/null || cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null); cpu=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1); mem=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo); os=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release); kern=$(uname -r); host=$(hostname); up=$(cut -d . -f 1 /proc/uptime); disk=$(df -h --output=used,size / | tail -n 1); printf 'model=%s\\ncpu=%s\\nmem=%s\\nos=%s\\nkern=%s\\nhost=%s\\nup=%s\\ndisk=%s\\n' \"$model\" \"$cpu\" \"$mem\" \"$os\" \"$kern\" \"$host\" \"$up\" \"$disk\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const ln of text.split("\n")) {
                    const i = ln.indexOf("=");
                    if (i > 0) m[ln.slice(0, i)] = ln.slice(i + 1).trim();
                }
                pg.model = m.model || "";
                pg.cpu = m.cpu || "";
                pg.os = (m.os || "").replace(/^"|"$/g, "");
                pg.kern = m.kern || "";
                pg.host = m.host || "";
                pg.memKb = parseFloat(m.mem || "0");
                pg.upSec = parseFloat(m.up || "0");
                const dk = (m.disk || "").split(/\s+/);
                pg.disk = dk.length === 2 && dk[0] ? `${dk[0]} of ${dk[1]} used` : "";
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 22

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "machine" }
                SetCard {
                    SetRow { label: "model"; value: pg.model; visible: pg.model !== "" }
                    SetRow { label: "processor"; value: pg.cpu; visible: pg.cpu !== "" }
                    SetRow { label: "memory"; value: pg.memText(); visible: pg.memKb > 0 }
                    SetRow { label: "display"; value: pg.screen; visible: pg.screen !== ""; divider: false }
                }
            }
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "system" }
                SetCard {
                    SetRow { label: "os"; value: pg.os; visible: pg.os !== "" }
                    SetRow { label: "kernel"; value: pg.kern; visible: pg.kern !== "" }
                    SetRow { label: "storage · /"; value: pg.disk; visible: pg.disk !== "" }
                    SetRow { label: "hostname"; value: pg.host; visible: pg.host !== "" }
                    SetRow { label: "uptime"; value: pg.upText(); visible: pg.upSec > 0; divider: false }
                }
            }
        }
    }
}
