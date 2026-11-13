import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs
import qs.components
import qs.services

// bluetooth: the device settings page's machinery, moved into the app. Bluez
// through quickshell (the adapter's address and the bluez version through
// bluetoothctl -- quickshell does not expose them). The adapter switch and
// discoverable, every device bluez knows -- paired ones tap to connect or
// disconnect, new ones tap to pair (trusted, then connect: bluez bonds inside
// connect, where Pair() alone leaves a bare ACL link it drops seconds later),
// battery where the device reports one. Scanning runs only while this page
// is open. The advanced block: adapter facts, a power-cycle reset, the
// service restart (pkexec), remove every device (two taps, armed).
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    readonly property var adapter: Bluetooth.defaultAdapter
    property string adapterAddress: ""
    property string bluezVer: ""
    property bool armWipe: false

    function barHas(w) { return Theme.state.bar.includes(w); }
    function barFlip(w) {
        const a = Theme.state.bar.slice();
        const i = a.indexOf(w);
        if (i >= 0) a.splice(i, 1); else a.push(w);
        Theme.state.bar = a;
    }

    Process {
        id: btInfoProc
        command: ["sh", "-c", "bluetoothctl show; bluetoothctl --version"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/Controller\s+([0-9A-Fa-f:]{17})/);
                if (m) pg.adapterAddress = m[1].toUpperCase();
                const v = text.match(/bluetoothctl:\s*([\d.]+)/);
                if (v) pg.bluezVer = v[1];
            }
        }
    }
    Timer { id: btCycle; interval: 700; onTriggered: if (pg.adapter) pg.adapter.enabled = true }
    Binding { when: pg.active && (pg.adapter?.enabled ?? false); target: pg.adapter; property: "discovering"; value: true }
    readonly property var btDevs: !adapter ? [] : Bluetooth.devices.values.slice()
        .sort((a, b) => (b.connected - a.connected) || ((b.paired || b.bonded) - (a.paired || a.bonded)) || (a.name || "").localeCompare(b.name || ""))
    function btIcon(i) {
        return /audio|head/.test(i ?? "") ? "\u{F02CB}" : /mouse/.test(i ?? "") ? "\u{F037D}" : /keyboard/.test(i ?? "") ? "\u{F030C}" : /phone/.test(i ?? "") ? "\u{F03F2}" : "\u{F00AF}";
    }
    onActiveChanged: {
        if (active) btInfoProc.running = true;
        else armWipe = false;
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
                SetHead { text: "bluetooth" }
                SetCard {
                    SetToggle {
                        label: "bluetooth"
                        sub: pg.adapter ? (pg.adapter.enabled ? "on" : "off") : ""
                        on: pg.adapter?.enabled ?? false
                        onFlip: want => { if (pg.adapter) pg.adapter.enabled = want; }
                    }
                    SetRow {
                        visible: !!pg.adapter && pg.adapter.enabled
                        label: "now discoverable as"
                        value: pg.adapter?.name ?? ""
                    }
                    SetToggle {
                        visible: !!pg.adapter && pg.adapter.enabled
                        label: "discoverable"
                        on: pg.adapter?.discoverable ?? false
                        onFlip: want => { if (pg.adapter) pg.adapter.discoverable = want; }
                    }
                    SetToggle {
                        label: "show in the bar"
                        on: pg.barHas("bluetooth")
                        divider: false
                        onFlip: pg.barFlip("bluetooth")
                    }
                    Lb { visible: !pg.adapter; px: 11; color: Theme.mute; text: "no bluetooth adapter on this machine" }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: `devices · ${pg.btDevs.length}` }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: pg.btDevs
                            BtRow { }
                        }
                    }
                    Lb { visible: pg.btDevs.length === 0; px: 11; color: Theme.mute; text: pg.adapter?.discovering ? "looking for devices nearby…" : "no devices" }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "advanced" }
                SetCard {
                    SetRow { label: "name"; value: pg.adapter?.name || "—" }
                    SetRow { label: "address"; value: pg.adapterAddress || "—" }
                    SetRow { label: "adapter"; value: pg.adapter?.adapterId || "—" }
                    SetRow { label: "bluez"; value: pg.bluezVer ? `version ${pg.bluezVer}` : "—" }
                    SetRow {
                        label: "reset the adapter"
                        sub: "power-cycle — connected devices drop, then reconnect"
                        clickable: true
                        onHit: if (pg.adapter) { pg.adapter.enabled = false; btCycle.restart(); }
                    }
                    SetRow {
                        label: "restart the bluetooth service"
                        sub: "pkexec — asks for your password"
                        clickable: true
                        onHit: Quickshell.execDetached(["pkexec", "systemctl", "restart", "bluetooth"])
                    }
                    SetRow {
                        label: pg.armWipe ? "tap again to remove all devices" : "remove all devices"
                        sub: "unpairs everything — each device must be paired again"
                        clickable: true
                        divider: false
                        onHit: {
                            if (!pg.armWipe) { pg.armWipe = true; return; }
                            for (const d of Bluetooth.devices.values) if (d.paired || d.bonded) d.forget();
                            pg.armWipe = false;
                        }
                    }
                }
            }
        }
    }

    component BtRow: Rectangle {
        id: brow
        required property var modelData
        readonly property var o: modelData
        readonly property bool on: o.connected
        readonly property bool busy: o.pairing || o.state === BluetoothDeviceState.Connecting || o.state === BluetoothDeviceState.Disconnecting
        width: parent ? parent.width : 0
        height: 56
        radius: Theme.corner(28)
        color: hov.hovered ? Theme.s3 : "transparent"
        Rectangle {
            id: bic
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: brow.on ? Theme.fg : Theme.s3
            Icon { anchors.centerIn: parent; text: pg.btIcon(brow.o.icon); font.pixelSize: 19; color: brow.on ? Theme.ink : Theme.fg }
        }
        Column {
            anchors { left: bic.right; leftMargin: 14; right: bact.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: brow.o.name || brow.o.deviceName || brow.o.address; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
            Lb {
                px: 10
                text: (brow.o.pairing ? "pairing" : brow.o.state === BluetoothDeviceState.Connecting ? "connecting" : brow.o.state === BluetoothDeviceState.Disconnecting ? "disconnecting"
                    : brow.on ? "connected" : brow.o.paired || brow.o.bonded ? "not connected" : "not paired") + (brow.o.batteryAvailable ? ` · ${Math.round(brow.o.battery * 100)}%` : "")
            }
        }
        Row {
            id: bact
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 8
            SetButton {
                visible: !brow.busy
                label: brow.on ? "disconnect" : brow.o.paired || brow.o.bonded ? "connect" : "pair"
                onHit: {
                    if (brow.on) brow.o.disconnect();
                    else if (brow.o.paired || brow.o.bonded) brow.o.connect();
                    else { brow.o.trusted = true; brow.o.connect(); } // connect, not pair: bluez bonds inside connect; Pair() alone drops the link (see BtMenu)
                }
            }
            SetButton {
                visible: brow.o.paired || brow.o.bonded
                label: "forget"
                onHit: brow.o.forget()
            }
        }
        HoverHandler { id: hov }
    }
}
