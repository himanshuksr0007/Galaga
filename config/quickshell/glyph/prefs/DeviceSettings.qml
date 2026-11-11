import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs
import qs.components
import qs.quick
import qs.services

// device settings: three full pages -- bluetooth, wi-fi, sound -- in the
// glyph settings' clothes but NOT part of them. No section column, no way
// in from prefs: each page opens only from its own bar menu's settings
// button (shell.qml wires the menus here), the way macOS opens its
// bluetooth pane from the bluetooth menu. Esc closes.
// Everything on the pages is the real machinery, most of it shared with
// the menus: bluez through quickshell (the adapter's address and the
// bluez version through bluetoothctl), networking through quickshell and
// nmcli (the hotspot is networkmanager's), sound through pipewire and
// the Eq service. The "show in the bar" switches edit Theme.state.bar,
// the tray list prefs -> BAR edits.
PanelWindow {
    id: root

    property string page: "bt" // "bt" | "wifi" | "sound"
    readonly property string title: page === "bt" ? "BLUETOOTH" : page === "wifi" ? "WI-FI" : "SOUND"

    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    function open(p) {
        page = p;
        shown = true;
        stage.forceActiveFocus();
        if (p === "bt") btInfoProc.running = true;
    }
    function close() { shown = false; }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-devsettings"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: root.t
    }

    // ---- shared state ----
    readonly property var adapter: Bluetooth.defaultAdapter
    function barHas(w) { return Theme.state.bar.includes(w); }
    function barFlip(w) {
        const a = Theme.state.bar.slice();
        const i = a.indexOf(w);
        if (i >= 0) a.splice(i, 1); else a.push(w);
        Theme.state.bar = a;
    }

    // ---- bluetooth facts and actions (the menu's info page, at page scale) ----
    property string adapterAddress: ""
    property string bluezVer: ""
    property bool armWipe: false
    Process {
        id: btInfoProc
        command: ["sh", "-c", "bluetoothctl show; bluetoothctl --version"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/Controller\s+([0-9A-Fa-f:]{17})/);
                if (m) root.adapterAddress = m[1].toUpperCase();
                const v = text.match(/bluetoothctl:\s*([\d.]+)/);
                if (v) root.bluezVer = v[1];
            }
        }
    }
    Timer { id: btCycle; interval: 700; onTriggered: if (root.adapter) root.adapter.enabled = true }
    Binding { when: root.shown && root.page === "bt" && (root.adapter?.enabled ?? false); target: root.adapter; property: "discovering"; value: true }
    readonly property var btDevs: !adapter ? [] : Bluetooth.devices.values.slice()
        .sort((a, b) => (b.connected - a.connected) || ((b.paired || b.bonded) - (a.paired || a.bonded)) || (a.name || "").localeCompare(b.name || ""))
    function btIcon(i) {
        return /audio|head/.test(i ?? "") ? "\u{F02CB}" : /mouse/.test(i ?? "") ? "\u{F037D}" : /keyboard/.test(i ?? "") ? "\u{F030C}" : /phone/.test(i ?? "") ? "\u{F03F2}" : "\u{F00AF}";
    }

    // ---- wi-fi facts and actions (the menu's, at page scale) ----
    readonly property var wdev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    property var ask: null
    property string werr: ""
    property bool armForget: false
    property bool showPass: false
    property bool hotspotOn: false
    property string hostName: ""
    property var drv: ({ driver: "", product: "", ip: "" })
    Binding { when: root.shown && root.page === "wifi" && Networking.wifiEnabled; target: root.wdev; property: "scannerEnabled"; value: true }
    readonly property var allNets: !wdev ? [] : wdev.networks.values.filter(n => n.name)
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    readonly property var knownNets: allNets.filter(n => n.known)
    readonly property var otherNets: allNets.filter(n => !n.known)
    readonly property var connNet: allNets.find(n => n.connected) ?? null
    function bars(n) {
        const lock = n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
        const i = Math.min(3, Math.floor(n.signalStrength * 4));
        return (lock ? ["\u{F0920}", "\u{F0923}", "\u{F0926}", "\u{F0929}"] : ["\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"])[i];
    }
    function tapNet(o) {
        werr = "";
        if (o.connected) return o.disconnect();
        if (o.known || o.security === WifiSecurityType.Open || o.security === WifiSecurityType.Owe) return o.connect();
        ask = ask === o ? null : o;
    }
    // shell.qml rolls the password once at first boot; this only backstops
    // an empty store, and an empty store is the only way a new one is rolled
    function ensureCreds() {
        if (!Theme.state.hotspotPass) {
            const abc = "abcdefghjkmnpqrstuvwxyz23456789";
            let p = "";
            for (let i = 0; i < 12; i++) p += abc[Math.floor(Math.random() * abc.length)];
            Theme.state.hotspotPass = p;
        }
        return [Theme.state.hotspotSsid || hostName || "glyph", Theme.state.hotspotPass];
    }
    // hotspot and wi-fi at once: one radio can only sit on one channel, so
    // the hotspot starts on the channel the live connection already uses
    property var hsCreds: []
    function hotspotUp() {
        hsCreds = ensureCreds();
        hsChanProc.command = ["nmcli", "-t", "-f", "IN-USE,CHAN", "device", "wifi", "list", "ifname", wdev.name];
        hsChanProc.running = true;
    }
    Process {
        id: hsChanProc
        stdout: StdioCollector {
            onStreamFinished: {
                let ch = 0;
                for (const l of text.split("\n")) if (l.startsWith("*:")) ch = parseInt(l.split(":")[1]) || 0;
                const a = ["nmcli", "device", "wifi", "hotspot", "ifname", root.wdev.name, "ssid", root.hsCreds[0], "password", root.hsCreds[1]];
                if (ch > 0) a.push("band", ch > 14 ? "a" : "bg", "channel", String(ch));
                Quickshell.execDetached(a);
            }
        }
    }
    function toggleHotspot() {
        if (!wdev) return;
        if (hotspotOn) Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"]);
        else hotspotUp();
        hsPoll.restart();
    }
    Process {
        id: nmActiveProc
        command: ["nmcli", "-t", "-f", "NAME", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: root.hotspotOn = text.split("\n").map(s => s.trim()).includes("Hotspot")
        }
    }
    Timer { interval: 3000; repeat: true; running: root.shown && root.page === "wifi"; onTriggered: nmActiveProc.running = true }
    Timer { id: hsPoll; interval: 1200; onTriggered: nmActiveProc.running = true }
    Timer { id: hsRestart; interval: 900; onTriggered: if (root.wdev) root.hotspotUp() }
    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: root.hostName = text.trim() }
    }
    Process {
        id: nmInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                root.drv = { driver: l[0] ?? "", product: l[1] ?? "", ip: (l[2] ?? "").split("/")[0] };
            }
        }
    }
    Timer { id: wifiCycle; interval: 700; onTriggered: Networking.wifiEnabled = true }
    onPageChanged: {
        armWipe = false;
        armForget = false;
        ask = null;
        werr = "";
        if (page === "wifi") {
            nmActiveProc.running = true;
            if (wdev) {
                nmInfoProc.command = ["nmcli", "-g", "GENERAL.DRIVER,GENERAL.PRODUCT,IP4.ADDRESS", "device", "show", wdev.name];
                nmInfoProc.running = true;
            }
        }
    }
    Component.onCompleted: hostProc.running = true

    // ---- sound state ----
    property var selDev: null // the output the sound page is showing, picked in the outputs list
    readonly property var selEq: selDev ? Eq.store(selDev.name) : { on: false, lo: 0, mid: 0, hi: 0 }
    PwObjectTracker { objects: root.selDev ? [root.selDev] : [] }

    Stage {
        id: stage
        opacity: root.t
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
        }

        // the word for the page, prefs' treatment: a red dot and the big dotted word
        Row {
            x: 150 - 30 * (1 - root.t)
            y: 64
            spacing: 26
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 13
                color: Theme.red
            }
            Num { text: root.title; font.pixelSize: 84 }
        }

        Row {
            x: 150
            anchors { bottom: parent.bottom; bottomMargin: 70 }
            spacing: 34
            Lb { text: "esc close"; TapHandler { onTapped: root.close() } }
        }

        // ============ BLUETOOTH PAGE ============
        Item {
            anchors { left: parent.left; leftMargin: 150; right: parent.right; rightMargin: 150; top: parent.top; topMargin: 216; bottom: parent.bottom; bottomMargin: 130 }
            visible: root.page === "bt"
            opacity: root.page === "bt" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Row {
                anchors.fill: parent
                spacing: 56

                // left rail: the tile, the state, the big switch
                Column {
                    width: 300
                    spacing: 18
                    Rectangle {
                        width: 132
                        height: 132
                        radius: Theme.corner(34)
                        color: Theme.s2
                        Icon { anchors.centerIn: parent; text: root.adapter?.enabled ? "\u{F00AF}" : "\u{F00B2}"; font.pixelSize: 62; color: root.adapter?.enabled ? Theme.fg : Theme.grey }
                    }
                    Text { textFormat: Text.PlainText; text: `Bluetooth: ${root.adapter?.enabled ? "On" : "Off"}`; font { family: Theme.ui; pixelSize: 20; weight: Font.DemiBold } color: Theme.fg }
                    PillBtn {
                        label: root.adapter?.enabled ? "turn bluetooth off" : "turn bluetooth on"
                        onHit: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                    }
                    Column {
                        visible: !!root.adapter && root.adapter.enabled
                        width: parent.width
                        spacing: 8
                        Lb { text: "now discoverable as" }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: root.adapter?.name ?? ""; font { family: Theme.ui; pixelSize: 16 } color: Theme.fg }
                        SwitchRow {
                            width: parent.width
                            label: "discoverable"
                            on: root.adapter?.discoverable ?? false
                            onFlip: if (root.adapter) root.adapter.discoverable = !root.adapter.discoverable
                        }
                    }
                    SwitchRow {
                        width: parent.width
                        label: "show in the bar"
                        on: root.barHas("bluetooth")
                        onFlip: root.barFlip("bluetooth")
                    }
                    Lb { visible: !root.adapter; px: 11; color: Theme.mute; text: "no bluetooth adapter on this machine" }
                }

                // main: devices, then the advanced block
                Flickable {
                    width: parent.width - 356
                    height: parent.height
                    contentHeight: btMain.height
                    clip: true
                    Column {
                        id: btMain
                        width: parent.width
                        spacing: 22

                        Column {
                            id: btDevCol
                            width: parent.width
                            spacing: 4
                            Lb { x: 4; text: `devices · ${root.btDevs.length}` }
                            Repeater {
                                model: root.btDevs
                                BtRow { }
                            }
                            Lb { visible: root.btDevs.length === 0; x: 4; px: 11; color: Theme.mute; text: root.adapter?.discovering ? "looking for devices nearby…" : "no devices" }
                        }

                        Column {
                            width: parent.width
                            spacing: 10
                            Lb { x: 4; text: "advanced" }
                            Column {
                                width: parent.width
                                spacing: 8
                                InfoLine { k: "name"; v: root.adapter?.name || "—" }
                                InfoLine { k: "address"; v: root.adapterAddress || "—" }
                                InfoLine { k: "adapter"; v: root.adapter?.adapterId || "—" }
                                InfoLine { k: "bluez"; v: root.bluezVer ? `version ${root.bluezVer}` : "—" }
                            }
                            ActLine {
                                label: "reset the adapter"
                                sub: "power-cycle — connected devices drop, then reconnect"
                                onHit: if (root.adapter) { root.adapter.enabled = false; btCycle.restart(); }
                            }
                            ActLine {
                                label: "restart the bluetooth service"
                                sub: "pkexec — asks for your password"
                                onHit: Quickshell.execDetached(["pkexec", "systemctl", "restart", "bluetooth"])
                            }
                            ActLine {
                                label: root.armWipe ? "tap again to remove all devices" : "remove all devices"
                                sub: "unpairs everything — each device must be paired again"
                                danger: root.armWipe
                                onHit: {
                                    if (!root.armWipe) { root.armWipe = true; return; }
                                    for (const d of Bluetooth.devices.values) if (d.paired || d.bonded) d.forget();
                                    root.armWipe = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ============ WI-FI PAGE ============
        Item {
            anchors { left: parent.left; leftMargin: 150; right: parent.right; rightMargin: 150; top: parent.top; topMargin: 216; bottom: parent.bottom; bottomMargin: 130 }
            visible: root.page === "wifi"
            opacity: root.page === "wifi" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Row {
                anchors.fill: parent
                spacing: 56

                Column {
                    width: 300
                    spacing: 18
                    Rectangle {
                        width: 132
                        height: 132
                        radius: Theme.corner(34)
                        color: Theme.s2
                        Icon { anchors.centerIn: parent; text: Networking.wifiEnabled ? "\u{F05A9}" : "\u{F05AA}"; font.pixelSize: 62; color: Networking.wifiEnabled ? Theme.fg : Theme.grey }
                    }
                    Text { textFormat: Text.PlainText; text: `Wi-Fi: ${Networking.wifiEnabled ? "On" : "Off"}`; font { family: Theme.ui; pixelSize: 20; weight: Font.DemiBold } color: Theme.fg }
                    PillBtn {
                        label: Networking.wifiEnabled ? "turn wi-fi off" : "turn wi-fi on"
                        onHit: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                    Column {
                        visible: Networking.wifiEnabled
                        width: parent.width
                        spacing: 8
                        Lb { text: "connected to" }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: root.connNet?.name ?? "not connected"; font { family: Theme.ui; pixelSize: 16 } color: Theme.fg }
                    }
                    SwitchRow {
                        width: parent.width
                        label: "show in the bar"
                        on: root.barHas("wifi")
                        onFlip: root.barFlip("wifi")
                    }
                    Lb { visible: !root.wdev; px: 11; color: Theme.mute; text: "no wi-fi card on this machine" }
                }

                Flickable {
                    width: parent.width - 356
                    height: parent.height
                    contentHeight: wifiMain.height
                    clip: true
                    Column {
                        id: wifiMain
                        width: parent.width
                        spacing: 22

                        // personal hotspot
                        Column {
                            visible: !!root.wdev && Networking.wifiEnabled
                            width: parent.width
                            spacing: 10
                            Lb { x: 4; text: "personal hotspot" }
                            SwitchRow {
                                width: parent.width
                                label: Theme.state.hotspotSsid || root.hostName || "hotspot"
                                sub: root.hotspotOn ? "on — other devices can join" : "off"
                                on: root.hotspotOn
                                onFlip: root.toggleHotspot()
                            }
                            Field {
                                id: hsName
                                label: "name"
                                hint: root.hostName || "hotspot"
                                Component.onCompleted: text = Theme.state.hotspotSsid
                                onEdited: Theme.state.hotspotSsid = text
                            }
                            Field {
                                id: hsPass
                                label: "password"
                                hint: "one is made when the hotspot first starts"
                                echo: root.showPass ? TextInput.Normal : TextInput.Password
                                Component.onCompleted: text = Theme.state.hotspotPass
                                onEdited: if (text) Theme.state.hotspotPass = text
                            }
                            SwitchRow {
                                width: parent.width
                                label: "show password"
                                on: root.showPass
                                onFlip: root.showPass = !root.showPass
                            }
                            ActLine {
                                visible: root.hotspotOn
                                label: "restart the hotspot"
                                sub: "applies the name and password above"
                                onHit: { Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"]); hsRestart.restart(); hsPoll.restart(); }
                            }
                        }

                        // known networks
                        Column {
                            visible: Networking.wifiEnabled
                            width: parent.width
                            spacing: 4
                            Lb { x: 4; text: `known networks · ${root.knownNets.length}` }
                            Column {
                                id: knownCol
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: root.knownNets
                                    NetRow { w: knownCol.width }
                                }
                            }
                            Lb { visible: root.knownNets.length === 0; x: 4; px: 11; color: Theme.mute; text: "no saved networks" }
                        }

                        // the password row for a new network
                        Column {
                            visible: !!root.ask
                            width: parent.width
                            spacing: 10
                            Lb { x: 4; text: root.ask ? `password · ${root.ask.name}` : "" }
                            Row {
                                width: parent.width
                                spacing: 10
                                Field {
                                    id: askPw
                                    width: parent.width - 130
                                    label: "password"
                                    hint: "the network's password"
                                    echo: TextInput.Password
                                }
                                PillBtn {
                                    label: "join"
                                    onHit: if (askPw.text && root.ask) { root.ask.connectWithPsk(askPw.text); askPw.text = ""; root.ask = null; }
                                }
                            }
                            Lb { visible: !!root.werr; x: 4; px: 11; color: Theme.red; text: root.werr }
                        }

                        // other networks
                        Column {
                            visible: Networking.wifiEnabled
                            width: parent.width
                            spacing: 4
                            Lb { x: 4; text: `other networks · ${root.otherNets.length}` }
                            Column {
                                id: otherCol
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: root.otherNets
                                    NetRow { w: otherCol.width }
                                }
                            }
                            Lb { visible: root.otherNets.length === 0; x: 4; px: 11; color: Theme.mute; text: "scanning…" }
                        }

                        // advanced
                        Column {
                            width: parent.width
                            spacing: 10
                            Lb { x: 4; text: "advanced" }
                            Column {
                                width: parent.width
                                spacing: 8
                                InfoLine { k: "interface"; v: root.wdev?.name || "—" }
                                InfoLine { k: "mac"; v: root.wdev?.address || "—" }
                                InfoLine { k: "card"; v: root.drv.product || "—" }
                                InfoLine { k: "driver"; v: root.drv.driver || "—" }
                                InfoLine { k: "ip address"; v: root.drv.ip || "—" }
                            }
                            ActLine {
                                label: "restart wi-fi"
                                sub: "radio off and on — drops the current network, then rejoins"
                                onHit: { Networking.wifiEnabled = false; wifiCycle.restart(); }
                            }
                            ActLine {
                                label: "restart networkmanager"
                                sub: "pkexec — asks for your password · drops every connection"
                                onHit: Quickshell.execDetached(["pkexec", "systemctl", "restart", "NetworkManager"])
                            }
                            ActLine {
                                label: root.armForget ? "tap again to forget all networks" : "forget all saved networks"
                                sub: "passwords go with them — each network must be joined again"
                                danger: root.armForget
                                onHit: {
                                    if (!root.armForget) { root.armForget = true; return; }
                                    for (const n of root.knownNets) n.forget();
                                    root.armForget = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ============ SOUND PAGE ============
        Item {
            anchors { left: parent.left; leftMargin: 150; right: parent.right; rightMargin: 150; top: parent.top; topMargin: 216; bottom: parent.bottom; bottomMargin: 130 }
            visible: root.page === "sound"
            opacity: root.page === "sound" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Row {
                anchors.fill: parent
                spacing: 56

                Column {
                    width: 300
                    spacing: 18
                    Rectangle {
                        width: 132
                        height: 132
                        radius: Theme.corner(34)
                        color: Theme.s2
                        Icon { anchors.centerIn: parent; text: Sys.muted ? "\u{F075F}" : "\u{F057E}"; font.pixelSize: 62; color: Theme.fg }
                    }
                    Column {
                        width: parent.width
                        spacing: 8
                        Lb { text: "output" }
                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Pipewire.defaultAudioSink ? outList.name(Pipewire.defaultAudioSink) : "none"; font { family: Theme.ui; pixelSize: 16 } color: Theme.fg }
                    }
                    VolSlider { width: parent.width }
                    SwitchRow {
                        width: parent.width
                        label: "mute"
                        on: Sys.muted
                        onFlip: if (Pipewire.defaultAudioSink?.audio) Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                    }
                    SwitchRow {
                        width: parent.width
                        label: "show in the bar"
                        on: root.barHas("sound")
                        onFlip: root.barFlip("sound")
                    }
                }

                Flickable {
                    width: parent.width - 356
                    height: parent.height
                    contentHeight: soundMain.height
                    clip: true
                    Column {
                        id: soundMain
                        width: parent.width
                        spacing: 22

                        Out {
                            id: outList
                            width: parent.width
                            open: true
                            inspectable: true
                            onInspect: n => root.selDev = n
                        }

                        // the picked output: its own volume, then the system eq in front of it
                        Column {
                            visible: !!root.selDev
                            width: parent.width
                            spacing: 12
                            Column {
                                width: parent.width
                                spacing: 4
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: root.selDev ? outList.name(root.selDev) : ""; font { family: Theme.ui; pixelSize: 18; weight: Font.DemiBold } color: Theme.fg }
                                Lb {
                                    px: 10
                                    text: root.selDev ? [outList.kind(root.selDev)[0],
                                        AudioDev.codecOf(root.selDev),
                                        AudioDev.batteryOf(root.selDev) >= 0 ? `${AudioDev.batteryOf(root.selDev)}%` : ""].filter(s => s).join(" · ") : ""
                                }
                            }
                            DevVol { width: parent.width; node: root.selDev }

                            Column {
                                visible: Eq.alive
                                width: parent.width
                                spacing: 10
                                SwitchRow {
                                    width: parent.width
                                    label: "system eq"
                                    sub: "bass, mid and treble this pc applies in front of the device"
                                    on: root.selEq.on
                                    onFlip: if (root.selDev) Eq.setOn(root.selDev, !root.selEq.on)
                                }
                                Column {
                                    width: parent.width
                                    spacing: 8
                                    opacity: root.selEq.on ? 1 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: Theme.t } }
                                    Band { label: "bass"; value: root.selEq.lo; onMoved: db => Eq.setBand(root.selDev.name, "lo", db) }
                                    Band { label: "mid"; value: root.selEq.mid; onMoved: db => Eq.setBand(root.selDev.name, "mid", db) }
                                    Band { label: "treble"; value: root.selEq.hi; onMoved: db => Eq.setBand(root.selDev.name, "hi", db) }
                                    Row {
                                        spacing: 8
                                        Repeater {
                                            model: [["flat", 0, 0, 0], ["bass", 7, 1, -2], ["vocal", -2, 5, 2], ["bright", -3, 1, 7]]
                                            Rectangle {
                                                id: chip
                                                required property var modelData
                                                readonly property bool on: root.selEq.lo === modelData[1] && root.selEq.mid === modelData[2] && root.selEq.hi === modelData[3]
                                                width: chipLb.width + 22
                                                height: 28
                                                radius: Theme.corner(14)
                                                color: on ? Theme.fg : Theme.s2
                                                Lb { id: chipLb; anchors.centerIn: parent; text: chip.modelData[0]; px: 11; color: chip.on ? Theme.ink : Theme.grey }
                                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: Eq.setPreset(root.selDev.name, chip.modelData[1], chip.modelData[2], chip.modelData[3]) }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // playback
                        Rectangle {
                            visible: !!Media.player
                            width: parent.width
                            height: 78
                            radius: Theme.corner(28)
                            color: Theme.s2
                            Art { id: sart; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56; step: 4; url: Media.player?.trackArtUrl ?? "" }
                            Column {
                                anchors { left: sart.right; leftMargin: 14; right: sctl.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackTitle || "Nothing on"; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackArtist ?? ""; font { family: Theme.ui; pixelSize: 12 } color: Theme.grey }
                            }
                            Controls { id: sctl; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } size: 18; play: 40 }
                        }
                    }
                }
            }
        }
    }

    // ---------- rows and controls, the menus' shapes at page scale ----------

    component BtRow: Rectangle {
        id: brow
        required property var modelData
        readonly property var o: modelData
        readonly property bool on: o.connected
        readonly property bool busy: o.pairing || o.state === BluetoothDeviceState.Connecting || o.state === BluetoothDeviceState.Disconnecting
        width: btDevCol.width
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
            Icon { anchors.centerIn: parent; text: root.btIcon(brow.o.icon); font.pixelSize: 19; color: brow.on ? Theme.ink : Theme.fg }
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
            PillBtn {
                visible: !brow.busy
                label: brow.on ? "disconnect" : brow.o.paired || brow.o.bonded ? "connect" : "pair"
                onHit: {
                    if (brow.on) brow.o.disconnect();
                    else if (brow.o.paired || brow.o.bonded) brow.o.connect();
                    else { brow.o.trusted = true; brow.o.pair(); }
                }
            }
            PillBtn {
                visible: brow.o.paired || brow.o.bonded
                label: "forget"
                dim: true
                onHit: brow.o.forget()
            }
        }
        HoverHandler { id: hov }
    }

    component NetRow: Rectangle {
        id: nrow
        property real w: 0
        required property var modelData
        readonly property var o: modelData
        readonly property bool on: o.connected
        readonly property bool busy: o.stateChanging
        width: w
        height: 56
        radius: Theme.corner(28)
        color: hov.hovered ? Theme.s3 : "transparent"
        Rectangle {
            id: nic
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: nrow.on ? Theme.fg : Theme.s3
            Icon { anchors.centerIn: parent; text: root.bars(nrow.o); font.pixelSize: 19; color: nrow.on ? Theme.ink : Theme.fg }
        }
        Column {
            anchors { left: nic.right; leftMargin: 14; right: nact.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: nrow.o.name; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
            Lb {
                px: 10
                text: `${nrow.on ? "connected" : nrow.busy ? "connecting" : nrow.o.known ? "saved" : WifiSecurityType.toString(nrow.o.security).toLowerCase()} · ${Math.round(nrow.o.signalStrength * 100)}%`
            }
        }
        Row {
            id: nact
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 8
            PillBtn {
                visible: nrow.o.known && !nrow.on
                label: "forget"
                dim: true
                onHit: nrow.o.forget()
            }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.tapNet(nrow.o) }
        Connections {
            target: nrow.o
            ignoreUnknownSignals: true
            function onConnectionFailed(r) {
                if (r === ConnectionFailReason.NoSecrets) root.ask = nrow.o;
                else root.werr = ConnectionFailReason.toString(r);
            }
        }
    }

    component Switch: Rectangle {
        id: sw
        property bool on: false
        signal flip
        width: 46
        height: 26
        radius: 13
        color: on ? Theme.fg : Theme.s2
        Behavior on color { ColorAnimation { duration: Theme.t } }
        Rectangle {
            x: sw.on ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: sw.on ? Theme.ink : Theme.grey
            Behavior on x { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sw.flip() }
    }

    component SwitchRow: Item {
        id: srow
        property string label: ""
        property string sub: ""
        property bool on: false
        signal flip
        height: sub ? 44 : 30
        Column {
            anchors { left: parent.left; leftMargin: 4; right: ssw.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: srow.label; font { family: Theme.ui; pixelSize: 15 } color: Theme.fg }
            Lb { visible: !!srow.sub; px: 10; color: Theme.mute; text: srow.sub }
        }
        Switch {
            id: ssw
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            on: srow.on
            onFlip: srow.flip()
        }
    }

    component PillBtn: Rectangle {
        id: pb
        property string label: ""
        property bool dim: false
        signal hit
        width: pbLb.width + 28
        height: 32
        radius: Theme.corner(16)
        color: pbhov.hovered ? Theme.fg : dim ? Theme.s2 : Theme.s3
        Behavior on color { ColorAnimation { duration: Theme.t } }
        Lb { id: pbLb; anchors.centerIn: parent; text: pb.label; px: 11; color: pbhov.hovered ? Theme.ink : dim ? Theme.grey : Theme.fg }
        HoverHandler { id: pbhov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pb.hit() }
    }

    component InfoLine: Item {
        property string k: ""
        property string v: ""
        width: parent ? parent.width : 0
        height: 22
        Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: k }
        Text {
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            width: parent.width * 0.62
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: v
            font { family: Theme.mono; pixelSize: 12 }
            color: Theme.fg
        }
    }

    component ActLine: Rectangle {
        property string label: ""
        property string sub: ""
        property bool danger: false
        signal hit
        width: parent ? parent.width : 0
        height: 54
        radius: Theme.corner(27)
        color: ahov.hovered ? Theme.s3 : Theme.s2
        Column {
            anchors { left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: label; font { family: Theme.ui; pixelSize: 14; weight: Font.DemiBold } color: danger ? Theme.red : Theme.fg }
            Lb { visible: !!sub; px: 10; color: Theme.mute; text: sub }
        }
        HoverHandler { id: ahov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: hit() }
    }

    component Field: Rectangle {
        id: fld
        property string label: ""
        property string hint: ""
        property alias text: fin.text
        property int echo: TextInput.Normal
        signal edited
        width: parent ? parent.width : 0
        height: 48
        radius: Theme.corner(24)
        color: Theme.s2
        border { width: fin.activeFocus ? 1 : 0; color: Theme.fg }
        Lb { id: flb; x: 18; anchors.verticalCenter: parent.verticalCenter; text: fld.label; color: fin.activeFocus ? Theme.fg : Theme.grey }
        TextInput {
            id: fin
            anchors { left: flb.right; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            font { family: Theme.ui; pixelSize: 15 }
            color: Theme.fg
            selectionColor: Theme.s3
            clip: true
            echoMode: fld.echo
            passwordCharacter: "•"
            activeFocusOnTab: true
            onEditingFinished: fld.edited()
            Text { visible: !fin.text; text: fld.hint; font: fin.font; color: Theme.mute }
        }
    }

    // the master volume slider, the sound menu's shape (Sys-driven)
    component VolSlider: Rectangle {
        id: sl
        readonly property real value: Sys.muted ? 0 : Sys.vol
        readonly property real shown: area.pressed ? area.v : value
        height: 54
        radius: Theme.corner(27)
        color: Theme.s2
        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11 - 2.8
            Repeater {
                model: Math.max(0, Math.floor((sl.width - 20) / 11) + 1)
                Rectangle { width: 2.8; height: 2.8; radius: 1.4; color: Theme.mute }
            }
        }
        Rectangle {
            width: Math.max(height, sl.width * sl.shown)
            height: parent.height
            radius: Theme.corner(27)
            color: Theme.fg
            Behavior on width { enabled: !area.pressed; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; text: Sys.muted ? "\u{F075F}" : "\u{F057E}"; font.pixelSize: 21; color: Theme.ink }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: val.width + 16
            height: val.height + 8
            radius: Theme.corner(10)
            color: Theme.s2
            Lb { id: val; anchors.centerIn: parent; text: Math.round(sl.shown * 100); color: Theme.grey }
        }
        MouseArea {
            id: area
            property real v
            property real wacc: 0
            anchors.fill: parent
            preventStealing: true
            function set(x) { v = Math.max(0, Math.min(1, x / width)); Sys.setVol(v); }
            onPressed: e => set(e.x)
            onPositionChanged: e => set(e.x)
            onWheel: e => {
                wacc += (e.inverted ? -1 : 1) * (e.angleDelta.y || -e.angleDelta.x) / 120 * 0.05 * (e.phase === Qt.NoScrollPhase ? 1 : 0.25);
                if (Math.abs(wacc) < 0.02) return;
                set((sl.shown + wacc) * width);
                wacc = 0;
            }
        }
    }

    // one device's own volume, the same slider driving the node itself
    component DevVol: Rectangle {
        id: dv
        property var node
        readonly property real value: node?.audio?.muted ? 0 : node?.audio?.volume ?? 0
        readonly property real shown: area.pressed ? area.v : value
        height: 54
        radius: Theme.corner(27)
        color: Theme.s2
        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11 - 2.8
            Repeater {
                model: Math.max(0, Math.floor((dv.width - 20) / 11) + 1)
                Rectangle { width: 2.8; height: 2.8; radius: 1.4; color: Theme.mute }
            }
        }
        Rectangle {
            width: Math.max(height, dv.width * dv.shown)
            height: parent.height
            radius: Theme.corner(27)
            color: Theme.fg
            Behavior on width { enabled: !area.pressed; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; text: dv.node?.audio?.muted ? "\u{F075F}" : "\u{F057E}"; font.pixelSize: 21; color: Theme.ink }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: val.width + 16
            height: val.height + 8
            radius: Theme.corner(10)
            color: Theme.s2
            Lb { id: val; anchors.centerIn: parent; text: Math.round(dv.shown * 100); color: Theme.grey }
        }
        MouseArea {
            id: area
            property real v
            property real wacc: 0
            anchors.fill: parent
            preventStealing: true
            function set(x) {
                if (!dv.node?.audio) return;
                v = Math.max(0, Math.min(1, x / width));
                dv.node.audio.muted = false;
                dv.node.audio.volume = v;
            }
            onPressed: e => set(e.x)
            onPositionChanged: e => set(e.x)
            onWheel: e => {
                wacc += (e.inverted ? -1 : 1) * (e.angleDelta.y || -e.angleDelta.x) / 120 * 0.05 * (e.phase === Qt.NoScrollPhase ? 1 : 0.25);
                if (Math.abs(wacc) < 0.02) return;
                set((dv.shown + wacc) * width);
                wacc = 0;
            }
        }
    }

    // one eq band, the sound menu's (a dotted track, a pill from the centre notch)
    component Band: Rectangle {
        id: bd
        property string label
        property real value
        signal moved(real db)
        readonly property real shown: area.pressed ? area.v : value
        width: parent ? parent.width : 0
        height: 46
        radius: Theme.corner(23)
        color: Theme.s2
        Rectangle { anchors.centerIn: parent; width: 2; height: 12; radius: 1; color: Theme.mute }
        Rectangle {
            readonly property real half: (bd.width / 2) * (bd.shown / 12)
            x: half >= 0 ? bd.width / 2 : bd.width / 2 + half
            width: Math.max(height, Math.abs(half))
            height: parent.height
            radius: Theme.corner(23)
            color: Theme.fg
            Behavior on x { enabled: !area.pressed; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            Behavior on width { enabled: !area.pressed; NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        }
        Lb { x: 16; anchors.verticalCenter: parent.verticalCenter; text: bd.label; color: bd.shown < -5 ? Theme.ink : Theme.grey }
        Rectangle {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: val.width + 16
            height: val.height + 8
            radius: Theme.corner(10)
            color: Theme.s2
            Lb { id: val; anchors.centerIn: parent; text: (bd.shown > 0 ? "+" : "") + Math.round(bd.shown); color: Theme.grey }
        }
        MouseArea {
            id: area
            property real v
            property real wacc: 0
            anchors.fill: parent
            preventStealing: true
            function set(x) { v = Math.max(-12, Math.min(12, (x / width - 0.5) * 24)); bd.moved(Math.round(v * 2) / 2); }
            onPressed: e => set(e.x)
            onPositionChanged: e => set(e.x)
            onDoubleClicked: bd.moved(0)
            onWheel: e => {
                wacc += (e.inverted ? -1 : 1) * (e.angleDelta.y || -e.angleDelta.x) / 120;
                if (Math.abs(wacc) < 0.5) return;
                bd.moved(Math.max(-12, Math.min(12, bd.shown + Math.round(wacc))));
                wacc = 0;
            }
        }
    }
}
