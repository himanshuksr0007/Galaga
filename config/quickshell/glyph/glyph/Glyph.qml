import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// Glyph: screen edges as LEDs on the back, instead of OSDs and popups in the middle of the screen.
// At the top -- a flash for a notification (red for critical ones) and an "island" with it, on the right -- volume/brightness bottom-up,
// at the bottom -- progress of long tasks (notifications with hint value) or the focus timer (Focus). They fade after 3 s
Scope {
    id: root

    // ---- right: volume and brightness ----
    property string kind: "vol"
    property real value: 0
    property bool flash: false // a vol/bri/mic flash owns the right strip while it is up
    property bool armed: false // do not show the first values at startup
    Timer { running: true; interval: 1500; onTriggered: root.armed = true }
    function level(k, v) {
        if (!armed || !Theme.state.edges) return;
        kind = k;
        value = v;
        flash = true;
        sideT.restart();
    }
    Connections {
        target: Sys.sink?.audio ?? null
        function onVolumeChanged() { root.level("vol", Sys.muted ? 0 : Sys.vol); }
        function onMutedChanged() { root.level("vol", Sys.muted ? 0 : Sys.vol); }
    }
    // mic mute gets the same flash: full strip and the mic glyph for live,
    // empty strip and the mic-off glyph for muted (no number -- it is a state, not a level)
    Connections {
        target: Sys.mic?.audio ?? null
        function onMutedChanged() { root.level("mic", Sys.micOn ? 1 : 0); }
    }
    Connections {
        target: Sys
        function onBriChanged() { root.level("bri", Sys.bri); }
    }
    Timer { id: sideT; interval: 3000; onTriggered: root.flash = false }

    // ---- reactive edges (prefs FEATURES): the strips get standing jobs ----
    // music: while something plays, the right strip is a VU meter fed by cava -- the same
    // process home's Glyph Matrix uses (services/Cava registers consumers by name, one
    // process for all). The vol/bri/mic flash takes the strip while it is up; the meter
    // returns when it fades. The level leans on the low bands, like the matrix does.
    readonly property bool vuOn: Theme.state.edges && Theme.state.featEdges && Media.playing
    onVuOnChanged: Cava.use("edges", vuOn)
    Component.onCompleted: Cava.use("edges", vuOn)
    Component.onDestruction: Cava.use("edges", false)
    readonly property real vuRaw: {
        const b = Cava.bars;
        return Math.max(0, Math.min(1, (b[0] + b[1] * 0.9 + b[2] * 0.75 + b[3] * 0.6 + b[4] * 0.45 + b[5] * 0.3 + b[6] * 0.2 + b[7] * 0.1) / 3.2));
    }
    property real vu: vuOn ? vuRaw : 0
    Behavior on vu { NumberAnimation { duration: 90 } } // cava lands in steps; the strip glides
    // charging: plugged in -- the bottom strip fills with the battery (below task/focus)
    readonly property bool charging: (bat?.isLaptopBattery ?? false) && !UPower.onBattery
    readonly property bool chargeJob: Theme.state.featEdges && charging
    // ...but only on the home screen: an app on the focused monitor's workspace
    // puts the charging fill and its pill away (Home.idle decides the same way).
    // The task and focus jobs above it in the strip are working overlays -- they stay
    readonly property bool homeIdle: (Hyprland.focusedMonitor?.activeWorkspace?.toplevels.values.length ?? 0) === 0
    readonly property bool chargeShown: chargeJob && homeIdle

    // ---- top: new notification -- a strip flash and a tile into the island stack ----
    property var note: null // the last one, for the flash
    // stack: field snapshots (a notification can be closed while the tile leaves -- the object will be gone), the object itself -- in refs for the action
    ListModel { id: stack }
    property var refs: ({})
    property int seq: 0
    readonly property int most: 4
    // tile into the stack: c -- { app, summary, body, icon (icon theme), glyph (nerd font), crit }; ref -- the notification, for the action
    function push(c, ref) {
        root.note = { urgency: c.crit ? NotificationUrgency.Critical : NotificationUrgency.Normal };
        noteT.restart();
        const key = String(++root.seq);
        if (ref) root.refs[key] = ref;
        stack.insert(0, Object.assign({ key, app: "", summary: "", body: "", icon: "", glyph: "", crit: false, leaving: false }, c));
        // more than most -- the oldest of the living ones leaves
        let live = 0;
        for (let i = 0; i < stack.count; i++) if (!stack.get(i).leaving && ++live > root.most) stack.setProperty(i, "leaving", true);
    }
    Connections {
        target: Notes
        function onArrived(n) {
            root.push({ app: n.appName || "app", summary: n.summary ?? "", body: n.body ?? "", icon: n.appIcon ?? "",
                        crit: n.urgency === NotificationUrgency.Critical }, n);
        }
    }

    // ---- power: charger plugged/unplugged, charged, discharging (15% -- warn, 5% -- red). A tile into the island,
    // past the notification history. armed -- not at startup ----
    readonly property var bat: UPower.displayDevice
    readonly property int pct: Math.round((bat?.percentage ?? 0) * 100)
    property int warned: 100
    function hm(s) { const m = Math.round(s / 60); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} m` : `${m} m`; }
    function power(summary, glyph, crit, time) {
        if (root.armed && root.bat?.isLaptopBattery) root.push({ app: "power", summary, body: `${root.pct}%` + (time ? ` · ${time}` : ""), glyph, crit: !!crit });
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.warned = 100;
            if (UPower.onBattery) root.power("On battery", "\u{F0079}", false, root.bat.timeToEmpty ? `${root.hm(root.bat.timeToEmpty)} left` : "");
            else root.power("Charging", "\u{F0084}", false, root.bat.timeToFull ? `full in ${root.hm(root.bat.timeToFull)}` : "");
        }
    }
    Connections {
        target: root.bat
        function onStateChanged() { if (root.bat.state === UPowerDeviceState.FullyCharged && !UPower.onBattery) root.power("Fully charged", "\u{F0079}"); }
        function onPercentageChanged() {
            if (!UPower.onBattery) return;
            if (root.pct <= 5 && root.warned > 5) { root.warned = 5; root.power("Battery critical", "\u{F0083}", true, "plug in now"); }
            else if (root.pct <= 15 && root.warned > 15) { root.warned = 15; root.power("Battery low", "\u{F0083}", false, "plug in soon"); }
        }
    }
    function dismiss(key) { for (let i = 0; i < stack.count; i++) if (stack.get(i).key === key) return stack.setProperty(i, "leaving", true); }
    function forget(key) {
        delete refs[key];
        for (let i = 0; i < stack.count; i++) if (stack.get(i).key === key) return stack.remove(i);
    }
    Timer { id: noteT; interval: 3000; onTriggered: root.note = null }
    readonly property bool crit: note?.urgency === NotificationUrgency.Critical
    // flash and island sit under the bar when it is on top and present on the focused screen (that is where they stand)
    readonly property bool underBar: Theme.state.barAt === "top" && Theme.scr(Hyprland.focusedMonitor?.name, "bar")

    Edge {
        id: top
        shown: !!root.note && Theme.state.edges
        anchors.top: true
        margins.top: root.underBar ? Math.ceil(78 * Theme.s) : 0
        implicitWidth: Math.ceil(640 * Theme.s)
        implicitHeight: Math.ceil(30 * Theme.s)
        Seg {
            x: 20
            y: 4
            width: 600
            height: 4
            n: 12
            f: 1
            on: root.crit ? Theme.red : Theme.fg
            layer.enabled: true
            layer.effect: Glow {}
            SequentialAnimation on opacity {
                running: top.shown
                loops: Animation.Infinite
                NumberAnimation { from: 0.15; to: 1; duration: 720; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0.15; duration: 1680; easing.type: Easing.InOutSine }
            }
        }
    }

    // island: stack of tiles at the top center, new ones on top. White outline (critical -- red), icon in a circle, red dot.
    // Each -- like a dynamic island: falls as a pill, spreads into a tile, text appears last; leaves back, and its place
    // collapses -- the ones below pull up. Each lives 4 s, hovering the stack holds all.
    // Fixed-size window (under most tiles), the mouse is caught only by the stack itself
    PanelWindow {
        visible: stack.count > 0
        anchors.top: true
        margins.top: root.underBar ? Math.ceil(78 * Theme.s) : 0
        implicitWidth: Math.ceil(600 * Theme.s)
        implicitHeight: Math.ceil((24 + root.most * 132) * Theme.s)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region { item: col }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "glyph-island"

        Stage {
            Column {
                id: col
                y: 24
                width: 600
                HoverHandler { id: hov }

                Repeater {
                    model: stack

                    Item {
                        id: c
                        required property int index
                        required property string key
                        required property string app
                        required property string summary
                        required property string body
                        required property string icon
                        required property string glyph
                        required property bool crit
                        required property bool leaving

                        // p 0...1 linear, each phase has its own ease-out-quart (like glide)
                        property real p: 0
                        Component.onCompleted: p = Qt.binding(() => leaving ? 0 : 1)
                        Behavior on p { NumberAnimation { duration: c.leaving ? 450 : 700 } }
                        onPChanged: if (leaving && p <= 0) Qt.callLater(root.forget, key)
                        function ph(a, b) { const x = Math.max(0, Math.min(1, (p - a) / (b - a))); return 1 - Math.pow(1 - x, 4); }
                        readonly property real drop: ph(0, 0.3)   // pill falls
                        readonly property real grow: ph(0.25, 0.8) // and spreads into a tile
                        readonly property real full: Math.max(86, txt.height + 32)

                        width: 600
                        height: (40 + (full - 40) * grow + 12) * drop // place in the stack grows and collapses with the tile
                        Timer { running: !c.leaving && !hov.hovered; interval: 4000; onTriggered: root.dismiss(c.key) }

                        Rectangle {
                            width: 140 + (600 - 140) * c.grow
                            height: 40 + (c.full - 40) * c.grow
                            x: (600 - width) / 2
                            y: -24 * (1 - c.drop)
                            opacity: c.drop
                            radius: Theme.corner(Math.min(34, height / 2))
                            clip: true
                            color: Theme.s1
                            border { width: 1; color: c.crit ? Theme.red : Theme.fg }

                            // content -- at full size in the center: text width does not change while the tile grows
                            Item {
                                anchors.centerIn: parent
                                width: 600
                                height: c.full
                                opacity: c.ph(0.7, 1)

                                Rectangle {
                                    id: ic
                                    x: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 54
                                    height: 54
                                    radius: 27
                                    color: Theme.s2
                                    Icon { anchors.centerIn: parent; visible: !img.visible; text: c.glyph || "\u{F009A}"; font.pixelSize: 24 }
                                    Image {
                                        id: img
                                        anchors.centerIn: parent
                                        width: 28
                                        height: 28
                                        visible: status === Image.Ready
                                        source: c.icon ? Quickshell.iconPath(c.icon, true) : ""
                                        sourceSize: Qt.size(28, 28)
                                        layer.enabled: true
                                        layer.effect: Dm { step: 2 }
                                    }
                                }
                                Column {
                                    id: txt
                                    anchors { left: ic.right; leftMargin: 16; right: dot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                    Lb { width: parent.width; elide: Text.ElideRight; text: `${c.app} · now` }
                                    Text {
                                        width: parent.width
                                        topPadding: 2
                                        elide: Text.ElideRight
                                        text: c.summary
                                        textFormat: Text.PlainText
                                        font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                                        color: Theme.fg
                                    }
                                    Text {
                                        width: parent.width
                                        visible: !!c.body
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                        text: c.body
                                        font { family: Theme.ui; pixelSize: 14 }
                                        color: Theme.grey
                                    }
                                }
                                // red dot -- only on the newest one: one red on screen
                                Rectangle { id: dot; visible: c.index === 0; anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter } width: 12; height: 12; radius: 6; color: Theme.red }
                            }

                            // click -- default action; the tile leaves, stays in history. The notification may already be closed --
                            // an empty wrapper without actions remains of the object
                            TapHandler {
                                onTapped: {
                                    root.refs[c.key]?.actions?.find(a => a.identifier === "default")?.invoke();
                                    root.dismiss(c.key);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- right: the vol/bri/mic flash, and under it the music VU ----
    Edge {
        id: side
        shown: root.flash || root.vuOn
        anchors.right: true
        implicitWidth: Math.ceil(160 * Theme.s)
        implicitHeight: Math.ceil(520 * Theme.s)
        Lit {
            x: 160 - 5 - 5
            y: 10
            width: 5
            height: 500
            n: 20
            vertical: true
            f: root.flash ? root.value : root.vu
        }
        Tag {
            visible: root.flash // the VU needs no capsule -- it is a meter, not a value
            vertical: true // the capsule stands upright for a vertical strip too: icon above the number
            anchors { right: parent.right; rightMargin: 26; verticalCenter: parent.verticalCenter }
            Icon { text: root.kind === "bri" ? "\u{F00E0}" : root.kind === "mic" ? (Sys.micOn ? "\u{F036C}" : "\u{F036D}") : Sys.muted ? "\u{F075F}" : "\u{F057E}" }
            Num { visible: root.kind !== "mic"; text: Math.round(root.value * 100); font.pixelSize: 30 }
        }
    }

    // ---- bottom: task progress first, then the focus drain, then the charging fill
    // (one strip, no capsule for the timer: it hangs for tens of minutes) ----
    readonly property var task: Notes.task
    readonly property bool focusJob: Focus.running && Theme.state.featEdges
    readonly property real progress: task ? Math.max(0, Math.min(100, task.hints.value ?? 0)) / 100
        : focusJob ? Focus.f : pct / 100
    Connections {
        target: Focus
        function onDone() { root.push({ app: "focus", summary: "Focus done", body: `${Focus.minutes} min`, glyph: "\u{F13AB}" }); }
    }
    Edge {
        shown: (!!root.task || root.focusJob || root.chargeShown) && Theme.state.edges
        anchors.bottom: true
        implicitWidth: Math.ceil(1100 * Theme.s)
        implicitHeight: Math.ceil(110 * Theme.s)
        Lit {
            x: 10
            y: 110 - 5 - 5
            width: 1080
            height: 5
            n: 40
            f: root.progress
        }
        Tag {
            visible: !!root.task
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 }
            Icon { text: "\u{F01DA}" }
            Lb { text: root.task?.summary ?? ""; color: Theme.fg }
            Num { text: Math.round(root.progress * 100) + "%"; font.pixelSize: 26 }
        }
        Tag {
            visible: !root.task && !root.focusJob && root.chargeShown
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 }
            Icon { text: "\u{F0084}" }
            Num { text: root.pct; font.pixelSize: 26 }
            Lb { text: "% · charging"; color: Theme.fg }
        }
    }

    // strip at the edge: transparent to the mouse, drawn in layout pixels
    component Edge: PanelWindow {
        property bool shown
        default property alias content: st.data
        visible: shown
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "glyph-edge"
        Stage { id: st }
    }
    // value capsule next to the strip; vertical -- content stacked
    component Tag: Rectangle {
        default property alias content: box.data
        property bool vertical
        width: vertical ? Math.max(52, box.width + 24) : box.width + 32
        height: vertical ? box.height + 36 : 52
        radius: Theme.corner(Math.min(width, height) / 2)
        color: Theme.s1
        border { width: 1; color: Theme.s2 }
        Grid {
            id: box
            anchors.centerIn: parent
            columns: parent.vertical ? 1 : 99
            spacing: parent.vertical ? 10 : 12
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
        }
    }
    // glow of lit segments -- the only "shadow" in the whole shell
    component Glow: MultiEffect {
        shadowEnabled: true
        shadowColor: Theme.glow
        shadowBlur: 0.7
        blurMax: 20
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
    }
}
