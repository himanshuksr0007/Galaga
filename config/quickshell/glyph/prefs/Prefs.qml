import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.settings

// glyph settings: Super+I. Not a form but objects. On the left a column of Doto words, as in the power menu -- the selected one large, with a red
// dot. On the right the section live: home -- a 3 x 3 bento mockup, deck -- a screen with a panel at the edge, windows -- a desktop with gaps,
// idle -- a minute scale along which the screen dims. Numbers -- rings of dots (drag around, wheel), toggles -- pills,
// where white slides in. Up/down -- sections, Tab -- between objects, left/right -- change, esc -- close.
// Everything applied immediately: Theme.state (glyph.json) and Rules.store (rules.json, shared with demonshot) + the needed apply.
// Gaps/border/blur/shadows -- via Theme.apply: Rules.windows() would give windows the demonshot look
PanelWindow {
    id: root

    property int sel: 0
    signal wallRequested // wallpapers -- their own screen (wall/Walls), opened by shell.qml
    readonly property var sections: ["HOME", "DECK", "BAR", "LOOK", "WINDOWS", "DISPLAY", "AUDIO", "POWER", "INPUT", "IDLE", "SHELL", "FEATURES", "DESKTOPS"]
    readonly property string moves: "shift ←→ move · ↵ swap · del drop · drag"
    readonly property string rings: "drag round the rings · scroll"
    readonly property var hints: [moves, moves, moves, "", rings, rings, "click or ←→ a device", "↵ or click a mode", rings, "drag the marks", "", "", ""]
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

    // ---- opening: its own animation (glyph layers in hypr have no_anim). The section is remembered between openings ----
    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
    function open() {
        shown = true;
        stage.forceActiveFocus();
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    function go(i) {
        sel = (i + sections.length) % sections.length;
        stage.forceActiveFocus(); // focus would be lost in a hidden section
    }

    // ---- id lists in Theme.state: home widgets, deck sections, bar tray. We edit a copy -- JsonAdapter writes the file on assignment.
    // All return a new cursor ----
    function edit(key, f) {
        const a = Theme.state[key].slice();
        f(a);
        Theme.state[key] = a;
    }
    function move(key, i, to) {
        if (to < 0 || to >= Theme.state[key].length || to === i) return i;
        edit(key, a => a.splice(to, 0, a.splice(i, 1)[0]));
        return to;
    }
    function cut(key, i) {
        const n = Theme.state[key].length;
        if (i >= n) return i;
        edit(key, a => a.splice(i, 1));
        return Math.max(0, Math.min(i, n - 2));
    }
    // Enter on the selected one: the next from all that is not there yet. In an empty list -- the first free one
    function cycle(key, i, all) {
        const a = Theme.state[key];
        if (all.every(k => a.includes(k))) return i;
        i = Math.min(i, a.length);
        let j = all.indexOf(a[i]);
        do j = (j + 1) % all.length; while (a.includes(all[j]));
        edit(key, b => b[i] = all[j]);
        return i;
    }
    // tray: if present -- remove, if not -- insert after the selected one
    function flip(key, w, cur) {
        const a = Theme.state[key], i = a.indexOf(w);
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
        const n = Theme.state[key].length, d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
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
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-prefs"

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
        // drag -- take the place of the one you dropped onto. What did not fit in 3 x 3 -- on the right as a pale outline ----
        Page {
            id: home
            k: 0
            caption: `home · bento 3 × 3 · ${used} of 9 cells`
            readonly property var cells: root.pack(Theme.state.widgets)
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
                        radius: 40
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

        // ---- BAR: bar tray stacked, as in the bar -- top to bottom; labels on the side. Tray -- what exists ----
        Page {
            id: bar
            k: 2
            caption: `bar · ${Theme.state.bar.length} of ${Theme.bars.length} in the tray · left edge`
            property int cur: 0
            // dragging from (-1 -- none): dy -- cursor shift in layout px, at -- where it is in the column, to -- where it will land
            property int from: -1
            property real dy: 0
            readonly property real at: Math.max(10, Math.min(10 + (Theme.state.bar.length - 1) * 68, 10 + from * 68 + dy))
            readonly property int to: Math.round((at - 10) / 68)

            Row {
                spacing: 200

                Rectangle {
                    id: col
                    width: 88
                    height: Math.max(1, Theme.state.bar.length) * 68 + 20
                    radius: 44
                    color: Theme.s1
                    border { width: 1; color: col.activeFocus ? Theme.fg : Theme.s2 }
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
                            y: bd.active ? bar.at : 10 + slot * 68
                            width: col.width
                            height: 68
                            z: bd.active ? 1 : 0
                            Behavior on y {
                                enabled: !bd.active
                                NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 52
                                height: 52
                                radius: 26
                                color: bs.hot ? Theme.fg : Theme.s2
                                border { width: bs.on && !bs.hot ? 1 : 0; color: Theme.fg }
                                Icon { anchors.centerIn: parent; text: root.icons[bs.modelData] ?? ""; font.pixelSize: 22; color: bs.hot ? Theme.ink : Theme.fg }
                            }
                            Lb { x: parent.width + 24; anchors.verticalCenter: parent.verticalCenter; text: bs.modelData; px: 10; color: bs.on ? Theme.fg : Theme.grey }
                            TapHandler {
                                onTapped: {
                                    col.forceActiveFocus();
                                    bar.cur = bar.cur === bs.index ? root.cycle("bar", bs.index, Theme.bars) : bs.index;
                                }
                            }
                            DragHandler {
                                id: bd
                                target: null
                                xAxis.enabled: false
                                onActiveTranslationChanged: bar.dy = activeTranslation.y / Theme.s
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
                    Toggle { width: 200; text: "window title"; on: Theme.state.barTitle; onFlip: Theme.state.barTitle = !Theme.state.barTitle }
                    Lb { topPadding: 6; text: "above the clock"; px: 10 }
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

            // profile photo: set copies the file next to glyph.json (state.avatar) and to
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
                    "glyph-photo", p]);
            }
            function clearPhoto() { photoClear.running = true; }
            Process {
                id: photoSet
                stdout: StdioCollector {
                    onStreamFinished: {
                        const t = text.trim();
                        if (t && t !== "missing") { Theme.state.avatar = t; look.photoMsg = ""; photoIn.text = ""; }
                        else look.photoMsg = "no such file";
                    }
                }
            }
            Process {
                id: photoClear
                command: ["sh", "-c",
                    'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; rm -f "$st"/avatar.*\n' +
                    'if [ -f "$st/face-backup" ]; then mv "$st/face-backup" "$HOME/.face"; else rm -f "$HOME/.face"; fi']
                onExited: { Theme.state.avatar = ""; look.photoMsg = ""; }
            }
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
                    // Glyph strips: volume on the right, progress at the bottom
                    Seg { visible: Theme.state.edges; x: parent.width - 12; y: 140; width: 4; height: 200; n: 12; f: 0.6; vertical: true }
                    Seg { visible: Theme.state.edges; x: 230; y: parent.height - 10; width: 300; height: 4; n: 24; f: 0.4 }
                }

                Column {
                    spacing: 14
                    Toggle { width: 200; text: "light"; on: Theme.light; onFlip: { Theme.state.themeMode = 0; Theme.state.light = !Theme.state.light; } }
                    Pick {
                        label: "theme"
                        opts: ["light", "dark", "auto"]
                        cur: Theme.state.themeMode === 1 ? 2 : Theme.light ? 0 : 1
                        onPicked: i => {
                            if (i === 2) Theme.state.themeMode = 1;
                            else { Theme.state.themeMode = 0; Theme.state.light = i === 0; }
                        }
                    }
                    TimeStep { visible: Theme.state.themeMode === 1; label: "light at"; value: Theme.state.lightAt; onMoved: v => Theme.state.lightAt = v }
                    TimeStep { visible: Theme.state.themeMode === 1; label: "dark at"; value: Theme.state.darkAt; onMoved: v => Theme.state.darkAt = v }
                    Toggle { width: 200; text: "dot grid"; on: Theme.state.grid; onFlip: Theme.state.grid = !Theme.state.grid }
                    Toggle { width: 200; text: "orb"; on: Theme.state.orb; onFlip: Theme.state.orb = !Theme.state.orb }
                    Toggle { width: 200; text: "24 hours"; on: Theme.state.clock24; onFlip: Theme.state.clock24 = !Theme.state.clock24 }
                    Toggle { width: 200; text: "blink"; on: Theme.state.blink; onFlip: Theme.state.blink = !Theme.state.blink }
                    Toggle { width: 200; text: "edges"; on: Theme.state.edges; onFlip: Theme.state.edges = !Theme.state.edges }
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
                    radius: 36
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
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) look.setPhoto();
                            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) root.go(root.sel + (e.key === Qt.Key_Up ? -1 : 1));
                            else if (e.key === Qt.Key_Escape) stage.forceActiveFocus();
                            else return;
                            e.accepted = true;
                        }
                    }
                }
                Act { icon: "\u{F012C}"; text: "set"; onHit: look.setPhoto() }
                Act { visible: !!Theme.state.avatar; icon: "\u{F0156}"; text: "clear"; onHit: look.clearPhoto() }
            }
            Lb { visible: !!look.photoMsg; text: look.photoMsg; px: 10; color: Theme.red }

            // name in the greeting; empty -- $USER
            Rectangle {
                width: 760
                height: 72
                radius: 36
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

        // ---- WINDOWS: desktop with two windows using live ring values. Window animation -- only if motion ----
        Page {
            k: 4
            caption: `windows · hyprland · gaps ${gIn.v} / ${gOut.v} · border ${bord.v} · rounding ${rnd.v}`

            Row {
                spacing: 40

                Mini {
                    id: desk
                    Repeater {
                        model: 2
                        Rectangle {
                            id: wnd
                            required property int index
                            readonly property real o: gOut.v * desk.k
                            readonly property real l: 78 * desk.k + o // bar 64 + gap 14
                            readonly property real w: (desk.width - l - o - 2 * gIn.v * desk.k) / 2
                            x: index ? l + w + 2 * gIn.v * desk.k : l
                            y: o
                            width: w
                            height: desk.height - 2 * o
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
            }

            Row {
                spacing: 40
                Dial { id: gIn; label: "gaps in"; to: 30; value: root.r.gapsIn; onMoved: v => { root.r.gapsIn = v; Theme.apply(); } }
                Dial { id: gOut; label: "gaps out"; to: 60; value: root.r.gapsOut; onMoved: v => { root.r.gapsOut = v; Theme.apply(); } }
                Dial { id: bord; label: "border"; to: 6; n: 24; value: root.r.border; onMoved: v => { root.r.border = v; Theme.apply(); } }
                Dial { id: rnd; label: "rounding"; to: 40; value: Theme.state.rounding; onMoved: v => Theme.state.rounding = v } // shell.qml calls Theme.apply itself
            }
        }

        // ---- DISPLAY: brightness as a big ring (live, from sysfs), screen as dots -- with scale the dots are bigger and sparser ----
        Page {
            k: 5
            caption: `display · ${Rules.mon.name.toLowerCase()} · ${Rules.hz} hz`

            Row {
                spacing: 60
                Column {
                    visible: Sys.hasBri
                    spacing: 22
                    Dial { anchors.horizontalCenter: parent.horizontalCenter; size: 340; n: 60; live: true; label: "brightness"; value: Math.round(Sys.bri * 100); onMoved: v => Sys.setBri(v / 100) }
                    // brightness key step: divisions per scale (Backlight.steps)
                    Pick { anchors.horizontalCenter: parent.horizontalCenter; label: "step"; opts: ["2.5%", "5%", "10%"]; cur: [40, 20, 10].indexOf(Theme.state.briSteps); onPicked: i => Theme.state.briSteps = [40, 20, 10][i] }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 22
                    Rectangle {
                        width: 420
                        height: 262
                        radius: 24
                        color: Theme.bg
                        border { width: 1; color: Theme.s3 }
                        Image {
                            readonly property real p: 5 * Rules.scale
                            anchors { fill: parent; margins: 14 }
                            fillMode: Image.Tile
                            source: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${p}" height="${p}"><circle cx="${p / 2}" cy="${p / 2}" r="${p * 0.2}" fill="#${Theme.hex(Theme.mute)}"/></svg>`)
                        }
                    }
                    Row {
                        spacing: 14
                        Num { id: resW; text: Math.round(Rules.mon.w / Rules.scale); font.pixelSize: 72 }
                        Num { anchors.baseline: resW.baseline; text: "×"; font.pixelSize: 40; color: Theme.mute }
                        Num { anchors.baseline: resW.baseline; text: Math.round(Rules.mon.h / Rules.scale); font.pixelSize: 72 }
                    }
                    Lb { text: "logical pixels" }
                }
            }
            Row {
                spacing: 24
                Pick { label: "scale"; opts: Rules.scales; cur: Rules.scaleIdx; onPicked: i => Rules.setScale(i) }
                Pick { label: "hz"; opts: Rules.rates.map(String); cur: Rules.rates.indexOf(Rules.refreshHz); onPicked: i => { root.r.refresh = Rules.rates[i]; Rules.monitor(); } }
            }
            Row {
                spacing: 40
                Toggle { anchors.verticalCenter: parent.verticalCenter; text: "night light"; on: Sys.night; onFlip: Sys.toggleNight() }
                Dial { label: "warmth · k"; from: 2500; to: 6500; step: 100; value: root.r.warmth; onMoved: v => { root.r.warmth = v; if (root.r.night) Rules.night(); } }
            }
        }

        // ---- AUDIO: output and input -- volume, mute, level, the default device (prefs/Audio) ----
        Page {
            id: audioPage
            k: 6
            caption: aud.caption
            Audio { id: aud; live: audioPage.visible && root.shown }
        }

        // ---- POWER: power modes (Rules.modes) -- four circles, the ring glows with strength, the selected one white.
        // ultra -- power saver plus 60 Hz, no animations, blur or shadows on top of the settings ----
        Page {
            k: 7
            caption: `power · ${Rules.modes[Rules.mode].what} · ${Rules.hz} hz`

            Row {
                spacing: 32
                Repeater {
                    model: Rules.modes.slice(0, Rules.modeCount)
                    Rectangle {
                        id: pc
                        required property var modelData
                        required property int index
                        readonly property bool on: Rules.mode === index
                        width: 230
                        height: 230
                        radius: 115
                        color: on ? Theme.fg : Theme.s1
                        border { width: activeFocus ? 2 : 1; color: activeFocus || on ? Theme.fg : Theme.s2 }
                        Behavior on color { ColorAnimation { duration: Theme.t } }
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
                            Rules.setMode(index);
                            e.accepted = true;
                        }
                        Ring { anchors { fill: parent; margins: 14 } n: 40; dot: 6; f: (pc.index + 1) / 4; on: pc.on ? Theme.ink : Theme.fg; off: pc.on ? Theme.mute : Theme.s3 }
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            Num { anchors.horizontalCenter: parent.horizontalCenter; text: pc.modelData.short; font.pixelSize: 54; color: pc.on ? Theme.ink : Theme.fg }
                            Lb { anchors.horizontalCenter: parent.horizontalCenter; text: pc.modelData.name; color: pc.on ? Theme.ink : Theme.grey }
                        }
                        TapHandler { onTapped: Rules.setMode(pc.index) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
            Lb { text: Rules.store.ultra ? `ultra · ${Rules.rates[0]} hz, no motion, no blur, no shadows — your settings come back when you leave` : "cpu profile only · hz, motion and looks stay yours" }
            Lb { visible: !PowerProfiles.hasPerformanceProfile; text: "no performance profile on this machine" }
        }

        // ---- INPUT: hold a key -- first dot immediately, delay pause, then rate per second; on live rings ----
        Page {
            id: inp
            k: 8
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
            }
            Row {
                spacing: 20
                Toggle { text: "natural scroll"; on: root.r.natural; onFlip: { root.r.natural = !root.r.natural; Rules.input(); } }
                Toggle { text: "tap to click"; on: root.r.tap; onFlip: { root.r.tap = !root.r.tap; Rules.input(); } }
                Toggle { text: "off while typing"; on: root.r.typingOff; onFlip: { root.r.typingOff = !root.r.typingOff; Rules.input(); } }
                Toggle { text: "flat accel"; on: root.r.flat; onFlip: { root.r.flat = !root.r.flat; Rules.input(); } }
            }
            Pick { label: "layout switch"; opts: Rules.switches.map(s => s[0]); cur: root.r.kbSwitch; onPicked: i => { root.r.kbSwitch = i; Rules.input(); } }
        }

        // ---- IDLE: minute scale without input. Dots dim on each event: awake -> locked -> screen off -> asleep.
        // Labels stretch along, past 60 -- never ----
        Page {
            k: 9
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
            k: 10
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
                    Num { text: root.meta.name ?? "GLYPH"; font.pixelSize: 140 }
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
        // The detailed controls live with their feature: theme times in LOOK, desktop names/walls in DESKTOPS,
        // the profile photo in LOOK. The essential app picker is below the switches, on this page ----
        Page {
            id: feats
            k: 11
            caption: "features · one switch each · off is fully off"

            // installed apps for the essential picker -- built once the entry list settles,
            // like the launcher (DesktopEntries trickles in at startup)
            property var apps: []
            Timer {
                id: fAppsT
                interval: 300
                running: true
                onTriggered: feats.apps = DesktopEntries.applications.values.filter(e => !e.noDisplay)
                    .map(e => ({ id: e.id, name: e.name, src: e.icon ? Quickshell.iconPath(e.icon, true) : "" }))
                    .sort((a, b) => a.name.localeCompare(b.name))
            }
            Connections {
                target: DesktopEntries.applications
                function onValuesChanged() { fAppsT.restart(); }
            }
            function flipApp(id) {
                const a = Theme.state.essentialApps.slice(), i = a.indexOf(id);
                if (i >= 0) a.splice(i, 1); else a.push(id);
                Theme.state.essentialApps = a;
            }

            Grid {
                columns: 2
                spacing: 14
                Toggle { width: 250; text: "genie · minimise"; on: Theme.state.genie; onFlip: Theme.state.genie = !Theme.state.genie }
                Toggle { width: 250; text: "genie · restore"; on: Theme.state.featGenieBack; onFlip: Theme.state.featGenieBack = !Theme.state.featGenieBack }
                Toggle { width: 250; text: "reactive edges"; on: Theme.state.featEdges; onFlip: Theme.state.featEdges = !Theme.state.featEdges }
                Toggle { width: 250; text: "exposé"; on: Theme.state.featExpose; onFlip: Theme.state.featExpose = !Theme.state.featExpose }
                Toggle { width: 250; text: "lock media"; on: Theme.state.featLockMedia; onFlip: Theme.state.featLockMedia = !Theme.state.featLockMedia }
                Toggle { width: 250; text: "launcher smarts"; on: Theme.state.featLauncher; onFlip: Theme.state.featLauncher = !Theme.state.featLauncher }
                Toggle { width: 250; text: "focus in bar"; on: Theme.state.featFocus; onFlip: Theme.state.featFocus = !Theme.state.featFocus }
                Toggle { width: 250; text: "named desktops"; on: Theme.state.featDesktops; onFlip: Theme.state.featDesktops = !Theme.state.featDesktops }
                Toggle { width: 250; text: "shot text + qr"; on: Theme.state.featShot; onFlip: Theme.state.featShot = !Theme.state.featShot }
                Toggle { width: 250; text: "theme · auto"; on: Theme.state.themeMode === 1; onFlip: Theme.state.themeMode = Theme.state.themeMode === 1 ? 0 : 1 }
                Toggle { width: 250; text: "essential only"; on: Theme.state.featEssential; onFlip: Theme.state.featEssential = !Theme.state.featEssential }
            }
            Lb { text: "theme times -- LOOK · desktops -- DESKTOPS · photo -- LOOK · essential apps -- below"; px: 10; color: Theme.mute }

            // essential apps: only these light the edges while "essential only" is on; the rest
            // still land in quick settings, muted. The list is kept even with the mode off.
            Column {
                spacing: 12
                Row {
                    spacing: 14
                    Lb { text: `essential apps · ${Theme.state.essentialApps.length} picked` }
                    Lb { visible: !Theme.state.featEssential; text: "mode off -- the list waits"; px: 10; color: Theme.mute }
                }
                Flickable {
                    width: 514
                    height: 296
                    clip: true
                    contentHeight: pickCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: pickCol
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: feats.apps
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
                                TapHandler { onTapped: feats.flipApp(prow.modelData.id) }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }
        }

        // ---- DESKTOPS: a name and a wallpaper per workspace (prefs FEATURES -> named desktops).
        // Unset -- the shell defaults: the number, the global wallpaper. The wallpaper is one of
        // the wall folder's files; picking one makes its screen copy in the wall cache, the same
        // conversion the wallpaper picker runs, so the wave crossfade has pixels to work with ----
        Page {
            id: dpage
            k: 12
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

    // section on the right: only the selected one is visible (Tab walks only visible ones), appears bottom-up
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
        readonly property real k: width / ((Rules.mon.w || 2880) / Rules.scale)
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
        Rectangle {
            x: 14 * parent.k
            y: 14 * parent.k
            width: 64 * parent.k
            height: parent.height - 28 * parent.k
            radius: width / 2
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
        radius: round ? cell / 2 : cell * 0.18
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
