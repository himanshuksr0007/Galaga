import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// general: the computer's name, and date & time. Changes go through timedatectl /
// hostnamectl behind pkexec (the DeviceSettings pattern); every value shown is read
// back from the tool afterwards, never assumed.
Item {
    id: pg

    property bool active: false
    property string host: ""
    property bool ntp: false
    property bool synced: false
    property string tz: ""
    property var zones: []
    property string zoneQuery: ""
    property bool editing: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    readonly property var shownZones: {
        const q = zoneQuery.trim().toLowerCase();
        if (!q) return zones;
        return zones.filter(z => z.toLowerCase().includes(q));
    }

    function refresh() {
        if (!hostProc.running) hostProc.running = true;
        if (!tdProc.running) tdProc.running = true;
        if (!zones.length && !zoneProc.running) zoneProc.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: pg.host = text.trim() }
    }
    Process {
        id: tdProc
        command: ["timedatectl", "show", "-p", "NTP", "-p", "NTPSynchronized", "-p", "Timezone"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const ln of text.split("\n")) {
                    const i = ln.indexOf("=");
                    if (i < 0) continue;
                    const k = ln.slice(0, i), v = ln.slice(i + 1).trim();
                    if (k === "NTP") pg.ntp = v === "yes";
                    else if (k === "NTPSynchronized") pg.synced = v === "yes";
                    else if (k === "Timezone") pg.tz = v;
                }
            }
        }
    }
    Process {
        id: zoneProc
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: pg.zones = text.split("\n").map(s => s.trim()).filter(s => s) }
    }
    Timer { id: reread; interval: 1000; onTriggered: pg.refresh() }

    SystemClock { id: clock; precision: SystemClock.Seconds }

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
                SetHead { text: "computer name" }
                SetCard {
                    SetRow {
                        label: "hostname"
                        value: pg.host
                        divider: pg.editing
                        SetButton {
                            label: pg.editing ? "cancel" : "edit"
                            onHit: { pg.editing = !pg.editing; if (pg.editing) { nameIn.text = pg.host; nameIn.forceActiveFocus(); } }
                        }
                    }
                    Item {
                        visible: pg.editing
                        width: parent ? parent.width : 0
                        height: pg.editing ? 64 : 0
                        Row {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 12
                            Rectangle {
                                width: parent.width - 108
                                height: 44
                                radius: Theme.corner(22)
                                color: Theme.s2
                                border { width: nameIn.activeFocus ? 1 : 0; color: Theme.fg }
                                TextInput {
                                    id: nameIn
                                    anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    font { family: Theme.ui; pixelSize: 15 }
                                    color: Theme.fg
                                    selectionColor: Theme.s3
                                    clip: true
                                    onAccepted: setBtn.hit()
                                }
                            }
                            SetButton {
                                id: setBtn
                                anchors.verticalCenter: parent.verticalCenter
                                label: "set"
                                onHit: {
                                    const n = nameIn.text.trim();
                                    if (!n) return;
                                    Quickshell.execDetached(["pkexec", "hostnamectl", "set-hostname", n]);
                                    pg.editing = false;
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
                SetHead { text: "date & time" }
                SetCard {
                    Item {
                        width: parent ? parent.width : 0
                        height: 76
                        Num {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: Theme.state.clock24 ? Qt.formatTime(clock.date, "hh:mm:ss") : Qt.formatTime(clock.date, "h:mm:ss ap")
                            font.pixelSize: 40
                        }
                        Lb {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: Qt.formatDate(clock.date, "dddd · d MMMM yyyy")
                            px: 12
                        }
                    }
                    SetToggle {
                        label: "set time automatically"
                        sub: pg.synced ? "network time · synchronised" : "network time · not synchronised"
                        on: pg.ntp
                        onFlip: want => {
                            Quickshell.execDetached(["pkexec", "timedatectl", "set-ntp", want ? "true" : "false"]);
                            reread.restart();
                        }
                    }
                    SetRow { label: "time zone"; value: pg.tz; divider: false }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "time zones" }
                SetCard {
                    pad: 14
                    Rectangle {
                        width: parent ? parent.width : 0
                        height: 40
                        radius: Theme.corner(20)
                        color: Theme.s2
                        Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; font.pixelSize: 17; color: Theme.mute }
                        TextInput {
                            anchors { left: parent.left; leftMargin: 42; right: parent.right; rightMargin: 14; top: parent.top; bottom: parent.bottom }
                            verticalAlignment: TextInput.AlignVCenter
                            font { family: Theme.ui; pixelSize: 14 }
                            color: Theme.fg
                            selectionColor: Theme.s3
                            clip: true
                            onTextChanged: pg.zoneQuery = text
                            Text { visible: !parent.text; text: "search time zones"; font: parent.font; color: Theme.mute }
                        }
                    }
                    ListView {
                        width: parent ? parent.width : 0
                        height: 252
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: pg.shownZones
                        delegate: Item {
                            required property var modelData
                            readonly property bool cur: modelData === pg.tz
                            width: pg.width - 28
                            height: 38
                            Rectangle {
                                anchors { fill: parent; leftMargin: -6; rightMargin: -6 }
                                radius: Theme.corner(10)
                                color: Theme.s2
                                opacity: zhov.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }
                            Rectangle {
                                visible: cur
                                width: 8; height: 8; radius: 4
                                color: Theme.accent
                                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            }
                            Text {
                                x: 24
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                font { family: Theme.ui; pixelSize: 14 }
                                color: cur ? Theme.fg : Theme.grey
                            }
                            HoverHandler { id: zhov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (modelData === pg.tz) return;
                                    Sounds.play("tick");
                                    Quickshell.execDetached(["pkexec", "timedatectl", "set-timezone", modelData]);
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
