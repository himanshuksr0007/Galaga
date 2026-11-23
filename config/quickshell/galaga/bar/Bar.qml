import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.services
import qs.settings

// bar: a pill at the left edge or on top -- Theme.state.barAt. First the mark (ring of 16 dots) -- launcher, the center turns red while recording or the microphone is on.
// Workspaces as dots, window title, Doto clock in the center, tray last -- a click opens quick settings.
// At the side everything is a column, on top -- a row. What is in the tray and in what order, whether there is a title -- Theme.state (settings, BAR section)
PanelWindow {
    id: root

    signal markClicked
    signal trayClicked
    signal trayAppsClicked(Item anchor)
    signal soundClicked(var origin)
    signal btClicked(var origin)
    signal wifiClicked(var origin)
    signal powerClicked
    signal clockClicked(var origin)
    signal powerCardClicked(Item anchor)

    readonly property bool vert: Theme.state.barAt !== "top" // everything but top (and unknown) -- at the left
    anchors { left: true; right: !vert; top: true; bottom: vert }
    implicitWidth: Math.ceil(78 * Theme.s)  // at the side
    implicitHeight: Math.ceil(78 * Theme.s) // on top
    // the strip is reserved, always: tiles, snaps and maximised windows are
    // given a work area that starts past the pill, so nothing slides under
    // the bar. A snapped window's title bar needs more room than the strip
    // alone -- Snap adds that clearance inside its own zones instead
    // (services/Snap.qml), so a maximised window still hugs the strip.
    exclusiveZone: Math.ceil(78 * Theme.s)
    color: "transparent"
    WlrLayershell.namespace: "galaga-bar"

    readonly property int active: Hyprland.focusedWorkspace?.id ?? 0
    // six dots, more -- if occupied or a distant one is open
    readonly property int count: Math.min(10, Math.max(6, active, ...Hyprland.workspaces.values.filter(w => w.toplevels.values.length).map(w => w.id)))
    readonly property var top: ToplevelManager.activeToplevel
    readonly property var bat: UPower.displayDevice
    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null

    // hyprland 0.56 with lua: dispatch accepts a lua expression
    function go(ws) { Hyprland.dispatch(`hl.dsp.focus({ workspace = "${ws}" })`); }

    function popoverOrigin(item) {
        if (vert) return null;
        return item.mapToItem(contentItem, 0, 0, item.width, item.height);
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Stage {
        Rectangle {
            id: pill
            x: 14 // from the screen edges
            y: 14
            width: root.vert ? 64 : parent.width - 28
            height: root.vert ? parent.height - 28 : 64
            radius: Theme.corner(32)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }

            Notch { onNotch: d => root.go(d > 0 ? "-1" : "+1") }

            // mark: ring of dots, center -- red while something is recording
            Item {
                id: mark
                x: root.vert ? (parent.width - width) / 2 : 18
                y: root.vert ? 18 : (parent.height - height) / 2
                width: 34
                height: 34
                Ring { anchors.fill: parent; n: 16; dot: 3 }
                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    radius: 4.5
                    color: Sys.live ? Theme.red : Theme.fg
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.markClicked() }
            }

            // workspaces: the current one stretches into a white pill, occupied ones grey, empty ones -- a line
            Pile {
                id: ws
                x: root.vert ? (parent.width - width) / 2 : mark.x + mark.width + 24
                y: root.vert ? mark.y + mark.height + 24 : (parent.height - height) / 2
                spacing: 8

                Repeater {
                    model: root.count

                    Rectangle {
                        required property int index
                        readonly property int n: index + 1
                        readonly property bool occ: (Hyprland.workspaces.values.find(w => w.id === n)?.toplevels.values.length ?? 0) > 0
                        readonly property bool on: root.active === n
                        property real len: on ? 28 : 8
                        width: root.vert ? 8 : len
                        height: root.vert ? len : 8
                        radius: 4
                        color: on ? Theme.fg : occ ? Theme.grey : Theme.s3
                        Behavior on len { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.go(parent.n) }
                    }
                }
            }

            // window title: from the workspaces to the clock; at the side -- rotated
            Item {
                id: title
                x: root.vert ? (parent.width - width) / 2 : ws.x + ws.width + 24
                y: root.vert ? ws.y + ws.height + 24 : (parent.height - height) / 2
                width: root.vert ? 20 : Math.max(0, clk.x - 24 - x)
                height: root.vert ? Math.max(0, clk.y - 24 - y) : 20
                clip: true
                visible: Theme.state.barTitle
                Lb {
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                    width: root.vert ? parent.height : parent.width
                    rotation: root.vert ? 90 : 0
                    elide: Text.ElideRight
                    visible: (Hyprland.focusedWorkspace?.toplevels.values.length ?? 0) > 0
                    text: root.top ? `${root.top.appId.split(".").pop()} · ${root.top.title}` : ""
                    px: 11
                }
            }

            // clock: at the side stacked 14 above 32 and the day, on top -- a row. Click -- calendar and focus timer (cal/Cal)
            Pile {
                id: clk
                anchors.centerIn: parent
                TapHandler { onTapped: root.clockClicked(root.popoverOrigin(parent)) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Num { text: Theme.hh(clock.date); font.pixelSize: 30 }
                Num { visible: !root.vert; text: ":"; font.pixelSize: 30 }
                Num { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 30 }
                Lb {
                    topPadding: root.vert ? 8 : 0
                    leftPadding: root.vert ? 0 : 12
                    text: Qt.locale("en_US").toString(clock.date, "ddd d")
                    px: 10
                }
            }

            // Tray in the order set in Desktop & Deck. Notifications open Quick.
            // Sound, Bluetooth, Wi-Fi and battery have their own menus.
            Pile {
                x: root.vert ? (parent.width - width) / 2 : parent.width - width - 22
                y: root.vert ? parent.height - height - 22 : (parent.height - height) / 2
                spacing: 20

                Repeater {
                    model: Theme.state.bar
                    Loader {
                        id: part
                        required property string modelData
                        // Keep the old slot dimensions so saved layouts keep their spacing.
                        readonly property bool reserved: modelData === "mode"
                        readonly property bool barAction: !reserved && modelData !== "power" && modelData !== "focus"
                        sourceComponent: reserved ? modeGap : root.parts[modelData] ?? null
                        visible: !!sourceComponent && (modelData !== "battery" || root.bat.isLaptopBattery) && (modelData !== "focus" || Theme.state.featFocus)
                        // the glyphs are small and the tray's spacing leaves 20 px of dead
                        // space between them: the hit area grows 10 px into the gap on
                        // every side, so neighbouring areas meet at the gap's middle and
                        // a press in the space counts for the icon it is closer to. The
                        // layout does not move -- the workspace dots' trick, wider.
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -10
                            enabled: part.barAction
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (part.modelData === "battery") {
                                    root.powerCardClicked(part);
                                    return;
                                }
                                switch (part.modelData) {
                                case "trayApps": root.trayAppsClicked(part); break;
                                case "sound": root.soundClicked(root.popoverOrigin(part)); break;
                                case "bluetooth": root.btClicked(root.popoverOrigin(part)); break;
                                case "wifi": root.wifiClicked(root.popoverOrigin(part)); break;
                                default: root.trayClicked();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property var parts: ({ wifi: wifiC, bluetooth: btC, sound: soundC, notes: notesC, focus: focusC, battery: batC, power: powerC, cat: catC, trayApps: trayAppsC })
    Component {
        id: trayAppsC
        Icon {
            text: "\u{F0143}"
            width: 16
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "background apps"
            Accessible.onPressAction: root.trayAppsClicked(parent)
            Keys.onReturnPressed: root.trayAppsClicked(parent)
            Keys.onEnterPressed: root.trayAppsClicked(parent)
            Keys.onSpacePressed: root.trayAppsClicked(parent)
        }
    }
    // RunCat: the busier the cpu, the faster it runs (250 ms a frame idle, 50 at full load). cpu is polled
    // while it is in the tray; the Binding is not in a delegate -- a destroyed value is not given back.
    // Grey as-is; in the light theme it would vanish on white, so it inverts to black, like the buds.
    // Shell performance lite: the cat stands still and its cpu polling stops with it (the Binding below)
    Component {
        id: catC
        AnimatedImage {
            width: 44
            height: 26
            playing: !Theme.perfLite
            source: "runcat.gif"
            mipmap: true
            speed: 1 + 4 * SysStats.cpu
            layer.enabled: Theme.light
            layer.effect: MultiEffect { brightness: -1 }
        }
    }
    Binding { target: SysStats; property: "cat"; value: Theme.state.bar.includes("cat") && !Theme.perfLite }
    // wifi: two arcs and a dot with round caps, like the battery; off gets a slash
    Component {
        id: wifiC
        Shape {
            id: wf
            width: 20
            height: 18
            transform: Translate { y: -2 } // the fan's optical centre is its dot, low in the box
            preferredRendererType: Shape.CurveRenderer
            readonly property color ink: root.wifi?.connected ? Theme.fg : Theme.grey
            ShapePath {
                strokeColor: wf.ink; strokeWidth: 2.2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                PathAngleArc { centerX: 10; centerY: 15; radiusX: 5.5; radiusY: 5.5; startAngle: 220; sweepAngle: 100 }
                PathAngleArc { centerX: 10; centerY: 15; radiusX: 10.5; radiusY: 10.5; startAngle: 220; sweepAngle: 100 }
            }
            ShapePath {
                strokeColor: Networking.wifiEnabled ? "transparent" : wf.ink; strokeWidth: 2.2; capStyle: ShapePath.RoundCap
                startX: 3; startY: 2
                PathLine { x: 17; y: 17 }
            }
            ShapePath {
                strokeWidth: -1; fillColor: wf.ink
                PathAngleArc { centerX: 10; centerY: 15; radiusX: 1.9; radiusY: 1.9; startAngle: 0; sweepAngle: 360 }
            }
        }
    }
    Component {
        id: btC
        Icon {
            text: Bluetooth.defaultAdapter?.enabled ? "\u{F00AF}" : "\u{F00B2}"
            color: Bluetooth.devices.values.some(d => d.connected) ? Theme.fg : Theme.grey
        }
    }
    Component {
        id: soundC
        Icon {
            text: Sys.muted ? "\u{F075F}" : "\u{F057E}"
            Notch { onNotch: d => Sys.setVol(Sys.vol + d * 0.05) }
        }
    }
    Component {
        id: notesC
        Icon {
            text: Theme.state.dnd ? "\u{F009B}" : "\u{F009A}"
            color: Notes.list.length ? Theme.fg : Theme.grey
        }
    }
    // at the side the battery stands upright, charge grows from the bottom; on top it lies down, growing from the
    // left. Charging -- a bolt first, the fill breathes while charging
    Component {
        id: batC
        Pile {
            id: batc
            spacing: 8
            readonly property bool ac: !UPower.onBattery
            readonly property bool charging: root.bat.state === UPowerDeviceState.Charging
            // breathing at 20 fps, like the orb in home/Back: an animation would drive the bar on every vsync (120 Hz) all the charging
            // hours. Cosine with period 2.2 s -- the same two InOutSine of 1.1 s
            property real phase: 0
            readonly property real pulse: charging ? 0.675 + 0.325 * Math.cos(phase * Math.PI / 1.1) : 1
            Timer { running: batc.charging; interval: 50; repeat: true; onTriggered: batc.phase = (batc.phase + 0.05) % 2.2; onRunningChanged: batc.phase = 0 }
            Icon { visible: batc.ac; text: "\u{F140B}"; font.pixelSize: 14 }
            Rectangle {
                width: root.vert ? 14 : 26
                height: root.vert ? 26 : 14
                radius: 7
                color: "transparent"
                border { width: 1.5; color: Theme.grey }
                Rectangle {
                    x: 3
                    y: parent.height - 3 - height
                    width: root.vert ? parent.width - 6 : (parent.width - 6) * root.bat.percentage
                    height: root.vert ? (parent.height - 6) * root.bat.percentage : parent.height - 6
                    radius: 4
                    color: root.batLow ? Theme.red : Theme.fg
                    opacity: batc.pulse
                }
            }
            // width sized for "100": on top the tray is right-aligned, 99 -> 100 would push everything left.
            // 12px and bold (was 10): the one number on the bar read at a glance, it has to land at a glance
            Lb { width: full.implicitWidth; horizontalAlignment: Text.AlignHCenter; text: Math.round(root.bat.percentage * 100); px: 12; font.bold: true }
            Lb { id: full; visible: false; text: "100"; px: 12; font.bold: true }
        }
    }
    Component { id: modeGap; Item { width: 40; height: 22 } }
    Component {
        id: powerC
        Icon {
            text: "\u{F0425}"
            color: pwr.hovered ? Theme.fg : Theme.grey
            HoverHandler { id: pwr; cursorShape: Qt.PointingHandCursor }
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.powerClicked() }
        }
    }
    // focus: a ring that drains as the timer runs, the remaining time under it in Doto;
    // hover or tap -- the timer card below. The timer itself is the Focus singleton
    // (session-scoped: a shell restart resets it -- Focus.qml says so too)
    Component {
        id: focusC
        Item {
            id: focw
            implicitWidth: focc.implicitWidth
            implicitHeight: focc.implicitHeight
            HoverHandler { onHoveredChanged: { root.focHot = hovered; root.peekF(focw); } Component.onDestruction: root.focHot = false }
            Pile {
                id: focc
                anchors.centerIn: parent
                spacing: 4
                Item {
                    width: 24
                    height: 24
                    Ring { anchors.fill: parent; n: 16; dot: 3; f: Focus.f; on: Focus.running ? Theme.fg : Theme.grey }
                    Icon { anchors.centerIn: parent; text: "\u{F13AB}"; font.pixelSize: 10; color: Theme.grey }
                }
                Num {
                    visible: Focus.running || Focus.paused
                    text: Focus.mmss(Focus.left)
                    font.pixelSize: 10
                    color: Theme.fg
                }
            }
            MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: root.focOpen = !root.focOpen }
        }
    }

    // Battery and performance share one card. Only clicks open it or select a power mode.
    readonly property bool batLow: UPower.onBattery && root.bat.percentage < 0.15
    property Item powerAnchor
    property point popAt
    property bool powOpen: false
    property alias powerAnimationDuration: popMotion.durationOverride
    property int powPeek: -1

    onPowOpenChanged: if (powOpen) Sounds.play("pop")
    onPowerAnchorChanged: if (!powerAnchor) powOpen = false
    function togglePowerCard(item) {
        if (powOpen && powerAnchor === item) {
            powOpen = false;
            return;
        }
        powerAnchor = item;
        popAt = item.mapToItem(pill, item.width, item.height);
        popMotion.origin = popoverOrigin(item);
        powOpen = true;
    }

    // ---- the focus card: the battery card's sibling, same anchoring with its own hover trigger ----
    property bool focHot: false
    property point focAt
    property bool focOpen: false
    readonly property bool focAny: focHot || fpopHov.hovered
    function peekF(it) { if (!fpop.visible) focAt = it.mapToItem(pill, it.width, it.height); }
    onFocAnyChanged: focAny ? focOpenT.restart() : focCloseT.restart()
    Timer { id: focOpenT; interval: 180; onTriggered: if (root.focAny) root.focOpen = true }
    Timer { id: focCloseT; interval: 300; onTriggered: if (!root.focAny) root.focOpen = false }
    function hm(sec) { const m = Math.round(sec / 60); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} m` : `${m} m`; }
    readonly property string batState: root.bat.state === UPowerDeviceState.Charging
        ? "charging" + (root.bat.timeToFull ? ` · full in ${hm(root.bat.timeToFull)}` : "")
        : !UPower.onBattery ? "on ac · full"
        : "on battery" + (root.bat.timeToEmpty ? ` · ${hm(root.bat.timeToEmpty)} left` : "")

    PopoverMotion { id: popMotion; opened: root.powOpen }
    PanelWindow {
        id: pop
        screen: root.screen
        visible: root.powOpen || popMotion.progress > 0
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "galaga-bar-pow"
        WlrLayershell.keyboardFocus: root.powOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        mask: Region { item: root.powOpen ? card : null }
        HyprlandFocusGrab {
            windows: [pop, root]
            active: root.powOpen && pop.visible
            onCleared: if (root.powOpen) root.powOpen = false
        }

        Stage {
            PopoverCard {
                id: card
                motion: popMotion
                unit: Theme.s
                x: root.vert ? 92 : Math.max(14, Math.min(parent.width - width - 14, pill.x + root.popAt.x - width))
                y: root.vert ? Math.max(14, Math.min(parent.height - height - 14, pill.y + root.popAt.y - height)) : 88
                width: Math.min(root.vert ? 440 : 380, parent.width - (root.vert ? 106 : 28))
                Behavior on x {
                    enabled: root.powOpen && popMotion.progress === 1 && popMotion.moving && !root.vert
                    NumberAnimation { duration: 288; easing.type: Easing.OutCubic }
                }
                height: body.height + 52
                transform: Translate { x: root.vert ? -16 * (1 - popMotion.progress) : 0 }
                focus: true
                Keys.onEscapePressed: root.powOpen = false

                Column {
                    id: body
                    x: 26
                    y: 26
                    width: parent.width - 52
                    spacing: 18

                    Row {
                        id: chargeRow
                        width: body.width
                        spacing: 14
                        Num {
                            id: charge
                            text: Math.round(root.bat.percentage * 100)
                            font.pixelSize: Math.min(72, chargeRow.width / 3)
                        }
                        Column {
                            width: Math.max(0, chargeRow.width - charge.width - chargeRow.spacing)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Lb { width: parent.width; text: "% battery"; color: Theme.fg }
                            Lb { width: parent.width; text: root.batState; wrapMode: Text.Wrap }
                        }
                    }
                    Seg { width: parent.width; height: 6; n: 24; f: root.bat.percentage; on: root.batLow ? Theme.red : Theme.fg }

                    Lb { topPadding: 6; text: "power mode" }
                    Row {
                        id: modes
                        width: body.width
                        spacing: 8
                        readonly property real cellWidth: (width - (Rules.modeCount - 1) * spacing) / Rules.modeCount
                        Repeater {
                            model: Rules.modeCount
                            Column {
                                id: mo
                                required property int index
                                readonly property bool on: Rules.mode === index
                                width: modes.cellWidth
                                spacing: 10
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(parent.width, root.vert ? 80 : 62)
                                    height: width
                                    radius: width / 2
                                    color: mo.on ? Theme.fg : moHov.hovered ? Theme.s3 : Theme.s2
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                    // ticks: how many are lit -- that much power
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                required property int index
                                                anchors.bottom: parent.bottom
                                                width: 5
                                                height: 8 + index * 6
                                                radius: 2.5
                                                color: index <= mo.index ? (mo.on ? Theme.ink : Theme.fg) : (mo.on ? Theme.mute : Theme.s3)
                                            }
                                        }
                                    }
                                    HoverHandler {
                                        id: moHov
                                        cursorShape: Qt.PointingHandCursor
                                        onHoveredChanged: if (hovered) root.powPeek = mo.index; else if (root.powPeek === mo.index) root.powPeek = -1
                                    }
                                    TapHandler { onTapped: Rules.setMode(mo.index) }
                                }
                                Lb {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    text: mo.index === 3 ? "max" : Rules.modes[mo.index].name
                                    color: mo.on ? Theme.fg : Theme.grey
                                }
                            }
                        }
                    }
                    Lb {
                        readonly property int i: root.powPeek >= 0 ? root.powPeek : Rules.mode
                        width: parent.width
                        elide: Text.ElideRight
                        text: `${Rules.modes[i].what} · ${i === 0 ? Rules.rates[0] : Rules.refreshHz} hz`
                    }
                }
            }
        }
    }

    PopupWindow {
        id: fpop
        property real t: root.focOpen ? 1 : 0
        Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        visible: t > 0
        anchor.item: pill
        anchor.rect: root.vert ? Qt.rect(pill.width + 14, root.focAt.y, 1, 1) : Qt.rect(root.focAt.x, pill.height + 14, 1, 1)
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: root.vert ? Edges.Top | Edges.Right : Edges.Bottom | Edges.Left
        implicitWidth: Math.ceil(360 * Theme.s)
        implicitHeight: Math.ceil(fcard.height * Theme.s)
        color: "transparent"

        Stage {
            Rectangle {
                id: fcard
                width: 360
                height: fbody.height + 52
                radius: Theme.corner(36)
                color: Theme.s1
                border { width: 1; color: Theme.s2 }
                opacity: fpop.t
                transform: Translate { x: root.vert ? -16 * (1 - fpop.t) : 0; y: root.vert ? 0 : -16 * (1 - fpop.t) }
                HoverHandler { id: fpopHov }

                Column {
                    id: fbody
                    x: 26
                    y: 26
                    width: parent.width - 52
                    spacing: 16

                    Row {
                        spacing: 14
                        Num { text: Focus.mmss(Focus.left); font.pixelSize: 44 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Lb { text: "focus"; color: Theme.fg }
                            Lb { text: Focus.running ? "running" : Focus.paused ? "paused" : "ready" }
                        }
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [15, 25, 45, 60]
                            Rectangle {
                                id: fp
                                required property int modelData
                                width: 56
                                height: 40
                                radius: 20
                                color: Focus.minutes === modelData ? Theme.fg : Theme.s2
                                Behavior on color { ColorAnimation { duration: Theme.t } }
                                Lb { anchors.centerIn: parent; text: fp.modelData + "m"; color: Focus.minutes === fp.modelData ? Theme.ink : Theme.fg }
                                TapHandler { onTapped: Focus.set(fp.modelData) }
                            }
                        }
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: Theme.s2
                            Lb { anchors.centerIn: parent; text: "−5"; color: Theme.fg }
                            TapHandler { onTapped: Focus.set(Math.max(1, Focus.minutes - 5)) }
                        }
                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: Theme.s2
                            Lb { anchors.centerIn: parent; text: "+5"; color: Theme.fg }
                            TapHandler { onTapped: Focus.set(Math.min(240, Focus.minutes + 5)) }
                        }
                    }
                    Row {
                        spacing: 10
                        Rectangle {
                            width: 150
                            height: 46
                            radius: 23
                            color: Theme.fg
                            Lb { anchors.centerIn: parent; text: Focus.running ? "pause" : Focus.paused ? "resume" : "start"; color: Theme.ink }
                            TapHandler { onTapped: Focus.toggle() }
                        }
                        Rectangle {
                            width: 110
                            height: 46
                            radius: 23
                            color: Theme.s2
                            Lb { anchors.centerIn: parent; text: "reset"; color: Theme.fg }
                            TapHandler { onTapped: Focus.reset() }
                        }
                    }
                }
            }
        }
    }
}
