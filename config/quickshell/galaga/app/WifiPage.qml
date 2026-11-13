import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs
import qs.components
import qs.services

// wi-fi: the device settings page's machinery, moved into the app. Networking
// through quickshell, the hotspot and the rest through nmcli -- the same calls
// WifiMenu makes. The radio and what's connected, this pc's own hotspot (its
// name and password live in Theme.state; shell.qml rolls the password once),
// known and other networks with a new network's password asked in place, a
// hidden-network join (the menu's nmcli call), and the advanced block: card
// facts, restart wi-fi, restart networkmanager (pkexec), forget every saved
// network (two taps, armed). Scanning runs only while this page is open.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    readonly property var wdev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    property var ask: null
    property string werr: ""
    property bool armForget: false
    property bool showPass: false
    property bool hotspotOn: false
    property string hostName: ""
    property var drv: ({ driver: "", product: "", ip: "" })
    property bool joinOpen: false

    function barHas(w) { return Theme.state.bar.includes(w); }
    function barFlip(w) {
        const a = Theme.state.bar.slice();
        const i = a.indexOf(w);
        if (i >= 0) a.splice(i, 1); else a.push(w);
        Theme.state.bar = a;
    }

    Binding { when: pg.active && Networking.wifiEnabled; target: pg.wdev; property: "scannerEnabled"; value: true }
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
        return [Theme.state.hotspotSsid || hostName || "galaga", Theme.state.hotspotPass];
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
                const a = ["nmcli", "device", "wifi", "hotspot", "ifname", pg.wdev.name, "ssid", pg.hsCreds[0], "password", pg.hsCreds[1]];
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
            onStreamFinished: pg.hotspotOn = text.split("\n").map(s => s.trim()).includes("Hotspot")
        }
    }
    Timer { interval: 3000; repeat: true; running: pg.active; onTriggered: nmActiveProc.running = true }
    Timer { id: hsPoll; interval: 1200; onTriggered: nmActiveProc.running = true }
    Timer { id: hsRestart; interval: 900; onTriggered: if (pg.wdev) pg.hotspotUp() }
    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: pg.hostName = text.trim() }
    }
    Process {
        id: nmInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                pg.drv = { driver: l[0] ?? "", product: l[1] ?? "", ip: (l[2] ?? "").split("/")[0] };
            }
        }
    }
    Timer { id: wifiCycle; interval: 700; onTriggered: Networking.wifiEnabled = true }
    onActiveChanged: {
        if (active) {
            nmActiveProc.running = true;
            if (wdev) {
                nmInfoProc.command = ["nmcli", "-g", "GENERAL.DRIVER,GENERAL.PRODUCT,IP4.ADDRESS", "device", "show", wdev.name];
                nmInfoProc.running = true;
            }
        } else {
            armForget = false;
            ask = null;
            werr = "";
            joinOpen = false;
        }
    }
    Component.onCompleted: hostProc.running = true

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
                SetHead { text: "wi-fi" }
                SetCard {
                    SetToggle {
                        label: "wi-fi"
                        sub: Networking.wifiEnabled ? "on" : "off"
                        on: Networking.wifiEnabled
                        onFlip: want => Networking.wifiEnabled = want
                    }
                    SetRow {
                        visible: Networking.wifiEnabled
                        label: "connected to"
                        value: pg.connNet?.name ?? "not connected"
                    }
                    SetToggle {
                        label: "show in the bar"
                        on: pg.barHas("wifi")
                        divider: false
                        onFlip: pg.barFlip("wifi")
                    }
                    Lb { visible: !pg.wdev; px: 11; color: Theme.mute; text: "no wi-fi card on this machine" }
                }
            }

            // personal hotspot
            Column {
                visible: !!pg.wdev && Networking.wifiEnabled
                width: parent.width
                spacing: 10
                SetHead { text: "personal hotspot" }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 10
                        SetToggle {
                            label: Theme.state.hotspotSsid || pg.hostName || "hotspot"
                            sub: pg.hotspotOn ? "on — other devices can join" : "off"
                            on: pg.hotspotOn
                            divider: !pg.hotspotOn
                            onFlip: pg.toggleHotspot()
                        }
                        Column {
                            width: parent.width
                            spacing: 8
                            Field {
                                id: hsName
                                label: "name"
                                hint: pg.hostName || "hotspot"
                                Component.onCompleted: text = Theme.state.hotspotSsid
                                onEdited: Theme.state.hotspotSsid = text
                            }
                            Field {
                                id: hsPass
                                label: "password"
                                hint: "one is made when the hotspot first starts"
                                echo: pg.showPass ? TextInput.Normal : TextInput.Password
                                Component.onCompleted: text = Theme.state.hotspotPass
                                onEdited: if (text) Theme.state.hotspotPass = text
                            }
                        }
                        SetToggle {
                            label: "show password"
                            on: pg.showPass
                            divider: pg.hotspotOn
                            onFlip: want => pg.showPass = want
                        }
                        Item {
                            visible: pg.hotspotOn
                            width: parent.width
                            height: 48
                            Lb { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: "applies the name and password above" }
                            SetButton {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                label: "restart the hotspot"
                                onHit: { Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"]); hsRestart.restart(); hsPoll.restart(); }
                            }
                        }
                    }
                }
            }

            // known networks
            Column {
                visible: Networking.wifiEnabled
                width: parent.width
                spacing: 10
                SetHead { text: `known networks · ${pg.knownNets.length}` }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: pg.knownNets
                            NetRow { }
                        }
                    }
                    Lb { visible: pg.knownNets.length === 0; px: 11; color: Theme.mute; text: "no saved networks" }
                }
            }

            // the password row for a new network
            Column {
                visible: !!pg.ask
                width: parent.width
                spacing: 10
                SetHead { text: pg.ask ? `password · ${pg.ask.name}` : "" }
                SetCard {
                    Item {
                        width: parent ? parent.width : 0
                        height: 48
                        Field {
                            id: askPw
                            anchors { left: parent.left; right: joinBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            label: "password"
                            hint: "the network's password"
                            echo: TextInput.Password
                        }
                        SetButton {
                            id: joinBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            label: "join"
                            onHit: if (askPw.text && pg.ask) { pg.ask.connectWithPsk(askPw.text); askPw.text = ""; pg.ask = null; }
                        }
                    }
                    Lb { visible: !!pg.werr; px: 11; color: Theme.red; text: pg.werr }
                }
            }

            // other networks
            Column {
                visible: Networking.wifiEnabled
                width: parent.width
                spacing: 10
                SetHead { text: `other networks · ${pg.otherNets.length}` }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: pg.otherNets
                            NetRow { }
                        }
                    }
                    Lb { visible: pg.otherNets.length === 0; px: 11; color: Theme.mute; text: "scanning…" }
                }
            }

            // join a hidden network by name (the menu's nmcli call)
            Column {
                visible: Networking.wifiEnabled
                width: parent.width
                spacing: 10
                Item {
                    width: parent.width
                    height: 24
                    Row {
                        spacing: 8
                        Lb { text: "join another network"; anchors.verticalCenter: parent.verticalCenter }
                        Icon { text: pg.joinOpen ? "\u{F0140}" : "\u{F0142}"; font.pixelSize: 13; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: pg.joinOpen = !pg.joinOpen }
                }
                SetCard {
                    visible: pg.joinOpen
                    Column {
                        width: parent.width
                        spacing: 10
                        Column {
                            width: parent.width
                            spacing: 8
                            Field { id: joinName; label: "name"; hint: "network name (ssid)" }
                            Field { id: joinPass; label: "password"; hint: "leave empty for an open one"; echo: TextInput.Password }
                        }
                        Item {
                            width: parent.width
                            height: 48
                            Lb { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: "for hidden networks — the name must be exact" }
                            SetButton {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                label: "join"
                                onHit: {
                                    if (!joinName.text || !pg.wdev) return;
                                    if (joinPass.text) Quickshell.execDetached(["nmcli", "device", "wifi", "connect", joinName.text, "password", joinPass.text, "hidden", "yes"]);
                                    else Quickshell.execDetached(["nmcli", "device", "wifi", "connect", joinName.text, "hidden", "yes"]);
                                    pg.joinOpen = false;
                                }
                            }
                        }
                    }
                }
            }

            // advanced
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "advanced" }
                SetCard {
                    SetRow { label: "interface"; value: pg.wdev?.name || "—" }
                    SetRow { label: "mac"; value: pg.wdev?.address || "—" }
                    SetRow { label: "card"; value: pg.drv.product || "—" }
                    SetRow { label: "driver"; value: pg.drv.driver || "—" }
                    SetRow { label: "ip address"; value: pg.drv.ip || "—" }
                    SetRow {
                        label: "restart wi-fi"
                        sub: "radio off and on — drops the current network, then rejoins"
                        clickable: true
                        onHit: { Networking.wifiEnabled = false; wifiCycle.restart(); }
                    }
                    SetRow {
                        label: "restart networkmanager"
                        sub: "pkexec — asks for your password · drops every connection"
                        clickable: true
                        onHit: Quickshell.execDetached(["pkexec", "systemctl", "restart", "NetworkManager"])
                    }
                    SetRow {
                        label: pg.armForget ? "tap again to forget all networks" : "forget all saved networks"
                        sub: "passwords go with them — each network must be joined again"
                        clickable: true
                        divider: false
                        onHit: {
                            if (!pg.armForget) { pg.armForget = true; return; }
                            for (const n of pg.knownNets) n.forget();
                            pg.armForget = false;
                        }
                    }
                }
            }
        }
    }

    component NetRow: Rectangle {
        id: nrow
        required property var modelData
        readonly property var o: modelData
        readonly property bool on: o.connected
        readonly property bool busy: o.stateChanging
        width: parent ? parent.width : 0
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
            Icon { anchors.centerIn: parent; text: pg.bars(nrow.o); font.pixelSize: 19; color: nrow.on ? Theme.ink : Theme.fg }
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
            SetButton {
                visible: nrow.o.known && !nrow.on
                label: "forget"
                onHit: nrow.o.forget()
            }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pg.tapNet(nrow.o) }
        Connections {
            target: nrow.o
            ignoreUnknownSignals: true
            function onConnectionFailed(r) {
                if (r === ConnectionFailReason.NoSecrets) pg.ask = nrow.o;
                else pg.werr = ConnectionFailReason.toString(r);
            }
        }
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
}
