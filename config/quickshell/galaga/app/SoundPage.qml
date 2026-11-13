import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.components
import qs.quick
import qs.services

// sound: the device settings page's machinery, moved into the app, with the
// sound menu's device page folded in. The current output and the master
// volume (Sys, the shell's chain), the outputs list (quick/Out -- tap picks
// through Eq, the chevron inspects), and the inspected device inlined below:
// its photo if one was dropped at buds/<slug>.png, the codec and the one
// charge bluez reports (AudioDev), per-bud charge and noise control for
// nothing / cmf buds (Sys.ear, their own protocol), its own volume, and the
// system eq the pc applies in front of it (services/Eq, gains saved per
// device in Theme.state.eqDev). Playback rides the shell's player (Media).
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    property var selDev: null // the output the device cards show, picked in the outputs list
    readonly property var selEq: selDev ? Eq.store(selDev.name) : { on: false, lo: 0, mid: 0, hi: 0 }
    readonly property bool devIsBuds: !!selDev && !!Sys.buds && AudioDev.btOf(selDev) === Sys.buds
    readonly property bool selGone: !!selDev && !Pipewire.nodes.values.includes(selDev)
    onSelGoneChanged: if (selGone) selDev = null
    onSelDevChanged: if (selDev && devIsBuds) Sys.earRun([])
    PwObjectTracker { objects: pg.selDev ? [pg.selDev] : [] }

    function barHas(w) { return Theme.state.bar.includes(w); }
    function barFlip(w) {
        const a = Theme.state.bar.slice();
        const i = a.indexOf(w);
        if (i >= 0) a.splice(i, 1); else a.push(w);
        Theme.state.bar = a;
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
                SetHead { text: "output" }
                SetCard {
                    SetRow {
                        label: Pipewire.defaultAudioSink ? outList.name(Pipewire.defaultAudioSink) : "none"
                    }
                    VolSlider { width: parent.width }
                    SetToggle {
                        label: "mute"
                        on: Sys.muted
                        onFlip: want => { if (Pipewire.defaultAudioSink?.audio) Pipewire.defaultAudioSink.audio.muted = want; }
                    }
                    SetToggle {
                        label: "show in the bar"
                        on: pg.barHas("sound")
                        divider: false
                        onFlip: pg.barFlip("sound")
                    }
                }
            }

            Out {
                id: outList
                width: parent.width
                open: true
                inspectable: true
                onInspect: n => pg.selDev = n
            }

            // the picked output: what it is, its charge, its own volume, then the eq
            Column {
                visible: !!pg.selDev
                width: parent.width
                spacing: 10
                SetHead { text: pg.selDev ? outList.name(pg.selDev) : "" }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 12

                        Row {
                            width: parent.width
                            spacing: 14
                            Item {
                                width: 64
                                height: 64
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 32
                                    color: Theme.s2
                                    Icon { anchors.centerIn: parent; visible: photo.status !== Image.Ready; text: pg.selDev ? outList.kind(pg.selDev)[1] : ""; font.pixelSize: 28; color: Theme.fg }
                                }
                                Image {
                                    id: photo
                                    anchors.fill: parent
                                    source: pg.selDev ? Quickshell.shellPath("buds/" + AudioDev.slug(outList.name(pg.selDev)) + ".png") : ""
                                    sourceSize: Qt.size(128, 128)
                                    fillMode: Image.PreserveAspectFit
                                    mipmap: true
                                    visible: status === Image.Ready
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 78
                                spacing: 3
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: pg.selDev ? outList.name(pg.selDev) : ""; font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold } color: Theme.fg }
                                Lb {
                                    px: 10
                                    text: pg.selDev ? [outList.kind(pg.selDev)[0],
                                        AudioDev.codecOf(pg.selDev),
                                        AudioDev.batteryOf(pg.selDev) >= 0 ? `${AudioDev.batteryOf(pg.selDev)}%` : ""].filter(s => s).join(" · ") : ""
                                }
                            }
                        }

                        // charge per bud and case -- nothing / cmf only, their protocol's numbers
                        Item {
                            visible: pg.devIsBuds && !!Sys.ear
                            width: parent.width
                            height: visible ? 96 : 0
                            Row {
                                anchors.centerIn: parent
                                spacing: 30
                                Repeater {
                                    model: pg.devIsBuds && Sys.ear ? ["l", "r", "case"].filter(k => Sys.ear[k] !== undefined) : []
                                    Column {
                                        id: ring
                                        required property string modelData
                                        readonly property real v: Sys.ear?.[ring.modelData] ?? 0
                                        property real k: 0
                                        NumberAnimation on k { from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
                                        spacing: 6
                                        Item {
                                            width: 74
                                            height: 74
                                            Ring { anchors.fill: parent; n: 30; dot: 4.6; f: ring.v / 100 * ring.k }
                                            Num { anchors.centerIn: parent; text: Math.round(ring.v * ring.k); font.pixelSize: 24 }
                                        }
                                        Lb { anchors.horizontalCenter: parent.horizontalCenter; text: ring.modelData; px: 10 }
                                    }
                                }
                            }
                        }

                        DevVol { width: parent.width; node: pg.selDev }

                        // noise control -- nothing / cmf only, the buds' own modes (Sys.ear)
                        Column {
                            visible: pg.devIsBuds && !!Sys.ear
                            width: parent.width
                            spacing: 8
                            Lb { x: 4; text: "noise control" }
                            Rectangle {
                                id: anc
                                width: parent.width
                                height: 50
                                radius: Theme.corner(25)
                                color: Theme.s2
                                readonly property real cell: (width - 12) / Sys.ancModes.length
                                readonly property int at: Sys.ancModes.findIndex(m => m[0] === Sys.ear?.mode)
                                Rectangle {
                                    visible: anc.at >= 0
                                    x: 6 + anc.cell * anc.at
                                    y: 6
                                    width: anc.cell
                                    height: parent.height - 12
                                    radius: height / 2
                                    color: Theme.fg
                                    Behavior on x { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                }
                                Repeater {
                                    model: Sys.ancModes
                                    Item {
                                        id: am
                                        required property var modelData
                                        required property int index
                                        x: 6 + anc.cell * index
                                        width: anc.cell
                                        height: anc.height
                                        Lb { anchors.centerIn: parent; text: am.modelData[1]; px: 10; color: anc.at === am.index ? Theme.ink : Theme.grey }
                                        TapHandler { onTapped: Sys.setAnc(am.modelData[0]) }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                            }
                        }
                    }
                }

                SetCard {
                    visible: Eq.alive
                    Column {
                        width: parent.width
                        spacing: 10
                        SetToggle {
                            label: "system eq"
                            sub: "bass, mid and treble this pc applies in front of the device"
                            on: pg.selEq.on
                            divider: false
                            onFlip: want => { if (pg.selDev) Eq.setOn(pg.selDev, want); }
                        }
                        Column {
                            width: parent.width
                            spacing: 8
                            opacity: pg.selEq.on ? 1 : 0.35
                            Behavior on opacity { NumberAnimation { duration: Theme.t } }
                            Band { label: "bass"; value: pg.selEq.lo; onMoved: db => Eq.setBand(pg.selDev.name, "lo", db) }
                            Band { label: "mid"; value: pg.selEq.mid; onMoved: db => Eq.setBand(pg.selDev.name, "mid", db) }
                            Band { label: "treble"; value: pg.selEq.hi; onMoved: db => Eq.setBand(pg.selDev.name, "hi", db) }
                            Row {
                                spacing: 8
                                Repeater {
                                    model: [["flat", 0, 0, 0], ["bass", 7, 1, -2], ["vocal", -2, 5, 2], ["bright", -3, 1, 7]]
                                    Rectangle {
                                        id: chip
                                        required property var modelData
                                        readonly property bool on: pg.selEq.lo === modelData[1] && pg.selEq.mid === modelData[2] && pg.selEq.hi === modelData[3]
                                        width: chipLb.width + 22
                                        height: 28
                                        radius: Theme.corner(14)
                                        color: on ? Theme.fg : Theme.s2
                                        Lb { id: chipLb; anchors.centerIn: parent; text: chip.modelData[0]; px: 11; color: chip.on ? Theme.ink : Theme.grey }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Eq.setPreset(pg.selDev.name, chip.modelData[1], chip.modelData[2], chip.modelData[3]) }
                                    }
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
