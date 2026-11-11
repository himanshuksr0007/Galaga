import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// the wi-fi menu: the bar's wi-fi icon opens this dropdown instead of all
// of quick settings -- the sound menu's frame and manners, wi-fi inside.
// A master switch, this pc's own hotspot (networkmanager's, through nmcli:
// toggle here, its name and password on the hotspot page), the saved
// networks, then every other network in range. Rows behave like the
// picker's in quick settings: tap connects or disconnects, a new secured
// network asks its password in place (connectWithPsk; a wrong one comes
// back as a connectionFailed and the password row returns), right-click
// forgets a saved one. Joining a hidden network by name lives under the
// other networks. The footer opens the wi-fi settings page (its own window,
// prefs/DeviceSettings); the (i) beside it opens the
// info page: interface, mac, card and driver (nmcli), the address, and
// the heavy actions -- restart wi-fi, restart networkmanager (pkexec),
// forget every saved network (two taps, armed).
PanelWindow {
    id: root

    signal settingsRequested

    property bool open: false
    function toggle() { open = !open; }
    function close() { open = false; }
    onOpenChanged: {
        if (open) {
            Sounds.play("pop");
            view = "main";
            ask = null;
            err = "";
            armForget = false;
            nmActiveProc.running = true;
        }
    }

    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    readonly property real colW: 336 // the panel's content width (380 - 44), the rows' measure
    readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    property string view: "main" // "main" | "hotspot" | "info"
    property var ask: null         // the network whose password is being typed
    property string err: ""
    property bool armForget: false
    property bool showPass: false
    property bool joinOpen: false
    property bool hotspotOn: false
    property string hostName: ""
    property var drv: ({ driver: "", product: "", ip: "" })

    onViewChanged: {
        if (view === "info" && dev) {
            nmInfoProc.command = ["nmcli", "-g", "GENERAL.DRIVER,GENERAL.PRODUCT,IP4.ADDRESS", "device", "show", dev.name];
            nmInfoProc.running = true;
        }
    }

    // scan while the menu is up, stop when it closes (picker.qml's binding)
    Binding { when: root.open && Networking.wifiEnabled; target: root.dev; property: "scannerEnabled"; value: true }

    readonly property var allNets: !dev ? [] : dev.networks.values.filter(n => n.name)
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
    readonly property var knownNets: allNets.filter(n => n.known)
    readonly property var otherNets: allNets.filter(n => !n.known)
    readonly property var connNet: allNets.find(n => n.connected) ?? null

    // the picker's arc glyphs: the set with a lock for secured networks
    function bars(n) {
        const lock = n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
        const i = Math.min(3, Math.floor(n.signalStrength * 4));
        return (lock ? ["\u{F0920}", "\u{F0923}", "\u{F0926}", "\u{F0929}"] : ["\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"])[i];
    }
    function tapNet(o) {
        err = "";
        if (o.connected) return o.disconnect();
        if (o.known || o.security === WifiSecurityType.Open || o.security === WifiSecurityType.Owe) return o.connect();
        ask = ask === o ? null : o;
    }

    // ---- the hotspot (networkmanager's "Hotspot" connection) ----
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
    // (windows does the same silently). No connection -- no constraint, and
    // networkmanager picks as before
    property var hsCreds: []
    function hotspotUp() {
        hsCreds = ensureCreds();
        hsChanProc.command = ["nmcli", "-t", "-f", "IN-USE,CHAN", "device", "wifi", "list", "ifname", dev.name];
        hsChanProc.running = true;
    }
    Process {
        id: hsChanProc
        stdout: StdioCollector {
            onStreamFinished: {
                let ch = 0;
                for (const l of text.split("\n")) if (l.startsWith("*:")) ch = parseInt(l.split(":")[1]) || 0;
                const a = ["nmcli", "device", "wifi", "hotspot", "ifname", root.dev.name, "ssid", root.hsCreds[0], "password", root.hsCreds[1]];
                if (ch > 0) a.push("band", ch > 14 ? "a" : "bg", "channel", String(ch));
                Quickshell.execDetached(a);
            }
        }
    }
    function toggleHotspot() {
        if (!dev) return;
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
    Timer { interval: 3000; repeat: true; running: root.open; onTriggered: nmActiveProc.running = true }
    Timer { id: hsPoll; interval: 1200; onTriggered: nmActiveProc.running = true }
    Timer { id: hsRestart; interval: 900; onTriggered: if (root.dev) root.hotspotUp() }
    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: root.hostName = text.trim() }
    }
    Component.onCompleted: hostProc.running = true

    // card and driver facts for the info page
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

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-wifi"

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: panel
        readonly property bool barTop: Theme.state.barAt === "top"
        width: 380
        height: (root.view === "main" ? mainCol.height : root.view === "hotspot" ? hsCol.height : infoCol.height) + 44
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        x: parent.width - width - 14
        y: barTop ? Math.ceil(86 * Theme.s) : parent.height - height - Math.ceil(86 * Theme.s)
        opacity: root.t
        transform: [
            Translate { y: (1 - root.t) * (panel.barTop ? -8 : 8) },
            Scale { origin.x: panel.width; origin.y: panel.barTop ? 0 : panel.height; xScale: 0.97 + 0.03 * root.t; yScale: 0.97 + 0.03 * root.t }
        ]
        radius: Theme.corner(36)
        color: Theme.s1
        border { width: 1; color: Theme.s2 }
        focus: true
        Keys.onEscapePressed: {
            if (root.view !== "main") root.view = "main";
            else if (root.ask) root.ask = null;
            else if (root.joinOpen) root.joinOpen = false;
            else root.close();
        }
        MouseArea { anchors.fill: parent } // clicking the panel does not close it

        Item {
            id: view2
            x: 22
            y: 22
            width: parent.width - 44
            height: parent.height - 44
            clip: true

            Row {
                x: root.view === "main" ? 0 : root.view === "hotspot" ? -view2.width : -2 * view2.width
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                spacing: 0

                // ---------- page 1: the menu ----------
                Item {
                    width: view2.width
                    height: mainCol.height
                    opacity: root.view === "main" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Column {
                        id: mainCol
                        width: parent.width
                        spacing: 16

                        Item {
                            width: parent.width
                            height: 26
                            Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "wi-fi" }
                            Lb {
                                anchors { right: sw.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                visible: !!root.err
                                width: Math.min(implicitWidth, 170)
                                elide: Text.ElideRight
                                text: root.err
                                color: Theme.red
                                TapHandler { onTapped: root.err = "" }
                            }
                            Switch {
                                id: sw
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                on: Networking.wifiEnabled
                                onFlip: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                        }

                        Lb { visible: !root.dev; x: 4; px: 11; color: Theme.mute; text: "no wi-fi card on this machine" }
                        Lb { visible: !!root.dev && !Networking.wifiEnabled; x: 4; px: 11; color: Theme.mute; text: "wi-fi is off" }

                        Column {
                            visible: !!root.dev && Networking.wifiEnabled
                            width: parent.width
                            spacing: 16

                            // personal hotspot
                            Column {
                                width: parent.width
                                spacing: 4
                                Lb { x: 4; text: "personal hotspot" }
                                Rectangle {
                                    width: parent.width
                                    height: 56
                                    radius: Theme.corner(28)
                                    color: hhov.hovered ? Theme.s3 : "transparent"
                                    Rectangle {
                                        id: hic
                                        x: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 44
                                        height: 44
                                        radius: 22
                                        color: root.hotspotOn ? Theme.fg : Theme.s3
                                        Icon { anchors.centerIn: parent; text: "\u{F05A9}"; font.pixelSize: 19; color: root.hotspotOn ? Theme.ink : Theme.fg }
                                    }
                                    Column {
                                        anchors { left: hic.right; leftMargin: 14; right: hsw.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Theme.state.hotspotSsid || root.hostName || "hotspot"; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
                                        Lb { px: 10; text: root.hotspotOn ? "on — other devices can join" : "off" }
                                    }
                                    Switch {
                                        id: hsw
                                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        on: root.hotspotOn
                                        onFlip: root.toggleHotspot()
                                    }
                                    HoverHandler { id: hhov }
                                }
                                Item {
                                    width: parent.width
                                    height: 22
                                    Row {
                                        x: 4
                                        spacing: 8
                                        Lb { text: "hotspot settings"; anchors.verticalCenter: parent.verticalCenter }
                                        Icon { text: "\u{F0142}"; font.pixelSize: 13; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.view = "hotspot" }
                                }
                            }

                            // known networks
                            Column {
                                width: parent.width
                                spacing: 4
                                Item {
                                    width: parent.width
                                    height: 20
                                    Lb { x: 4; text: "known networks" }
                                    Lb { anchors.right: parent.right; rightPadding: 4; visible: root.knownNets.length > 0; px: 10; color: Theme.mute; text: "right-click forgets" }
                                }
                                Repeater {
                                    model: root.knownNets
                                    NetRow { }
                                }
                                Lb { visible: root.knownNets.length === 0; x: 4; px: 11; color: Theme.mute; text: "no saved networks" }
                            }

                            // the password row (the picker's, moved in here)
                            Rectangle {
                                visible: !!root.ask
                                width: parent.width
                                height: 56
                                radius: Theme.corner(28)
                                color: Theme.s2
                                border { width: 1; color: Theme.s3 }
                                onVisibleChanged: if (visible) pw.forceActiveFocus()
                                Lb { x: 22; y: 6; px: 9; color: Theme.mute; text: root.ask ? `password · ${root.ask.name}` : "" }
                                TextInput {
                                    id: pw
                                    anchors { left: parent.left; leftMargin: 22; right: go.left; rightMargin: 12; bottom: parent.bottom; bottomMargin: 8 }
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    font { family: Theme.mono; pixelSize: 16; letterSpacing: 2 }
                                    color: Theme.fg
                                    selectionColor: Theme.fg
                                    selectedTextColor: Theme.ink
                                    clip: true
                                    onAccepted: if (text) go.send()
                                    Lb { visible: !pw.text; anchors.verticalCenter: parent.verticalCenter; text: "enter password"; color: Theme.mute }
                                }
                                Rectangle {
                                    id: go
                                    function send() { root.ask.connectWithPsk(pw.text); pw.text = ""; root.ask = null; }
                                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    width: 44
                                    height: 44
                                    radius: 22
                                    color: pw.text ? Theme.fg : Theme.s3
                                    Icon { anchors.centerIn: parent; text: "\u{F0054}"; font.pixelSize: 19; color: pw.text ? Theme.ink : Theme.grey }
                                    TapHandler { onTapped: if (pw.text) go.send() }
                                }
                            }

                            // other networks
                            Column {
                                width: parent.width
                                spacing: 4
                                Lb { x: 4; text: "other networks" }
                                Flickable {
                                    width: parent.width
                                    height: Math.min(otherCol.height, 252)
                                    contentHeight: otherCol.height
                                    clip: true
                                    interactive: contentHeight > height
                                    Column {
                                        id: otherCol
                                        width: parent.width
                                        spacing: 4
                                        Repeater {
                                            model: root.otherNets
                                            NetRow { }
                                        }
                                        Lb { visible: root.otherNets.length === 0; x: 4; px: 11; color: Theme.mute; text: "scanning…" }
                                    }
                                }
                                // join a hidden network by name
                                Column {
                                    width: parent.width
                                    spacing: 8
                                    Item {
                                        width: parent.width
                                        height: 22
                                        Row {
                                            x: 4
                                            spacing: 8
                                            Lb { text: "join another network"; anchors.verticalCenter: parent.verticalCenter }
                                            Icon { text: root.joinOpen ? "\u{F0140}" : "\u{F0142}"; font.pixelSize: 13; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.joinOpen = !root.joinOpen }
                                    }
                                    Column {
                                        visible: root.joinOpen
                                        width: parent.width
                                        spacing: 8
                                        Field { id: joinName; label: "name"; hint: "network name (ssid)" }
                                        Field { id: joinPass; label: "password"; hint: "leave empty for an open one"; echo: TextInput.Password }
                                        ActLine {
                                            label: "join"
                                            sub: "for hidden networks — the name must be exact"
                                            onHit: {
                                                if (!joinName.text || !root.dev) return;
                                                if (joinPass.text) Quickshell.execDetached(["nmcli", "device", "wifi", "connect", joinName.text, "password", joinPass.text, "hidden", "yes"]);
                                                else Quickshell.execDetached(["nmcli", "device", "wifi", "connect", joinName.text, "hidden", "yes"]);
                                                root.joinOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // footer -- prefs, centred; the (i) for the info page sits at the
                        // panel's right border, centred on the same line
                        Item {
                            width: parent.width
                            height: 26
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Lb { text: "wi-fi settings"; anchors.verticalCenter: parent.verticalCenter }
                                Icon { text: "\u{F0142}"; font.pixelSize: 13; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { root.close(); root.settingsRequested(); } }
                            }
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                                width: 26
                                height: 26
                                radius: 13
                                color: "transparent"
                                border { width: 1; color: Theme.s3 }
                                Icon { anchors.centerIn: parent; text: "\u{F02FC}"; font.pixelSize: 14; color: Theme.grey }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.view = "info" }
                            }
                        }
                    }
                }

                // ---------- page 2: hotspot settings ----------
                Item {
                    width: view2.width
                    height: hsCol.height
                    opacity: root.view === "hotspot" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Column {
                        id: hsCol
                        width: parent.width
                        spacing: 16

                        BackRow { text: "personal hotspot" }

                        Column {
                            width: parent.width
                            spacing: 10
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
                            Item {
                                width: parent.width
                                height: 26
                                Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "show password" }
                                Switch {
                                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                    on: root.showPass
                                    onFlip: root.showPass = !root.showPass
                                }
                            }
                            Lb { x: 4; px: 10; color: Theme.mute; text: "a wpa2 network run by networkmanager · changes apply when the hotspot restarts" }
                            ActLine {
                                visible: root.hotspotOn
                                label: "restart the hotspot"
                                sub: "applies the name and password above"
                                onHit: { Quickshell.execDetached(["nmcli", "connection", "down", "Hotspot"]); hsRestart.restart(); hsPoll.restart(); root.view = "main"; }
                            }
                        }
                    }
                }

                // ---------- page 3: info ----------
                Item {
                    width: view2.width
                    height: infoCol.height
                    opacity: root.view === "info" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Column {
                        id: infoCol
                        width: parent.width
                        spacing: 16

                        BackRow { text: "wi-fi" }

                        Column {
                            width: parent.width
                            spacing: 8
                            InfoLine { k: "interface"; v: root.dev?.name || "—" }
                            InfoLine { k: "mac"; v: root.dev?.address || "—" }
                            InfoLine { k: "card"; v: root.drv.product || "—" }
                            InfoLine { k: "driver"; v: root.drv.driver || "—" }
                            InfoLine { k: "ip address"; v: root.drv.ip || "—" }
                            InfoLine { k: "network"; v: root.connNet?.name || "—" }
                            InfoLine { k: "state"; v: Networking.wifiEnabled ? "on" : "off" }
                        }

                        Column {
                            width: parent.width
                            spacing: 10
                            ActLine {
                                label: "restart wi-fi"
                                sub: "radio off and on — drops the current network, then rejoins"
                                onHit: { Networking.wifiEnabled = false; wifiCycle.restart(); }
                            }
                            ActLine {
                                label: "restart networkmanager"
                                sub: "pkexec — asks for your password · drops every connection"
                                onHit: { Quickshell.execDetached(["pkexec", "systemctl", "restart", "NetworkManager"]); root.close(); }
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
    }

    // one network row, the picker's shape
    component NetRow: Rectangle {
        id: nrow
        required property var modelData
        readonly property var o: modelData
        readonly property bool on: o.connected
        readonly property bool busy: o.stateChanging
        width: root.colW
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
            Icon {
                anchors.centerIn: parent
                text: root.bars(nrow.o)
                font.pixelSize: 19
                color: nrow.on ? Theme.ink : Theme.fg
                SequentialAnimation on opacity {
                    running: nrow.busy
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.25; duration: 450 }
                    NumberAnimation { to: 1; duration: 450 }
                }
            }
        }
        Column {
            anchors { left: nic.right; leftMargin: 14; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: nrow.o.name; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
            Lb {
                px: 10
                text: `${nrow.on ? "connected" : nrow.busy ? "connecting" : nrow.o.known ? "saved" : WifiSecurityType.toString(nrow.o.security).toLowerCase()} · ${Math.round(nrow.o.signalStrength * 100)}%`
            }
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.tapNet(o) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (o.known) o.forget() }
        Connections {
            target: nrow.o
            ignoreUnknownSignals: true
            function onConnectionFailed(r) {
                if (r === ConnectionFailReason.NoSecrets) root.ask = nrow.o;
                else root.err = ConnectionFailReason.toString(r);
            }
        }
    }

    // the small sliding switch, the sound menu's shape
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

    component Field: Rectangle {
        id: fld
        property string label: ""
        property string hint: ""
        property alias text: fin.text
        property int echo: TextInput.Normal
        signal edited
        width: root.colW
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

    component BackRow: Item {
        id: brow
        property string text: ""
        width: root.colW
        height: 24
        Row {
            spacing: 8
            Icon { text: "\u{F0141}"; font.pixelSize: 15; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
            Lb { text: brow.text; anchors.verticalCenter: parent.verticalCenter }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.view = "main" }
    }

    component InfoLine: Item {
        property string k: ""
        property string v: ""
        width: root.colW
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
        width: root.colW
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
}
