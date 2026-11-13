import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs
import qs.components
import qs.services
import qs.settings

// battery: UPower's display device for charge and time, /sys for health, the
// power controls -- the modes (Rules), the auto saver, and the shell's own
// performance pick -- and the idle scale at the bottom.
Item {
    id: pg

    property bool active: false
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBat: bat ? !!bat.isLaptopBattery : false
    property real health: -1
    property string cycles: ""

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    function stateText() {
        if (!bat) return "";
        switch (bat.state) {
        case UPowerDeviceState.Charging: return "charging";
        case UPowerDeviceState.Discharging: return "on battery";
        case UPowerDeviceState.FullyCharged: return "fully charged";
        case UPowerDeviceState.PendingCharge: return "waiting to charge";
        case UPowerDeviceState.PendingDischarge: return "waiting to discharge";
        case UPowerDeviceState.Empty: return "empty";
        default: return "";
        }
    }
    function hm(sec) {
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
        return h ? `${h} h ${m} min` : `${m} min`;
    }
    readonly property bool showTime: hasBat && ((bat.state === UPowerDeviceState.Charging && bat.timeToFull > 0)
        || (bat.state === UPowerDeviceState.Discharging && bat.timeToEmpty > 0))

    onActiveChanged: {
        if (!active) return;
        Rules.checkPower();
        if (!healthProc.running) healthProc.running = true;
    }
    Component.onCompleted: { if (!healthProc.running) healthProc.running = true; }

    Process {
        id: healthProc
        command: ["sh", "-c", "b=/sys/class/power_supply/BAT0; for f in charge_full charge_full_design energy_full energy_full_design cycle_count; do echo \"$f=$(cat $b/$f 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const ln of text.split("\n")) {
                    const i = ln.indexOf("=");
                    if (i > 0) m[ln.slice(0, i)] = parseFloat(ln.slice(i + 1)) || 0;
                }
                const full = m.charge_full || m.energy_full || 0;
                const design = m.charge_full_design || m.energy_full_design || 0;
                pg.health = full > 0 && design > 0 ? Math.round(full / design * 100) : -1;
                const raw = text.match(/cycle_count=(\d+)/);
                pg.cycles = raw ? raw[1] : "";
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
                visible: pg.hasBat
                width: parent.width
                spacing: 10
                SetHead { text: "battery" }
                SetCard {
                    Item {
                        width: parent ? parent.width : 0
                        height: 104
                        Ring {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 84
                            height: 84
                            n: 48
                            dot: 5
                            f: pg.bat ? pg.bat.percentage : 0
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 112; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Num { text: pg.bat ? Math.round(pg.bat.percentage * 100) + "%" : ""; font.pixelSize: 42 }
                            Lb { text: pg.stateText(); px: 11.5 }
                        }
                    }
                    SetRow {
                        visible: pg.showTime
                        label: pg.bat && pg.bat.state === UPowerDeviceState.Charging ? "time to full" : "time to empty"
                        value: pg.bat ? pg.hm(pg.bat.state === UPowerDeviceState.Charging ? pg.bat.timeToFull : pg.bat.timeToEmpty) : ""
                        divider: false
                    }
                }
            }

            Column {
                visible: pg.health >= 0 || pg.cycles !== ""
                width: parent.width
                spacing: 10
                SetHead { text: "health" }
                SetCard {
                    SetRow { label: "maximum capacity"; value: pg.health + " %"; visible: pg.health >= 0; divider: pg.cycles !== "" }
                    SetRow { label: "charge cycles"; value: pg.cycles; visible: pg.cycles !== ""; divider: false }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "power mode" }
                SetCard {
                    Repeater {
                        model: Rules.modes.slice(0, Rules.modeCount)
                        SetRow {
                            required property var modelData
                            required property int index
                            label: modelData.name
                            value: modelData.what
                            clickable: true
                            divider: index < Rules.modeCount - 1
                            onHit: { Sounds.play("tick"); Rules.setMode(index); }
                            Rectangle {
                                visible: Rules.mode === index
                                width: 9
                                height: 9
                                radius: 4.5
                                color: Theme.accent
                            }
                        }
                    }
                    Lb {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 12
                        text: Rules.store.ultra ? `battery saver · ${Rules.rates[0]} hz, no motion, no blur, no shadows — your settings come back when you leave` : "cpu profile only · hz, motion and looks stay yours"
                    }
                    Lb {
                        visible: Rules.powerOk && !PowerProfiles.hasPerformanceProfile
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 8
                        text: "no performance profile on this machine"
                    }
                    Lb {
                        visible: !Rules.powerOk
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 8
                        px: 10
                        color: Theme.red
                        text: "power-profiles-daemon isn't answering — the cpu profile can't change (battery saver's screen and looks still apply). fix: sudo systemctl enable --now power-profiles-daemon"
                    }
                }
            }

            Column {
                visible: pg.hasBat
                width: parent.width
                spacing: 10
                SetHead { text: "automatic" }
                SetCard {
                    SetToggle {
                        label: "auto saver on battery"
                        on: Rules.store.powerAuto
                        divider: false
                        onFlip: want => Rules.store.powerAuto = want
                    }
                    Lb {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 10
                        px: 10.5
                        text: "unplug — battery saver takes over by itself · plug in — the mode you had comes back · a mode picked by hand on battery cancels the return"
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "shell performance" }
                SetCard {
                    SetPick {
                        label: "shell"
                        opts: ["full", "trim", "lite"]
                        cur: Theme.state.perf
                        divider: false
                        onPicked: i => Theme.state.perf = i
                    }
                    Lb {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 10
                        px: 10.5
                        text: Theme.state.perf === 0 ? "full · stats every 2 s · recording/airplane check every 3 s · monitor read-back every 5 s · visualisers and ambient motion as set"
                            : Theme.state.perf === 1 ? "trim · stats every 4 s · check every 6 s · read-back every 10 s · the orb breathes at half rate"
                            : "lite · stats every 8 s · check every 12 s · read-back every 20 s · visualisers off, the cat and the spinning covers stand still, the orb frozen"
                    }
                }
            }

            // idle: minutes without input, on one scale. Dots dim on each
            // event: awake -> locked -> screen off -> asleep. Past 60 — never
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "idle" }
                SetCard {
                    Item {
                        id: idleLine
                        width: parent.width
                        height: 268
                        readonly property var at: [lk.v, dpms.v, zz.v]

                        Repeater {
                            model: 61
                            Rectangle {
                                required property int index
                                readonly property int lvl: idleLine.at.filter(m => m && m <= index).length
                                x: index * 12 - 3
                                y: 224
                                width: 7
                                height: 7
                                radius: 3.5
                                color: [Theme.fg, Theme.grey, Theme.mute, Theme.s3][lvl]
                            }
                        }
                        // never -- an empty ring beyond the scale
                        Rectangle { x: 62 * 12 - 6; y: 221; width: 13; height: 13; radius: 6.5; color: "transparent"; border { width: 1; color: Theme.mute } }
                        Repeater {
                            model: [0, 15, 30, 45, 60]
                            Lb { required property int modelData; x: modelData * 12 - width / 2; y: 246; text: modelData; px: 10 }
                        }
                        Lb { x: 62 * 12 - width / 2; y: 246; text: "never"; px: 10 }

                        Mark { id: lk; row: 0; label: "lock"; value: Rules.store.lockAfter; onMoved: v => { Rules.store.lockAfter = v; Rules.idle(); } }
                        Mark { id: dpms; row: 1; label: "screen off"; value: Rules.store.dpmsAfter; onMoved: v => { Rules.store.dpmsAfter = v; Rules.idle(); } }
                        Mark { id: zz; row: 2; label: Rules.hibernateOn ? "sleep · hibernate" : "sleep"; value: Rules.store.sleepAfter; onMoved: v => { Rules.store.sleepAfter = v; Rules.idle(); } }
                    }
                    Row {
                        spacing: 26
                        Repeater {
                            model: [["awake", Theme.fg], ["locked", Theme.grey], ["dark", Theme.mute], ["asleep", Theme.s3]]
                            Row {
                                required property var modelData
                                spacing: 10
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: parent.modelData[1] }
                                Lb { text: parent.modelData[0]; px: 10 }
                            }
                        }
                    }
                    SetPick {
                        label: "sleep into"
                        visible: Rules.canHibernate
                        opts: ["suspend", "hibernate"]
                        cur: Rules.store.hibernate ? 1 : 0
                        onPicked: i => { Rules.store.hibernate = i === 1; Rules.idle(); }
                    }
                    SetToggle {
                        label: "caffeine"
                        on: Sys.caffeine
                        divider: false
                        onFlip: want => Sys.caffeine = want
                    }
                }
            }
        }
    }

    // an idle mark: leg to the scale, Doto number and name. Drag along the
    // scale, left/right -- by a minute; past 60 -- never (0). While dragging
    // -- its own v; rules.json and hypridle update on release or after
    // 400 ms of silence
    component Mark: Item {
        id: mk
        property int row
        property string label
        property int value
        property int v: value
        signal moved(int v)
        function put(m) {
            m = m > 60.5 ? 0 : Math.max(1, Math.round(m));
            if (m === v) return;
            v = m;
            wait.restart();
        }
        onValueChanged: if (!ma.pressed && !wait.running) v = value
        Timer { id: wait; interval: 400; onTriggered: if (!ma.pressed && mk.v !== mk.value) mk.moved(mk.v) }

        x: (v || 62) * 12
        y: row * 76
        width: 140
        height: 224 - y
        activeFocusOnTab: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Left) put(v ? v - 1 : 60);
            else if (e.key === Qt.Key_Right) put(v ? v + 1 : 61);
            else return;
            e.accepted = true;
        }
        Behavior on x { NumberAnimation { duration: 120 } }

        Rectangle { width: 1; height: parent.height; color: mk.activeFocus || ma.pressed ? Theme.fg : Theme.mute }
        Column {
            x: 12
            Num { text: mk.v || "—"; font.pixelSize: 40 }
            Lb { topPadding: 6; text: mk.label; px: 10; color: mk.activeFocus ? Theme.fg : Theme.grey }
        }
        MouseArea {
            id: ma
            width: parent.width
            height: 76
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            onPressed: mk.forceActiveFocus()
            onPositionChanged: e => mk.put(mapToItem(idleLine, e.x, 0).x / 12)
            onReleased: {
                wait.stop();
                if (mk.v !== mk.value) mk.moved(mk.v);
            }
        }
    }
}
