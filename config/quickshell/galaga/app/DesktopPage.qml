import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.components
import qs.services
import qs.settings

// desktop & deck: the home bento, the deck sections and the bar tray — the
// same editors the old settings had, on cards — and a name and a wallpaper
// per desktop. Everything applied immediately through Theme.state.
// The drag math needs no scale division here: there is no stage canvas in
// the app, handler translations arrive in layout units already.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    // the screen HOME configures: on open -- the focused one; unplugged -- the
    // first. (The displays page keeps its own pick; each page remembers its.)
    property string pickMon
    readonly property var names: Quickshell.screens.map(s => s.name)
    readonly property string mon: names.includes(pickMon) ? pickMon : names[0] ?? ""
    readonly property bool multi: names.length > 1
    onActiveChanged: if (active) { pickMon = Hyprland.focusedMonitor?.name ?? pickMon; wscan.running = true; syncDeskName(); }
    onMonChanged: homeCur = 0 // another screen has its own set -- the cursor from the last one misses

    // glyphs for home views, deck sections and the bar tray
    readonly property var icons: ({
        weather: "\u{F0595}", calendar: "\u{F00ED}", cpu: "\u{F061A}", ram: "\u{F035B}", gpu: "\u{F08AE}", disk: "\u{F02CA}",
        battery: "\u{F0079}", buds: "\u{F02CB}", player: "\u{F040A}", system: "\u{F0128}", cat: "\u{F011B}", cava: "\u{F0EA2}",
        clock: "\u{F0150}", perf: "\u{F04C5}", net: "\u{F05A9}", media: "\u{F075A}",
        layout: "\u{F030C}", wifi: "\u{F05A9}", bluetooth: "\u{F00AF}", sound: "\u{F057E}", notes: "\u{F009A}", focus: "\u{F13AB}",
        mode: "\u{F04C5}", power: "\u{F0425}"
    })
    // round home widgets, the rest -- a square
    readonly property var rounds: ["weather", "cpu", "ram", "gpu", "disk", "battery", "buds", "cava"]

    // ---- id lists in Theme.state: home widgets, deck sections, bar tray. We
    // edit a copy -- JsonAdapter writes the file on assignment. All return a
    // new cursor. Widgets belong to the screen mon: with several screens an
    // edit gives it its own set; until edited -- the shared one ----
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
    // Enter on the selected one: the next from all that is not there yet. In an
    // empty list -- the first free one
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
    // list keys in focus: left/right select, shift left/right reorder,
    // Enter/space -- change view, del -- remove. -1 -- not our key
    function nav(e, key, cur, all) {
        const n = list(key).length, d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0;
        if (d && (e.modifiers & Qt.ShiftModifier)) return move(key, cur, cur + d);
        if (d) return n ? (cur + d + n) % n : 0;
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) return cycle(key, cur, all);
        if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) return cut(key, cur);
        return -1;
    }
    // bento layout, like home (and like grid-auto-flow in the concept): left
    // to right, top to bottom; does not fit in a row -- next row, the hole
    // remains; three rows, beyond that -- skipped
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

    // ---- home state ----
    property int homeCur: 0
    readonly property var homeCells: pg.pack(pg.list("widgets"))
    readonly property var homePlaced: homeCells.filter(c => c.fits)
    readonly property var homeOff: homeCells.filter(c => !c.fits)
    readonly property int homeUsed: homePlaced.reduce((a, c) => a + c.span, 0)
    readonly property var homeCurCell: homeCells[homeCur] ?? null
    function homeTap(i) {
        grid.forceActiveFocus();
        homeCur = homeCur === i ? pg.cycle("widgets", i, Object.keys(Theme.kinds)) : i;
    }
    // dropped at grid point p: on a widget -- its place, in an empty cell --
    // after the last one before it; outside the grid -- nothing
    function homeLand(i, p) {
        if (p.x < 0 || p.y < 0 || p.x > grid.width || p.y > grid.height) return;
        const at = Math.min(2, Math.floor(p.y / 184)) * 3 + Math.min(2, Math.floor(p.x / 184));
        const hit = homePlaced.find(c => c.row * 3 + c.col <= at && at < c.row * 3 + c.col + c.span);
        const n = homePlaced.filter(c => c.row * 3 + c.col < at).length; // fitted ones -- always the start of the list
        homeCur = pg.move("widgets", i, hit ? hit.i : i < n ? n - 1 : n);
    }

    // ---- deck state ----
    property int deckCur: 0
    property int deckFrom: -1 // dragging section (-1 -- none)
    property real deckDx: 0
    readonly property real deckAt: Math.max(10, Math.min(10 + (Theme.state.deck.length - 1) * 104, 10 + deckFrom * 104 + deckDx))
    readonly property int deckTo: Math.round((deckAt - 10) / 104)

    // ---- bar state ----
    property int barCur: 0
    property int barFrom: -1
    property real barD: 0
    readonly property bool barOnTop: Theme.state.barAt === "top"
    readonly property real barStep: barOnTop ? 104 : 68 // a slot along the bar
    readonly property real barAt2: Math.max(10, Math.min(10 + (Theme.state.bar.length - 1) * barStep, 10 + barFrom * barStep + barD))
    readonly property int barTo: Math.round((barAt2 - 10) / barStep)
    // a full top bar is wider than the page: the strip sits scaled to fit
    readonly property real barK: barOnTop ? Math.min(1, 800 / (Math.max(1, Theme.state.bar.length) * 104 + 20)) : 1

    // ---- desktops state: a name and a wallpaper per workspace. Unset -- the
    // shell defaults: the number, the global wallpaper. The wallpaper is one
    // of the wall folder's files; picking one makes its screen copy in the
    // wall cache, the same conversion the wallpaper picker runs ----
    property int dws: 1
    property var wallFiles: []
    readonly property string wres: {
        const s = Quickshell.screens[0];
        return s ? `${Math.round(s.width * s.devicePixelRatio)}x${Math.round(s.height * s.devicePixelRatio)}^` : "2880x1800^";
    }
    onDwsChanged: syncDeskName()
    function syncDeskName() { deskNameIn.text = Theme.state.wsNames[String(dws)] ?? ""; }
    function setDeskName(v) {
        const n = Object.assign({}, Theme.state.wsNames);
        if (v) n[String(dws)] = v; else delete n[String(dws)];
        Theme.state.wsNames = n;
    }
    function setDeskWall(p) {
        const w = Object.assign({}, Theme.state.wsWalls);
        if (p) w[String(dws)] = p; else delete w[String(dws)];
        Theme.state.wsWalls = w;
        if (p) wcopy.exec(["bash", "-c", "b=$(basename \"$1\"); [ \"$2/$b.jpg\" -nt \"$1\" ] || { magick \"$1[0]\" -resize \"$3\" -quality 90 \"$2/.$b.jpg\" 2>/dev/null && mv \"$2/.$b.jpg\" \"$2/$b.jpg\"; }", "bash", p, Theme.wallCache, wres]);
    }
    Process {
        id: wscan
        command: ["bash", "-c", "shopt -s nullglob nocaseglob; for f in \"$1\"/*.{jpg,jpeg,png,webp}; do printf '%s\n' \"$f\"; done", "bash", Theme.state.wallDir || Quickshell.env("HOME") + "/Pictures/Wallpapers"]
        stdout: StdioCollector { onStreamFinished: pg.wallFiles = text.split("\n").filter(Boolean).sort() }
    }
    Process { id: wcopy }

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

            // ---- HOME: home at 168/220 scale -- same views, order and
            // layout. Click -- select, another click or Enter -- next view,
            // drag -- take the place of the one you dropped onto. What did
            // not fit in 3 x 3 -- below as a pale outline ----
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "home" }
                Lb { text: `bento 3 × 3 · ${pg.homeUsed} of 9 cells` + (pg.multi ? ` · ${pg.mon.toLowerCase()}${Theme.scr(pg.mon, "home") ? "" : " · hidden there, displays shows it"}` : ""); px: 11; color: Theme.mute }
                SetCard {
                    visible: pg.multi
                    SetPick {
                        label: "screen"
                        opts: pg.names.map(n => n.toLowerCase())
                        cur: pg.names.indexOf(pg.mon)
                        divider: false
                        onPicked: i => pg.pickMon = pg.names[i]
                    }
                }
                Item {
                    id: grid
                    width: 536
                    height: 536
                    activeFocusOnTab: true
                    Keys.onPressed: e => {
                        const c = pg.nav(e, "widgets", pg.homeCur, Object.keys(Theme.kinds));
                        if (c < 0) return;
                        pg.homeCur = c;
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
                        model: pg.homePlaced
                        Tile {
                            x: modelData.col * 184
                            y: modelData.row * 184
                        }
                    }
                }
                Row {
                    spacing: 16
                    Num { id: usedN; text: pg.homeUsed; font.pixelSize: 54 }
                    Num { anchors.baseline: usedN.baseline; text: "/9"; font.pixelSize: 24; color: Theme.mute }
                    Lb {
                        anchors.verticalCenter: parent.verticalCenter
                        text: !pg.homeCurCell ? "empty · click a widget below to add one" : `${pg.homeCurCell.id} · ${pg.homeCurCell.span} cell${pg.homeCurCell.span > 1 ? "s" : ""}${pg.homeCurCell.fits ? "" : " · off grid"}`
                        px: 11.5
                    }
                }
                // the cat's gif (services/Gifs) -- shown while the cat is
                // selected. Click or ←→ when focused
                Column {
                    id: gifPick
                    visible: pg.homeCurCell?.id === "cat"
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
                            GifDots { anchors { fill: parent; margins: 6 } path: th.modelData; bg: th.color; playing: gifPick.visible && pg.active }
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
                Lb { text: pg.homeOff.length ? `off grid · ${pg.homeOff.length}` : "everything fits"; px: 11; color: Theme.mute }
                Flow {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: pg.homeOff
                        Tile { cell: 84; gap: 8 }
                    }
                }
                Lb { text: "widgets"; px: 11; color: Theme.mute }
                Tray {
                    fit: 820
                    ids: Object.keys(Theme.kinds)
                    icons: pg.icons
                    used: Theme.state.widgets
                    dim: pg.homeOff.map(c => c.id)
                    widths: Theme.kinds
                    onToggled: key => pg.homeCur = pg.flip("widgets", key, pg.homeCur)
                }
            }

            // ---- DECK: screen, bottom center -- deck, right -- quick
            // settings; both slide out on hovering their edge. Deck sections
            // in order, as in the panel; the tray -- which ones exist ----
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "deck" }
                Lb { text: `deck · ${Theme.state.deck.length} of ${Theme.decks.length} sections · bottom edge`; px: 11; color: Theme.mute }
                ScreenMock {
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
                        id: deckStrip
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 30 }
                        width: Math.max(1, Theme.state.deck.length) * 104 + 20
                        height: 116
                        radius: Theme.corner(40)
                        color: Theme.s1
                        border { width: 1; color: deckStrip.activeFocus ? Theme.fg : Theme.s2 }
                        Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            const c = pg.nav(e, "deck", pg.deckCur, Theme.decks);
                            if (c < 0) return;
                            pg.deckCur = c;
                            e.accepted = true;
                        }

                        Lb { visible: !Theme.state.deck.length; anchors.centerIn: parent; text: "empty" }
                        Repeater {
                            model: Theme.state.deck
                            Item {
                                id: ds
                                required property string modelData
                                required property int index
                                readonly property bool on: pg.deckCur === index
                                readonly property bool hot: on && deckStrip.activeFocus
                                // while dragging: this one follows the cursor, those between it and the drop point -- one step toward its place
                                readonly property int slot: pg.deckFrom < 0 ? index
                                    : index > pg.deckFrom && index <= pg.deckTo ? index - 1
                                    : index < pg.deckFrom && index >= pg.deckTo ? index + 1 : index
                                x: dd.active ? pg.deckAt : 10 + slot * 104
                                width: 104
                                height: deckStrip.height
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
                                        Icon { anchors.centerIn: parent; text: pg.icons[ds.modelData] ?? ""; font.pixelSize: 24; color: ds.hot ? Theme.ink : Theme.fg }
                                    }
                                    Lb { anchors.horizontalCenter: parent.horizontalCenter; text: ds.modelData; px: 10; color: ds.on ? Theme.fg : Theme.grey }
                                }
                                TapHandler {
                                    onTapped: {
                                        deckStrip.forceActiveFocus();
                                        pg.deckCur = pg.deckCur === ds.index ? pg.cycle("deck", ds.index, Theme.decks) : ds.index;
                                    }
                                }
                                DragHandler {
                                    id: dd
                                    target: null
                                    yAxis.enabled: false
                                    onActiveTranslationChanged: pg.deckDx = activeTranslation.x
                                    onActiveChanged: {
                                        if (active) {
                                            pg.deckCur = ds.index;
                                            pg.deckFrom = ds.index;
                                            return;
                                        }
                                        // drop -- after the signal: changing the list recreates the sections, including this one
                                        const from = pg.deckFrom, to = pg.deckTo;
                                        Qt.callLater(() => {
                                            pg.deckFrom = -1;
                                            pg.deckCur = pg.move("deck", from, to);
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
                SetCard {
                    SetToggle { label: "deck · hover"; on: Theme.state.deckHover; onFlip: want => Theme.state.deckHover = want }
                    SetToggle { label: "quick · hover"; on: Theme.state.quickHover; divider: false; onFlip: want => Theme.state.quickHover = want }
                    Lb { topPadding: 10; text: "bottom edge · right edge · the genie effect itself is on the features page"; px: 10.5; color: Theme.mute }
                }
                Lb { text: "sections"; px: 11; color: Theme.mute }
                Tray {
                    fit: 820
                    ids: Theme.decks
                    icons: pg.icons
                    used: Theme.state.deck
                    onToggled: key => pg.deckCur = pg.flip("deck", key, pg.deckCur)
                }
            }

            // ---- BAR: the tray in order, as in the bar: at the side a
            // column (labels beside), on top a row (labels under the icon);
            // drag -- along the bar. The pool -- what exists ----
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "bar" }
                Lb { text: `bar · ${Theme.state.bar.length} of ${Theme.bars.length} in the tray · ${pg.barOnTop ? "top" : "left"} edge`; px: 11; color: Theme.mute }
                Item {
                    width: parent.width
                    height: barStrip.height * pg.barK
                    Rectangle {
                        id: barStrip
                        scale: pg.barK
                        transformOrigin: Item.TopLeft
                        readonly property int n: Math.max(1, Theme.state.bar.length)
                        width: pg.barOnTop ? n * 104 + 20 : 88
                        height: pg.barOnTop ? 116 : n * 68 + 20
                        radius: Theme.corner(pg.barOnTop ? 40 : 44)
                        color: Theme.s1
                        border { width: 1; color: barStrip.activeFocus ? Theme.fg : Theme.s2 }
                        Behavior on width { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        Behavior on height { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            const c = pg.nav(e, "bar", pg.barCur, Theme.bars);
                            if (c < 0) return;
                            pg.barCur = c;
                            e.accepted = true;
                        }

                        Lb { visible: !Theme.state.bar.length; anchors.centerIn: parent; text: "empty"; px: 10 }
                        Repeater {
                            model: Theme.state.bar
                            Item {
                                id: bs
                                required property string modelData
                                required property int index
                                readonly property bool on: pg.barCur === index
                                readonly property bool hot: on && barStrip.activeFocus
                                readonly property int slot: pg.barFrom < 0 ? index
                                    : index > pg.barFrom && index <= pg.barTo ? index - 1
                                    : index < pg.barFrom && index >= pg.barTo ? index + 1 : index
                                // the place along the bar: behind the cursor while dragging
                                property real pos: bd.active ? pg.barAt2 : 10 + slot * pg.barStep
                                Behavior on pos {
                                    enabled: !bd.active
                                    NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide }
                                }
                                x: pg.barOnTop ? pos : 0
                                y: pg.barOnTop ? 0 : pos
                                width: pg.barOnTop ? 104 : barStrip.width
                                height: pg.barOnTop ? barStrip.height : 68
                                z: bd.active ? 1 : 0

                                Rectangle {
                                    id: bdot
                                    x: (parent.width - width) / 2
                                    y: pg.barOnTop ? 18 : (parent.height - height) / 2
                                    width: 52
                                    height: 52
                                    radius: 26
                                    color: bs.hot ? Theme.fg : Theme.s2
                                    border { width: bs.on && !bs.hot ? 1 : 0; color: Theme.fg }
                                    Icon { anchors.centerIn: parent; text: pg.icons[bs.modelData] ?? ""; font.pixelSize: 22; color: bs.hot ? Theme.ink : Theme.fg }
                                }
                                Lb {
                                    x: pg.barOnTop ? (parent.width - width) / 2 : parent.width + 24
                                    y: pg.barOnTop ? bdot.y + bdot.height + 10 : (parent.height - height) / 2
                                    text: bs.modelData
                                    px: 10
                                    color: bs.on ? Theme.fg : Theme.grey
                                }
                                TapHandler {
                                    onTapped: {
                                        barStrip.forceActiveFocus();
                                        pg.barCur = pg.barCur === bs.index ? pg.cycle("bar", bs.index, Theme.bars) : bs.index;
                                    }
                                }
                                DragHandler {
                                    id: bd
                                    target: null
                                    xAxis.enabled: pg.barOnTop
                                    yAxis.enabled: !pg.barOnTop
                                    onActiveTranslationChanged: pg.barD = (pg.barOnTop ? activeTranslation.x : activeTranslation.y)
                                    onActiveChanged: {
                                        if (active) {
                                            pg.barCur = bs.index;
                                            pg.barFrom = bs.index;
                                            return;
                                        }
                                        const from = pg.barFrom, to = pg.barTo;
                                        Qt.callLater(() => {
                                            pg.barFrom = -1;
                                            pg.barCur = pg.move("bar", from, to);
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
                SetCard {
                    Lb { text: "edge"; px: 11; color: Theme.mute }
                    // screens with the pill at their own edge; left/right -- the other one
                    Row {
                        id: edges
                        topPadding: 10
                        spacing: 20
                        activeFocusOnTab: true
                        Keys.onPressed: e => {
                            if (e.key !== Qt.Key_Left && e.key !== Qt.Key_Right && e.key !== Qt.Key_Space && e.key !== Qt.Key_Return) return;
                            Theme.state.barAt = pg.barOnTop ? "left" : "top";
                            e.accepted = true;
                        }
                        Repeater {
                            model: ["left", "top"]
                            Column {
                                id: ed
                                required property string modelData
                                readonly property bool on: (modelData === "top") === pg.barOnTop
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
                    SetToggle {
                        label: "window title"
                        sub: pg.barOnTop ? "left of the clock" : "above the clock"
                        on: Theme.state.barTitle
                        divider: false
                        onFlip: want => Theme.state.barTitle = want
                    }
                }
                Lb { text: "tray"; px: 11; color: Theme.mute }
                Tray {
                    fit: 820
                    ids: Theme.bars
                    icons: pg.icons
                    used: Theme.state.bar
                    onToggled: key => pg.barCur = pg.flip("bar", key, pg.barCur)
                }
            }

            // ---- DESKTOPS: a name and a wallpaper per workspace ----
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "desktops" }
                SetCard {
                    Lb {
                        visible: !Theme.state.featDesktops
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "off — turn on features → named desktops; what you set here waits"
                        px: 11
                        color: Theme.red
                    }
                    Row {
                        topPadding: 6
                        spacing: 10
                        Repeater {
                            model: 10
                            Rectangle {
                                id: dchip
                                required property int index
                                width: 40
                                height: 40
                                radius: 20
                                color: pg.dws === index + 1 ? Theme.fg : Theme.s2
                                Behavior on color { ColorAnimation { duration: Theme.t } }
                                Num { anchors.centerIn: parent; text: dchip.index + 1; font.pixelSize: 15; color: pg.dws === dchip.index + 1 ? Theme.ink : Theme.fg }
                                TapHandler { onTapped: pg.dws = dchip.index + 1 }
                            }
                        }
                    }
                    Row {
                        topPadding: 14
                        spacing: 12
                        Rectangle {
                            width: 380
                            height: 44
                            radius: 22
                            color: Theme.s2
                            TextInput {
                                id: deskNameIn
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.s3
                                selectedTextColor: Theme.fg
                                font { family: Theme.ui; pixelSize: 14 }
                                clip: true
                                onAccepted: pg.setDeskName(text.trim())
                                Text {
                                    visible: !deskNameIn.text
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "name — empty is the number"
                                    font { family: Theme.ui; pixelSize: 12 }
                                    color: Theme.mute
                                }
                            }
                        }
                        SetButton { anchors.verticalCenter: parent.verticalCenter; label: "set name"; onHit: pg.setDeskName(deskNameIn.text.trim()) }
                        SetButton { anchors.verticalCenter: parent.verticalCenter; label: "clear"; onHit: { pg.setDeskName(""); deskNameIn.text = ""; } }
                    }
                    Lb { topPadding: 14; text: "wallpaper"; px: 11; color: Theme.mute }
                    Flickable {
                        width: parent.width
                        height: Math.min(240, (pg.wallFiles.length + 1) * 48)
                        clip: true
                        contentWidth: width
                        contentHeight: wallCol.height
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: wallCol
                            width: parent.width
                            SetRow {
                                label: "default"
                                clickable: true
                                divider: pg.wallFiles.length > 0
                                onHit: pg.setDeskWall("")
                                Rectangle {
                                    visible: !Theme.state.wsWalls[String(pg.dws)]
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: Theme.accent
                                }
                            }
                            Repeater {
                                model: pg.wallFiles
                                SetRow {
                                    required property string modelData
                                    required property int index
                                    label: modelData.slice(modelData.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "")
                                    clickable: true
                                    divider: index < pg.wallFiles.length - 1
                                    onHit: pg.setDeskWall(modelData)
                                    Rectangle {
                                        visible: Theme.state.wsWalls[String(pg.dws)] === modelData
                                        width: 9
                                        height: 9
                                        radius: 4.5
                                        color: Theme.accent
                                    }
                                }
                            }
                        }
                    }
                    Lb {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 12
                        text: "the name shows on the desktops overview; the wallpaper crossfades in on switch"
                        px: 10.5
                        color: Theme.mute
                    }
                }
            }
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

    // widget in the home mockup: circle or square (scaled), dotted icon, name.
    // Selected -- white outline, in focus -- entirely white. Did not fit --
    // pale outline
    component Tile: Rectangle {
        id: tile
        required property var modelData // { id, i, row, col, span, fits }
        property real cell: 168
        property real gap: 16
        readonly property bool on: pg.homeCur === modelData.i
        readonly property bool hot: on && grid.activeFocus
        readonly property bool round: pg.rounds.includes(modelData.id)
        width: modelData.span * cell + (modelData.span - 1) * gap
        height: cell
        radius: round ? cell / 2 : Theme.corner(cell * 0.18)
        color: hot ? Theme.fg : modelData.fits ? Theme.s1 : "transparent"
        border { width: on ? 2 : 1; color: on ? Theme.fg : modelData.fits ? Theme.s2 : Theme.mute }
        z: drag.active ? 1 : 0
        readonly property real dx: drag.activeTranslation.x
        readonly property real dy: drag.activeTranslation.y
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
                text: pg.icons[tile.modelData.id] ?? "?"
                font.pixelSize: tile.cell * 0.26
                color: tile.hot ? Theme.ink : tile.modelData.fits ? Theme.fg : Theme.grey
                layer.enabled: true
                layer.effect: Dm { step: 3 }
            }
            Lb { visible: tile.cell > 100; anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.id; px: 10; color: tile.hot ? Theme.ink : Theme.grey }
        }
        TapHandler { onTapped: pg.homeTap(tile.modelData.i) }
        // drop -- after the signal: changing the list recreates the tiles, including this one
        DragHandler {
            id: drag
            target: null
            onActiveChanged: {
                if (active) {
                    pg.homeCur = tile.modelData.i;
                    return;
                }
                const p = grid.mapFromItem(tile.parent, tile.x + tile.width / 2 + tile.dx, tile.y + tile.height / 2 + tile.dy);
                Qt.callLater(pg.homeLand, tile.modelData.i, p);
            }
        }
    }
}
