import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// the settings app: a real window in the shell's clothes. Self-drawn mac discs in the
// header (the window is org.quickshell, so hyprbars leaves it alone -- rules.lua); the
// discs act on this window, the focused one, through the same hyprctl dispatchers the
// title bars use. Sidebar + pages; every page lives in its own file beside this one.
FloatingWindow {
    id: win

    title: "Settings"
    width: 1180
    height: 780
    color: Theme.bg
    visible: false

    property string page: "about"
    property string query: ""
    property string host: ""
    property real t: visible ? 1 : 0
    signal studioRequested
    signal vpnRequested

    Behavior on t { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }

    readonly property var heads: ({
        about: ["ABOUT", "this machine · hardware and system"],
        general: ["GENERAL", "name · date and time"],
        sound: ["SOUND", "output · volume · per-device eq"],
        notifications: ["NOTIFICATIONS", "essential only · who gets through"],
        lock: ["LOCK", "the face they meet first"],
        wifi: ["WI-FI", "networks · hotspot · saved and nearby"],
        bt: ["BLUETOOTH", "paired and nearby devices · adapter"],
        network: ["NETWORK", "devices and saved connections"],
        vpn: ["VPN", "clash verge and networkmanager tunnels"],
        battery: ["BATTERY", "charge · power modes · shell performance"],
        mouse: ["MOUSE & TOUCHPAD", "pointer and pad · applied live by the shell"]
    })

    function open(p) {
        if (p && heads[p]) page = p;
        visible = true;
        Sounds.play("pop");
    }
    function close() {
        visible = false;
        Sounds.play("pop");
    }
    function toggle() { visible ? close() : open(); }
    function select(p) {
        if (page === p) return;
        page = p;
        Sounds.play("tick");
    }

    Process {
        running: true
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: win.host = text.trim() }
    }

    component Disc: Rectangle {
        property string glyph: ""
        property string glyphColor: "#F2F2F2"
        property bool ring: false
        signal hit
        width: 30
        height: 30
        radius: 15
        border { width: ring ? 1 : 0; color: Theme.s3 }
        Icon {
            anchors.centerIn: parent
            text: parent.glyph
            font.pixelSize: 14
            color: parent.glyphColor
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.hit() }
    }

    component NavRow: Item {
        property string pid: ""
        property string icon: ""
        property string label: ""
        property string keys: ""
        readonly property bool sel: win.page === pid
        readonly property bool match: !win.query || (label + " " + keys).toLowerCase().includes(win.query)
        visible: match
        width: parent ? parent.width : 0
        height: 40
        Rectangle {
            anchors.fill: parent
            radius: Theme.corner(12)
            color: sel ? Theme.fg : Theme.s2
            opacity: sel ? 1 : (nhov.hovered ? 0.7 : 0)
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Icon {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: icon
            font.pixelSize: 19
            color: sel ? Theme.ink : Theme.grey
        }
        Text {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            text: label
            font { family: Theme.ui; pixelSize: 14 }
            color: sel ? Theme.ink : Theme.fg
        }
        HoverHandler { id: nhov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: win.select(pid) }
    }

    Item {
        anchors.fill: parent
        opacity: win.t
        focus: true
        Keys.onEscapePressed: win.close()

        // ---- header: discs + the word ----
        Item {
            id: hdr
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 62
            Row {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Disc {
                    color: "#D71921"
                    glyph: "\u{F0156}"
                    onHit: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close()"])
                }
                Disc {
                    color: "#F2F2F2"
                    glyph: "\u{F0374}"
                    glyphColor: "#000000"
                    ring: true
                    onHit: Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/minimise.sh"])
                }
                Disc {
                    color: "#000000"
                    glyph: "\u{F0293}"
                    ring: true
                    onHit: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })"])
                }
            }
            Num {
                anchors.centerIn: parent
                text: "SETTINGS"
                font.pixelSize: 26
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.s2
            }
        }

        // ---- sidebar ----
        Rectangle {
            id: side
            anchors { left: parent.left; top: hdr.bottom; bottom: parent.bottom }
            width: 300
            color: Theme.s1
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 1
                color: Theme.s2
            }

            Rectangle {
                id: search
                x: 16
                y: 16
                width: parent.width - 32
                height: 38
                radius: Theme.corner(19)
                color: Theme.s2
                border { width: searchIn.activeFocus ? 1 : 0; color: Theme.fg }
                Icon { x: 13; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; font.pixelSize: 17; color: Theme.mute }
                TextInput {
                    id: searchIn
                    anchors { left: parent.left; leftMargin: 40; right: parent.right; rightMargin: 12; top: parent.top; bottom: parent.bottom }
                    verticalAlignment: TextInput.AlignVCenter
                    font { family: Theme.ui; pixelSize: 14 }
                    color: Theme.fg
                    selectionColor: Theme.s3
                    clip: true
                    onTextChanged: win.query = text.trim().toLowerCase()
                    Text {
                        visible: !searchIn.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        font: searchIn.font
                        color: Theme.mute
                    }
                }
            }

            Row {
                id: ucard
                x: 16
                y: 70
                spacing: 13
                Item {
                    width: 46
                    height: 46
                    Ring { anchors.fill: parent; n: 26; dot: 3.5; f: 1; visible: !ava.visible }
                    Image {
                        id: ava
                        anchors.fill: parent
                        source: Theme.state.avatar ? Theme.url(Theme.state.avatar) : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        layer.enabled: visible
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: maskItem }
                    }
                    Item {
                        id: maskItem
                        width: 46
                        height: 46
                        layer.enabled: true
                        visible: false
                        Rectangle { anchors.fill: parent; radius: 23; color: "black" }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: Theme.state.name || Quickshell.env("USER") || ""
                        font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold }
                        color: Theme.fg
                    }
                    Lb { text: win.host; px: 10.5; color: Theme.mute }
                }
            }

            Flickable {
                anchors { left: parent.left; right: parent.right; top: ucard.bottom; topMargin: 18; bottom: studio.top }
                clip: true
                contentWidth: width
                contentHeight: navCol.height
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: navCol
                    x: 12
                    width: parent.width - 24
                    spacing: 4
                    Lb { x: 10; visible: !win.query; text: "system"; px: 10.5; color: Theme.mute; bottomPadding: 4 }
                    NavRow { pid: "about"; icon: "\u{F02FC}"; label: "About"; keys: "system machine info version hardware" }
                    NavRow { pid: "general"; icon: "\u{F0493}"; label: "General"; keys: "hostname date time timezone clock name" }
                    NavRow { pid: "sound"; icon: "\u{F057E}"; label: "Sound"; keys: "sound audio volume output speaker eq equalizer mute" }
                    NavRow { pid: "notifications"; icon: "\u{F009A}"; label: "Notifications"; keys: "notifications essential dnd alerts apps mute island" }
                    Lb { x: 10; visible: !win.query; text: "network"; px: 10.5; color: Theme.mute; topPadding: 14; bottomPadding: 4 }
                    NavRow { pid: "wifi"; icon: "\u{F05A9}"; label: "Wi-Fi"; keys: "wifi wi-fi wireless networks hotspot internet" }
                    NavRow { pid: "bt"; icon: "\u{F00AF}"; label: "Bluetooth"; keys: "bluetooth devices pairing buds headphones" }
                    NavRow { pid: "network"; icon: "\u{F059F}"; label: "Network"; keys: "ethernet wifi connections ip address devices" }
                    NavRow { pid: "vpn"; icon: "\u{F0483}"; label: "VPN"; keys: "vpn wireguard tunnel clash verge proxy portal" }
                    Lb { x: 10; visible: !win.query; text: "appearance"; px: 10.5; color: Theme.mute; topPadding: 14; bottomPadding: 4 }
                    NavRow { pid: "lock"; icon: "\u{F033E}"; label: "Lock"; keys: "lock screen photo wallpaper clock face greeter password" }
                    Lb { x: 10; visible: !win.query; text: "power"; px: 10.5; color: Theme.mute; topPadding: 14; bottomPadding: 4 }
                    NavRow { pid: "battery"; icon: "\u{F0079}"; label: "Battery"; keys: "battery power saver mode performance health charge" }
                    Lb { x: 10; visible: !win.query; text: "devices"; px: 10.5; color: Theme.mute; topPadding: 14; bottomPadding: 4 }
                    NavRow { pid: "mouse"; icon: "\u{F037D}"; label: "Mouse & Touchpad"; keys: "mouse touchpad trackpad pointer scroll tap accel speed" }
                }
            }

            Item {
                id: studio
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 58
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1
                    color: Theme.s2
                }
                Item {
                    x: 12
                    y: 9
                    width: parent.width - 24
                    height: 40
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.corner(12)
                        color: Theme.s2
                        opacity: shov.hovered ? 0.7 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "\u{F030C}"; font.pixelSize: 19; color: Theme.grey }
                    Text {
                        x: 44
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Galaga Studio"
                        font { family: Theme.ui; pixelSize: 14 }
                        color: Theme.fg
                    }
                    Icon { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "\u{F0142}"; font.pixelSize: 17; color: Theme.mute }
                    HoverHandler { id: shov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            win.close();
                            win.studioRequested();
                        }
                    }
                }
            }
        }

        // ---- content ----
        Item {
            anchors { left: side.right; right: parent.right; top: hdr.bottom; bottom: parent.bottom }
            Item {
                id: stage
                anchors { fill: parent; leftMargin: 30; rightMargin: 30; topMargin: 24; bottomMargin: 20 }
                Num {
                    id: ptitle
                    text: win.heads[win.page][0]
                    font.pixelSize: 36
                }
                Lb {
                    anchors { left: ptitle.left; top: ptitle.bottom; topMargin: 6 }
                    text: win.heads[win.page][1]
                    px: 11.5
                }
                Item {
                    anchors { left: parent.left; right: parent.right; top: ptitle.bottom; topMargin: 52; bottom: parent.bottom }
                    AboutPage { anchors.fill: parent; active: win.page === "about" }
                    GeneralPage { anchors.fill: parent; active: win.page === "general" }
                    SoundPage { anchors.fill: parent; active: win.visible && win.page === "sound" }
                    WifiPage { anchors.fill: parent; active: win.visible && win.page === "wifi" }
                    BtPage { anchors.fill: parent; active: win.visible && win.page === "bt" }
                    NetworkPage { anchors.fill: parent; active: win.page === "network" }
                    VpnPage { anchors.fill: parent; active: win.page === "vpn"; onPanelRequested: win.vpnRequested() }
                    BatteryPage { anchors.fill: parent; active: win.page === "battery" }
                    MousePage { anchors.fill: parent; active: win.page === "mouse" }
                    NotificationsPage { anchors.fill: parent; active: win.page === "notifications" }
                    LockPage { anchors.fill: parent; active: win.page === "lock" }
                }
            }
        }
    }
}
