import QtQuick
import Quickshell
import qs
import qs.components
import qs.services

// appearance: where colour is from and where it lands, and the home screen's
// chrome. On top -- a desktop in the palette of the sample under the cursor
// or in focus (none -- the current one): bar, quick settings, kitty, player,
// the Galaga strip; the roles called out on the right, and a click on one
// opens the hex picker for it. Under it, where the colour is from and the
// theme; then what the source has. The home screen follows its toggles live
// in the mock under them. Theme controls live here and nowhere else.
Item {
    id: pg

    property bool active: false
    signal wallRequested

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    property Item hot: null // the sample under the cursor or in focus
    readonly property var p: hot?.item.pal ?? Theme.pal
    readonly property string src: Theme.state.paint === "scheme" ? (Theme.pal.group === "more" ? "" : Theme.pal.group + " ") + Theme.pal.name
        : Theme.state.paint === "wall" && Theme.tones.length ? `wallpaper · ${Theme.pal.name}` : "nothing"
    function block(h) { return Theme.styles.find(b => b.head === h)?.items ?? []; }
    function peek(sw) {
        if (sw.peek) hot = sw;
        else if (hot === sw) hot = null;
    }
    // a colour well was clicked: the palette preview steps aside (the picker
    // edits the live colour, not the one under the cursor) and the picker opens
    function openPicker(key) {
        hot = null;
        picker.open(key, key.startsWith("a") ? "ansi " + key.slice(1) : key);
    }

    SystemClock { id: clock; enabled: pg.active; precision: SystemClock.Minutes }
    readonly property string hello: { const h = clock.date.getHours(); return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"; }
    readonly property string who: (Theme.state.name || Quickshell.env("USER")).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    property bool dim: false // the clock colon is dimmed
    Timer { running: pg.active && Theme.state.blink; interval: 500; repeat: true; onTriggered: pg.dim = !pg.dim }

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
                SetHead { text: "colour" }
                // the desk mock is drawn for a 1040 canvas; the page is 780
                // inside the card column, so it sits at three-quarter size
                Item {
                    width: parent.width
                    height: 388 * 0.75
                    Desk {
                        scale: 0.75
                        transformOrigin: Item.TopLeft
                        p: pg.p
                        onPickColour: key => pg.openPicker(key)
                    }
                }
                Lb {
                    text: `style · ${pg.src} · ${Theme.light ? "light" : "dark"}` + (pg.hot && !pg.hot.item.now ? `   →   ${pg.hot.item.name} · click sets it` : "")
                    px: 11
                    color: Theme.mute
                }
                // customs: your own colours sit on top of the palette,
                // everywhere, until reset
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
                SetCard {
                    SetPick {
                        label: "from"
                        opts: ["nothing", "wall", "palette"]
                        cur: ["", "wall", "scheme"].indexOf(Theme.state.paint)
                        onPicked: i => Theme.state.paint = ["", "wall", "scheme"][i]
                    }
                    SetPick {
                        label: "theme"
                        opts: ["light", "dark", "auto"]
                        cur: Theme.state.themeMode === 1 ? 2 : Theme.light ? 0 : 1
                        divider: Theme.state.themeMode !== 1
                        onPicked: i => {
                            if (i === 2) Theme.state.themeMode = 1;
                            else { Theme.state.themeMode = 0; Theme.setLight(i === 0); }
                        }
                    }
                    // the auto schedule's hours -- only while theme is auto
                    Row {
                        visible: Theme.state.themeMode === 1
                        topPadding: 12
                        spacing: 40
                        TimeStep { label: "light at"; value: Theme.state.lightAt; onMoved: v => Theme.state.lightAt = v }
                        TimeStep { label: "dark at"; value: Theme.state.darkAt; onMoved: v => Theme.state.darkAt = v }
                    }
                }
            }

            // what the source has
            Column {
                visible: !Theme.state.paint
                width: parent.width
                Lb { text: "black · white dots · one red — nothing to pick"; color: Theme.mute }
            }
            Column {
                visible: Theme.state.paint === "wall"
                width: parent.width
                spacing: 10
                SetHead { text: "from the wallpaper" }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 26
                        // the wallpaper as dots; click -- the wallpaper screen
                        Rectangle {
                            width: 168
                            height: 105
                            radius: Theme.corner(14)
                            color: "transparent"
                            border { width: Theme.wall ? 0 : 1; color: Theme.s3 }
                            Image {
                                anchors.fill: parent
                                source: visible ? Theme.url(Theme.wallSrc(Theme.wall)) : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(336, 210)
                                asynchronous: true
                                layer.enabled: true
                                layer.effect: Dm { step: 4 }
                            }
                            Lb { visible: !Theme.wall; anchors.centerIn: parent; px: 10; text: "no wallpaper" }
                            TapHandler { onTapped: pg.wallRequested() }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                        Column {
                            spacing: 6
                            Lb { text: Theme.tones.length ? "tones · from the wallpaper" : "no colour in it · click it for another" }
                            Row {
                                Repeater {
                                    model: pg.block("tones").length
                                    Swatch { id: tw; item: pg.block("tones")[index] ?? ({ name: "" }); onPeekChanged: pg.peek(tw) }
                                }
                            }
                        }
                    }
                    Column {
                        visible: Theme.tones.length > 0
                        topPadding: 14
                        spacing: 6
                        Lb { text: "variant · how much colour, like material you" }
                        Row {
                            Repeater {
                                model: pg.block("variant").length
                                Swatch { id: vw; item: pg.block("variant")[index] ?? ({ name: "" }); onPeekChanged: pg.peek(vw) }
                            }
                        }
                    }
                }
            }
            Column {
                visible: Theme.state.paint === "scheme"
                width: parent.width
                spacing: 10
                SetHead { text: "palettes" }
                Flow {
                    width: parent.width
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
                                    Swatch { id: pw; item: sb.block.items[index] ?? ({ name: "" }); onPeekChanged: pg.peek(pw) }
                                }
                            }
                        }
                    }
                }
            }

            // the home screen: the mock follows the toggles; name -- into a pill
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "home screen" }
                ScreenMock {
                    Orb { visible: Theme.state.orb; x: 400; y: 110; scale: 330 / 1100; transformOrigin: Item.TopLeft }
                    Row {
                        x: 60
                        y: 52
                        Num { id: hrs; text: Theme.hh(clock.date); font.pixelSize: 120 }
                        Num { text: ":"; font.pixelSize: 120; opacity: Theme.state.blink && pg.dim ? 0.2 : 1 }
                        Num { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 120 }
                        Lb { visible: !Theme.state.clock24; anchors.baseline: hrs.baseline; leftPadding: 12; text: clock.date.getHours() < 12 ? "am" : "pm" }
                    }
                    Lb { x: 64; y: 172; text: Qt.locale("en_US").toString(clock.date, "dddd · d MMMM"); px: 11 }
                    Text {
                        x: 62
                        y: 232
                        textFormat: Text.StyledText
                        text: `${pg.hello},<br><font color="${Theme.grey}">${pg.who}.</font>`
                        font { family: Theme.ui; pixelSize: 30; weight: Font.Light }
                        lineHeight: 1.1
                        color: Theme.fg
                    }
                    // Galaga strips: volume on the right, progress at the bottom
                    Seg { visible: Theme.state.edges; x: parent.width - 12; y: 140; width: 4; height: 200; n: 12; f: 0.6; vertical: true }
                    Seg { visible: Theme.state.edges; x: 230; y: parent.height - 10; width: 300; height: 4; n: 24; f: 0.4 }
                }
                SetCard {
                    SetToggle { label: "dot grid"; on: Theme.state.grid; onFlip: want => Theme.state.grid = want }
                    SetToggle { label: "orb"; on: Theme.state.orb; onFlip: want => Theme.state.orb = want }
                    SetToggle { label: "24 hours"; on: Theme.state.clock24; onFlip: want => Theme.state.clock24 = want }
                    SetToggle { label: "blink"; on: Theme.state.blink; onFlip: want => Theme.state.blink = want }
                    SetToggle { label: "edges"; on: Theme.state.edges; onFlip: want => Theme.state.edges = want }
                    SetToggle { label: "home · clock"; on: Theme.state.homeClock; onFlip: want => Theme.state.homeClock = want }
                    SetToggle { label: "home · greeting"; on: Theme.state.homeHello; onFlip: want => Theme.state.homeHello = want }
                    SetToggle { label: "home · widgets"; on: Theme.state.homeBento; divider: false; onFlip: want => Theme.state.homeBento = want }
                }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 14
                        Lb { id: nameL; anchors.verticalCenter: parent.verticalCenter; text: "name"; color: nameIn.activeFocus ? Theme.fg : Theme.grey }
                        Rectangle {
                            width: parent.width - nameL.width - 14
                            height: 52
                            radius: Theme.corner(26)
                            color: Theme.s2
                            border { width: nameIn.activeFocus ? 1 : 0; color: Theme.fg }
                            TextInput {
                                id: nameIn
                                anchors { left: parent.left; leftMargin: 22; right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                                text: Theme.state.name
                                maximumLength: 24
                                font { family: Theme.ui; pixelSize: 16 }
                                color: Theme.fg
                                selectionColor: Theme.s3
                                clip: true
                                onTextEdited: Theme.state.name = text
                                Text { visible: !nameIn.text; text: Quickshell.env("USER"); font: nameIn.font; color: Theme.mute }
                                Keys.onPressed: e => {
                                    if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) nameIn.focus = false;
                                    else return;
                                    e.accepted = true;
                                }
                            }
                        }
                    }
                    SetRow {
                        label: "wallpaper"
                        sub: "the wallpaper screen"
                        chevron: true
                        clickable: true
                        divider: false
                        onHit: pg.wallRequested()
                    }
                }
            }
        }
    }

    // the hex picker: one instance over the page, opened by the desk's wells
    HexPick { id: picker; anchors.centerIn: parent; z: 100 }

    // small round stepper button (theme times)
    component Round: Rectangle {
        id: rd
        property string text
        signal hit
        width: 40
        height: 40
        radius: 20
        color: Theme.s2
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
