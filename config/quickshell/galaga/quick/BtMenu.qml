import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// the bluetooth menu: the bar's bluetooth icon opens this dropdown instead
// of all of quick settings -- the sound menu's frame and manners, bluetooth
// inside. A master switch, discoverable as its own switch, then two lists:
// paired devices (tap connects or disconnects, right-click forgets -- the
// picker's manners in quick settings) and new devices found while the menu
// is open (tap pairs). Battery is the number bluez itself reports
// (BluetoothDevice.battery), shown only when the device reports one.
// The footer opens the bluetooth settings page (prefs/DeviceSettings --
// its own window, not part of prefs, reached only from here); the (i)
// the info page: adapter name, address and bluez version (bluetoothctl --
// quickshell does not expose the address), and the heavy actions -- reset
// the adapter (a power cycle), restart the service (pkexec), remove every
// device (two taps, armed).
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
            armWipe = false;
            btInfoProc.running = true;
        }
    }

    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property real colW: 336 // the panel's content width (380 - 44), the rows' measure
    property string view: "main" // "main" | "info"
    property bool armWipe: false
    property string adapterAddress: ""
    property string bluezVer: ""

    // scan while the menu is up, stop when it closes (picker.qml's binding)
    Binding { when: root.open && (root.adapter?.enabled ?? false); target: root.adapter; property: "discovering"; value: true }

    readonly property var pairedDevs: !adapter ? [] : Bluetooth.devices.values.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || ""))
    readonly property var newDevs: !adapter ? [] : Bluetooth.devices.values.filter(d => !d.paired && !d.bonded && d.deviceName)
        .sort((a, b) => (a.name || "").localeCompare(b.name || ""))

    function btIcon(i) {
        return /audio|head/.test(i ?? "") ? "\u{F02CB}" : /mouse/.test(i ?? "") ? "\u{F037D}" : /keyboard/.test(i ?? "") ? "\u{F030C}" : /phone/.test(i ?? "") ? "\u{F03F2}" : "\u{F00AF}";
    }
    function tapDev(o) {
        if (o.pairing) return o.cancelPair();
        // a new device goes through connect(), not pair(): bluez bonds as part of
        // connecting (the bluetoothctl sequence -- connect, bonded, paired,
        // profiles), while Pair() alone raises a bare ACL link for the bonding
        // and drops it seconds later when no profile ever connects
        if (!o.paired && !o.bonded) { o.trusted = true; return o.connect(); }
        return o.connected ? o.disconnect() : o.connect();
    }

    // the adapter's address and the bluez version live outside quickshell's
    // types; bluetoothctl prints both
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

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-bt"

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: panel
        readonly property bool barTop: Theme.state.barAt === "top"
        width: 380
        height: (root.view === "main" ? mainCol.height : infoCol.height) + 44
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
        Keys.onEscapePressed: { if (root.view !== "main") root.view = "main"; else root.close(); }
        MouseArea { anchors.fill: parent } // clicking the panel does not close it

        Item {
            id: view2
            x: 22
            y: 22
            width: parent.width - 44
            height: parent.height - 44
            clip: true

            Row {
                x: root.view === "main" ? 0 : -view2.width
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
                            Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "bluetooth" }
                            Switch {
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                on: root.adapter?.enabled ?? false
                                onFlip: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                            }
                        }

                        Lb { visible: !root.adapter; x: 4; px: 11; color: Theme.mute; text: "no bluetooth adapter on this machine" }
                        Lb { visible: !!root.adapter && !root.adapter.enabled; x: 4; px: 11; color: Theme.mute; text: "bluetooth is off" }

                        Column {
                            visible: !!root.adapter && root.adapter.enabled
                            width: parent.width
                            spacing: 16

                            Column {
                                width: parent.width
                                spacing: 6
                                Item {
                                    width: parent.width
                                    height: 26
                                    Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "discoverable" }
                                    Switch {
                                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                        on: root.adapter?.discoverable ?? false
                                        onFlip: if (root.adapter) root.adapter.discoverable = !root.adapter.discoverable
                                    }
                                }
                                Lb { x: 4; px: 10; color: Theme.mute; text: "while on, other devices can find this pc to pair with it" }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Item {
                                    width: parent.width
                                    height: 20
                                    Lb { x: 4; text: "devices" }
                                    Lb { anchors.right: parent.right; rightPadding: 4; visible: root.pairedDevs.length > 0; px: 10; color: Theme.mute; text: "right-click forgets" }
                                }
                                Repeater {
                                    model: root.pairedDevs
                                    DevRow { }
                                }
                                Lb { visible: root.pairedDevs.length === 0; x: 4; px: 11; color: Theme.mute; text: "no paired devices" }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Item {
                                    width: parent.width
                                    height: 20
                                    Lb { x: 4; text: "new devices" }
                                    Lb { anchors.right: parent.right; rightPadding: 4; px: 10; color: Theme.mute; text: root.adapter?.discovering ? "scanning…" : "" }
                                }
                                Repeater {
                                    model: root.newDevs
                                    DevRow { }
                                }
                                Lb { visible: root.newDevs.length === 0; x: 4; px: 11; color: Theme.mute; text: root.adapter?.discovering ? "looking for devices nearby…" : "nothing nearby" }
                            }
                        }

                        // footer -- a real manager if there is one, centred; the (i) for the
                        // info page sits at the panel's right border, centred on the same line
                        Item {
                            width: parent.width
                            height: 26
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Lb { text: "bluetooth settings"; anchors.verticalCenter: parent.verticalCenter }
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

                // ---------- page 2: info ----------
                Item {
                    width: view2.width
                    height: infoCol.height
                    opacity: root.view === "info" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Column {
                        id: infoCol
                        width: parent.width
                        spacing: 16

                        Item {
                            width: parent.width
                            height: 24
                            Row {
                                spacing: 8
                                Icon { text: "\u{F0141}"; font.pixelSize: 15; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                                Lb { text: "bluetooth"; anchors.verticalCenter: parent.verticalCenter }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.view = "main" }
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            InfoLine { k: "name"; v: root.adapter?.name || "—" }
                            InfoLine { k: "address"; v: root.adapterAddress || "—" }
                            InfoLine { k: "adapter"; v: root.adapter?.adapterId || "—" }
                            InfoLine { k: "bluez"; v: root.bluezVer ? `version ${root.bluezVer}` : "—" }
                            InfoLine { k: "discoverable"; v: root.adapter?.discoverable ? "on" : "off" }
                            InfoLine { k: "state"; v: root.adapter?.enabled ? "on" : "off" }
                        }

                        Column {
                            width: parent.width
                            spacing: 10
                            ActLine {
                                label: "reset the adapter"
                                sub: "power-cycle — connected devices drop, then reconnect"
                                onHit: if (root.adapter) { root.adapter.enabled = false; btCycle.restart(); }
                            }
                            ActLine {
                                label: "restart the bluetooth service"
                                sub: "pkexec — asks for your password"
                                onHit: { Quickshell.execDetached(["pkexec", "systemctl", "restart", "bluetooth"]); root.close(); }
                            }
                            ActLine {
                                label: root.armWipe ? "tap again to remove all devices" : "remove all devices"
                                sub: "unpairs everything — each device must be paired again"
                                danger: root.armWipe
                                onHit: {
                                    if (!root.armWipe) { root.armWipe = true; return; }
                                    for (const d of root.pairedDevs) d.forget();
                                    root.armWipe = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // one device row, the picker's shape: a disc with the kind glyph, the
    // name, what it is doing, and the charge bluez reports when it does
    component DevRow: Rectangle {
        id: drow
        required property var modelData
        readonly property var o: modelData
        readonly property bool on: o.connected
        readonly property bool busy: o.pairing || o.state === BluetoothDeviceState.Connecting || o.state === BluetoothDeviceState.Disconnecting
        width: root.colW
        height: 56
        radius: Theme.corner(28)
        color: hov.hovered ? Theme.s3 : "transparent"

        Rectangle {
            id: dic
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: drow.on ? Theme.fg : Theme.s3
            Icon {
                anchors.centerIn: parent
                text: root.btIcon(drow.o.icon)
                font.pixelSize: 19
                color: drow.on ? Theme.ink : Theme.fg
                SequentialAnimation on opacity {
                    running: drow.busy
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.25; duration: 450 }
                    NumberAnimation { to: 1; duration: 450 }
                }
            }
        }
        Column {
            anchors { left: dic.right; leftMargin: 14; right: batL.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: drow.o.name || drow.o.deviceName || drow.o.address; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
            Lb {
                px: 10
                text: drow.o.pairing ? "pairing" : drow.o.state === BluetoothDeviceState.Connecting ? "connecting" : drow.o.state === BluetoothDeviceState.Disconnecting ? "disconnecting"
                    : drow.on ? "connected" : drow.o.paired || drow.o.bonded ? "paired" : "tap to pair"
            }
        }
        Lb {
            id: batL
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            visible: o.batteryAvailable
            text: `${Math.round(o.battery * 100)}%`
            color: Theme.fg
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.tapDev(o) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (o.paired || o.bonded) o.forget() }
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
