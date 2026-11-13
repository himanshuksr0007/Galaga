import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components

// network: NetworkManager through nmcli, the same calls WifiMenu and DeviceSettings
// make. Devices with their addresses, wired connect/disconnect, and every saved
// connection with up/down -- vpn and wireguard profiles live on the VPN page instead.
Item {
    id: pg

    property bool active: false
    property var devs: []
    property var conns: []
    property var activeUuids: []

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    // nmcli -t separates fields with ':' and escapes a literal one as '\:'
    function splitT(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) cur += line[++i];
            else if (c === ":") { out.push(cur); cur = ""; }
            else cur += c;
        }
        out.push(cur);
        return out;
    }
    function refresh() {
        if (!devProc.running) devProc.running = true;
        if (!conProc.running) conProc.running = true;
        if (!actProc.running) actProc.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: devProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                for (const ln of text.split("\n")) {
                    if (!ln.trim()) continue;
                    const f = pg.splitT(ln);
                    if (f.length >= 4 && f[1] !== "loopback") rows.push({ dev: f[0], type: f[1], state: f[2], conn: f[3] });
                }
                pg.devs = rows;
            }
        }
    }
    Process {
        id: conProc
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,AUTOCONNECT", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                for (const ln of text.split("\n")) {
                    if (!ln.trim()) continue;
                    const f = pg.splitT(ln);
                    if (f.length >= 4 && f[2] !== "vpn" && f[2] !== "wireguard")
                        rows.push({ name: f[0], uuid: f[1], type: f[2], auto: f[3] === "yes" });
                }
                pg.conns = rows;
            }
        }
    }
    Process {
        id: actProc
        command: ["nmcli", "-t", "-f", "UUID", "connection", "show", "--active"]
        stdout: StdioCollector { onStreamFinished: pg.activeUuids = text.split("\n").map(s => s.trim()).filter(s => s) }
    }
    Timer { id: reread; interval: 1300; onTriggered: pg.refresh() }

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

            Item {
                width: parent.width
                height: 30
                SetHead { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: "devices" }
                SetButton {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    label: "refresh"
                    onHit: pg.refresh()
                }
            }
            Lb { visible: !pg.devs.length; text: "no network devices" }
            Repeater {
                model: pg.devs
                Column {
                    id: dcard
                    required property var modelData
                    property string addr: ""
                    property string gw: ""
                    property string dns: ""
                    width: parent.width
                    spacing: 10

                    Process {
                        id: det
                        running: true
                        command: ["nmcli", "device", "show", dcard.modelData.dev]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const dns = [];
                                for (const ln of text.split("\n")) {
                                    const i = ln.indexOf(":");
                                    if (i < 0) continue;
                                    const k = ln.slice(0, i).trim(), v = ln.slice(i + 1).trim();
                                    if (k === "IP4.ADDRESS[1]") dcard.addr = v;
                                    else if (k === "IP4.GATEWAY") dcard.gw = v;
                                    else if (k.startsWith("IP4.DNS")) dns.push(v);
                                }
                                dcard.dns = dns.join(" · ");
                            }
                        }
                    }
                    Connections {
                        target: pg
                        function onActiveChanged() { if (pg.active && !det.running) det.running = true; }
                    }

                    Row {
                        spacing: 12
                        SetHead { text: dcard.modelData.dev }
                        Lb {
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${dcard.modelData.type} · ${dcard.modelData.state}`
                            px: 10.5
                            color: dcard.modelData.state === "connected" ? Theme.fg : Theme.mute
                        }
                    }
                    SetCard {
                        SetRow { label: "connection"; value: dcard.modelData.conn; visible: dcard.modelData.conn !== "" }
                        SetRow { label: "address"; value: dcard.addr; visible: dcard.addr !== "" }
                        SetRow { label: "gateway"; value: dcard.gw; visible: dcard.gw !== "" }
                        SetRow { label: "dns"; value: dcard.dns; visible: dcard.dns !== ""; divider: dcard.modelData.type === "ethernet" }
                        Item {
                            visible: dcard.modelData.type === "ethernet" && (dcard.modelData.state === "connected" || dcard.modelData.state === "disconnected")
                            width: parent ? parent.width : 0
                            height: visible ? 48 : 0
                            SetButton {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                label: dcard.modelData.state === "connected" ? "disconnect" : "connect"
                                danger: dcard.modelData.state === "connected"
                                onHit: {
                                    Quickshell.execDetached(["nmcli", "device", dcard.modelData.state === "connected" ? "disconnect" : "connect", dcard.modelData.dev]);
                                    reread.restart();
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "saved connections" }
                SetCard {
                    Lb { visible: !pg.conns.length; text: "no saved connections" }
                    Repeater {
                        model: pg.conns
                        SetRow {
                            required property var modelData
                            required property int index
                            readonly property bool up: pg.activeUuids.includes(modelData.uuid)
                            label: modelData.name
                            sub: modelData.type + (modelData.auto ? " · connects automatically" : "")
                            value: up ? "connected" : ""
                            divider: index < pg.conns.length - 1
                            SetButton {
                                label: up ? "disconnect" : "connect"
                                danger: up
                                onHit: {
                                    Quickshell.execDetached(["nmcli", "connection", up ? "down" : "up", "uuid", modelData.uuid]);
                                    reread.restart();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
