import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components

// vpn: two real backends, no third invented. The clash verge tunnel is the Sys
// singleton's, exactly what the quick panel tile and the tunnel panel drive --
// Sys.vpn reads it, Sys.toggleVpn() switches it (and wakes verge when it sleeps).
// NetworkManager's own vpn/wireguard profiles come from nmcli with up/down.
// The captive-portal hold is Theme.state.vpnPortal, maintained by the tunnel panel.
Item {
    id: pg

    property bool active: false
    property var conns: []
    property var activeUuids: []
    signal panelRequested

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

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
        if (!conProc.running) conProc.running = true;
        if (!actProc.running) actProc.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: conProc
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                for (const ln of text.split("\n")) {
                    if (!ln.trim()) continue;
                    const f = pg.splitT(ln);
                    if (f.length >= 3 && (f[2] === "vpn" || f[2] === "wireguard"))
                        rows.push({ name: f[0], uuid: f[1], type: f[2] });
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

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "clash verge" }
                SetCard {
                    SetToggle {
                        label: "tunnel"
                        sub: "system proxy or tun, through clash verge"
                        on: Sys.vpn
                        divider: true
                        onFlip: Sys.toggleVpn()
                    }
                    SetRow {
                        label: "state"
                        value: !Sys.verge ? "clash verge is not running" : (Sys.vpn ? "on" : "off")
                        divider: Theme.state.vpnPortal
                    }
                    SetRow {
                        visible: Theme.state.vpnPortal
                        label: "captive portal"
                        value: "sign in to the network — the tunnel is held down"
                        divider: false
                    }
                    Item {
                        width: parent ? parent.width : 0
                        height: 48
                        SetButton {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            label: "open tunnel panel"
                            onHit: pg.panelRequested()
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "networkmanager" }
                SetCard {
                    Lb { visible: !pg.conns.length; text: "no vpn or wireguard connections saved" }
                    Repeater {
                        model: pg.conns
                        SetRow {
                            required property var modelData
                            required property int index
                            readonly property bool up: pg.activeUuids.includes(modelData.uuid)
                            label: modelData.name
                            sub: modelData.type
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
