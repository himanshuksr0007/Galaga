import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs
import qs.components
import qs.services
import qs.settings

// battery: UPower's display device for charge and time, /sys for health, and the
// power controls that used to live on Prefs' POWER page -- the modes (Rules),
// the auto saver, and the shell's own performance pick. One home: Prefs no
// longer carries them.
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
        }
    }
}
