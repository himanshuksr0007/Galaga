import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services
import qs.settings

// galaga settings: Super+I. Not a form but objects. On the left a column of Doto words, as in the power menu -- the selected one large, with a red
// dot. On the right the section live: home -- a 3 x 3 bento mockup, deck -- a screen with a panel at the edge, windows -- a desktop with gaps,
// idle -- a minute scale along which the screen dims. Numbers -- rings of dots (drag around, wheel), toggles -- pills,
// where white slides in. Up/down -- sections, Tab -- between objects, left/right -- change, esc -- close.
// Everything applied immediately: Theme.state (galaga.json) and Rules.store (rules.json, shared with demonshot) + the needed apply.
// Gaps/border/blur/shadows -- via Theme.apply: Rules.windows() would give windows the demonshot look
PanelWindow {
    id: root

    property int sel: 0
    signal wallRequested // wallpapers -- their own screen (wall/Walls), opened by shell.qml
    readonly property var sections: ["HOME", "DECK", "BAR", "LOOK", "STYLE", "LOCK", "WINDOWS", "DISPLAY", "AUDIO", "INPUT", "IDLE", "SHELL", "FEATURES", "ESSENTIAL", "DESKTOPS"]
    readonly property string moves: "shift ←→ move · ↵ swap · del drop · drag"
    readonly property string rings: "drag round the rings · scroll"
    readonly property var hints: [moves, moves, moves, "", "hover to preview · ↵ or click sets it · click a colour to change it", "the face they meet first", rings, "drag a screen to move it · " + rings, "click or ←→ a device", rings, "drag the marks", "", "", "click picks who gets through", ""]
    readonly property var r: Rules.store

    // glyphs for home views, deck sections and the bar tray
    readonly property var icons: ({
        weather: "\u{F0595}", calendar: "\u{F00ED}", cpu: "\u{F061A}", ram: "\u{F035B}", gpu: "\u{F08AE}", disk: "\u{F02CA}",
        battery: "\u{F0079}", buds: "\u{F02CB}", player: "\u{F040A}", system: "\u{F0128}", cat: "\u{F011B}", cava: "\u{F0EA2}",
        clock: "\u{F0150}", perf: "\u{F04C5}", net: "\u{F05A9}", media: "\u{F075A}",
        layout: "\u{F030C}", wifi: "\u{F05A9}", bluetooth: "\u{F00AF}", sound: "\u{F057E}", notes: "\u{F009A}", focus: "\u{F13AB}",
        mode: "\u{F04C5}", power: "\u{F0425}"
    })
    // round home widgets, the rest -- a 40 square. ponytail: ram/gpu/disk/battery -- a guess (rings); Home will decide -- fix it
    readonly property var rounds: ["weather", "cpu", "ram", "gpu", "disk", "battery", "buds", "cava"]

    // ---- opening: its own animation (galaga layers in hypr have no_anim). The section is remembered between openings ----
    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    function open() {
        pickMon = Hyprland.focusedMonitor?.name ?? "";
        shown = true;
        stage.forceActiveFocus();
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    function go(i) {
        sel = (i + sections.length) % sections.length;
        stage.forceActiveFocus(); // focus would be lost in a hidden section
    }

    // the live value of a colour role as a "#hex" string (STYLE's wells and the picker read
    // it): Theme.pal already carries any custom colour on top of the palette
    function liveHex(key) {
        if (key.startsWith("a")) return "#" + Theme.hex(Theme.pal.ansi[Number(key.slice(1))]);
        return "#" + Theme.hex({ fg: Theme.fg, s1: Theme.s1, s2: Theme.s2, s3: Theme.s3, mute: Theme.mute, grey: Theme.grey, bg: Theme.bg, accent: Theme.accent, red: Theme.red }[key] ?? Theme.fg);
    }
    // a colour well was clicked on STYLE: the palette preview steps aside (the picker edits
    // the live colour, not the one under the cursor) and the picker opens on it
    function openPicker(key) {
        tint.hot = null;
        picker.open(key, key.startsWith("a") ? "ansi " + key.slice(1) : key);
    }

    // the screen DISPLAY and HOME configure: on open -- the focused one; unplugged -- the first
    property string pickMon
    readonly property var names: Quickshell.screens.map(s => s.name)
    readonly property string mon: names.includes(pickMon) ? pickMon : names[0] ?? ""
    readonly property bool multi: names.length > 1
    onMonChanged: home.cur = 0 // another screen has its own set -- the cursor from the last one misses

    // ---- id lists in Theme.state: home widgets, deck sections, bar tray. We edit a copy -- JsonAdapter writes the file on assignment.
    // All return a new cursor. Widgets belong to the screen mon: with several screens an edit gives it its own set;
    // until edited -- the shared one ----
    function list(key) { return key === "widgets" ? Theme.scr(mon, "widgets") : Theme.state[key]; }
    function edit(key, f) {
        const a = list(key).slice();
        f(a);
        if (key === "widgets" && (multi || Theme.own(mon)?.widgets)) Theme.setScr(mon, "widgets", a);
        else Theme.state[key] = a;
    }
    function move(key, i, to) {
        if (to < 0 || to >= list(key).length || to === i) return i;
        edit(key, a => a.splice(to, 0, a.splice(i, 1)[0]));
        return to;
    }
    function cut(key, i) {
        const n = list(key).length;
        if (i >= n) return i;
        edit(key, a => a.splice(i, 1));
        return Math.max(0, Math.min(i, n - 2));
    }
    // Enter on the selected one: the next from all that is not there yet. In an empty list -- the first free one
    function cycle(key, i, all) {
        const a = list(key);
        if (all.every(k => a.includes(k))) return i;
        i = Math.min(i, a.length);
        let j = all.indexOf(a[i]);
        do j = (j + 1) % all.length; while (a.includes(all[j]));
        edit(key, b => b[i] = all[j]);
        return i;
    }
    // tray: if present -- remove, if not -- insert after the selected one
    function flip(key, w, cur) {
        const a = list(key), i = a.indexOf(w);
        if (i >= 0) {
            edit(key, b => b.splice(i, 1));
            return Math.max(0, Math.min(i < cur ? cur - 1 : cur, a.length - 2));
        }
        const at = Math.min(cur + 1, a.length);
        edit(key, b => b.splice(at, 0, w));
        return at;
    }
    // list keys in focus: left/right select, shift left/right reorder, Enter/space -- change view, del -- remove. -1 -- not our key
    function nav(e, key, cur, all) {
        const n = list(key).length, d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
        if (d && (e.modifiers & Qt.ShiftModifier)) return move(key, cur, cur + d);
        if (d) return n ? (cur + d + n) % n : 0;
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) return cycle(key, cur, all);
        if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) return cut(key, cur);
        return -1;
    }
    // bento layout, like home (and like grid-auto-flow in the concept): left to right, top to bottom; does not fit in a row -- next row,
    // the hole remains; three rows, beyond that -- skipped
    function pack(ids) {
        let row = 0, col = 0;
        return ids.map((w, i) => {
            const span = Theme.kinds[w] ?? 1;
            if (col + span > 3) {
                row++;
                col = 0;
            }
            const c = { id: w, i, row, col, span, fits: row < 3 };
            col += span;
            return c;
        });
    }

    SystemClock { id: clock; enabled: root.visible; precision: SystemClock.Minutes }
    readonly property string hello: { const h = clock.date.getHours(); return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"; }
    readonly property string who: (Theme.state.name || Quickshell.env("USER")).replace(/&/g, "&amp;").replace(/</g, "&lt;")

    // name and label of the current shell -- from its rice.json (the same one the Rice app draws)
    property var meta: ({})
    FileView { path: Quickshell.shellPath("rice.json"); onLoaded: try { root.meta = JSON.parse(text()); } catch (e) {} }
    // "switch shell" -- only when there is something to choose from: other shells, folders with rice.json nearby (Demon's Shot...)
    property int shells: 1
    Process {
        running: root.visible
        command: [Quickshell.env("HOME") + "/.config/quickshell/rice/rice", "list"]
        stdout: StdioCollector { onStreamFinished: root.shells = text.trim().split("\n").length }
    }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    // on demand with several screens, not exclusive: a click into a window on the other monitor takes the
    // keyboard, a click back returns it. One screen -- exclusive, as before
    WlrLayershell.keyboardFocus: shown ? multi ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-prefs"

    Rectangle {
        anchors.fill: parent
        color: Theme.bg // solid: bright window pieces showed through at 5%
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: stage.forceActiveFocus() } // outside -- only drop focus; esc closes
    }

    Stage {
        id: stage
        opacity: root.t
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.go(root.sel - 1);
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) root.go(root.sel + 1);
            else if (e.key === Qt.Key_Right && stage.activeFocus) stage.nextItemInFocusChain(true)?.forceActiveFocus();
            else if (e.key === Qt.Key_Escape) root.close();
            else return;
            e.accepted = true;
        }

        // sections: selected one large with a red dot (while typing a name, red is the caret, the dot turns white)
        Column {
            x: 150 - 30 * (1 - root.t)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            Repeater {
                model: root.sections
                Row {
                    id: word
                    required property string modelData
                    required property int index
                    readonly property bool on: root.sel === index
                    spacing: 26
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: word.on
                        width: 26
                        height: 26
                        radius: 13
                        color: name.activeFocus ? Theme.fg : Theme.red
                    }
                    Num {
                        text: word.modelData
                        font.pixelSize: word.on ? 112 : 46
                        color: word.on ? Theme.fg : Theme.mute
                        Behavior on font.pixelSize { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                    }
                    TapHandler { onTapped: root.go(word.index) }
                }
            }
        }

        Row {
            x: 150
            anchors { bottom: parent.bottom; bottomMargin: 70 }
            spacing: 34
            Lb { text: "↑↓ section" }
            Lb { text: "tab · ←→ change" }
            Lb { visible: !!text; text: root.hints[root.sel] }
            Lb { text: "esc close"; TapHandler { onTapped: root.close() } }
        }

        // ---- HOME: home at 168/220 scale -- same views, order and layout. Click -- select, another click or Enter -- next view,
        // drag -- take the place of the one you dropped onto. What did not fit in 3 x 3 -- on the right as a pale outline.
        // Several screens -- which one is on top: each has its own set ----
        Page {
            id: home
            k: 0
            caption: `home${root.multi ? ` · ${root.mon.toLowerCase()}${Theme.scr(root.mon, "home") ? "" : " · hidden there, display shows it"}` : ""}`
                + ` · bento 3 × 3 · ${used} of 9 cells`
            readonly property var cells: root.pack(root.list("widgets"))
            readonly property var placed: cells.filter(c => c.fits)
            readonly property var off: cells.filter(c => !c.fits)
            readonly property int used: placed.reduce((a, c) => a + c.span, 0)
            readonly property var cur_: cells[cur] ?? null
            property int cur: 0

            function tap(i) {
                grid.forceActiveFocus();
                cur = cur === i ? root.cycle("widgets", i, Object.keys(Theme.kinds)) : i;
            }
            // dropped at grid point p: on a widget -- its place, in an empty cell -- after the last one before it; outside the grid -- nothing
            function land(i, p) {
                if (p.x < 0 || p.y < 0 || p.x > grid.width || p.y > grid.height) return;
                const at = Math.min(2, Math.floor(p.y / 184)) * 3 + Math.min(2, Math.floor(p.x / 184));
                const hit = placed.find(c => c.row * 3 + c.col <= at && at < c.row * 3 + c.col + c.span);
                const n = placed.filter(c => c.row * 3 + c.col < at).length; // fitted ones -- always the start of the list
                cur = root.move("widgets", i, hit ? hit.i : i < n ? n - 1 : n);
            }

            Pick { visible: root.multi; label: "screen"; opts: root.names.map(n => n.toLowerCase()); cur: root.names.indexOf(root.mon); onPicked: i => root.pickMon = root.names[i] }

            Row {
                spacing: 60

                Item {
                    id: grid
                    width: 536
                    height: 536
                    activeFocusOnTab: true
                    Keys.onPressed: e => {
                        const c = root.nav(e, "widgets", home.cur, Object.keys(Theme.kinds));
                        if (c < 0) return;
                        home.cur = c;
                        e.accepted = true;
                    }
                    Repeater {
                        model: 9
                        Dots {
                            required property int index
                            x: index % 3 * 184
                            y: Math.floor(index / 3) * 184
                        }
                    }
                    Repeater {
                        model: home.placed
                        Tile {
                            x: modelData.col * 184
                            y: modelData.row * 184
                        }
                    }
                }

                Column {
                    width: 404
                    spacing: 12
                    Lb { text: "cells" }
                    Row {
                        spacing: 10
                        Num { id: usedN; text: home.used; font.pixelSize: 150 }
                        Num { anchors.baseline: usedN.baseline; text: "/9"; font.pixelSize: 54; color: Theme.mute }
                    }
                    Lb {
                        width: parent.width
                        elide: Text.ElideRight
                        text: !home.cur_ ? "empty · ↵ adds one" : `${home.cur_.id} · ${home.cur_.span} cell${home.cur_.span > 1 ? "s" : ""}${home.cur_.fits ? "" : " · off grid"}`
                    }
                    // the cat's gif (services/Gifs) -- shown while the cat is selected. Click or ←→ when focused
                    Column {
                        id: gifPick
                        visible: home.cur_?.id === "cat"
                        topPadding: 28
                        spacing: 12
                        Lb {
                            width: 404
                            elide: Text.ElideRight
                            text: `gif · ${Gifs.name(Gifs.cur)} · ${Gifs.sel + 1} of ${Gifs.list.length}`
                            color: gifStrip.activeFocus ? Theme.fg : Theme.grey
                        }
                        ListView {
                            id: gifStrip
                            width: 404
                            height: 58
                            orientation: ListView.Horizontal
                            spacing: (width - 6 * 58) / 5 // exactly six across
                            clip: true
                            snapMode: ListView.SnapToItem
                            boundsBehavior: Flickable.StopAtBounds
                            keyNavigationEnabled: false
                            activeFocusOnTab: true
                            model: Gifs.list
                            currentIndex: Gifs.sel
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                            Keys.onPressed: e => {
                                if (e.key === Qt.Key_Left) Gifs.step(-1);
                                else if (e.key === Qt.Key_Right) Gifs.step(1);
                                else return;
                                e.accepted = true;
                            }
                            delegate: Rectangle {
                                id: th
                                required property string modelData
                                required property int index
                                readonly property bool on: index === Gifs.sel
                                width: 58
                                height: 58
                                radius: Theme.corner(width * 0.18)
                                color: Theme.s1
                                border { width: on ? 2 : 1; color: on ? Theme.fg : Theme.s2 }
                                GifDots { anchors { fill: parent; margins: 6 } path: th.modelData; bg: th.color; playing: gifPick.visible && root.visible }
                                TapHandler {
                                    onTapped: {
                                        Gifs.pick(th.modelData);
                                        gifStrip.forceActiveFocus();
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                    Item { width: 1; height: 40 }
                    Lb { text: home.off.length ? `off grid · ${home.off.length}` : "everything fits" }
                    Flow {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: home.off
                            Tile { cell: 84; gap: 8 }
                        }
                    }
                }
            }

            Tray {
                ids: Object.keys(Theme.kinds)
                icons: root.icons
                used: Theme.state.widgets
                dim: home.off.map(c => c.id)
                widths: Theme.kinds
                onToggled: key => home.cur = root.flip("widgets", key, home.cur)
            }
        }

        // ---- DECK: screen, bottom center -- deck, right -- quick settings; both slide out on hovering their edge.
        // deck sections in order, as in the panel; tray -- which ones exist ----
        Page {
            id: deck
            k: 1
            caption: `deck · ${Theme.state.deck.length} of ${Theme.decks.length} sections · bottom edge`
            property int cur: 0
            // dragging section from (-1 -- none): dx -- cursor shift in layout px, at -- where it is in the strip, to -- where it will land
            property int from: -1
            property real dx: 0
            readonly property real at: Math.max(10, Math.min(10 + (Theme.state.deck.length - 1) * 104, 10 + from * 104 + dx))
            readonly property int to: Math.round((at - 10) / 104)

            Row {
                spacing: 40

                Mini {
                    // edges that catch the cursor: bottom -- deck, right -- quick settings
                    Seg {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                        width: 320
                        height: 4
                        n: 24
                        f: Theme.state.deckHover ? 1 : 0
                    }
                    Seg {
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        width: 4
                        height: 240
                        n: 16
                        vertical: true
                        f: Theme.state.quickHover ? 1 : 0
                    }

                    Rectangle {
                        id: strip
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 30 }
                        width: Math.max(1, Theme.state.deck.length) * 104 + 20
                        height: 116
                        radius: Theme.corner(40)
                        color: Theme.s1
                        border { width: 1; color: strip.activeFocus ? Theme.fg : Theme.s2 }
                        Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            const c = root.nav(e, "deck", deck.cur, Theme.decks);
                            if (c < 0) return;
                            deck.cur = c;
                            e.accepted = true;
                        }

                        Lb { visible: !Theme.state.deck.length; anchors.centerIn: parent; text: "empty" }
                        Repeater {
                            model: Theme.state.deck
                            Item {
                                id: ds
                                required property string modelData
                                required property int index
                                readonly property bool on: deck.cur === index
                                readonly property bool hot: on && strip.activeFocus
                                // while dragging: this one follows the cursor, those between it and the drop point -- one step toward its place
                                readonly property int slot: deck.from < 0 ? index
                                    : index > deck.from && index <= deck.to ? index - 1
                                    : index < deck.from && index >= deck.to ? index + 1 : index
                                x: dd.active ? deck.at : 10 + slot * 104
                                width: 104
                                height: strip.height
                                z: dd.active ? 1 : 0
                                Behavior on x {
                                    enabled: !dd.active
                                    NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 56
                                        height: 56
                                        radius: 28
                                        color: ds.hot ? Theme.fg : Theme.s2
                                        border { width: ds.on && !ds.hot ? 1 : 0; color: Theme.fg }
                                        Icon { anchors.centerIn: parent; text: root.icons[ds.modelData] ?? ""; font.pixelSize: 24; color: ds.hot ? Theme.ink : Theme.fg }
                                    }
                                    Lb { anchors.horizontalCenter: parent.horizontalCenter; text: ds.modelData; px: 10; color: ds.on ? Theme.fg : Theme.grey }
                                }
                                TapHandler {
                                    onTapped: {
                                        strip.forceActiveFocus();
                                        deck.cur = deck.cur === ds.index ? root.cycle("deck", ds.index, Theme.decks) : ds.index;
                                    }
                                }
                                DragHandler {
                                    id: dd
                                    target: null
                                    yAxis.enabled: false
                                    // without target the shift is in scene px, while Stage is scaled
                                    onActiveTranslationChanged: deck.dx = activeTranslation.x / Theme.s
                                    onActiveChanged: {
                                        if (active) {
                                            deck.cur = ds.index;
                                            deck.from = ds.index;
                                            return;
                                        }
                                        // drop -- after the signal: changing the list recreates the sections, including this one
                                        const from = deck.from, to = deck.to;
                                        Qt.callLater(() => {
                                            deck.from = -1;
                                            deck.cur = root.move("deck", from, to);
                                        });
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    spacing: 14
                    Toggle { width: 200; text: "deck · hover"; on: Theme.state.deckHover; onFlip: Theme.state.deckHover = !Theme.state.deckHover }
                    Toggle { width: 200; text: "quick · hover"; on: Theme.state.quickHover; onFlip: Theme.state.quickHover = !Theme.state.quickHover }
                    Lb { topPadding: 6; text: "bottom edge · right edge"; px: 10 }
                    Lb { text: "genie lives in FEATURES now"; px: 10; color: Theme.mute }
                }
            }

            Tray {
                ids: Theme.decks
                icons: root.icons
                used: Theme.state.deck
                onToggled: key => deck.cur = root.flip("deck", key, deck.cur)
            }
        }

        // ---- BAR: the edge -- two screens in miniature, click chooses. The tray -- as in the bar: at the side a column
        // (labels beside), on top a row (labels under the icon), in order; drag -- along the bar. The pool -- what exists ----
        Page {
            id: bar
            k: 2
            caption: `bar · ${Theme.state.bar.length} of ${Theme.bars.length} in the tray · ${onTop ? "top" : "left"} edge`
            readonly property bool onTop: Theme.state.barAt === "top"
            readonly property real step: onTop ? 104 : 68 // a slot along the bar
            property int cur: 0
            // dragging from (-1 -- nobody): d -- the cursor's shift along the bar in layout px, at -- where it is, to -- where it will land
            property int from: -1
            property real d: 0
            readonly property real at: Math.max(10, Math.min(10 + (Theme.state.bar.length - 1) * step, 10 + from * step + d))
            readonly property int to: Math.round((at - 10) / step)

            Grid {
                columns: bar.onTop ? 1 : 2
                columnSpacing: 200
                rowSpacing: 40

                Rectangle {
                    id: col
                    readonly property int n: Math.max(1, Theme.state.bar.length)
                    width: bar.onTop ? n * 104 + 20 : 88
                    height: bar.onTop ? 116 : n * 68 + 20
                    radius: Theme.corner(bar.onTop ? 40 : 44)
                    color: Theme.s1
                    border { width: 1; color: col.activeFocus ? Theme.fg : Theme.s2 }
                    Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                    Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                    activeFocusOnTab: true
                    Keys.onPressed: e => {
                        const c = root.nav(e, "bar", bar.cur, Theme.bars);
                        if (c < 0) return;
                        bar.cur = c;
                        e.accepted = true;
                    }

                    Lb { visible: !Theme.state.bar.length; anchors.centerIn: parent; text: "empty"; px: 10 }
                    Repeater {
                        model: Theme.state.bar
                        Item {
                            id: bs
                            required property string modelData
                            required property int index
                            readonly property bool on: bar.cur === index
                            readonly property bool hot: on && col.activeFocus
                            readonly property int slot: bar.from < 0 ? index
                                : index > bar.from && index <= bar.to ? index - 1
                                : index < bar.from && index >= bar.to ? index + 1 : index
                            // the place along the bar: behind the cursor while dragging
                            property real pos: bd.active ? bar.at : 10 + slot * bar.step
                            Behavior on pos {
                                enabled: !bd.active
                                NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
                            }
                            x: bar.onTop ? pos : 0
                            y: bar.onTop ? 0 : pos
                            width: bar.onTop ? 104 : col.width
                            height: bar.onTop ? col.height : 68
                            z: bd.active ? 1 : 0

                            Rectangle {
                                id: bdot
                                x: (parent.width - width) / 2
                                y: bar.onTop ? 18 : (parent.height - height) / 2
                                width: 52
                                height: 52
                                radius: 26
                                color: bs.hot ? Theme.fg : Theme.s2
                                border { width: bs.on && !bs.hot ? 1 : 0; color: Theme.fg }
                                Icon { anchors.centerIn: parent; text: root.icons[bs.modelData] ?? ""; font.pixelSize: 22; color: bs.hot ? Theme.ink : Theme.fg }
                            }
                            Lb {
                                x: bar.onTop ? (parent.width - width) / 2 : parent.width + 24
                                y: bar.onTop ? bdot.y + bdot.height + 10 : (parent.height - height) / 2
                                text: bs.modelData
                                px: 10
                                color: bs.on ? Theme.fg : Theme.grey
                            }
                            TapHandler {
                                onTapped: {
                                    col.forceActiveFocus();
                                    bar.cur = bar.cur === bs.index ? root.cycle("bar", bs.index, Theme.bars) : bs.index;
                                }
                            }
                            DragHandler {
                                id: bd
                                target: null
                                xAxis.enabled: bar.onTop
                                yAxis.enabled: !bar.onTop
                                onActiveTranslationChanged: bar.d = (bar.onTop ? activeTranslation.x : activeTranslation.y) / Theme.s
                                onActiveChanged: {
                                    if (active) {
                                        bar.cur = bs.index;
                                        bar.from = bs.index;
                                        return;
                                    }
                                    const from = bar.from, to = bar.to;
                                    Qt.callLater(() => {
                                        bar.from = -1;
                                        bar.cur = root.move("bar", from, to);
                                    });
                                }
                            }
                        }
                    }
                }

                Column {
                    spacing: 14
                    Lb { text: "edge" }
                    // screens with the pill at their own edge; left/right -- the other one
                    Row {
                        id: edges
                        spacing: 20
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            if (e.key !== Qt.Key_Left && e.key !== Qt.Key_Right && e.key !== Qt.Key_Space && e.key !== Qt.Key_Return) return;
                            Theme.state.barAt = bar.onTop ? "left" : "top";
                            e.accepted = true;
                        }
                        Repeater {
                            model: ["left", "top"]
                            Column {
                                id: ed
                                required property string modelData
                                readonly property bool on: (modelData === "top") === bar.onTop
                                spacing: 10
                                Rectangle {
                                    width: 200
                                    height: 125
                                    radius: 18
                                    color: Theme.bg
                                    border { width: ed.on && edges.activeFocus ? 2 : 1; color: ed.on ? Theme.fg : Theme.s3 }
                                    Behavior on border.color { ColorAnimation { duration: Theme.t } }
                                    Rectangle {
                                        x: 10
                                        y: 10
                                        width: ed.modelData === "top" ? parent.width - 20 : 16
                                        height: ed.modelData === "top" ? 16 : parent.height - 20
                                        radius: 8
                                        color: ed.on ? Theme.fg : Theme.s3
                                        Behavior on color { ColorAnimation { duration: Theme.t } }
                                    }
                                    TapHandler { onTapped: Theme.state.barAt = ed.modelData }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                                Lb { anchors.horizontalCenter: parent.horizontalCenter; text: ed.modelData; px: 10; color: ed.on ? Theme.fg : Theme.grey }
                            }
                        }
                    }
                    Item { width: 1; height: 12 }
                    Toggle { width: 200; text: "window title"; on: Theme.state.barTitle; onFlip: Theme.state.barTitle = !Theme.state.barTitle }
                    Lb { topPadding: 6; text: bar.onTop ? "left of the clock" : "above the clock"; px: 10 }
                }
            }

            Tray {
                ids: Theme.bars
                icons: root.icons
                used: Theme.state.bar
                onToggled: key => bar.cur = root.flip("bar", key, bar.cur)
            }
        }

        // ---- LOOK: home in miniature follows the toggles; name -- into a pill ----
        Page {
            id: look
            k: 3
            caption: "look · the home screen, live"
            property bool dim: false // colon is dimmed

            Timer { running: look.visible && root.visible && Theme.state.blink; interval: 500; repeat: true; onTriggered: look.dim = !look.dim }

            Row {
                spacing: 40

                Mini {
                    Orb { visible: Theme.state.orb; x: 400; y: 110; scale: 330 / 1100; transformOrigin: Item.TopLeft }
                    Row {
                        x: 60
                        y: 52
                        Num { id: hrs; text: Theme.hh(clock.date); font.pixelSize: 120 }
                        Num { text: ":"; font.pixelSize: 120; opacity: Theme.state.blink && look.dim ? 0.2 : 1 }
                        Num { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 120 }
                        Lb { visible: !Theme.state.clock24; anchors.baseline: hrs.baseline; leftPadding: 12; text: clock.date.getHours() < 12 ? "am" : "pm" }
                    }
                    Lb { x: 64; y: 172; text: Qt.locale("en_US").toString(clock.date, "dddd · d MMMM"); px: 11 }
                    Text {
                        x: 62
                        y: 232
                        textFormat: Text.StyledText
                        text: `${root.hello},<br><font color="${Theme.grey}">${root.who}.</font>`
                        font { family: Theme.ui; pixelSize: 30; weight: Font.Light }
                        lineHeight: 1.1
                        color: Theme.fg
                    }
                    // Galaga strips: volume on the right, progress at the bottom
                    Seg { visible: Theme.state.edges; x: parent.width - 12; y: 140; width: 4; height: 200; n: 12; f: 0.6; vertical: true }
                    Seg { visible: Theme.state.edges; x: 230; y: parent.height - 10; width: 300; height: 4; n: 24; f: 0.4 }
                }

                Column {
                    spacing: 14
                    // no theme controls here -- they live on STYLE, with the colours they restyle
                    Toggle { width: 200; text: "dot grid"; on: Theme.state.grid; onFlip: Theme.state.grid = !Theme.state.grid }
                    Toggle { width: 200; text: "orb"; on: Theme.state.orb; onFlip: Theme.state.orb = !Theme.state.orb }
                    Toggle { width: 200; text: "24 hours"; on: Theme.state.clock24; onFlip: Theme.state.clock24 = !Theme.state.clock24 }
                    Toggle { width: 200; text: "blink"; on: Theme.state.blink; onFlip: Theme.state.blink = !Theme.state.blink }
                    Toggle { width: 200; text: "edges"; on: Theme.state.edges; onFlip: Theme.state.edges = !Theme.state.edges }
                    // on home: which parts of the home screen show at all (Isaqdn03's section hides)
                    Toggle { width: 200; text: "home · clock"; on: Theme.state.homeClock; onFlip: Theme.state.homeClock = !Theme.state.homeClock }
                    Toggle { width: 200; text: "home · greeting"; on: Theme.state.homeHello; onFlip: Theme.state.homeHello = !Theme.state.homeHello }
                    Toggle { width: 200; text: "home · widgets"; on: Theme.state.homeBento; onFlip: Theme.state.homeBento = !Theme.state.homeBento }
                    Act {
                        icon: "\u{F02E9}"
                        text: "wallpaper"
                        onHit: {
                            root.close();
                            root.wallRequested();
                        }
                    }
                }
            }

            // name in the greeting; empty -- $USER
            Rectangle {
                width: 760
                height: 72
                radius: Theme.corner(36)
                color: Theme.s2
                border { width: name.activeFocus ? 1 : 0; color: Theme.fg }
                Lb { id: nameL; x: 30; anchors.verticalCenter: parent.verticalCenter; text: "name"; color: name.activeFocus ? Theme.fg : Theme.grey }
                TextInput {
                    id: name
                    anchors { left: nameL.right; leftMargin: 24; right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
                    text: Theme.state.name
                    maximumLength: 24
                    activeFocusOnTab: true
                    font { family: Theme.ui; pixelSize: 24 }
                    color: Theme.fg
                    selectionColor: Theme.s3
                    clip: true
                    onTextEdited: Theme.state.name = text
                    cursorDelegate: Rectangle {
                        width: 2
                        color: name.activeFocus ? Theme.red : "transparent"
                        Timer { running: name.activeFocus; interval: 500; repeat: true; onTriggered: parent.opacity = 1 - parent.opacity }
                    }
                    Text { visible: !name.text; text: Quickshell.env("USER"); font: name.font; color: Theme.mute }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) root.go(root.sel + (e.key === Qt.Key_Up ? -1 : 1));
                        else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) stage.forceActiveFocus();
                        else return;
                        e.accepted = true;
                    }
                }
            }
        }

        // ---- STYLE: where colour is from and where it lands. On top -- a desktop in the palette of the sample under
        // the cursor or in focus (none -- the current one): bar, quick settings, kitty, player, the Galaga strip; right of
        // it the roles as callouts, like a drawing: which colour goes where. Under it, where the colour is from and the
        // theme; then what the source has: the wallpaper as dots (click -- the picker), its tones and variants (the ring
        // -- how much colour) or the palettes by group. The same choice as the launcher's style (Theme.styles). Samples
        // by index: a new Theme.styles does not recreate the circles on every pick, and focus stays where it was ----
        Page {
            id: tint
            k: 4
            property Item hot: null // the sample under the cursor or in focus
            readonly property var p: hot?.item.pal ?? Theme.pal
            readonly property string src: Theme.state.paint === "scheme" ? (Theme.pal.group === "more" ? "" : Theme.pal.group + " ") + Theme.pal.name
                : Theme.state.paint === "wall" && Theme.tones.length ? `wallpaper · ${Theme.pal.name}` : "nothing"
            caption: `style · ${src} · ${Theme.light ? "light" : "dark"}` + (hot && !hot.item.now ? `   →   ${hot.item.name} · ↵ sets it` : "")
            function block(h) { return Theme.styles.find(b => b.head === h)?.items ?? []; }
            function peek(sw) {
                if (sw.peek) hot = sw;
                else if (hot === sw) hot = null;
            }

            Desk { p: tint.p; onPickColour: key => root.openPicker(key) }

            // customs: your own colours sit on top of the palette, everywhere, until reset
            Row {
                spacing: 14
                Lb { anchors.verticalCenter: parent.verticalCenter; text: "click a colour on the right to make it your own"; px: 10; color: Theme.mute }
                Rectangle {
                    visible: Object.keys(Theme.state.custom).length > 0
                    width: rcL.implicitWidth + 28
                    height: 32
                    radius: 16
                    color: Theme.s2
                    Lb { id: rcL; anchors.centerIn: parent; text: "reset customs"; px: 11; color: Theme.fg }
                    TapHandler { onTapped: Theme.state.custom = ({}) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Lb { anchors.verticalCenter: parent.verticalCenter; visible: Object.keys(Theme.state.custom).length > 0; text: "they sit on top of every palette"; px: 10; color: Theme.mute }
            }

            Row {
                spacing: 24
                Pick {
                    label: "from"
                    opts: ["nothing", "wall", "palette"]
                    cur: ["", "wall", "scheme"].indexOf(Theme.state.paint)
                    onPicked: i => Theme.state.paint = ["", "wall", "scheme"][i]
                }
                Pick {
                    label: "theme"
                    opts: ["light", "dark", "auto"]
                    cur: Theme.state.themeMode === 1 ? 2 : Theme.light ? 0 : 1
                    onPicked: i => {
                        if (i === 2) Theme.state.themeMode = 1;
                        else { Theme.state.themeMode = 0; Theme.setLight(i === 0); }
                    }
                }
            }

            // the auto schedule's hours -- only while theme is auto (Theme.state.themeMode 1)
            Row {
                visible: Theme.state.themeMode === 1
                spacing: 40
                TimeStep { label: "light at"; value: Theme.state.lightAt; onMoved: v => Theme.state.lightAt = v }
                TimeStep { label: "dark at"; value: Theme.state.darkAt; onMoved: v => Theme.state.darkAt = v }
            }

            // what the source has. One height for all: the Page is centered, and the layout would jump when the source
            // changes. ponytail: 300 by eye, palettes in two rows; if it grows -- the Item grows past it
            Item {
                width: 1040
                height: Math.max(300, own.height)
                Column {
                    id: own
                    spacing: 28
                    Lb { visible: !Theme.state.paint; text: "black · white dots · one red — nothing to pick"; color: Theme.mute }
                    Row {
                        visible: Theme.state.paint === "wall"
                        spacing: 34
                        // the wallpaper as dots; click -- the picker
                        Rectangle {
                            width: 168
                            height: 105
                            radius: Theme.corner(14)
                            color: "transparent"
                            border { width: Theme.wall ? 0 : 1; color: Theme.s3 }
                            Image {
                                anchors.fill: parent
                                source: visible ? Theme.url(Theme.wallSrc(Theme.wall)) : "" // not visible -- no texture
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(336, 210)
                                asynchronous: true
                                layer.enabled: true
                                layer.effect: Dm { step: 4 }
                            }
                            Lb { visible: !Theme.wall; anchors.centerIn: parent; px: 10; text: "no wallpaper" }
                            TapHandler {
                                onTapped: {
                                    root.close();
                                    root.wallRequested();
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                        Column {
                            spacing: 6
                            Lb { text: Theme.tones.length ? "tones · from the wallpaper" : "no colour in it · click it for another" }
                            Row {
                                Repeater {
                                    model: tint.block("tones").length
                                    Swatch { id: tw; item: tint.block("tones")[index] ?? ({ name: "" }); onPeekChanged: tint.peek(tw) }
                                }
                            }
                        }
                    }
                    Column {
                        visible: Theme.state.paint === "wall" && Theme.tones.length > 0
                        spacing: 6
                        Lb { text: "variant · how much colour, like material you" }
                        Row {
                            Repeater {
                                model: tint.block("variant").length
                                Swatch { id: vw; item: tint.block("variant")[index] ?? ({ name: "" }); onPeekChanged: tint.peek(vw) }
                            }
                        }
                    }
                    // palettes by group -- the blocks between source and theme
                    Flow {
                        visible: Theme.state.paint === "scheme"
                        width: 1040
                        spacing: 40
                        Repeater {
                            model: Theme.state.paint === "scheme" ? Theme.styles.length - 2 : 0
                            Column {
                                id: sb
                                required property int index
                                readonly property var block: Theme.styles[index + 1] ?? ({ head: "", items: [] })
                                spacing: 6
                                Lb { text: sb.block.head }
                                Row {
                                    Repeater {
                                        model: sb.block.items.length
                                        Swatch { id: pw; item: sb.block.items[index] ?? ({ name: "" }); onPeekChanged: tint.peek(pw) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- LOCK: everything about the face -- the photo, a wallpaper of its own, the
        // clock's shape, and what may show on it. The desktop's look stays on LOOK; this page
        // is the lock alone (and the greeter, which shares the face) ----
        Page {
            id: lockp
            k: 5
            caption: "lock · the face they meet first"

            // profile photo: set copies the file next to galaga.json (state.avatar) and to
            // ~/.face; a ~/.face that was already there is backed up into the state dir
            // first, and clear brings it back (or removes ours). The lock reads
            // state.avatar; the greeter gets its copy from install.sh --greeter.
            property string photoMsg: ""
            function setPhoto() {
                const raw = photoIn.text.trim();
                const p = raw.startsWith("~/") ? Quickshell.env("HOME") + raw.slice(1) : raw;
                if (!p) { photoMsg = "type a path first"; return; }
                photoSet.exec(["sh", "-c",
                    'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; mkdir -p "$st"; src="$1"; [ -f "$src" ] || { echo missing; exit 1; }\n' +
                    'ext="${src##*.}"; case "$ext" in jpg|jpeg|png|webp|JPG|JPEG|PNG|WEBP) ;; *) ext=png ;; esac\n' +
                    '[ -f "$HOME/.face" ] && [ ! -f "$st/face-backup" ] && cp "$HOME/.face" "$st/face-backup"\n' +
                    'cp "$src" "$st/avatar.$ext" && cp "$src" "$HOME/.face" && printf "%s" "$st/avatar.$ext"',
                    "galaga-photo", p]);
            }
            function clearPhoto() { photoClear.running = true; }
            Process {
                id: photoSet
                stdout: StdioCollector {
                    onStreamFinished: {
                        const t = text.trim();
                        if (t && t !== "missing") { Theme.state.avatar = t; lockp.photoMsg = ""; photoIn.text = ""; }
                        else lockp.photoMsg = "no such file";
                    }
                }
            }
            Process {
                id: photoClear
                command: ["sh", "-c",
                    'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; rm -f "$st"/avatar.*\n' +
                    'if [ -f "$st/face-backup" ]; then mv "$st/face-backup" "$HOME/.face"; else rm -f "$HOME/.face"; fi']
                onExited: { Theme.state.avatar = ""; lockp.photoMsg = ""; }
            }

            // the lock's own wallpaper: set copies the file next to galaga.json
            // (state.lockWall) and the face draws it instead of the desktop wallpaper;
            // the greeter gets its copy from install.sh --greeter. Clear -- the desktop
            // wallpaper again
            property string wallMsg: ""
            function setWall() {
                const raw = wallIn.text.trim();
                const p = raw.startsWith("~/") ? Quickshell.env("HOME") + raw.slice(1) : raw;
                if (!p) { wallMsg = "type a path first"; return; }
                lwSet.exec(["sh", "-c",
                    'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; mkdir -p "$st"; src="$1"; [ -f "$src" ] || { echo missing; exit 1; }\n' +
                    'ext="${src##*.}"; case "$ext" in jpg|jpeg|png|webp|JPG|JPEG|PNG|WEBP) ;; *) ext=jpg ;; esac\n' +
                    'rm -f "$st"/lockwall.*\n' +
                    'cp "$src" "$st/lockwall.$ext" && printf "%s" "$st/lockwall.$ext"',
                    "galaga-lockwall", p]);
            }
            function clearWall() { lwClear.running = true; }
            Process {
                id: lwSet
                stdout: StdioCollector {
                    onStreamFinished: {
                        const t = text.trim();
                        if (t && t !== "missing") { Theme.state.lockWall = t; lockp.wallMsg = ""; wallIn.text = ""; }
                        else lockp.wallMsg = "no such file";
                    }
                }
            }
            Process {
                id: lwClear
                command: ["sh", "-c", 'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; rm -f "$st"/lockwall.*']
                onExited: { Theme.state.lockWall = ""; lockp.wallMsg = ""; }
            }

            // profile photo: a path field and a live preview -- the picker this shell can
            // stand behind (there is no file dialog in its toolkit). Set -- the photo shows
            // on the lock (and, after install.sh --greeter, at boot); clear -- back to dots.
            Row {
                spacing: 14
                Item {
                    width: 72
                    height: 72
                    Ring { anchors.fill: parent; n: 24; dot: 3; f: 1 }
                    Item {
                        visible: pvImg.status === Image.Ready
                        anchors { fill: parent; margins: 12 }
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: pvMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                        Image {
                            id: pvImg
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(96, 96)
                            source: {
                                const t = photoIn.text.trim();
                                const p = t.startsWith("~/") ? Quickshell.env("HOME") + t.slice(1) : t;
                                return p ? "file://" + p : Theme.state.avatar ? "file://" + Theme.state.avatar : "";
                            }
                        }
                    }
                    Rectangle { id: pvMask; anchors { fill: parent; margins: 12 } radius: width / 2; visible: false; layer.enabled: true }
                    Rectangle { visible: pvImg.status !== Image.Ready; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.fg }
                }
                Rectangle {
                    width: 360
                    height: 72
                    radius: Theme.corner(36)
                    color: Theme.s2
                    border { width: photoIn.activeFocus ? 1 : 0; color: Theme.fg }
                    Lb { id: photoL; x: 30; anchors.verticalCenter: parent.verticalCenter; text: "photo"; color: photoIn.activeFocus ? Theme.fg : Theme.grey }
                    TextInput {
                        id: photoIn
                        anchors { left: photoL.right; leftMargin: 24; right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
                        font { family: Theme.ui; pixelSize: 20 }
                        color: Theme.fg
                        selectionColor: Theme.s3
                        clip: true
                        activeFocusOnTab: true
                        Text { visible: !photoIn.text; text: Theme.state.avatar || "~/Pictures/me.png"; font: photoIn.font; color: Theme.mute }
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) lockp.setPhoto();
                            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) root.go(root.sel + (e.key === Qt.Key_Up ? -1 : 1));
                            else if (e.key === Qt.Key_Escape) stage.forceActiveFocus();
                            else return;
                            e.accepted = true;
                        }
                    }
                }
                Act { icon: "\u{F012C}"; text: "set"; onHit: lockp.setPhoto() }
                Act { visible: !!Theme.state.avatar; icon: "\u{F0156}"; text: "clear"; onHit: lockp.clearPhoto() }
            }
            Lb { visible: !!lockp.photoMsg; text: lockp.photoMsg; px: 10; color: Theme.red }

            // the lock's own wallpaper: a path field and a preview, like the photo
            Row {
                spacing: 14
                Item {
                    width: 128
                    height: 72
                    Rectangle { anchors.fill: parent; radius: Theme.corner(14); color: Theme.s2 }
                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: lwMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                        Image {
                            id: lwImg
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(256, 144)
                            source: {
                                const t = wallIn.text.trim();
                                const p = t.startsWith("~/") ? Quickshell.env("HOME") + t.slice(1) : t;
                                return p ? "file://" + p : Theme.state.lockWall ? "file://" + Theme.state.lockWall : "";
                            }
                        }
                    }
                    Rectangle { id: lwMask; anchors.fill: parent; radius: Theme.corner(14); visible: false; layer.enabled: true }
                    Lb { visible: lwImg.status !== Image.Ready; anchors.centerIn: parent; text: "wall"; px: 10; color: Theme.mute }
                }
                Rectangle {
                    width: 360
                    height: 72
                    radius: Theme.corner(36)
                    color: Theme.s2
                    border { width: wallIn.activeFocus ? 1 : 0; color: Theme.fg }
                    Lb { id: wallL; x: 30; anchors.verticalCenter: parent.verticalCenter; text: "wallpaper"; color: wallIn.activeFocus ? Theme.fg : Theme.grey }
                    TextInput {
                        id: wallIn
                        anchors { left: wallL.right; leftMargin: 24; right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
                        font { family: Theme.ui; pixelSize: 20 }
                        color: Theme.fg
                        selectionColor: Theme.s3
                        clip: true
                        activeFocusOnTab: true
                        Text { visible: !wallIn.text; text: Theme.state.lockWall || "~/Pictures/lock.jpg"; font: wallIn.font; color: Theme.mute }
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) lockp.setWall();
                            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) root.go(root.sel + (e.key === Qt.Key_Up ? -1 : 1));
                            else if (e.key === Qt.Key_Escape) stage.forceActiveFocus();
                            else return;
                            e.accepted = true;
                        }
                    }
                }
                Act { icon: "\u{F012C}"; text: "set"; onHit: lockp.setWall() }
                Act { visible: !!Theme.state.lockWall; icon: "\u{F0156}"; text: "clear"; onHit: lockp.clearWall() }
            }
            Lb { visible: !!lockp.wallMsg; text: lockp.wallMsg; px: 10; color: Theme.red }

            // the clock's shape: matrix -- the dotted time; stacked -- hours over minutes;
            // analogue -- dots and hands, like the nothing widget clocks
            Row {
                spacing: 14
                Pick {
                    label: "clock"
                    opts: ["matrix", "stacked", "analogue"]
                    cur: Theme.state.lockClock
                    onPicked: i => Theme.state.lockClock = i
                }
                Lb { anchors.verticalCenter: parent.verticalCenter; text: "how the time sits on the face"; px: 10; color: Theme.mute }
            }

            Grid {
                columns: 2
                spacing: 14
                Toggle { width: 250; text: "media + summary"; on: Theme.state.featLockMedia; onFlip: Theme.state.featLockMedia = !Theme.state.featLockMedia }
                Toggle { width: 250; text: "hide length"; on: Theme.state.lockHideLen; onFlip: Theme.state.lockHideLen = !Theme.state.lockHideLen }
                Toggle { width: 250; text: "one screen"; on: Theme.state.lockOneScreen; onFlip: Theme.state.lockOneScreen = !Theme.state.lockOneScreen }
            }
        }

        // ---- WINDOWS: desktop with two windows using live ring values. Window animation -- only if motion ----
        Page {
            k: 6
            caption: `windows · hyprland · gaps ${gIn.v} / ${gOut.v} · border ${bord.v} · rounding ${rnd.v} · panels ${pan.v} %`

            // narrower than the other pages on purpose: this row carries TWO toggle
            // columns beside the desktop, and at the Mini's full 760 the second one
            // ran off the window's right edge (the Page starts at x 800)
            Row {
                spacing: 24

                Mini {
                    id: desk
                    width: 620
                    Repeater {
                        model: 2
                        Rectangle {
                            id: wnd
                            required property int index
                            readonly property real o: gOut.v * desk.k
                            readonly property real l: 78 * Theme.s * desk.k + o // bar 64 + gap 14, in logical px
                            readonly property real w: (desk.width - (at === "top" ? o : l) - o - 2 * gIn.v * desk.k) / 2
                            readonly property string at: Theme.state.barAt
                            x: (at !== "top" ? l : o) + (index ? w + 2 * gIn.v * desk.k : 0)
                            y: at === "top" ? l : o
                            width: w
                            height: desk.height - (at === "top" ? l : o) - o
                            radius: rnd.v * desk.k
                            color: Theme.s1
                            border { width: bord.v ? Math.max(1, bord.v * desk.k) : 0; color: index ? Theme.s3 : Theme.fg }
                            Behavior on x { enabled: root.r.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on y { enabled: root.r.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on width { enabled: root.r.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                            Behavior on height { enabled: root.r.motion; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

                            Column {
                                x: 20
                                y: 20
                                spacing: 9
                                Lb { text: wnd.index ? "zen" : "kitty"; px: 10; color: wnd.index ? Theme.mute : Theme.grey }
                                Repeater {
                                    model: [0.7, 0.45, 0.85, 0.3, 0.6, 0.5]
                                    Rectangle {
                                        required property real modelData
                                        width: (wnd.width - 40) * modelData
                                        height: 5
                                        radius: 2.5
                                        color: Theme.s3
                                    }
                                }
                            }
                        }
                    }
                }

                // ponytail: blur and shadows are not visible in the mockup (flat black) -- toggles only
                Column {
                    spacing: 14
                    Toggle { width: 200; text: "blur"; on: root.r.blur; onFlip: { root.r.blur = !root.r.blur; Theme.apply(); } }
                    Toggle { width: 200; text: "shadow"; on: root.r.shadow; onFlip: { root.r.shadow = !root.r.shadow; Theme.apply(); } }
                    Toggle { width: 200; text: "motion"; on: root.r.motion; onFlip: { root.r.motion = !root.r.motion; Rules.motion(); } }
                }

                // what stays on in game mode (Rules.store.game*). Off -- game mode drops it; dnd -- only
                // auto game mode (services/Game) sets it. Tearing is always on in game mode
                Column {
                    spacing: 14
                    Item { width: 200; height: keepT.height; Lb { x: 22; anchors.verticalCenter: parent.verticalCenter; text: "in a game" } }
                    Toggle { id: keepT; width: 200; text: "gaps"; on: root.r.gameGaps; onFlip: { root.r.gameGaps = !root.r.gameGaps; Theme.apply(); } }
                    Toggle { width: 200; text: "motion"; on: root.r.gameMotion; onFlip: { root.r.gameMotion = !root.r.gameMotion; Rules.motion(); } }
                    Toggle { width: 200; text: "blur"; on: root.r.gameBlur; onFlip: { root.r.gameBlur = !root.r.gameBlur; Theme.apply(); } }
                    Toggle { width: 200; text: "shadow"; on: root.r.gameShadow; onFlip: { root.r.gameShadow = !root.r.gameShadow; Theme.apply(); } }
                    Toggle { width: 200; text: "dnd"; on: root.r.gameDnd; onFlip: root.r.gameDnd = !root.r.gameDnd }
                }
            }

            Row {
                spacing: 40
                Dial { id: gIn; label: "gaps in"; to: 30; value: root.r.gapsIn; onMoved: v => { root.r.gapsIn = v; Theme.apply(); } }
                Dial { id: gOut; label: "gaps out"; to: 60; value: root.r.gapsOut; onMoved: v => { root.r.gapsOut = v; Theme.apply(); } }
                Dial { id: bord; label: "border"; to: 6; n: 24; value: root.r.border; onMoved: v => { root.r.border = v; Theme.apply(); } }
                Dial { id: rnd; label: "rounding"; to: 40; value: Theme.state.rounding; onMoved: v => Theme.state.rounding = v } // shell.qml calls Theme.apply itself
                Dial { id: pan; label: "panels"; to: 100; step: 5; value: Theme.state.corners; onMoved: v => Theme.state.corners = v } // the shell's corners, %
            }
        }

        // ---- DISPLAY: the screens as hypr placed them (click or left/right -- choose); everything below is the chosen
        // one's: brightness (the built-in's), logical px, scale and hz, bar and home on it. Night light -- on all ----
        Page {
            id: disp
            k: 7
            readonly property var m: Rules.mons.find(x => x.name === root.mon) ?? Rules.mon
            readonly property var w: Rules.want(m)
            caption: `display · ${m.name.toLowerCase()} · ${m.w} × ${m.h} · ${m.hz} hz`

            Row {
                spacing: 60
                Column {
                    z: 1 // a screen is dragged by the map's edge -- over the brightness ring
                    spacing: 22
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
                            const d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0, n = root.names.length;
                            if (!d || !n) return;
                            root.pickMon = root.names[(root.names.indexOf(root.mon) + d + n) % n];
                            e.accepted = true;
                        }
                        Repeater {
                            model: map.ms
                            Rectangle {
                                id: sc
                                required property var modelData
                                readonly property bool on: modelData.name === root.mon
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
                                        root.pickMon = sc.modelData.name;
                                        map.forceActiveFocus();
                                    }
                                }
                                HoverHandler { cursorShape: root.multi ? Qt.OpenHandCursor : Qt.PointingHandCursor }
                                // drag -- it docks flush to a neighbour (Rules.dock); dropped -- Rules.place. While hypr has
                                // not answered the last drop it does not drag: the math would run from stale places. Without a
                                // target the shift is in scene px, and the Stage is scaled
                                DragHandler {
                                    target: null
                                    enabled: root.multi && (!map.held || active)
                                    cursorShape: Qt.ClosedHandCursor
                                    onActiveTranslationChanged: {
                                        if (!active) return;
                                        const m = sc.modelData, k = Theme.s * map.k;
                                        map.at = Rules.dock({ x: m.x + activeTranslation.x / k, y: m.y + activeTranslation.y / k, w: m.lw, h: m.lh },
                                                           map.ms.filter(o => o.name !== m.name), 16 / map.k);
                                    }
                                    onActiveChanged: {
                                        const m = sc.modelData;
                                        if (active) {
                                            root.pickMon = m.name;
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
                        Num { id: resW; text: disp.m.lw; font.pixelSize: 72 }
                        Num { anchors.baseline: resW.baseline; text: "×"; font.pixelSize: 40; color: Theme.mute }
                        Num { anchors.baseline: resW.baseline; text: disp.m.lh; font.pixelSize: 72 }
                    }
                    Lb { text: "logical pixels" }
                }
                // backlight -- the built-in's; externals over DDC -- no (services/Backlight)
                Column {
                    visible: Sys.hasBri && disp.m.name === Rules.mon.name
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 22
                    Dial { anchors.horizontalCenter: parent.horizontalCenter; size: 300; n: 60; live: true; label: "brightness"; value: Math.round(Sys.bri * 100); onMoved: v => Sys.setBri(v / 100) }
                    // the brightness keys' step: divisions per scale (Backlight.steps)
                    Pick { anchors.horizontalCenter: parent.horizontalCenter; label: "step"; opts: ["2.5%", "5%", "10%"]; cur: [40, 20, 10].indexOf(Theme.state.briSteps); onPicked: i => Theme.state.briSteps = [40, 20, 10][i] }
                }
            }
            Row {
                spacing: 24
                Pick { label: "scale"; opts: Rules.scales; cur: disp.w.scale ? Rules.scales.indexOf(String(disp.w.scale)) : 0; onPicked: i => Rules.set(disp.m.name, "scale", i ? +Rules.scales[i] : 0) }
                // there can be five or eight rates (a TV, 165 Hz) -- narrower segments, so the row stays on the canvas
                Pick { label: "hz"; seg: Math.min(104, 416 / opts.length); opts: disp.m.rates.map(String); cur: disp.m.rates.indexOf(disp.w.refresh); onPicked: i => Rules.set(disp.m.name, "refresh", disp.m.rates[i]) }
            }
            // on one screen too: the bar was taken off the laptop in a dock, undocked -- the only way back is here
            Row {
                spacing: 20
                Toggle { text: "bar"; on: Theme.scr(root.mon, "bar"); onFlip: Theme.setScr(root.mon, "bar", !on) }
                Toggle { text: "home"; on: Theme.scr(root.mon, "home"); onFlip: Theme.setScr(root.mon, "home", !on) }
                Lb { anchors.verticalCenter: parent.verticalCenter; leftPadding: 10; text: "on this screen · its widgets — in home" }
                // the externals' own places, scales and rates -- forget them, back to the hypr config (Rules.forget)
                Act { visible: Object.keys(Rules.store.outs).length > 0; icon: "\u{F0450}"; text: "hypr config"; onHit: Rules.forget() }
            }
            Row {
                spacing: 20
                Toggle { text: "arrange screens"; on: root.r.manageMonitor; onFlip: { root.r.manageMonitor = !root.r.manageMonitor; if (root.r.manageMonitor) Rules.monitor(true); } }
                Lb { anchors.verticalCenter: parent.verticalCenter; text: "off — monitors stay in your hypr config (a rotated screen, a hand-built layout)"; px: 10; color: Theme.mute }
            }
            Row {
                spacing: 40
                Toggle { anchors.verticalCenter: parent.verticalCenter; text: "night light"; on: Sys.night; onFlip: Sys.toggleNight() }
                Dial { label: "warmth · k · all screens"; from: 2500; to: 6500; step: 100; value: root.r.warmth; onMoved: v => { root.r.warmth = v; if (root.r.night) Rules.night(); } }
            }
        }

        // ---- AUDIO: output and input -- volume, mute, level, the default device (prefs/Audio) ----
        Page {
            id: audioPage
            k: 8
            caption: aud.caption
            Audio { id: aud; live: audioPage.visible && root.shown }
        }

        // ---- INPUT: hold a key -- first dot immediately, delay pause, then rate per second; on live rings ----
        Page {
            id: inp
            k: 9
            caption: "input · keyboard · touchpad"
            property int n: 0 // how many "typed"; 0 -- key released
            Timer {
                running: inp.visible && root.visible
                repeat: true
                interval: inp.n === 0 ? 700 : inp.n === 1 ? delay.v : 1000 / rate.v
                onTriggered: inp.n = (inp.n + 1) % 41
            }

            Row {
                spacing: 30
                Rectangle {
                    width: 110
                    height: 110
                    radius: 30
                    color: inp.n ? Theme.fg : Theme.s1
                    border { width: 1; color: Theme.s2 }
                    Num { anchors.centerIn: parent; text: "A"; font.pixelSize: 54; color: inp.n ? Theme.ink : Theme.fg }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    Row {
                        spacing: 6
                        Repeater {
                            model: 40
                            Rectangle {
                                required property int index
                                width: 14
                                height: 14
                                radius: 7
                                color: index < inp.n ? Theme.fg : Theme.s2
                            }
                        }
                    }
                    Lb { text: `hold a key · first, ${delay.v} ms, then ${rate.v} a second` }
                }
            }
            Row {
                spacing: 40
                Dial { id: delay; label: "delay · ms"; from: 150; to: 600; step: 10; value: root.r.repeatDelay; onMoved: v => { root.r.repeatDelay = v; Rules.input(); } }
                Dial { id: rate; label: "rate · /s"; from: 10; to: 60; value: root.r.repeatRate; onMoved: v => { root.r.repeatRate = v; Rules.input(); } }
                Dial { label: "scroll · %"; from: 10; to: 100; step: 5; value: root.r.scroll; onMoved: v => { root.r.scroll = v; Rules.input(); } }
                Dial { label: "pointer"; from: -100; to: 100; step: 5; value: root.r.sens; onMoved: v => { root.r.sens = v; Rules.input(); } }
                Dial { label: "mouse · %"; from: 50; to: 200; step: 10; value: root.r.mouseScroll; onMoved: v => { root.r.mouseScroll = v; Rules.input(); } }
            }
            Row {
                spacing: 20
                Toggle { text: "mouse · natural scroll"; on: root.r.mouseNatural; onFlip: { root.r.mouseNatural = !root.r.mouseNatural; Rules.input(); } }
            }
            Row {
                spacing: 20
                Toggle { text: "natural scroll"; on: root.r.natural; onFlip: { root.r.natural = !root.r.natural; Rules.input(); } }
                Toggle { text: "tap to click"; on: root.r.tap; onFlip: { root.r.tap = !root.r.tap; Rules.input(); } }
                Toggle { text: "off while typing"; on: root.r.typingOff; onFlip: { root.r.typingOff = !root.r.typingOff; Rules.input(); } }
                Toggle { text: "flat accel"; on: root.r.flat; onFlip: { root.r.flat = !root.r.flat; Rules.input(); } }
                Toggle { text: "shell sets input"; on: root.r.manageInput; onFlip: { root.r.manageInput = !root.r.manageInput; if (root.r.manageInput) Rules.input(); } }
            }
            Pick { label: "layout switch"; opts: Rules.switches.map(s => s[0]); cur: root.r.kbSwitch; onPicked: i => { root.r.kbSwitch = i; Rules.input(); } }
        }

        // ---- IDLE: minute scale without input. Dots dim on each event: awake -> locked -> screen off -> asleep.
        // Labels stretch along, past 60 -- never ----
        Page {
            k: 10
            caption: "idle · minutes without input · hypridle"

            Item {
                id: line
                width: 1000
                height: 300
                readonly property var at: [lk.v, dpms.v, zz.v]

                Repeater {
                    model: 61
                    Rectangle {
                        required property int index
                        readonly property int lvl: line.at.filter(m => m && m <= index).length
                        x: index * 15 - 4
                        y: 246
                        width: 8
                        height: 8
                        radius: 4
                        color: [Theme.fg, Theme.grey, Theme.mute, Theme.s3][lvl]
                    }
                }
                // never -- an empty ring beyond the scale
                Rectangle { x: 62 * 15 - 7; y: 243; width: 14; height: 14; radius: 7; color: "transparent"; border { width: 1; color: Theme.mute } }
                Repeater {
                    model: [0, 15, 30, 45, 60]
                    Lb { required property int modelData; x: modelData * 15 - width / 2; y: 272; text: modelData; px: 10 }
                }
                Lb { x: 62 * 15 - width / 2; y: 272; text: "never"; px: 10 }

                Mark { id: lk; row: 0; label: "lock"; value: root.r.lockAfter; onMoved: v => { root.r.lockAfter = v; Rules.idle(); } }
                Mark { id: dpms; row: 1; label: "screen off"; value: root.r.dpmsAfter; onMoved: v => { root.r.dpmsAfter = v; Rules.idle(); } }
                Mark { id: zz; row: 2; label: Rules.hibernateOn ? "sleep · hibernate" : "sleep"; value: root.r.sleepAfter; onMoved: v => { root.r.sleepAfter = v; Rules.idle(); } }
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
            Row {
                spacing: 24
                Pick { label: "sleep into"; visible: Rules.canHibernate; opts: ["suspend", "hibernate"]; cur: root.r.hibernate ? 1 : 0; onPicked: i => { root.r.hibernate = i === 1; Rules.idle(); } }
                Toggle { text: "caffeine"; on: Sys.caffeine; onFlip: Sys.caffeine = !Sys.caffeine }
            }
        }

        // ---- SHELL: the rice mark and the name of the live shell; the switcher -- the Rice app ----
        Page {
            k: 11
            caption: "shell · quickshell"

            Row {
                spacing: 50
                Item {
                    width: 260
                    height: 260
                    Ring { anchors.fill: parent; n: 16; dot: 14; f: 1 }
                    Rectangle { anchors.centerIn: parent; width: 52; height: 52; radius: 26; color: Theme.fg }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 18
                    Lb { text: "running now" }
                    Num { text: root.meta.name ?? "GALAGA"; font.pixelSize: 140 }
                    Lb { text: root.meta.tagline ?? "" }
                }
            }
            Row {
                spacing: 20
                Act {
                    visible: root.shells > 1
                    icon: "\u{F04E1}"
                    text: "switch shell"
                    onHit: {
                        root.close();
                        Quickshell.execDetached(["qs", "-c", "rice"]);
                    }
                }
                Act { icon: "\u{F0450}"; text: "reload"; onHit: Quickshell.reload(false) }
                Toggle { text: "do not disturb"; on: Theme.state.dnd; onFlip: Theme.state.dnd = !Theme.state.dnd }
            }
        }

        // ---- FEATURES: one persisted switch per feature of the programme; off -- the feature is fully inert.
        // Grouped by what the feature touches. The detailed controls live with their feature: theme and
        // its times on STYLE (the theme switch used to sit here too -- one home per setting, so it went),
        // desktop names/walls in DESKTOPS, the profile photo in LOCK. Essential notifications
        // has a page of its own (ESSENTIAL) ----
        Page {
            id: feats
            k: 12
            caption: "features · one switch each · off is fully off"

            Column {
                spacing: 10
                FeatHead { text: "genie" }
                Grid {
                    columns: 2
                    spacing: 14
                    Toggle { width: 250; text: "genie · minimise"; on: Theme.state.genie; onFlip: Theme.state.genie = !Theme.state.genie }
                    Toggle { width: 250; text: "genie · restore"; on: Theme.state.featGenieBack; onFlip: Theme.state.featGenieBack = !Theme.state.featGenieBack }
                }
            }
            Column {
                spacing: 10
                FeatHead { text: "interface" }
                Grid {
                    columns: 2
                    spacing: 14
                    Toggle { width: 250; text: "reactive edges"; on: Theme.state.featEdges; onFlip: Theme.state.featEdges = !Theme.state.featEdges }
                    Toggle { width: 250; text: "exposé"; on: Theme.state.featExpose; onFlip: Theme.state.featExpose = !Theme.state.featExpose }
                    Toggle { width: 250; text: "launcher smarts"; on: Theme.state.featLauncher; onFlip: Theme.state.featLauncher = !Theme.state.featLauncher }
                    Toggle { width: 250; text: "focus in bar"; on: Theme.state.featFocus; onFlip: Theme.state.featFocus = !Theme.state.featFocus }
                    Toggle { width: 250; text: "named desktops"; on: Theme.state.featDesktops; onFlip: Theme.state.featDesktops = !Theme.state.featDesktops }
                }
            }
            Column {
                spacing: 10
                FeatHead { text: "system" }
                Grid {
                    columns: 2
                    spacing: 14
                    Toggle { width: 250; text: "shot text + qr"; on: Theme.state.featShot; onFlip: Theme.state.featShot = !Theme.state.featShot }
                    Toggle { width: 250; text: "auto game mode"; on: Theme.state.featGameAuto; onFlip: Theme.state.featGameAuto = !Theme.state.featGameAuto }
                    Toggle { width: 250; text: "sounds"; on: Theme.state.sounds; onFlip: { Theme.state.sounds = !Theme.state.sounds; if (Theme.state.sounds) Sounds.play("pop"); } }
                }
            }

            // the first-login card (welcome/Welcome.qml): bring it back
            Row {
                spacing: 14
                Lb { anchors.verticalCenter: parent.verticalCenter; text: "welcome card" }
                Rectangle {
                    width: showL.implicitWidth + 28
                    height: 32
                    radius: 16
                    color: Theme.s2
                    Lb { id: showL; anchors.centerIn: parent; text: "show"; px: 11; color: Theme.fg }
                    TapHandler { onTapped: { Theme.state.welcomed = false; root.close(); } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Lb { anchors.verticalCenter: parent.verticalCenter; text: "the keys, once more"; px: 10; color: Theme.mute }
            }
        }

        // ---- ESSENTIAL: who gets through. While the mode is on, only the picked apps
        // arrive out loud (island, edge flash, sound); the rest still land in quick
        // settings, muted, and critical notifications always come through (Notes.qml).
        // The list is kept with the mode off. It was a section of FEATURES until it
        // outgrew it; the mode and the list live here now ----
        Page {
            id: ess
            k: 13
            caption: "essential · who gets through"

            // installed apps for the essential picker -- built once the entry list settles,
            // like the launcher (DesktopEntries trickles in at startup)
            property var apps: []
            Timer {
                id: fAppsT
                interval: 300
                running: true
                onTriggered: ess.apps = DesktopEntries.applications.values.filter(e => !e.noDisplay)
                    .map(e => ({ id: e.id, name: e.name, src: e.icon ? Quickshell.iconPath(e.icon, true) : "" }))
                    .sort((a, b) => a.name.localeCompare(b.name))
            }
            Connections {
                target: DesktopEntries.applications
                function onValuesChanged() { fAppsT.restart(); }
            }
            property string essQuery: ""
            readonly property var essList: apps.filter(a => !essQuery || a.name.toLowerCase().includes(essQuery))
            function flipApp(id) {
                const a = Theme.state.essentialApps.slice(), i = a.indexOf(id);
                if (i >= 0) a.splice(i, 1); else a.push(id);
                Theme.state.essentialApps = a;
            }


            Column {
                spacing: 12
                Row {
                    spacing: 14
                    Toggle { width: 250; text: "essential only"; on: Theme.state.featEssential; onFlip: Theme.state.featEssential = !Theme.state.featEssential }
                    Lb { anchors.verticalCenter: parent.verticalCenter; visible: Theme.state.featEssential; text: `${Theme.state.essentialApps.length} picked`; px: 11; color: Theme.mute }
                    Lb { anchors.verticalCenter: parent.verticalCenter; visible: !Theme.state.featEssential; text: "mode off -- the list waits"; px: 10; color: Theme.mute }
                }
                Lb {
                    width: 514
                    wrapMode: Text.WordWrap
                    text: "picked apps light the island, flash the edges and make the sound. everything else still arrives -- muted, in quick settings. critical notifications always come through."
                    px: 10
                    color: Theme.mute
                }
                Lb {
                    visible: Theme.state.featEssential && Theme.state.essentialApps.length === 0
                    width: 514
                    wrapMode: Text.WordWrap
                    text: "nothing picked yet -- with the mode on, everything but critical arrives muted"
                    px: 10
                    color: Theme.red
                }
                Rectangle {
                    width: 514
                    height: 44
                    radius: 22
                    color: Theme.s2
                    TextInput {
                        id: essIn
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        selectionColor: Theme.s3
                        selectedTextColor: Theme.fg
                        font { family: Theme.ui; pixelSize: 14 }
                        clip: true
                        onTextChanged: ess.essQuery = text.trim().toLowerCase()
                    }
                    Lb { visible: !essIn.text && !essIn.activeFocus; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "search apps"; px: 11 }
                }
                Flickable {
                    width: 514
                    height: 336
                    clip: true
                    contentHeight: pickCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: pickCol
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: ess.essList
                            Rectangle {
                                id: prow
                                required property var modelData
                                readonly property bool on: Theme.state.essentialApps.includes(modelData.id)
                                width: pickCol.width
                                height: 48
                                radius: 14
                                color: on ? Theme.s2 : "transparent"
                                border { width: 1; color: on ? Theme.s3 : "transparent" }
                                Behavior on color { ColorAnimation { duration: Theme.t } }
                                Image {
                                    x: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    visible: status === Image.Ready
                                    source: prow.modelData.src
                                    sourceSize: Qt.size(24, 24)
                                }
                                Lb {
                                    x: 48
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 110
                                    elide: Text.ElideRight
                                    text: prow.modelData.name
                                    color: prow.on ? Theme.fg : Theme.grey
                                }
                                Rectangle {
                                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: prow.on ? Theme.fg : "transparent"
                                    border { width: 1.5; color: prow.on ? Theme.fg : Theme.mute }
                                    Behavior on color { ColorAnimation { duration: Theme.t } }
                                    Rectangle { visible: prow.on; anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.red }
                                }
                                TapHandler { onTapped: ess.flipApp(prow.modelData.id) }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
                Lb { visible: ess.essList.length === 0 && ess.essQuery !== ""; text: "no app matches the search"; px: 10; color: Theme.mute }
            }

        }

        // ---- DESKTOPS: a name and a wallpaper per workspace (prefs FEATURES -> named desktops).
        // Unset -- the shell defaults: the number, the global wallpaper. The wallpaper is one of
        // the wall folder's files; picking one makes its screen copy in the wall cache, the same
        // conversion the wallpaper picker runs, so the wave crossfade has pixels to work with ----
        Page {
            id: dpage
            k: 14
            caption: "name + wallpaper per desktop"
            property int dws: 1
            property var wallFiles: []
            readonly property string wres: {
                const s = Quickshell.screens[0];
                return s ? `${Math.round(s.width * s.devicePixelRatio)}x${Math.round(s.height * s.devicePixelRatio)}^` : "2880x1800^";
            }
            onVisibleChanged: if (visible) { wscan.running = true; nameIn.text = Theme.state.wsNames[String(dws)] ?? ""; }
            onDwsChanged: nameIn.text = Theme.state.wsNames[String(dws)] ?? ""
            function setName(v) {
                const n = Object.assign({}, Theme.state.wsNames);
                if (v) n[String(dws)] = v; else delete n[String(dws)];
                Theme.state.wsNames = n;
            }
            function setWall(p) {
                const w = Object.assign({}, Theme.state.wsWalls);
                if (p) w[String(dws)] = p; else delete w[String(dws)];
                Theme.state.wsWalls = w;
                if (p) wcopy.exec(["bash", "-c", "b=$(basename \"$1\"); [ \"$2/$b.jpg\" -nt \"$1\" ] || { magick \"$1[0]\" -resize \"$3\" -quality 90 \"$2/.$b.jpg\" 2>/dev/null && mv \"$2/.$b.jpg\" \"$2/$b.jpg\"; }", "bash", p, Theme.wallCache, wres]);
            }
            Process {
                id: wscan
                command: ["bash", "-c", "shopt -s nullglob nocaseglob; for f in \"$1\"/*.{jpg,jpeg,png,webp}; do printf '%s\n' \"$f\"; done", "bash", Theme.state.wallDir || Quickshell.env("HOME") + "/Pictures/Wallpapers"]
                stdout: StdioCollector { onStreamFinished: dpage.wallFiles = text.split("\n").filter(Boolean).sort() }
            }
            Process { id: wcopy }

            Lb { visible: !Theme.state.featDesktops; text: "off -- turn on FEATURES → named desktops; what you set here waits"; px: 11; color: Theme.red }
            Row {
                spacing: 10
                Repeater {
                    model: 10
                    Rectangle {
                        id: dchip
                        required property int index
                        width: 40
                        height: 40
                        radius: 20
                        color: dpage.dws === index + 1 ? Theme.fg : Theme.s2
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        Num { anchors.centerIn: parent; text: dchip.index + 1; font.pixelSize: 15; color: dpage.dws === dchip.index + 1 ? Theme.ink : Theme.fg }
                        TapHandler { onTapped: dpage.dws = dchip.index + 1 }
                    }
                }
            }
            Row {
                spacing: 12
                Rectangle {
                    width: 300
                    height: 44
                    radius: 22
                    color: Theme.s2
                    TextInput {
                        id: nameIn
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        selectionColor: Theme.s3
                        selectedTextColor: Theme.fg
                        font { family: Theme.ui; pixelSize: 14 }
                        clip: true
                        onAccepted: dpage.setName(text.trim())
                    }
                    Lb { visible: !nameIn.text && !nameIn.activeFocus; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "name -- empty is the number"; px: 11 }
                }
                Act { text: "set name"; onHit: dpage.setName(nameIn.text.trim()) }
                Act { text: "clear"; onHit: { dpage.setName(""); nameIn.text = ""; } }
            }
            Pick {
                label: "wallpaper"
                width: 514
                opts: ["default"].concat(dpage.wallFiles.map(p => p.slice(p.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "")))
                cur: Math.max(0, dpage.wallFiles.indexOf(Theme.state.wsWalls[String(dpage.dws)] ?? "") + 1)
                onPicked: i => dpage.setWall(i === 0 ? "" : dpage.wallFiles[i - 1])
            }
            Lb { text: "the name shows on the desktops overview; the wallpaper crossfades in on switch"; px: 10; color: Theme.mute }
        }
    }

    // the hex picker (STYLE): one instance over the pages, opened by root.openPicker
    HexPick { id: picker; anchors.centerIn: parent; z: 100 }

    // section on the right: only the selected one is visible (Tab walks only visible ones), appears bottom-up
    // the colour picker behind STYLE's wells: a saturation/value square over the pure hue,
    // a hue strip under it, and a hex field for typing the exact colour. It works on a draft --
    // the system changes on "set", once, through Theme.setCustom; "reset" drops this one
    // colour's custom and the palette's own value returns
    component HexPick: Rectangle {
        id: hp
        property string key: ""
        property string label: ""
        property real h: 0
        property real sv: 1
        property real vv: 1
        readonly property color draft: Qt.hsva(h, sv, vv, 1)
        readonly property string draftHex: "#" + Theme.hex(draft)
        function open(k, name) {
            key = k;
            label = name;
            const c = Qt.color(root.liveHex(k));
            h = c.hsvHue < 0 ? 0 : c.hsvHue;
            sv = c.hsvSaturation;
            vv = c.hsvValue;
            hexIn.text = root.liveHex(k);
            visible = true;
            hexIn.forceActiveFocus();
        }
        function commit() { Theme.setCustom(key, draftHex); visible = false; stage.forceActiveFocus(); }
        function drop() { Theme.setCustom(key, null); visible = false; stage.forceActiveFocus(); }
        visible: false
        width: 400
        height: 446
        radius: Theme.corner(24)
        color: Theme.s1
        border { width: 1; color: Theme.s3 }
        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 14
            Row {
                spacing: 10
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Theme.red }
                Lb { text: hp.label; px: 13; color: Theme.fg }
                Lb { text: Theme.state.custom[hp.key] ? "· your colour" : "· from the palette"; px: 10; color: Theme.mute }
            }
            Rectangle {
                id: svBox
                width: parent.width
                height: 186
                radius: Theme.corner(14)
                color: Qt.hsva(hp.h, 1, 1, 1)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.corner(14)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#FFFFFF" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.corner(14)
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: "#000000" }
                    }
                }
                Rectangle {
                    x: hp.sv * parent.width - 9
                    y: (1 - hp.vv) * parent.height - 9
                    width: 18
                    height: 18
                    radius: 9
                    color: hp.draft
                    border { width: 2; color: "#FFFFFF" }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: m => setSv(m)
                    onPositionChanged: m => { if (pressed) setSv(m); }
                    function setSv(m) {
                        hp.sv = Math.max(0, Math.min(1, m.x / width));
                        hp.vv = 1 - Math.max(0, Math.min(1, m.y / height));
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 16
                radius: 8
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#FF0000" }
                    GradientStop { position: 0.17; color: "#FFFF00" }
                    GradientStop { position: 0.33; color: "#00FF00" }
                    GradientStop { position: 0.5; color: "#00FFFF" }
                    GradientStop { position: 0.67; color: "#0000FF" }
                    GradientStop { position: 0.83; color: "#FF00FF" }
                    GradientStop { position: 1; color: "#FF0000" }
                }
                Rectangle {
                    x: hp.h * parent.width - 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 22
                    radius: 4
                    color: Qt.hsva(hp.h, 1, 1, 1)
                    border { width: 2; color: "#FFFFFF" }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: m => hp.h = Math.max(0, Math.min(1, m.x / width))
                    onPositionChanged: m => { if (pressed) hp.h = Math.max(0, Math.min(1, m.x / width)); }
                }
            }
            Row {
                spacing: 12
                Rectangle { width: 44; height: 44; radius: Theme.corner(12); color: hp.draft; border { width: 1; color: Theme.s3 } }
                Rectangle {
                    width: 158
                    height: 44
                    radius: 22
                    color: Theme.s2
                    border { width: hexIn.activeFocus ? 1 : 0; color: Theme.fg }
                    TextInput {
                        id: hexIn
                        anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        font { family: Theme.mono; pixelSize: 15 }
                        color: Theme.fg
                        selectionColor: Theme.s3
                        clip: true
                        onEditingFinished: {
                            const t = text.trim();
                            if (/^#?[0-9a-fA-F]{6}$/.test(t)) {
                                const c = Qt.color(t.startsWith("#") ? t : "#" + t);
                                hp.h = c.hsvHue < 0 ? 0 : c.hsvHue;
                                hp.sv = c.hsvSaturation;
                                hp.vv = c.hsvValue;
                            }
                            text = hp.draftHex;
                        }
                    }
                }
                Lb { anchors.verticalCenter: parent.verticalCenter; text: "hex"; px: 10; color: Theme.mute }
            }
            Row {
                spacing: 10
                Act { icon: "\u{F012C}"; text: "set"; onHit: hp.commit() }
                Act { visible: !!Theme.state.custom[hp.key]; icon: "\u{F0156}"; text: "reset"; onHit: hp.drop() }
                Act { text: "cancel"; onHit: { hp.visible = false; stage.forceActiveFocus(); } }
            }
        }
        Keys.onEscapePressed: { visible = false; stage.forceActiveFocus(); }
    }

    // a group head (FEATURES): red dot + caps label
    component FeatHead: Row {
        id: fh
        property string text
        spacing: 10
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.red }
        Lb { text: fh.text; px: 12; color: Theme.grey }
    }

    component Page: Column {
        required property int k
        property string caption
        x: 800
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: visible ? 0 : 24
        visible: root.sel === k
        opacity: visible ? 1 : 0
        spacing: 28
        Behavior on opacity { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
        Lb { text: parent.caption }
    }

    // screen in 16:10 miniature: wallpaper (dot grid, if enabled) and bar; k -- logical screen px in layout px
    component Mini: Rectangle {
        readonly property real k: width / (Rules.mon.w ? Rules.mon.w / Rules.scale : Quickshell.screens[0]?.width ?? 1920)
        width: 760
        height: 475
        radius: 24
        color: Theme.bg
        border { width: 1; color: Theme.s3 }
        Image {
            visible: Theme.state.grid
            anchors { fill: parent; margins: 12 }
            fillMode: Image.Tile
            source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="1" fill="#${Theme.hex(Theme.s2)}"/></svg>`)
        }
        // the bar at its own edge: the offset 14 and thickness 64 are layout px, on screen they are Theme.s logical ones
        Rectangle {
            readonly property real u: Theme.s * parent.k
            readonly property bool onTop: Theme.state.barAt === "top"
            x: 14 * u
            y: 14 * u
            width: onTop ? parent.width - 28 * u : 64 * u
            height: onTop ? 64 * u : parent.height - 28 * u
            radius: Theme.corner(Math.min(width, height) / 2)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
        }
    }

    // empty mockup cell: 4 x 4 dimmed dots
    component Dots: Grid {
        columns: 4
        padding: 30
        spacing: 28
        Repeater {
            model: 16
            Rectangle { width: 6; height: 6; radius: 3; color: Theme.s3 }
        }
    }

    // widget in the home mockup: circle or 40 square (scaled), dotted icon, name. Selected -- white outline,
    // in focus -- entirely white. Did not fit -- pale outline
    component Tile: Rectangle {
        id: tile
        required property var modelData // { id, i, row, col, span, fits }
        property real cell: 168
        property real gap: 16
        readonly property bool on: home.cur === modelData.i
        readonly property bool hot: on && grid.activeFocus
        readonly property bool round: root.rounds.includes(modelData.id)
        width: modelData.span * cell + (modelData.span - 1) * gap
        height: cell
        radius: round ? cell / 2 : Theme.corner(cell * 0.18)
        color: hot ? Theme.fg : modelData.fits ? Theme.s1 : "transparent"
        border { width: on ? 2 : 1; color: on ? Theme.fg : modelData.fits ? Theme.s2 : Theme.mute }
        z: drag.active ? 1 : 0
        // without target the shift is in scene px, while Stage is scaled
        readonly property real dx: drag.activeTranslation.x / Theme.s
        readonly property real dy: drag.activeTranslation.y / Theme.s
        transform: Translate { x: drag.active ? tile.dx : 0; y: drag.active ? tile.dy : 0 }
        Behavior on color { ColorAnimation { duration: Theme.t } }

        Ring {
            visible: tile.round && tile.cell > 100
            anchors { fill: parent; margins: 10 }
            n: 40
            dot: 4
            f: 0.66
            on: tile.hot ? Theme.ink : Theme.fg
            off: tile.hot ? Theme.fade(Theme.ink, 0.15) : Theme.s3
        }
        Column {
            anchors.centerIn: parent
            spacing: 10
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.icons[tile.modelData.id] ?? "?"
                font.pixelSize: tile.cell * 0.26
                color: tile.hot ? Theme.ink : tile.modelData.fits ? Theme.fg : Theme.grey
                layer.enabled: true
                layer.effect: Dm { step: 3 }
            }
            Lb { visible: tile.cell > 100; anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.id; px: 10; color: tile.hot ? Theme.ink : Theme.grey }
        }
        TapHandler { onTapped: home.tap(tile.modelData.i) }
        // drop -- after the signal: changing the list recreates the tiles, including this one
        DragHandler {
            id: drag
            target: null
            onActiveChanged: {
                if (active) {
                    home.cur = tile.modelData.i;
                    return;
                }
                const p = grid.mapFromItem(tile.parent, tile.x + tile.width / 2 + tile.dx, tile.y + tile.height / 2 + tile.dy);
                Qt.callLater(home.land, tile.modelData.i, p);
            }
        }
    }

    // idle label: leg to the scale, Doto number and name. Drag along the scale, left/right -- by a minute; past 60 -- never (0).
    // while dragging -- its own v, in rules.json and hypridle -- on release or after 400 ms of silence
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

        x: (v || 62) * 15
        y: row * 76
        width: 160
        height: 250 - y
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
            Num { text: mk.v || "—"; font.pixelSize: 44 }
            Lb { topPadding: 6; text: mk.label; px: 10; color: mk.activeFocus ? Theme.fg : Theme.grey }
        }
        MouseArea {
            id: ma
            width: parent.width
            height: 76
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            onPressed: mk.forceActiveFocus()
            onPositionChanged: e => mk.put(mapToItem(line, e.x, 0).x / 15)
            onReleased: {
                wait.stop();
                if (mk.v !== mk.value) mk.moved(mk.v);
            }
        }
    }

    // button: pill with an icon in a circle. Click, Enter, space
    component Act: Rectangle {
        id: act
        property string icon
        property string text
        signal hit
        width: actL.implicitWidth + 110
        height: 64
        radius: 32
        color: Theme.s2
        border { width: activeFocus ? 1 : 0; color: Theme.fg }
        activeFocusOnTab: true
        Keys.onPressed: e => {
            if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
            act.hit();
            e.accepted = true;
        }
        Rectangle {
            x: 6
            y: 6
            width: 52
            height: 52
            radius: 26
            color: Theme.s3
            Icon { anchors.centerIn: parent; text: act.icon; font.pixelSize: 22 }
        }
        Lb { id: actL; x: 76; anchors.verticalCenter: parent.verticalCenter; text: act.text; color: act.activeFocus ? Theme.fg : Theme.grey }
        TapHandler { onTapped: act.hit() }
    }

    // small round stepper button (theme times)
    component Round: Rectangle {
        id: rd
        property string text
        signal hit
        width: 40
        height: 40
        radius: 20
        color: rd.activeFocus ? Theme.s3 : Theme.s2
        activeFocusOnTab: true
        Keys.onPressed: e => {
            if (e.key !== Qt.Key_Space && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter) return;
            rd.hit();
            e.accepted = true;
        }
        Text {
            anchors.centerIn: parent
            text: rd.text
            font { family: Theme.ui; pixelSize: 20 }
            color: Theme.fg
        }
        TapHandler { onTapped: rd.hit() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    // a time of day: Doto hh:mm, steppers move 15 minutes (wraps at midnight)
    component TimeStep: Row {
        id: ts
        property string label
        property int value // minutes after midnight
        signal moved(int v)
        spacing: 12
        function put(v) { ts.moved(((v % 1440) + 1440) % 1440); }
        Lb { anchors.verticalCenter: parent.verticalCenter; text: ts.label }
        Round { text: "−"; onHit: ts.put(ts.value - 15) }
        Num {
            anchors.verticalCenter: parent.verticalCenter
            text: `${String(Math.floor(ts.value / 60)).padStart(2, "0")}:${String(ts.value % 60).padStart(2, "0")}`
            font.pixelSize: 34
        }
        Round { text: "+"; onHit: ts.put(ts.value + 15) }
    }
}
