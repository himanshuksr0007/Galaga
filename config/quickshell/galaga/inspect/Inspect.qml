import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.settings
import "../app"

PanelWindow {
    id: win
    signal dismissed()
    property string phase: "capture"
    property string bannerText: "reading text…"
    property string output: ""
    property var languages: []
    property string language: "eng"
    property var handlers: ({})
    property var words: []
    property int first: -1
    property int last: -1
    property bool menu: false
    property point menuAt: Qt.point(0, 0)
    readonly property string dotFace: Qt.fontFamilies().find(f => /^n[ ._-]?dot/i.test(f)) ?? Theme.dot
    screen: Quickshell.screens.find(s => s.name === win.output) ?? Quickshell.screens[0]
    visible: phase !== "capture"
    anchors { left: true; top: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "galaga-inspect"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (win.output && !Quickshell.screens.some(s => s.name === win.output)) win.dismissed();
        }
    }
    IpcHandler { target: "inspect"; function close(): void { win.dismissed(); } }
    function error(message) { phase = "message"; bannerText = message; }
    function receive(line) {
        const msg = JSON.parse(line);
        if (msg.error) { error(msg.error); return; }
        if (msg.frame) {
            output = msg.output;
            frame.source = msg.frame;
            phase = "working";
        } else if (msg.languages) {
            languages = msg.languages;
            language = languages.includes("eng") ? "eng" : (languages[0] ?? "");
            handlers = msg.handlers;
        } else if (msg.words) {
            words = msg.words;
            phase = words.length ? "text" : "message";
            bannerText = words.length ? "drag across words · ctrl+c to copy" : "no text found";
        }
    }
    function wordAt(x, y) {
        const px = x * frame.sourceSize.width / page.width, py = y * frame.sourceSize.height / page.height;
        return words.findIndex(w => px >= w.x && px < w.x+w.w && py >= w.y && py < w.y+w.h);
    }
    readonly property string selection: {
        if (first < 0 || last < 0) return "";
        const picked = words.slice(Math.min(first,last), Math.max(first,last)+1);
        return picked.map((w,i) => (i ? (String(w.line) === String(picked[i-1].line) ? " " : "\n") : "") + w.text).join("");
    }
    function copyText() {
        if (!selection || copyJob.running) return;
        copyJob.payload = selection;
        copyJob.exec(["wl-copy", "--type", "text/plain;charset=utf-8"]);
    }
    Process {
        id: copyJob
        stdinEnabled: true
        property string payload
        onStarted: { write(payload); stdinEnabled = false; }
        onExited: code => { stdinEnabled = true; win.bannerText = code ? "copy failed" : "copied"; }
    }
    function browse(url) { Qt.openUrlExternally(url); menu = false; }
    function openActions(point) {
        menuAt = point; menu = true;
        (selection ? copyButton : languageButton).forceActiveFocus();
    }
    onMenuChanged: if (!menu) page.forceActiveFocus()
    component Action: SetButton {
        activeFocusOnTab: true
        border.width: activeFocus ? 1 : 0
        border.color: Theme.accent
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: hit()
        Keys.onReturnPressed: hit()
        Keys.onSpacePressed: hit()
    }
    Process {
        id: worker
        stdinEnabled: true
        stdout: SplitParser { onRead: line => win.receive(line) }
        onExited: code => { if (code && win.phase !== "message") win.error("recognition unavailable"); }
    }
    Component.onCompleted: worker.exec(["python3", Quickshell.shellPath("inspect/worker.py")])
    Component.onDestruction: if (worker.running) worker.signal(15)

    Stage {
        id: page
        focus: true
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (event.key === Qt.Key_Escape) {
                if (win.menu) win.menu = false; else win.dismissed();
            } else if (ctrl && event.key === Qt.Key_A && win.words.length) {
                win.first = 0; win.last = win.words.length-1;
            } else if (ctrl && event.key === Qt.Key_C) win.copyText();
            else if (win.words.length && (event.key === Qt.Key_Right || event.key === Qt.Key_Left)) {
                win.last = Math.max(0, Math.min(win.words.length-1, win.last + (event.key === Qt.Key_Right ? 1 : -1)));
                if (!(event.modifiers & Qt.ShiftModifier) || win.first < 0) win.first = win.last;
            } else if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier) && win.selection) win.openActions(Qt.point(width/2,height/2));
            else return;
            event.accepted = true;
        }
        Image { id: frame; anchors.fill: parent; cache: false; onStatusChanged: if (status === Image.Error) win.error("frame unavailable") }
        // Paint just the selected words in one item, including long OCR results.
        Canvas {
            id: highlights
            anchors.fill: parent
            onPaint: {
                const c = getContext("2d");
                c.clearRect(0,0,width,height);
                if (win.first < 0 || win.last < 0) return;
                const sx = width/frame.sourceSize.width, sy = height/frame.sourceSize.height;
                c.fillStyle = Qt.alpha(Theme.accent, 0.35); c.strokeStyle = Theme.fg;
                for (let i=Math.min(win.first,win.last); i<=Math.max(win.first,win.last); ++i) {
                    const w = win.words[i];
                    c.fillRect(w.x*sx,w.y*sy,w.w*sx,w.h*sy);
                    c.strokeRect(w.x*sx,w.y*sy,w.w*sx,w.h*sy);
                }
            }
            Connections {
                target: win
                function onFirstChanged() { highlights.requestPaint(); }
                function onLastChanged() { highlights.requestPaint(); }
            }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent; hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: win.phase === "text" && win.wordAt(mouseX,mouseY) >= 0 ? Qt.IBeamCursor : Qt.ArrowCursor
            onPressed: e => {
                if (win.menu) { win.menu = false; return; }
                const p = Qt.point(e.x,e.y);
                if (e.button === Qt.RightButton && win.languages.length > 1 && !win.selection
                        && win.wordAt(e.x,e.y) < 0 && win.phase !== "working") {
                    win.openActions(p); return;
                }
                if (win.phase !== "text") return;
                const index = win.wordAt(e.x,e.y);
                if (e.button === Qt.RightButton && index >= 0) {
                    if (index < Math.min(win.first,win.last) || index > Math.max(win.first,win.last))
                        win.first = win.last = index;
                    win.openActions(p);
                } else win.first = win.last = index;
            }
            onPositionChanged: e => {
                if (!(pressedButtons & Qt.LeftButton)) return;
                if (win.phase === "text" && win.first >= 0) {
                    const i = win.wordAt(e.x,e.y);
                    if (i >= 0) win.last = i;
                }
            }
        }
        IslandTile {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24 + (Theme.state.barAt === "top" && Theme.scr(win.screen?.name, "bar") ? Math.ceil(78 * Theme.s) / Theme.s : 0)
            app: "galaga"
            summary: "Live Text"
            body: win.bannerText
            icon: ""
            glyph: "\u{F0E70}"
            crit: false
            leaving: false
            interactive: false
            presented: win.visible
        }
        Rectangle {
            id: card
            visible: opacity > 0; enabled: win.menu
            opacity: win.menu ? 1 : 0; scale: 0.98 + opacity*0.02
            Behavior on opacity { NumberAnimation { duration: Rules.moving ? Theme.t/2 : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }
            x: Math.max(0,Math.min(page.width-width,win.menuAt.x)); y: Math.max(0,Math.min(page.height-height,win.menuAt.y))
            width: actions.implicitWidth+28; height: actions.implicitHeight+24
            color: Theme.s1; radius: Theme.corner(16); border.color: Theme.s3
            Column {
                id: actions; anchors.centerIn: parent; spacing: 6
                Num { font.family: win.dotFace; text: win.selection ? "selection" : "language"; font.pixelSize: 28 }
                Action { id: copyButton; visible: !!win.selection; label: "copy   ctrl+c"; onHit: { win.copyText(); win.menu = false; } }
                Action {
                    id: languageButton
                    visible: (win.phase === "text" || win.phase === "message") && win.languages.length > 1
                    label: "language · " + win.language
                    onHit: {
                        win.language = win.languages[(win.languages.indexOf(win.language)+1)%win.languages.length];
                        win.first = win.last = -1; win.words = []; win.phase = "working"; win.menu = false;
                        win.bannerText = "reading text…";
                        worker.write(JSON.stringify({language:win.language})+"\n");
                    }
                }
                Action { visible: !!win.selection; label: "translate · google"; onHit: win.browse("https://translate.google.com/?sl=auto&text="+encodeURIComponent(win.selection)) }
                Action { visible: !!win.selection; label: "look up · duckduckgo"; onHit: win.browse("https://duckduckgo.com/?q="+encodeURIComponent(win.selection)) }
                Action {
                    visible: !!win.handlers.mailto && /^[^\s@?&#]+@[\w.-]+\.[a-z]+$/i.test(win.selection)
                    label: "compose email"; onHit: win.browse("mailto:"+encodeURIComponent(win.selection).replace("%40","@"))
                }
                Action {
                    visible: !!win.handlers.tel && /^\+?[0-9][0-9 ()-]{4,20}[0-9]$/.test(win.selection)
                    label: "open dialler"; onHit: win.browse("tel:"+win.selection.replace(/[ ()-]/g,""))
                }
            }
        }
    }
}
