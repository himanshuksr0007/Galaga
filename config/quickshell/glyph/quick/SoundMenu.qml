import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// the sound menu: the bar's speaker opens this small dropdown instead of all
// of quick settings. Two pages slide inside it, macOS-style. The first is the
// volume slider and the output list (the outputs Quick keeps behind a
// right-click, unfolded for good). A row's chevron opens the second page --
// one output device, with only the controls that device really has:
//   every device   its own volume, playback, a photo if one was dropped in
//   bluetooth      the codec pipewire negotiated, the one charge bluez
//                  reports through upower (AudioDev) -- never per-bud
//                  numbers, those need a vendor protocol
//   nothing / cmf  charge per bud and case + noise control (Sys.ear, the
//                  buds' own protocol -- the same section Quick shows)
//   eq unlocked    bass / mid / treble the pc applies in front of the
//                  device (services/Eq) -- labelled as the pc's work
// Click the speaker again, click anywhere else, or press Esc to close it;
// the wheel over the bar icon still rides the volume, and opening quick
// settings puts this away, as this puts quick away (shell.qml wires them).
PanelWindow {
    id: root

    signal settingsRequested

    property bool open: false
    function toggle() { open = !open; }
    function close() { open = false; }
    onOpenChanged: {
        if (open) {
            Sounds.play("pop");
            view = "out";
            if (AudioDev.btOf(dev) === Sys.buds && Sys.buds) Sys.earRun([]);
        }
    }

    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    // ---- pages ----
    property string view: "out" // "out" | "dev"
    property var dev: null      // the PwNode the device page shows
    readonly property bool devGone: !!dev && !Pipewire.nodes.values.includes(dev)
    onDevGoneChanged: if (devGone) view = "out"
    readonly property bool devIsBuds: !!dev && !!Sys.buds && AudioDev.btOf(dev) === Sys.buds
    readonly property var devKind: dev ? outList.kind(dev) : ["", "", 0]
    function showDevice(n) {
        dev = n;
        view = "dev";
        if (AudioDev.btOf(n) === Sys.buds && Sys.buds) Sys.earRun([]);
    }
    PwObjectTracker { objects: root.dev ? [root.dev] : [] }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-sound"

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        id: panel
        readonly property bool barTop: Theme.state.barAt === "top"
        width: 380
        height: (root.view === "out" ? outCol.height : devCol.height) + 44
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
        Keys.onEscapePressed: { if (root.view === "dev") root.view = "out"; else root.close(); }
        MouseArea { anchors.fill: parent } // clicking the panel does not close it

        Item {
            id: view2
            x: 22
            y: 22
            width: parent.width - 44
            height: parent.height - 44
            clip: true

            Row {
                x: root.view === "out" ? 0 : -view2.width
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                spacing: 0

                // ---------- page 1: outputs ----------
                Item {
                    width: view2.width
                    height: outCol.height
                    opacity: root.view === "out" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Column {
                        id: outCol
                        width: parent.width
                        spacing: 16

                        Item {
                            width: parent.width
                            height: 24
                            Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "sound" }
                            Icon {
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                text: Sys.muted ? "\u{F075F}" : "\u{F057E}"
                                color: Sys.muted ? Theme.red : Theme.grey
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { if (Sys.sink?.audio) Sys.sink.audio.muted = !Sys.sink.audio.muted; } }
                            }
                        }

                        VolSlider { }

                        Out { id: outList; width: parent.width; open: true; inspectable: true; onInspect: n => root.showDevice(n) }
                    }
                }

                // ---------- page 2: one device ----------
                Item {
                    width: view2.width
                    height: devCol.height
                    opacity: root.view === "dev" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Column {
                        id: devCol
                        width: parent.width
                        spacing: 16

                        // back row
                        Item {
                            width: parent.width
                            height: 24
                            Row {
                                spacing: 6
                                anchors.verticalCenter: parent.verticalCenter
                                Icon { text: "\u{F0141}"; font.pixelSize: 16; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                                Lb { text: "outputs"; anchors.verticalCenter: parent.verticalCenter }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.view = "out" }
                            }
                            Lb { anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter } text: root.devKind[0] }
                        }

                        // hero: photo when one was dropped at buds/<slug>.png (the buds card's
                        // convention), the kind icon otherwise; name and what it is under it
                        Column {
                            width: parent.width
                            spacing: 8
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 104
                                height: 104
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.corner(52)
                                    color: Theme.s2
                                    Icon { anchors.centerIn: parent; visible: photo.status !== Image.Ready; text: root.devKind[1]; font.pixelSize: 46; color: Theme.fg }
                                }
                                Image {
                                    id: photo
                                    anchors.fill: parent
                                    source: root.dev ? Quickshell.shellPath("buds/" + AudioDev.slug(outList.name(root.dev)) + ".png") : ""
                                    sourceSize: Qt.size(208, 208)
                                    fillMode: Image.PreserveAspectFit
                                    mipmap: true
                                    visible: status === Image.Ready
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: root.dev ? outList.name(root.dev) : ""
                                font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                                color: Theme.fg
                            }
                            Lb {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: [root.devKind[0], AudioDev.codecOf(root.dev), "connected"].filter(s => s).join(" · ")
                            }
                        }

                        // charge rings: per bud + case when the buds' own protocol reports them
                        // (nothing / cmf), otherwise the single number bluez reports, if any
                        Row {
                            id: batRow
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 30
                            visible: root.devIsBuds ? !!Sys.ear : batOne >= 0
                            readonly property int batOne: root.dev && root.t > 0 ? AudioDev.batteryOf(root.dev) : -1
                            Repeater {
                                model: root.devIsBuds && Sys.ear ? ["l", "r", "case"].filter(k => Sys.ear[k] !== undefined) : (batRow.batOne >= 0 ? ["one"] : [])
                                Column {
                                    id: ring
                                    required property string modelData
                                    readonly property real v: ring.modelData === "one" ? batRow.batOne : (Sys.ear?.[ring.modelData] ?? 0)
                                    property real k: 0
                                    NumberAnimation on k { from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
                                    spacing: 6
                                    Item {
                                        width: 74
                                        height: 74
                                        Ring { anchors.fill: parent; n: 30; dot: 4.6; f: ring.v / 100 * ring.k }
                                        Num { anchors.centerIn: parent; text: Math.round(ring.v * ring.k); font.pixelSize: 24 }
                                    }
                                    Lb { anchors.horizontalCenter: parent.horizontalCenter; text: ring.modelData === "one" ? "battery" : ring.modelData; px: 10 }
                                }
                            }
                        }

                        // not the output right now -- one tap makes it so (through Eq, like the rows)
                        Rectangle {
                            visible: !!root.dev && Pipewire.defaultAudioSink !== root.dev && Eq.engaged !== root.dev
                            width: parent.width
                            height: 46
                            radius: Theme.corner(23)
                            color: hov2.hovered ? Theme.s3 : Theme.s2
                            Row {
                                anchors.centerIn: parent
                                spacing: 10
                                Icon { text: "\u{F057E}"; font.pixelSize: 17; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                                Lb { text: "use as output"; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                            }
                            HoverHandler { id: hov2; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Eq.pick(root.dev) }
                        }

                        // the device's own volume
                        Column {
                            width: parent.width
                            spacing: 8
                            Lb { x: 4; text: "volume" }
                            DevSlider { }
                        }

                        // noise control -- nothing / cmf only, the buds' own modes (Sys.ear)
                        Column {
                            visible: root.devIsBuds && !!Sys.ear
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

                        // system eq -- the pc shapes the sound in front of this device
                        Column {
                            visible: Eq.alive && !!root.dev
                            width: parent.width
                            spacing: 10
                            Item {
                                width: parent.width
                                height: 24
                                Lb { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "system eq" }
                                // a small sliding switch, the anc pill in miniature
                                Rectangle {
                                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                    width: 46
                                    height: 26
                                    radius: 13
                                    color: eqOn ? Theme.fg : Theme.s2
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                    Rectangle {
                                        x: eqOn ? parent.width - width - 3 : 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: eqOn ? Theme.ink : Theme.grey
                                        Behavior on x { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Eq.setOn(root.dev, !eqOn) }
                                }
                            }
                            Column {
                                width: parent.width
                                spacing: 8
                                opacity: eqOn ? 1 : 0.35
                                Behavior on opacity { NumberAnimation { duration: Theme.t } }
                                Band { label: "bass"; value: eqs.lo; onMoved: db => Eq.setBand(root.dev.name, "lo", db) }
                                Band { label: "mid"; value: eqs.mid; onMoved: db => Eq.setBand(root.dev.name, "mid", db) }
                                Band { label: "treble"; value: eqs.hi; onMoved: db => Eq.setBand(root.dev.name, "hi", db) }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: [["flat", 0, 0, 0], ["bass", 7, 1, -2], ["vocal", -2, 5, 2], ["bright", -3, 1, 7]]
                                        Rectangle {
                                            id: chip
                                            required property var modelData
                                            readonly property bool on: eqs.lo === modelData[1] && eqs.mid === modelData[2] && eqs.hi === modelData[3]
                                            width: chipLb.width + 22
                                            height: 28
                                            radius: Theme.corner(14)
                                            color: on ? Theme.fg : Theme.s2
                                            Lb { id: chipLb; anchors.centerIn: parent; text: chip.modelData[0]; px: 11; color: chip.on ? Theme.ink : Theme.grey }
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: Eq.setPreset(root.dev.name, chip.modelData[1], chip.modelData[2], chip.modelData[3]) }
                                        }
                                    }
                                }
                                Lb { x: 4; px: 10; color: Theme.mute; text: "applied by the pc before the sound leaves · saved for this device" }
                            }
                        }

                        // playback -- whatever is playing, through the shell's player
                        Rectangle {
                            visible: !!Media.player
                            width: parent.width
                            height: 78
                            radius: Theme.corner(28)
                            color: Theme.s2
                            Art { id: mart; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56; step: 4; url: Media.player?.trackArtUrl ?? "" }
                            Column {
                                anchors { left: mart.right; leftMargin: 14; right: mctl.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackTitle || "Nothing on"; font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold } color: Theme.fg }
                                Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackArtist ?? ""; font { family: Theme.ui; pixelSize: 12 } color: Theme.grey }
                            }
                            Controls { id: mctl; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } size: 18; play: 40 }
                        }

                        // footer -- the full sound settings live in prefs
                        Item {
                            width: parent.width
                            height: 22
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Lb { text: "sound settings"; anchors.verticalCenter: parent.verticalCenter }
                                Icon { text: "\u{F0142}"; font.pixelSize: 13; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { root.close(); root.settingsRequested(); } }
                        }
                    }
                }
            }
        }
    }

    // this device's settings snapshot, live from the store (Eq)
    readonly property var eqs: dev ? Eq.store(dev.name) : { on: false, lo: 0, mid: 0, hi: 0 }
    readonly property bool eqOn: eqs.on

    // the house slider, as in Quick: filled -- a white pill with the icon,
    // empty -- a row of dots, the level in a chip at the right. This one
    // drives the shell's volume (the current output chain)
    component VolSlider: Rectangle {
        id: sl
        readonly property real value: Sys.muted ? 0 : Sys.vol
        readonly property real shown: area.pressed ? area.v : value
        width: parent.width
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
                if (Math.abs(wacc) < 0.02)
                    return;
                Sys.setVol(Math.max(0, Math.min(1, sl.shown + wacc)));
                wacc = 0;
            }
        }
    }

    // the same slider bound to the shown device itself -- every sink carries
    // its own level, whether or not it is the output right now
    component DevSlider: Rectangle {
        id: sl
        readonly property real value: root.dev?.audio?.muted ? 0 : (root.dev?.audio?.volume ?? 0)
        readonly property real shown: area.pressed ? area.v : value
        width: parent.width
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
            Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; text: root.dev?.audio?.muted ? "\u{F075F}" : "\u{F057E}"; font.pixelSize: 21; color: Theme.ink }
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
            function set(x) {
                if (!root.dev?.audio) return;
                v = Math.max(0, Math.min(1, x / width));
                root.dev.audio.muted = false;
                root.dev.audio.volume = v;
            }
            onPressed: e => set(e.x)
            onPositionChanged: e => set(e.x)
            onWheel: e => {
                wacc += (e.inverted ? -1 : 1) * (e.angleDelta.y || -e.angleDelta.x) / 120 * 0.05 * (e.phase === Qt.NoScrollPhase ? 1 : 0.25);
                if (Math.abs(wacc) < 0.02)
                    return;
                set((sl.shown + wacc) * width);
            }
        }
    }

    // one eq band: a dotted track, a white pill growing from the centre notch
    // to the gain, the value in a chip. Drag, wheel, or double-tap to zero
    component Band: Rectangle {
        id: bd
        property string label
        property real value // decibels, -12..12
        signal moved(real db)
        readonly property real shown: area.pressed ? area.v : value
        width: parent.width
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
                if (Math.abs(wacc) < 0.5)
                    return;
                bd.moved(Math.max(-12, Math.min(12, bd.shown + Math.round(wacc))));
                wacc = 0;
            }
        }
    }
}
