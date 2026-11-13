import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components
import qs.services
import qs.settings

// displays: the screens as hypr placed them (click or left/right -- choose);
// everything below is the chosen one's: brightness (the built-in's), logical
// px, scale and hz, bar and home on it. Night light -- on all. (The home page
// keeps its own screen pick; each page remembers its.)
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    property string pickMon
    readonly property var names: Quickshell.screens.map(s => s.name)
    readonly property string mon: names.includes(pickMon) ? pickMon : names[0] ?? ""
    readonly property bool multi: names.length > 1
    onActiveChanged: if (active) pickMon = Hyprland.focusedMonitor?.name ?? pickMon

    readonly property var m: Rules.mons.find(x => x.name === pg.mon) ?? Rules.mon
    readonly property var w: Rules.want(m)

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
                SetHead { text: "screens" }
                Lb { text: `${pg.m.name.toLowerCase()} · ${pg.m.w} × ${pg.m.h} · ${pg.m.hz} hz`; px: 11; color: Theme.mute }
                Item {
                    id: map
                    readonly property var ms: Rules.mons
                    // a screen is held: at -- where it will land (logical px); kept there until hypr answers with new monitors
                    property string held: ""
                    property var at: null
                    onMsChanged: held = ""
                    readonly property real x0: Math.min(...ms.map(m => m.x))
                    readonly property real y0: Math.min(...ms.map(m => m.y))
                    readonly property real bw: Math.max(...ms.map(m => m.x + m.lw)) - x0
                    readonly property real bh: Math.max(...ms.map(m => m.y + m.lh)) - y0
                    readonly property real k: Math.min(width / bw, height / bh)
                    width: 560
                    height: 320
                    activeFocusOnTab: true
                    Keys.onPressed: e => {
                        const d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0, n = pg.names.length;
                        if (!d || !n) return;
                        pg.pickMon = pg.names[(pg.names.indexOf(pg.mon) + d + n) % n];
                        e.accepted = true;
                    }
                    Repeater {
                        model: map.ms
                        Rectangle {
                            id: sc
                            required property var modelData
                            readonly property bool on: modelData.name === pg.mon
                            readonly property var p: map.held === modelData.name && map.at ? map.at : modelData
                            x: (map.width - map.bw * map.k) / 2 + (p.x - map.x0) * map.k + 5
                            y: (map.height - map.bh * map.k) / 2 + (p.y - map.y0) * map.k + 5
                            z: map.held === modelData.name ? 1 : 0
                            width: modelData.lw * map.k - 10
                            height: modelData.lh * map.k - 10
                            radius: Theme.corner(18)
                            color: Theme.bg
                            border { width: sc.on && map.activeFocus ? 2 : 1; color: sc.on ? Theme.fg : Theme.s3 }
                            Behavior on border.color { ColorAnimation { duration: Theme.t } }
                            Image {
                                anchors { fill: parent; margins: 12 }
                                fillMode: Image.Tile
                                source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><circle cx="5" cy="5" r="1.5" fill="#${Theme.hex(sc.on ? Theme.mute : Theme.s2)}"/></svg>`)
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: sc.modelData.name; color: sc.on ? Theme.fg : Theme.grey }
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: `${sc.modelData.w} × ${sc.modelData.h}`; px: 10 }
                            }
                            TapHandler {
                                onTapped: {
                                    pg.pickMon = sc.modelData.name;
                                    map.forceActiveFocus();
                                }
                            }
                            HoverHandler { cursorShape: pg.multi ? Qt.OpenHandCursor : Qt.PointingHandCursor }
                            // drag -- it docks flush to a neighbour (Rules.dock); dropped -- Rules.place. While hypr has
                            // not answered the last drop it does not drag: the math would run from stale places
                            DragHandler {
                                target: null
                                enabled: pg.multi && (!map.held || active)
                                cursorShape: Qt.ClosedHandCursor
                                onActiveTranslationChanged: {
                                    if (!active) return;
                                    const m = sc.modelData;
                                    map.at = Rules.dock({ x: m.x + activeTranslation.x / map.k, y: m.y + activeTranslation.y / map.k, w: m.lw, h: m.lh },
                                                       map.ms.filter(o => o.name !== m.name), 16 / map.k);
                                }
                                onActiveChanged: {
                                    const m = sc.modelData;
                                    if (active) {
                                        pg.pickMon = m.name;
                                        map.at = null;
                                        map.held = m.name;
                                        return;
                                    }
                                    if (map.at && (map.at.x !== m.x || map.at.y !== m.y)) Rules.place(m.name, map.at.x, map.at.y);
                                    else map.held = "";
                                }
                            }
                        }
                    }
                }
                Row {
                    spacing: 14
                    Num { id: resW; text: pg.m.lw; font.pixelSize: 54 }
                    Num { anchors.baseline: resW.baseline; text: "×"; font.pixelSize: 30; color: Theme.mute }
                    Num { anchors.baseline: resW.baseline; text: pg.m.lh; font.pixelSize: 54 }
                    Lb { anchors.baseline: resW.baseline; leftPadding: 10; text: "logical pixels"; px: 11 }
                }
            }

            // backlight -- the built-in's; externals over DDC -- no (services/Backlight)
            Column {
                visible: Sys.hasBri && pg.m.name === Rules.mon.name
                width: parent.width
                spacing: 10
                SetHead { text: "brightness" }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 30
                        Dial { size: 220; n: 60; live: true; label: "brightness"; value: Math.round(Sys.bri * 100); onMoved: v => Sys.setBri(v / 100) }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Lb { text: "the brightness keys' step"; px: 11; color: Theme.mute }
                            Item {
                                width: 260
                                height: 48
                                SetPick {
                                    opts: ["2.5%", "5%", "10%"]
                                    cur: [40, 20, 10].indexOf(Theme.state.briSteps)
                                    divider: false
                                    onPicked: i => Theme.state.briSteps = [40, 20, 10][i]
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "screen" }
                SetCard {
                    SetPick {
                        label: "scale"
                        opts: Rules.scales
                        cur: pg.w.scale ? Rules.scales.indexOf(String(pg.w.scale)) : 0
                        onPicked: i => Rules.set(pg.m.name, "scale", i ? +Rules.scales[i] : 0)
                    }
                    SetPick {
                        label: "hz"
                        seg: Math.min(90, 560 / Math.max(1, pg.m.rates.length))
                        opts: pg.m.rates.map(String)
                        cur: pg.m.rates.indexOf(pg.w.refresh)
                        divider: false
                        onPicked: i => Rules.set(pg.m.name, "refresh", pg.m.rates[i])
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "on this screen" }
                SetCard {
                    SetToggle { label: "bar"; on: Theme.scr(pg.mon, "bar"); onFlip: want => Theme.setScr(pg.mon, "bar", want) }
                    SetToggle { label: "home"; on: Theme.scr(pg.mon, "home"); onFlip: want => Theme.setScr(pg.mon, "home", want) }
                    SetRow {
                        visible: Object.keys(Rules.store.outs).length > 0
                        label: "hypr config"
                        sub: "forget the externals' own places, scales and rates"
                        divider: false
                        SetButton { label: "forget"; onHit: Rules.forget() }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "arrange" }
                SetCard {
                    SetToggle {
                        label: "arrange screens"
                        on: Rules.store.manageMonitor
                        divider: false
                        onFlip: want => { Rules.store.manageMonitor = want; if (want) Rules.monitor(true); }
                    }
                    Lb {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 10
                        px: 10.5
                        color: Theme.mute
                        text: "off — monitors stay in your hypr config (a rotated screen, a hand-built layout)"
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "night light" }
                SetCard {
                    SetToggle { label: "night light"; on: Sys.night; onFlip: want => Sys.toggleNight() }
                    Row {
                        topPadding: 8
                        Dial { label: "warmth · k · all screens"; from: 2500; to: 6500; step: 100; value: Rules.store.warmth; onMoved: v => { Rules.store.warmth = v; if (Rules.store.night) Rules.night(); } }
                    }
                }
            }
        }
    }
}
