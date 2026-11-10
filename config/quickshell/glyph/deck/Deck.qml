import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// deck: dashboard at the bottom center, like caelestia, only from under the bottom edge. Cursor at the edge (2 px strip) for 150 ms --
// the panel slides out, left it -- hides after 300 ms. Sections -- Theme.state.deck in order (ids from Theme.decks), in columns.
// No scrim or keyboard: peek and leave. A window on each screen, no more than one open
Scope {
    id: root

    property var on: null // the screen where it is open
    function toggle() { on = on ? null : Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]; }

    // "min" (minimised windows) is a fixed section at the right end: a state file saved before
    // it existed does not list it, so it is appended when missing rather than staying invisible
    readonly property var ids: { const l = Theme.state.deck.filter(id => Theme.decks.includes(id)); if (!l.includes("min")) l.push("min"); return l; }
    readonly property int h: 232 // section height in layout pixels

    // open -- detailed polling (detailed is set by Home via deckOpen) and processes with frequency
    Binding { target: Sys; property: "deckOpen"; value: root.on !== null }
    Binding { target: SysStats; property: "perf"; value: root.on !== null }

    // opening re-syncs the window model, or a window parked before the deck first
    // opened can take minutes to show in the minimised section: Quickshell's
    // movewindow handler resolves the destination workspace WITHOUT creating it,
    // and the special:minimized workspace only enters the model through a full
    // refresh (its createworkspace event is parsed as an int id, which a special
    // workspace's name does not survive) -- so a park the event path dropped sits
    // in the model with its old workspace until something unrelated refreshes it.
    // refreshToplevels() re-reads the client list and resolves every window's
    // workspace with creation on: the dropped park lands immediately.
    onOnChanged: if (on !== null) Hyprland.refreshToplevels()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var en: Qt.locale("en_US")
    function hm(d) { return Qt.formatTime(d, Theme.state.clock24 ? "hh:mm" : "h:mm ap"); }
    function week(d) { // ISO week, as in Home
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
    }

    // network history -- matrix columns, [rx, tx]. Own tick on the same cadence SysStats writes rx/tx
    // (Theme.statsMs): 20 columns span 40 s at full, longer when the shell performance level stretches it
    property var net: []
    Timer { running: root.on !== null; interval: Theme.statsMs; repeat: true; onTriggered: root.net = root.net.concat([[SysStats.rx, SysStats.tx]]).slice(-20) }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool open: root.on === modelData
            property real t: open ? 1 : 0
            Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

            screen: modelData
            // in fullscreen Top is not drawn, Qt stops committing frames and a layer
            // change is never seen by Hyprland -- so there is no strip there, and
            // Super+Space creates the window anew, already in Overlay.
            // hasFullscreen covers maximized too (Super+Alt+F): the edge is silent there as well
            visible: Theme.state.deckHover && root.ids.length > 0 && !Hyprland.monitorFor(modelData)?.activeWorkspace?.hasFullscreen || t > 0
            anchors.bottom: true
            implicitWidth: Math.ceil(panel.width * Theme.s)
            implicitHeight: Math.ceil((panel.height + 14) * Theme.s)
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // closed -- Top: the Glyph progress strip draws over it; open -- Overlay, visible above a fullscreen window too
            WlrLayershell.layer: t > 0 ? WlrLayer.Overlay : WlrLayer.Top
            WlrLayershell.namespace: "glyph-deck"
            // closed -- the mouse is caught only by the strip at the edge (screen corners are free), open -- the whole window including the gap under the panel
            mask: Region { y: win.open ? 0 : win.height - 2; width: win.width; height: win.open ? win.height : 2 }

            Timer { id: dwell; interval: 150; onTriggered: root.on = win.modelData }
            Timer { id: leave; interval: 300; onTriggered: if (win.open) root.on = null }

            Stage {
                // strip and panel -- one window: the cursor does not jump between surfaces, hovered does not blink
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            leave.stop();
                            if (!win.open && Theme.state.deckHover) dwell.restart();
                        } else {
                            dwell.stop();
                            if (win.open) leave.restart();
                        }
                    }
                }

                Rectangle {
                    id: panel
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (1 - win.t) * (height + 14) // slides out from under the edge
                    width: row.width + 52
                    height: root.h + 52
                    opacity: win.t // not visible: a hidden Row has width 0, and the window is measured by it
                    radius: Theme.corner(40)
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }

                    Row {
                        id: row
                        x: 26
                        y: 26
                        spacing: 16
                        Repeater {
                            model: root.ids
                            Row {
                                id: cell
                                required property string modelData
                                required property int index
                                spacing: 16
                                // between sections -- a column of dots, the minimised section included
                                Image {
                                    visible: cell.index > 0
                                    width: 4
                                    height: root.h
                                    fillMode: Image.TileVertically
                                    source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="4" height="10"><circle cx="2" cy="5" r="1.5" fill="#${Theme.hex(Theme.s3)}"/></svg>`)
                                }
                                Loader { sourceComponent: ({ clock: clockC, weather: weatherC, perf: perfC, net: netC, media: mediaC, min: minC })[cell.modelData] }
                            }
                        }
                    }
                }
            }

            // clock, date, week; daylight as segments from sunrise to sunset
            Component {
                id: clockC
                Column {
                    width: 216
                    Lb { text: root.en.dayName(clock.date.getDay()) + (Theme.state.clock24 ? "" : clock.date.getHours() < 12 ? " · am" : " · pm") }
                    Num {
                        topPadding: lead + 10
                        text: Theme.state.clock24 ? Qt.formatTime(clock.date, "hh:mm") : (clock.date.getHours() % 12 || 12) + Qt.formatTime(clock.date, ":mm")
                        font.pixelSize: 72
                    }
                    Lb { topPadding: 12; text: `${root.en.toString(clock.date, "d MMMM")} · week ${root.week(clock.date)}` }
                    Item { width: 1; height: 24 }
                    Seg { width: parent.width; height: 6; n: 24; f: Weather.sun ? (clock.date - Weather.sun.rise) / (Weather.sun.set - Weather.sun.rise) : 0 }
                    Item {
                        width: parent.width
                        height: 28
                        Meta { y: 12; icon: "\u{F059C}"; text: Weather.sun ? root.hm(Weather.sun.rise) : "--:--" }
                        Meta { y: 12; anchors.right: parent.right; icon: "\u{F059B}"; text: Weather.sun ? root.hm(Weather.sun.set) : "--:--" }
                    }
                }
            }

            // now large and four days ahead, glyphs through a dot mask
            Component {
                id: weatherC
                Column {
                    width: 188
                    Lb { width: parent.width; elide: Text.ElideRight; text: Weather.ok ? Weather.name(Weather.now.code) : "no sky" }
                    Item { width: 1; height: 10 }
                    Row {
                        spacing: 8
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.glyph(Weather.now?.code ?? 3, Weather.now?.day)
                            font.pixelSize: 48
                            layer.enabled: true
                            layer.effect: Dm { step: 3 }
                        }
                        Num { anchors.verticalCenter: parent.verticalCenter; text: Weather.ok ? Math.round(Weather.now.temp) + "°" : "--"; font.pixelSize: 54 }
                    }
                    Lb { topPadding: 8; visible: Weather.ok; text: `feels ${Math.round(Weather.now?.feels)}° · ${Math.round(Weather.now?.wind)} m/s`; px: 11 }
                    Item { width: 1; height: 18 }
                    Row {
                        spacing: 8
                        Repeater {
                            model: Weather.days.slice(1, 5)
                            Column {
                                required property var modelData
                                required property int index
                                width: 41
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: root.en.dayName((clock.date.getDay() + index + 1) % 7, Locale.ShortFormat); px: 10 }
                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    topPadding: lead + 6
                                    text: Weather.glyph(modelData.code, true)
                                    font.pixelSize: 24
                                    layer.enabled: true
                                    layer.effect: Dm { step: 2 }
                                }
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; topPadding: 6; text: Math.round(modelData.max) + "°"; px: 11; color: Theme.fg }
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.min) + "°"; px: 11 }
                            }
                        }
                    }
                }
            }

            // cpu/mem/gpu rings with temperatures, top processes as segments, cores as a matrix
            Component {
                id: perfC
                Column {
                    width: 300
                    Row {
                        id: gauges
                        spacing: 18
                        Gauge { on: win.open; f: SysStats.cpu; label: `cpu · ${Math.round(SysStats.cpuTemp)}°` }
                        Gauge { on: win.open; f: SysStats.mem; label: `mem · ${SysStats.memUsed.toFixed(1)}g` }
                        Gauge { on: win.open; f: SysStats.gpu; label: `gpu · ${Math.round(SysStats.gpuTemp)}°` }
                    }
                    Item { width: 1; height: 18 }
                    Row {
                        spacing: 14
                        // the section is root.h tall (the panel is sized by it, not by content):
                        // this row gets what the gauges and the spacer leave, no more
                        height: root.h - gauges.height - 18
                        Column {
                            width: 160
                            spacing: 4
                            Lb { bottomPadding: 2; text: "processes"; px: 10 }
                            Repeater {
                                model: SysStats.procs
                                Row {
                                    required property var modelData
                                    spacing: 6
                                    Lb { width: 78; elide: Text.ElideRight; text: modelData[0]; px: 10; color: Theme.fg }
                                    Lb { width: 34; horizontalAlignment: Text.AlignRight; text: Math.round(modelData[1]) + "%"; px: 10 }
                                    Seg { anchors.verticalCenter: parent.verticalCenter; width: 36; height: 5; n: 6; spacing: 3; f: modelData[1] / 100 }
                                }
                            }
                        }
                        Column {
                            width: 126
                            height: parent.height
                            spacing: 6
                            Lb { id: coresLabel; text: `cores · ${SysStats.cpuFreq.toFixed(1)} ghz`; px: 10 }
                            // column per core: top dot white, below it grey -- like the cpu graph in Home
                            Grid {
                                id: cores
                                anchors.horizontalCenter: parent.horizontalCenter
                                readonly property int n: Math.max(1, SysStats.cores.length)
                                // the cell has to fit both ways: 8 rows are fixed, so on a machine with
                                // few cores the width alone would make the grid taller than this column
                                // (8 * d + 7 * spacing) and it would spill out of the panel -- cap d by
                                // the height the column actually has, the width wins when cores are many
                                readonly property real d: Math.min((width - (n - 1) * spacing) / n, (height - 7 * spacing) / 8)
                                width: parent.width
                                height: parent.height - coresLabel.height - parent.spacing
                                columns: n
                                spacing: 3
                                Repeater {
                                    model: cores.n * 8
                                    Rectangle {
                                        required property int index
                                        readonly property int up: 8 - Math.floor(index / cores.n) // 8 at the top ... 1 at the bottom
                                        readonly property int lvl: Math.round(1 + 7 * (SysStats.cores[index % cores.n] ?? 0))
                                        width: cores.d
                                        height: cores.d
                                        radius: cores.d / 2
                                        color: up === lvl ? Theme.fg : up < lvl ? Theme.grey : Theme.s2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // receive/send Doto and 40 s matrix: receive grows up from the middle, send (grey) -- down
            Component {
                id: netC
                Column {
                    width: 176
                    Lb { width: parent.width; elide: Text.ElideRight; text: "net · " + (SysStats.iface || "offline") }
                    Item { width: 1; height: 10 }
                    Speed { icon: "\u{F0045}"; b: SysStats.rx }
                    Item { width: 1; height: 8 }
                    Speed { icon: "\u{F005D}"; b: SysStats.tx }
                    Item { width: 1; height: 18 }
                    Grid {
                        id: hist
                        // scale -- window peak, but not less than 10 kb/s: silence does not draw noise
                        readonly property real peak: Math.max(10240, ...root.net.map(p => Math.max(p[0], p[1])))
                        readonly property real d: (width - 19 * spacing) / 20
                        width: parent.width
                        columns: 20
                        spacing: 3
                        Repeater {
                            model: 20 * 10
                            Rectangle {
                                required property int index
                                readonly property int r: Math.floor(index / 20) // 0...9 top to bottom
                                readonly property bool tx: r >= 5
                                readonly property var p: root.net[index % 20 - 20 + root.net.length] ?? [0, 0]
                                readonly property bool lit: (tx ? r - 4 : 5 - r) <= Math.ceil(5 * (tx ? p[1] : p[0]) / hist.peak)
                                width: hist.d
                                height: hist.d
                                radius: hist.d / 2
                                color: lit ? (tx ? Theme.grey : Theme.fg) : Theme.s2
                            }
                        }
                    }
                }
            }

            // player: cover as dots spins while playing and deck is open
            Component {
                id: mediaC
                Column {
                    width: 240
                    Lb { width: parent.width; elide: Text.ElideRight; text: Media.player?.identity ?? "silence" }
                    Item { width: 1; height: 12 }
                    Row {
                        spacing: 14
                        Item {
                            id: art
                            width: 84
                            height: 84
                            property real turn: 0
                            Timer { running: win.open && Media.playing && !Theme.perfLite; interval: 33; repeat: true; onTriggered: art.turn = (art.turn + 360 / 14 / 30) % 360 }
                            Art { anchors.fill: parent; rotation: art.turn; url: Media.player?.trackArtUrl ?? ""; step: 5 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 142
                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: Media.player?.trackTitle || "Nothing on"
                                textFormat: Text.PlainText
                                font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                                color: Theme.fg
                            }
                            Text { textFormat: Text.PlainText; width: parent.width; elide: Text.ElideRight; text: Media.player?.trackArtist ?? ""; font { family: Theme.ui; pixelSize: 13 } color: Theme.grey }
                        }
                    }
                    Item { width: 1; height: 16 }
                    // firefox does not send length
                    Seg { width: parent.width; height: 6; n: 20; f: Media.player?.lengthSupported && Media.player.length > 0 ? Media.position / Media.player.length : 0 }
                    Item {
                        width: parent.width
                        height: 26
                        visible: !!Media.player
                        Lb { y: 8; text: Media.time(Media.position); px: 11 }
                        Lb { y: 8; anchors.right: parent.right; visible: !!Media.player?.lengthSupported; text: Media.time(Media.player?.length); px: 11 }
                    }
                    Item { width: 1; height: 8 }
                    Controls { anchors.horizontalCenter: parent.horizontalCenter; size: 20; play: 48 }
                }
            }

            // minimised windows (parked on special:minimized by the white title-bar button /
            // Super+Alt+M): icon + name; click brings the window back to the current
            // workspace, right-click opens a small menu over the row (Restore / Close).
            // Membership reads the toplevel's typed workspace property: Quickshell updates it
            // on every movewindow event, so this binding re-evaluates as windows park and
            // return. Do NOT read the workspace out of lastIpcObject -- that is a snapshot
            // from the last j/clients fetch (shell start / config reload) and never changes
            // when a window moves, which left this section permanently empty. The class still
            // comes from lastIpcObject: it never changes during a window's life, and the
            // launcher's windows mode reads it the same way. Icons resolve like the
            // launcher's (DesktopEntries heuristic).
            Component {
                id: minC
                Item {
                    id: minSec
                    width: 184
                    height: root.h

                    // right-click menu state: which parked window it acts on, and how
                    // far down the section it opens (kept inside the section)
                    property string menuAddr: ""
                    property real menuY: 0
                    // the deck closing takes the menu with it
                    readonly property bool deckOpen: win.open
                    onDeckOpenChanged: if (!deckOpen) menuAddr = ""
                    function openMenu(addr, y) {
                        menuAddr = addr;
                        menuY = Math.max(0, Math.min(y, root.h - 78));
                    }

                    Column {
                        id: minCol
                        width: parent.width
                        spacing: 8
                        Lb { id: minLabel; text: minCol.mins.length > 0 ? `minimised · ${minCol.mins.length}` : "minimised"; px: 10 }
                        readonly property var mins: Hyprland.toplevels.values
                            .filter(t => t.workspace?.name === "special:minimized")
                            .map(t => {
                                const cls = t.lastIpcObject?.class ?? "";
                                const icon = DesktopEntries.heuristicLookup(cls)?.icon;
                                return { name: t.title || cls, src: icon ? Quickshell.iconPath(icon, true) : "", addr: t.address };
                            })
                        // the exact inverse of the park in titlebars.lua, plus follow: the window
                        // lands on the workspace you are looking at, focused. The workspace is a
                        // STRING selector, like every other dispatch in this shell (the bar's
                        // workspace switch, the launcher's focus, the park itself): the bare
                        // number was the one form no other call site sends, and the click died
                        // silently with it -- a rejected dispatch only ever logs. The deck
                        // closes on restore: the window coming back is the result, it is
                        // what you should see. The address takes the 0x form: Quickshell's
                        // toplevel address is bare hex, Hyprland's address: selector wants
                        // the prefix -- without it the dispatch matches nothing and fails
                        // silently (the launcher's focus learned this first; these two call
                        // sites never got the memo, so restore and close both died here).
                        function restore(addr) {
                            const ws = Hyprland.focusedWorkspace;
                            minSec.menuAddr = "";
                            if (ws) {
                                // the genie gets first refusal (FEATURES -> genie restore): it kept the
                                // park-time snapshot and expands it back into the live window, doing its
                                // own move. False -- nothing kept for this window -- the plain restore
                                // below runs, byte-identical to before
                                if (Theme.state.featGenieBack && GenieLink.handler && GenieLink.handler(addr, ws.id)) {
                                    root.on = null;
                                    return;
                                }
                                Hyprland.dispatch(`hl.dsp.window.move({ window = "address:0x${addr}", workspace = "${ws.id}", follow = true })`);
                                root.on = null;
                            }
                        }
                        function closeWin(addr) {
                            minSec.menuAddr = "";
                            if (GenieLink.drop) GenieLink.drop(addr); // its kept snapshot goes with it
                            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:0x${addr}" })`);
                        }
                        ListView {
                            id: minList
                            visible: minCol.mins.length > 0
                            width: parent.width
                            height: root.h - minLabel.height - minCol.spacing // the rest of the section height
                            clip: true
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            model: minCol.mins
                            // rows fade in as windows park; on the way out (restore
                            // from the menu, close) they fade and collapse, and
                            // the rows below glide up into the gap
                            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic } }
                            remove: Transition {
                                NumberAnimation { property: "opacity"; to: 0; duration: 150; easing.type: Easing.InCubic }
                                NumberAnimation { property: "height"; to: 0; duration: 150; easing.type: Easing.InCubic }
                            }
                            displaced: Transition { NumberAnimation { properties: "x,y"; duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            delegate: Rectangle {
                                id: minRow
                                required property var modelData
                                width: minList.width
                                height: 30
                                radius: 10
                                color: hov.hovered ? Theme.s2 : "transparent"
                                Row {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Item {
                                        width: 18
                                        height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        Image { anchors.fill: parent; source: modelData.src; visible: !!modelData.src; sourceSize: Qt.size(18, 18) }
                                        Rectangle { visible: !modelData.src; anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: Theme.s3 }
                                    }
                                    Lb { width: minList.width - 42; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; px: 11; color: Theme.fg }
                                }
                                HoverHandler { id: hov }
                                // TapHandlers, one per button -- the input pattern of every
                                // other row in this shell (launcher cells, clipboard entries,
                                // quick notifications), and the one this row shipped with.
                                // A MouseArea in a ListView delegate was tried instead and
                                // its clicks never arrived: the view's own press handling
                                // and a MouseArea fight over the press, while pointer
                                // handlers negotiate the grab with the view instead of
                                // competing for it. Each handler owns exactly one button,
                                // so neither can shadow the other.
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: minCol.restore(modelData.addr)
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: {
                                        const p = minRow.mapToItem(minSec, 0, 0);
                                        minSec.openMenu(modelData.addr, p.y + minRow.height + 2);
                                    }
                                }
                            }
                        }
                        // nothing parked: the box stays, quietly labelled in dots -- never a blank gap
                        Column {
                            visible: minCol.mins.length === 0
                            width: parent.width
                            Item { width: 1; height: 30 }
                            Num { anchors.horizontalCenter: parent.horizontalCenter; text: "nothing"; font.pixelSize: 26; color: Theme.grey }
                            Num { anchors.horizontalCenter: parent.horizontalCenter; text: "minimised"; font.pixelSize: 26; color: Theme.grey }
                        }
                    }

                    // a click anywhere else in the section closes the menu (and is
                    // eaten -- it was aimed at the menu, not at what sits under it)
                    MouseArea {
                        anchors.fill: parent
                        visible: minSec.menuAddr !== ""
                        z: 5
                        onClicked: minSec.menuAddr = ""
                    }
                    // the menu, in the panel's own language: an s2 card, rows light
                    // up s3. Restore is the left-click action; Close closes the
                    // window by address (its row then leaves the list live)
                    Rectangle {
                        visible: minSec.menuAddr !== ""
                        x: 0
                        y: minSec.menuY
                        z: 6
                        width: 184
                        height: 72
                        radius: Theme.corner(14)
                        color: Theme.s2
                        border { width: 1; color: Theme.s3 }
                        Column {
                            anchors { fill: parent; margins: 4 }
                            Rectangle {
                                width: parent.width
                                height: 32
                                radius: 10
                                color: rHov.hovered ? Theme.s3 : "transparent"
                                Lb { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Restore"; px: 11; color: Theme.fg }
                                HoverHandler { id: rHov }
                                TapHandler { onTapped: minCol.restore(minSec.menuAddr) }
                            }
                            Rectangle {
                                width: parent.width
                                height: 32
                                radius: 10
                                color: cHov.hovered ? Theme.s3 : "transparent"
                                Lb { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Close"; px: 11; color: Theme.fg }
                                HoverHandler { id: cHov }
                                TapHandler { onTapped: minCol.closeWin(minSec.menuAddr) }
                            }
                        }
                    }
                }
            }
        }
    }

    // ring with a number inside and a label; on -- dots light up in a wave on open
    component Gauge: Column {
        id: g
        property real f
        property bool on
        property string label
        spacing: 8
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88
            height: 88
            Ring { anchors.fill: parent; n: 32; dot: 4; f: g.on ? g.f : 0 }
            Num { anchors.centerIn: parent; text: Math.round(g.f * 100); font.pixelSize: 30 }
        }
        Lb { anchors.horizontalCenter: parent.horizontalCenter; text: g.label; px: 10 }
    }
    // speed: arrow, Doto number, unit as a label
    component Speed: Row {
        id: sp
        property string icon
        property real b
        readonly property var v: SysStats.rate(b).split(" ")
        spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; text: sp.icon; font.pixelSize: 18 }
        Num { anchors.verticalCenter: parent.verticalCenter; text: sp.v[0]; font.pixelSize: 44 }
        Lb { anchors.verticalCenter: parent.verticalCenter; text: sp.v[1]; px: 11 }
    }
    component Meta: Row {
        id: m
        property string icon
        property string text
        spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; text: m.icon; font.pixelSize: 16 }
        Lb { anchors.verticalCenter: parent.verticalCenter; text: m.text; px: 11 }
    }
}
