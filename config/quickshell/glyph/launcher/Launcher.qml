import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs
import qs.components

// launcher: tap Super or Super+Space. Panel 860 centered, screen dims to 74%. Search pill with a red caret,
// modes as chips (Tab): apps / run / windows / calc / style. No query -- "recent" and all apps in a grid of 6, alphabet on the right.
// style -- colour, like scheme in caelestia: where from (nothing, wallpaper, palette), under it -- the wallpaper tones and
// variants (tonal spot...) or the palettes (catppuccin, rose pine...), the theme (Theme.styles, the same as STYLE in settings).
// Circles are samples, a dot in one -- what is set. Upstream gave style the run slot; run stays here, style is its own chip
// Appears like Charms and Clip: rises 24 and fades. Icons -- the theme's icons as dots in circles; selected -- white circle
PanelWindow {
    id: root

    property int mode: 0
    property int sel: 0
    readonly property var modes: ["apps", "run", "windows", "calc", "style", "tray"]
    readonly property string query: input.text
    property var uses: ({}) // app id -> how many times opened

    // the theme icon or the path from .desktop; none (or the file is gone) -- the
    // generic app icon, not an empty circle. Synthetic entries (files, run) keep
    // their own glyph instead -- they have no icon file at all
    function icon(name) { return Quickshell.iconPath(name || "application-x-executable", "application-x-executable"); }

    // at startup DesktopEntries adds entries one by one (~160 valuesChanged): a binding would rebuild the grid for each --
    // seconds of freeze. We build once, when the list settles
    property var apps: []
    Timer {
        id: appsT
        interval: 300
        running: true
        onTriggered: root.apps = DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => ({
            id: e.id, name: e.name, src: root.icon(e.icon),
            extra: `${e.id} ${e.genericName} ${(e.keywords ?? []).join(" ")}`.toLowerCase(), run: () => e.execute()
        })).sort((a, b) => a.name.localeCompare(b.name))
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { appsT.restart(); }
    }
    // windows -- only while the windows mode is open: otherwise any title change would rebuild the list
    // tray -- only while the tray mode is open: otherwise every new message (telegram's tooltip counter)
    // would rebuild the list. The name is the tooltip (discord's title is empty). A menu-only item
    // (onlyMenu) doesn't close the launcher on click -- its menu opens under it instead
    readonly property var tray: !visible || mode !== 5 ? [] : SystemTray.items.values.map(i => ({
        name: i.tooltipTitle || i.title || i.id, src: i.icon, extra: i.id.toLowerCase(), tray: i,
        keep: i.onlyMenu, run: () => i.onlyMenu || i.activate()
    }))
    readonly property var wins: !visible || mode !== 2 ? [] : Hyprland.toplevels.values.map(t => {
        const cls = t.lastIpcObject?.class ?? "";
        return { name: t.title, src: icon(DesktopEntries.heuristicLookup(cls)?.icon), extra: cls.toLowerCase(),
                 run: () => { focusT.addr = t.address; focusT.restart(); } };
    })
    // while the launcher holds the keyboard (Exclusive), Hyprland switches the
    // workspace but won't give the window focus -- and once the keyboard is let
    // go it refocuses the old window with its workspace. So focus once released
    // (it goes with the next frame). 100 ms is a frame's worth of slack
    Timer {
        id: focusT
        property string addr
        interval: 100
        onTriggered: Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${addr}" })`) // Quickshell gives the address without 0x
    }

    // subsequence: word start and consecutive -- higher. hl -- indexes of matched letters
    function match(s, q) {
        if (!q) return { score: 1, hl: [] };
        const l = s.toLowerCase(), hl = [], at = l.indexOf(q);
        if (at >= 0) { for (let k = 0; k < q.length; k++) hl.push(at + k); return { score: (at === 0 ? 100 : 50) - at, hl }; }
        let i = 0;
        for (const c of q) {
            i = l.indexOf(c, i);
            if (i < 0) return null;
            hl.push(i++);
        }
        return { score: 10, hl };
    }
    function filter(src, q) {
        const out = [];
        for (const it of src) {
            const m = match(it.name, q);
            if (m) out.push(Object.assign({}, it, { hl: m.hl, score: m.score }));
            else if (it.extra.includes(q)) out.push(Object.assign({}, it, { hl: [], score: 1 }));
        }
        return out.sort((a, b) => b.score - a.score || (uses[b.id] ?? 0) - (uses[a.id] ?? 0));
    }

    // ---- smarts (apps mode, prefs FEATURES): the query is understood before it is searched ----
    // a conversion from the built-in table (no rates -- no currency), an arithmetic line for
    // qalc, or "kill <app>" for the app's windows. The answer is a strip above the results;
    // it holds Enter until Down hands the keys to the grid. Files ride the grid itself.
    property var smart: null
    property string smartOut: ""
    property bool smartFocus: true
    property var fileItems: []

    readonly property var units: ({
        mm: ["length", 0.001], cm: ["length", 0.01], m: ["length", 1], km: ["length", 1000],
        "in": ["length", 0.0254], inch: ["length", 0.0254], ft: ["length", 0.3048], foot: ["length", 0.3048], yd: ["length", 0.9144], mi: ["length", 1609.344], mile: ["length", 1609.344],
        g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], lb: ["mass", 0.45359237], oz: ["mass", 0.0283495231],
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
        kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], day: ["time", 86400], week: ["time", 604800],
        ms: ["speed", 1], kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704],
        ml: ["volume", 0.001], l: ["volume", 1], gal: ["volume", 3.785411784]
    })
    function fmt(x) {
        if (x === 0) return "0";
        return Math.abs(x) >= 1e6 || Math.abs(x) < 1e-4 ? x.toExponential(4) : String(Math.round(x * 1e6) / 1e6);
    }
    function convert(q) {
        const m = q.toLowerCase().match(/^(-?[\d.]+)\s*([a-z°]+)\s+(?:to|in)\s+([a-z°]+)$/);
        if (!m) return "";
        const v = parseFloat(m[1]);
        if (isNaN(v)) return "";
        const a = m[2].replace("°", ""), b = m[3].replace("°", "");
        const T = { c: [x => x + 273.15, x => x - 273.15], f: [x => (x - 32) * 5 / 9 + 273.15, x => (x - 273.15) * 9 / 5 + 32], k: [x => x, x => x] };
        if (T[a] || T[b]) {
            if (!T[a] || !T[b]) return "";
            return `${m[1]} ${m[2]} = ${fmt(T[b][1](T[a][0](v)))} ${m[3]}`;
        }
        const ua = units[a], ub = units[b];
        if (!ua || !ub || ua[0] !== ub[0]) return "";
        return `${m[1]} ${m[2]} = ${fmt(v * ua[1] / ub[1])} ${m[3]}`;
    }
    function computeSmart() {
        smart = null;
        smartOut = "";
        if (mode !== 0 || !Theme.state.featLauncher) return;
        const q = query.trim();
        if (!q) return;
        const km = q.match(/^kill\s+(.+)$/i);
        if (km) {
            const needle = km[1].trim().toLowerCase();
            const wins = Hyprland.toplevels.values.filter(t => {
                const cls = t.lastIpcObject?.class ?? "";
                return cls.toLowerCase().includes(needle) || (DesktopEntries.heuristicLookup(cls)?.name ?? "").toLowerCase().includes(needle);
            });
            if (wins.length) {
                const addrs = wins.map(t => t.address);
                smart = { kind: "kill", text: `kill ${km[1].trim()}`, sub: `${addrs.length} window${addrs.length > 1 ? "s" : ""}`,
                          act: () => addrs.forEach(a => Hyprland.dispatch(`hl.dsp.window.close({ window = "address:0x${a}" })`)) };
            }
            return;
        }
        const cv = convert(q);
        if (cv) {
            smart = { kind: "conv", text: cv, sub: "conversion", act: () => Quickshell.execDetached(["wl-copy", cv.slice(cv.indexOf(" = ") + 3)]) };
            return;
        }
        if (/^[0-9\s+\-*/().%^]+$/.test(q) && /[0-9]/.test(q) && /[+\-*/%^]/.test(q)) {
            smart = { kind: "maths", text: q, sub: "maths", act: () => { if (root.smartOut) Quickshell.execDetached(["wl-copy", root.smartOut]); } };
            smartCalc.exec(["qalc", "-t", q]); // exec cancels the previous run, like calc mode
        }
    }
    Process { id: smartCalc; stdout: StdioCollector { onStreamFinished: root.smartOut = text.trim() } }

    // files under home: bounded (depth 3, first 24), searched on a pause in typing
    Timer { id: fileT; interval: 250; onTriggered: root.findFiles() }
    function findFiles() {
        const q = query.trim();
        if (mode !== 0 || !Theme.state.featLauncher || q.length < 2) { fileItems = []; return; }
        findProc.exec(["sh", "-c", 'find "$1" -maxdepth 3 -not -path "*/.*" -type f -iname "*$2*" 2>/dev/null | head -24',
                       "glyph-find", Quickshell.env("HOME"), q.split("").filter(c => !"\"$`\\".includes(c)).join("")]); // quotes and dollars stay out of the shell line
    }
    Process {
        id: findProc
        stdout: StdioCollector {
            onStreamFinished: root.fileItems = text.split("\n").filter(Boolean).map(p => ({
                name: p.slice(p.lastIndexOf("/") + 1), glyph: "\u{F0214}", src: "", hl: [],
                run: () => Quickshell.execDetached(["xdg-open", p])
            }));
        }
    }

    // blocks: { head, sub, items }; each cell -- row/col, the arrows move by them
    readonly property var blocks: {
        const q = query.trim().toLowerCase();
        let b;
        if (mode === 1) b = q ? [{ head: "run", items: [{ name: query, glyph: "\u{F018D}", hl: [], run: () => Quickshell.execDetached(["sh", "-c", query]) }] }] : [];
        else if (mode === 4) b = Theme.styles.map(x => ({ head: x.head, items: filter(x.items.map(it => Object.assign({ extra: "", keep: true }, it)), q) })).filter(x => x.items.length);
        else if (mode === 3) b = [];
        else if (mode === 2) b = [{ head: "windows", sub: String(wins.length), items: filter(wins, q) }];
        else if (mode === 5) b = [{ head: "tray", sub: String(tray.length), items: filter(tray, q) }];
        else if (q) {
            const r = filter(apps, q);
            b = [{ head: "results", sub: String(r.length), items: r }];
            if (Theme.state.featLauncher && fileItems.length) b.push({ head: "files", sub: String(fileItems.length), items: fileItems });
        } else {
            const recent = apps.filter(a => uses[a.id]).sort((a, b) => uses[b.id] - uses[a.id]).slice(0, 6);
            b = (recent.length ? [{ head: "recent", items: recent }] : []).concat([{ head: "all apps", sub: String(apps.length), all: true, items: apps }]);
        }
        let row = 0, k = 0;
        for (const x of b) {
            x.items = x.items.map((it, i) => Object.assign({}, it, { row: row + Math.floor(i / 6), col: i % 6, k: k++ }));
            row += Math.ceil(x.items.length / 6);
        }
        return b;
    }
    readonly property var flat: blocks.reduce((a, x) => a.concat(x.items), [])
    readonly property var cur: flat[sel] ?? null

    property bool shown: false
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function open() {
        menuOpen = false;
        focusT.stop(); // a window from the last opening doesn't steal this one's focus
        input.text = "";
        mode = 0;
        sel = 0;
        flick.contentY = 0;
        shown = true;
        input.forceActiveFocus();
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    function move(dr, dc) {
        if (!flat.length) return;
        if (dc) return sel = (sel + dc + flat.length) % flat.length;
        const c = cur, row = flat.filter(x => x.row === c.row + dr);
        if (row.length) sel = row.reduce((a, x) => Math.abs(x.col - c.col) < Math.abs(a.col - c.col) ? x : a).k;
    }
    function launch() {
        if (!shown) return; // fades for Theme.t and still catches clicks: a second click of a double-click -- a second window
        if (mode === 0 && smart && smartFocus) { // the smart strip holds Enter until Down is pressed
            const s = smart;
            close();
            s.act();
            return;
        }
        if (mode === 3) {
            if (calcOut) Quickshell.execDetached(["wl-copy", calcOut]);
            return close();
        }
        const it = cur;
        if (!it) return;
        if (it.keep) return it.run(); // style samples apply in place -- the launcher stays open
        close();
        if (it.id) {
            uses = Object.assign({}, uses, { [it.id]: (uses[it.id] ?? 0) + 1 });
            usesFile.setText(JSON.stringify(uses));
        }
        it.run();
    }

    FileView {
        id: usesFile
        path: Quickshell.statePath("launcher-uses.json")
        printErrors: false
        onLoaded: try { root.uses = JSON.parse(text()); } catch (e) {}
    }

    property string calcOut: ""
    Process { id: calc; stdout: StdioCollector { onStreamFinished: root.calcOut = text.trim() } }
    onQueryChanged: {
        sel = 0;
        smartFocus = true;
        computeSmart();
        fileT.restart();
        if (mode === 3 && query.trim()) calc.exec(["qalc", "-t", query]); // exec cancels the previous calculation
        else calcOut = "";
    }
    onModeChanged: { sel = 0; flick.contentY = 0; menuOpen = false; computeSmart(); if (mode === 3) queryChanged(); }
    // list shrank without a new query (a window closed in windows) -- cursor past the end, cur empty
    onFlatChanged: sel = Math.max(0, Math.min(sel, flat.length - 1))

    onVisibleChanged: if (visible) input.forceActiveFocus()

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-launcher"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Stage {
        id: stage

        Rectangle {
            id: panel
            x: (stage.width - width) / 2
            y: 140 + 24 * (1 - root.t)
            width: 860
            height: Math.min(stage.height - 280, 30 + 66 + 20 + body.height + 34)
            opacity: root.t
            radius: Theme.corner(44)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }
            MouseArea { anchors.fill: parent }

            // search: pill, red caret, mode chips
            Rectangle {
                id: search
                x: 34
                y: 30
                width: parent.width - 68
                height: 66
                radius: Theme.corner(33)
                color: Theme.s2

                Icon { id: lens; x: 24; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; color: Theme.grey; font.pixelSize: 22 }
                TextInput {
                    id: input
                    anchors { left: lens.right; leftMargin: 16; right: chips.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    font { family: Theme.ui; pixelSize: 22 }
                    color: Theme.fg
                    selectionColor: Theme.s3
                    clip: true
                    cursorDelegate: Rectangle {
                        width: 2
                        color: Theme.red
                        Timer { running: input.activeFocus; interval: 500; repeat: true; onTriggered: parent.opacity = 1 - parent.opacity }
                    }
                    Text {
                        visible: !input.text
                        x: 6
                        text: ["Search apps, files, commands", "Run a command", "Find a window", "2 + 2, 20 usd to eur…", "Colour from nothing, the wallpaper or a palette", "Apps running in the background"][root.mode]
                        font: input.font
                        color: Theme.mute
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) root.close();
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.launch();
                        else if (e.key === Qt.Key_Tab) root.mode = (root.mode + 1) % 4;
                        else if (e.key === Qt.Key_Backtab) root.mode = (root.mode + 3) % 4;
                        else if (e.key === Qt.Key_Down) { if (root.smartFocus && root.smart && root.mode === 0) root.smartFocus = false; else root.move(1, 0); } // the strip hands the keys to the grid
                        else if (e.key === Qt.Key_Up) { if (!root.smartFocus && root.smart && root.mode === 0 && root.cur && root.flat.length && root.cur.row === root.flat[0].row) root.smartFocus = true; else root.move(-1, 0); } // back up onto the strip
                        else if (e.key === Qt.Key_Right && (!input.text || input.cursorPosition === input.text.length) && root.flat.length) root.move(0, 1);
                        else if (e.key === Qt.Key_Left && (!input.text || input.cursorPosition === 0) && root.flat.length) root.move(0, -1);
                        else return;
                        e.accepted = true;
                    }
                }
                Row {
                    id: chips
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Repeater {
                        model: root.modes
                        Rectangle {
                            required property string modelData
                            required property int index
                            width: chip.width + 32
                            height: chip.height + 20
                            radius: height / 2
                            color: root.mode === index ? Theme.fg : "transparent"
                            Lb { id: chip; anchors.centerIn: parent; text: parent.modelData; px: 11; color: root.mode === parent.index ? Theme.ink : Theme.grey }
                            TapHandler { onTapped: { root.mode = parent.index; input.forceActiveFocus(); } }
                        }
                    }
                }
            }

            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: search.bottom; bottom: parent.bottom; topMargin: 20; leftMargin: 34; rightMargin: 34; bottomMargin: 34 }
                contentHeight: body.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function ensure(y, h) {
                    if (y < contentY) contentY = y;
                    else if (y + h > contentY + height) contentY = y + h - height;
                }

                Column {
                    id: body
                    width: flick.width

                    // the smart strip: maths / conversion / kill, above the results
                    Item {
                        visible: root.mode === 0 && !!root.smart && !!root.query.trim()
                        width: body.width
                        height: visible ? 70 : 0
                        Rectangle {
                            width: parent.width
                            height: 56
                            radius: Theme.corner(28)
                            color: Theme.s2
                            border { width: root.smartFocus ? 1 : 0; color: Theme.fg }
                            Icon {
                                id: smIcon
                                x: 20
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.smart?.kind === "kill" ? "\u{F0156}" : root.smart?.kind === "conv" ? "\u{F0779}" : "\u{F00EC}"
                                font.pixelSize: 20
                                color: Theme.grey
                            }
                            Text {
                                anchors { left: smIcon.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                width: parent.width - 210
                                elide: Text.ElideRight
                                text: root.smart?.kind === "maths" ? `${root.smart.text} = ${root.smartOut || "…"}` : root.smart?.text ?? ""
                                font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                                color: Theme.fg
                            }
                            Lb {
                                anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                                text: root.smart?.kind === "kill" ? `↵ kill · ${root.smart.sub}` : root.smart?.kind === "conv" ? "↵ copy" : "↵ copy result"
                                px: 10
                            }
                            TapHandler { onTapped: { root.smartFocus = true; root.launch(); } }
                        }
                    }

                    // calc: answer large, Enter -- copy
                    Column {
                        visible: root.mode === 3
                        topPadding: 10
                        spacing: 10
                        Lb { text: root.calcOut ? "↵ copy" : "qalc" }
                        Num { width: body.width; elide: Text.ElideRight; text: root.calcOut || "—"; font.pixelSize: 96 }
                    }

                    // by index, not by array: a new blocks (letter in search, launch, recent) does not recreate ~160 cells
                    // with icons and layers -- only their data changes
                    Repeater {
                        id: blockRep
                        model: root.blocks.length

                        Column {
                            id: block
                            required property int index
                            readonly property var modelData: root.blocks[index] ?? ({ head: "", items: [] })
                            readonly property Item g: grid
                            width: body.width
                            topPadding: index ? 30 : 10 // +20 for flick at the top: scrolled content is clipped with a gap under the search

                            Row {
                                spacing: 14
                                bottomPadding: 18
                                // Doto letter group: which letters are in the window now
                                Num { visible: !!block.modelData.all; anchors.baseline: blab.baseline; text: root.range; font.pixelSize: 34 }
                                Lb { id: blab; text: block.modelData.head + (block.modelData.sub ? ` · ${block.modelData.sub}` : "") }
                            }
                            Grid {
                                id: grid
                                columns: 6
                                rowSpacing: 22
                                Repeater {
                                    model: block.modelData.items.length
                                    Cell { items: block.modelData.items; gy: block.y + grid.y }
                                }
                            }
                        }
                    }
                }
            }

            // alphabet on the right: letters in the window -- white, click -- jump to the first one with that letter
            Column {
                visible: root.mode === 0 && !root.query && !!root.allGrid
                anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 130 }
                spacing: 3
                Repeater {
                    model: [..."ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
                    Text {
                        required property string modelData
                        width: 12
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font { family: Theme.mono; pixelSize: 10 }
                        color: root.range.includes(modelData) ? Theme.fg : Theme.mute
                        TapHandler { onTapped: root.jump(parent.modelData) }
                    }
                }
            }
        }
        // a tray app's menu: under its circle, within the panel's width; downward it leaves the panel, like a popover
        Rectangle {
            id: menu
            property real mt: root.menuOpen && root.mode === 5 ? 1 : 0
            Behavior on mt { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            visible: mt > 0 && rows.count > 0
            x: Math.max(panel.x + 20, Math.min(panel.x + panel.width - width - 20, (root.peek?.x ?? 0) - width / 2))
            y: (root.peek?.y ?? 0) + 14 + 12 * (1 - mt)
            width: 320
            height: list.height + 20
            Behavior on x { enabled: menu.visible; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            Behavior on height { enabled: menu.visible; NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            opacity: root.t * mt
            radius: Theme.corner(28)
            color: Theme.s2
            border { width: 1; color: Theme.s3 }
            clip: true
            MouseArea { anchors.fill: parent } // a miss lands here, not on the dim -- that would close the launcher
            HoverHandler { id: menuHov }
            QsMenuOpener { id: opener; menu: root.sub.length ? root.sub[root.sub.length - 1] : root.peek?.tray?.menu ?? null }

            Column {
                id: list
                x: 10
                y: 10
                width: parent.width - 20

                Item {
                    visible: root.sub.length > 0
                    width: list.width
                    height: 40
                    Rectangle { anchors.fill: parent; radius: Theme.corner(20); color: backHov.hovered ? Theme.s3 : "transparent" }
                    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0141}"; color: Theme.grey }
                    Lb { x: 38; anchors.verticalCenter: parent.verticalCenter; text: "back"; px: 11 }
                    HoverHandler { id: backHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.sub = root.sub.slice(0, -1) }
                }
                Repeater {
                    id: rows
                    model: opener.children
                    Item {
                        id: row
                        required property QsMenuEntry modelData
                        readonly property bool sep: modelData.isSeparator
                        readonly property bool on: modelData.checkState === Qt.Checked
                        width: list.width
                        height: sep ? 13 : 40
                        Rectangle { visible: row.sep; anchors.centerIn: parent; width: parent.width - 28; height: 1; color: Theme.s3 }
                        Rectangle { visible: !row.sep; anchors.fill: parent; radius: Theme.corner(20); color: rowHov.hovered && row.modelData.enabled ? Theme.s3 : "transparent" }
                        Text {
                            visible: !row.sep
                            anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 40; verticalCenter: parent.verticalCenter }
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            text: row.modelData.text
                            font { family: Theme.ui; pixelSize: 15 }
                            color: row.modelData.enabled ? Theme.fg : Theme.mute
                        }
                        // справа: подменю — шеврон; галочка или радио — точка, отмечен — белая, нет — кольцо
                        Icon {
                            visible: row.modelData.hasChildren
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: "\u{F0142}"
                            color: Theme.grey
                        }
                        Rectangle {
                            visible: row.modelData.buttonType !== QsMenuButtonType.None && !row.modelData.hasChildren
                            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            width: 12
                            height: 12
                            radius: 6
                            color: row.on ? Theme.fg : "transparent"
                            border { width: 1.5; color: row.on ? Theme.fg : Theme.mute }
                        }
                        HoverHandler { id: rowHov; enabled: !row.sep; cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: !row.sep && row.modelData.enabled
                            onTapped: {
                                if (row.modelData.hasChildren) return root.sub = root.sub.concat([row.modelData]);
                                row.modelData.triggered();
                                root.close();
                            }
                        }
                    }
                }
            }
        }

    }

    // letters of all apps whose rows are visible now: "A-F"
    readonly property var allItems: blocks.find(b => b.all)?.items ?? []
    readonly property Item allGrid: { const i = blocks.findIndex(b => b.all); return blockRep.count > i && i >= 0 ? blockRep.itemAt(i)?.g ?? null : null; }
    readonly property string range: {
        if (!allGrid || !allItems.length) return "";
        const top = allGrid.mapToItem(body, 0, 0).y, rh = 88 + 10 + 20 + 22; // circle, gap, label, margin
        const r0 = Math.max(0, Math.floor((flick.contentY - top) / rh)), r1 = Math.floor((flick.contentY + flick.height - top) / rh);
        const seen = allItems.slice(r0 * 6, (r1 + 1) * 6).map(a => a.name[0].toUpperCase());
        return seen.length ? seen[0] === seen[seen.length - 1] ? seen[0] : `${seen[0]}–${seen[seen.length - 1]}` : "";
    }
    function jump(l) {
        const i = allItems.findIndex(a => a.name[0].toUpperCase() >= l);
        if (i < 0) return;
        sel = allItems[i].k;
        flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), allGrid.mapToItem(body, 0, 0).y + Math.floor(i / 6) * (88 + 10 + 20 + 22));
    }

    // app: circle 88 with a glyph or dotted icon, label -- matched letters white
    // ---- a tray app's menu: hover a circle -- a card under it with its menu items. A submenu replaces the
    // list in place, with "back" on top; an entry runs and closes the launcher. Left both the circle and
    // the card -- it fades. Mouse only; arrows into it if someone asks ----
    property Item hotCell: null // the circle under the cursor
    property var peek: null // { tray, x, y }: whose menu, and where its cell's bottom is; held while the card fades
    property var sub: [] // open submenus; the last is on screen
    property bool menuOpen: false
    readonly property bool menuHot: !!hotCell || menuHov.hovered
    onMenuHotChanged: if (!menuHot) menuT.restart()
    Timer { id: menuT; interval: 300; onTriggered: if (!root.menuHot) root.menuOpen = false }
    function hover(cell) {
        const p = cell.mapToItem(stage, cell.width / 2, cell.height);
        if (!menuOpen || peek?.tray !== cell.modelData.tray) sub = [];
        peek = { tray: cell.modelData.tray, x: p.x, y: p.y };
        hotCell = cell;
        sel = cell.modelData.k;
        menuOpen = true;
    }

    component Cell: Column {
        id: cell
        required property int index
        property var items: []
        readonly property var modelData: items[index] ?? ({ name: "", hl: [] })
        readonly property bool on: root.sel === modelData.k
        // Quickshell recreates the layer-shell window on every open, and an Image
        // uploads its texture into the new context even hidden: ~160 icons were
        // ~60 ms of the first frame. Outside the scroll (a row of slack) the cell
        // is empty and iconless; the height is its own, so nothing jumps
        property real gy // the grid's y in body
        readonly property bool near: gy + y < flick.contentY + flick.height + 140 && gy + y + height > flick.contentY - 140
        width: body.width / 6
        height: 88 + spacing + label.implicitHeight
        spacing: 10
        onOnChanged: if (on) flick.ensure(mapToItem(body, 0, 0).y - 8, height + 8) // 8 -- a sample's ring above the circle

        Rectangle {
            id: disc
            visible: cell.near
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88
            height: 88
            radius: 44
            color: cell.modelData.fill ?? (cell.on ? Theme.fg : Theme.s2)
            border { width: cell.modelData.fill ? 1 : 0; color: Theme.s3 } // a black sample on the panel
            // a sample under the cursor gets a ring around it: filling it white would lose the colour. dot -- the
            // palette's accent; what is set now -- a dot in the middle
            Rectangle { visible: cell.on && !!cell.modelData.fill; anchors.centerIn: parent; width: 104; height: 104; radius: 52; color: "transparent"; border { width: 2; color: Theme.fg } }
            Rectangle { id: inner; visible: !!cell.modelData.dot; anchors.centerIn: parent; width: 40; height: 40; radius: 20; color: cell.modelData.dot ?? "transparent" }
            Rectangle { visible: !!cell.modelData.now; anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: Theme.on(inner.visible ? inner.color : disc.color) }
            Icon {
                anchors.centerIn: parent
                visible: !!cell.modelData.glyph
                text: cell.modelData.glyph ?? ""
                font.pixelSize: 36
                color: cell.on ? Theme.ink : Theme.fg
            }
            Image {
                anchors.centerIn: parent
                visible: !cell.modelData.glyph && status === Image.Ready
                width: 44
                height: 44
                source: cell.near ? cell.modelData.src ?? "" : ""
                sourceSize: Qt.size(44, 44)
                asynchronous: true
                retainWhileLoading: true // the cell's app changed -- old icon while the new one loads
                layer.enabled: cell.near // a layer draws its own Image even hidden
                layer.effect: Dm { step: 2.5 }
            }
            TapHandler { onTapped: { root.sel = cell.modelData.k; root.launch(); } }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            HoverHandler {
                enabled: root.mode === 5 && !!cell.modelData.tray
                onHoveredChanged: if (hovered) root.hover(cell); else if (root.hotCell === cell) root.hotCell = null
            }
        }
        Text {
            id: label
            visible: cell.near
            width: parent.width - 8
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.StyledText
            readonly property var hl: cell.modelData.hl ?? []
            text: [...cell.modelData.name].map((c, i) => {
                const e = c === "<" ? "&lt;" : c === "&" ? "&amp;" : c;
                return hl.includes(i) ? `<font color="${Theme.fg}">${e}</font>` : e;
            }).join("")
            font { family: Theme.ui; pixelSize: 14 }
            color: cell.on ? Theme.fg : Theme.grey
        }
    }
}
