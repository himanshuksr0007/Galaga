import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import "../app"

Scope {
    id: picker
    signal dismissed()
    property var frames: ({})
    property string output: ""
    property point point: Qt.point(0,0)
    property bool locked: false
    property bool displayInfo: false
    property bool hex: true
    property int aperture: 1
    property string space: "capture"
    property var reading: null
    property bool copying: false
    property string feedback: ""
    readonly property string dotFace: Qt.fontFamilies().find(f => /^n[ ._-]?dot/i.test(f)) ?? Theme.dot
    function track(name, x, y) {
        if (locked || copying) return;
        if (output !== name) reading = null;
        output = name;
        point = Qt.point(Math.min(1,Math.max(0,x)), Math.min(1,Math.max(0,y)));
        schedule();
    }
    function schedule() { if (!tick.running) tick.start(); }
    function request(kind) {
        if (!output || !worker.running || copying) return;
        if (kind) { tick.stop(); copying = true; }
        worker.write(JSON.stringify({output:output, x:point.x, y:point.y, size:aperture,
                                     space:space, hex:hex, copy:kind})+"\n");
    }
    Timer { id: tick; interval: 16; onTriggered: picker.request("") }
    IpcHandler { target: "colourmeter"; function close(): void { picker.dismissed(); } }
    Connections { target: Quickshell; function onScreensChanged() { picker.dismissed(); } }
    Process {
        id: worker
        stdinEnabled: true
        stdout: SplitParser { onRead: line => {
            const msg = JSON.parse(line);
            if (msg.frames) {
                picker.frames = msg.frames;
                const c = msg.cursor;
                const s = Quickshell.screens.find(s => msg.frames[s.name] && c.x >= s.x && c.x < s.x+s.width
                                                    && c.y >= s.y && c.y < s.y+s.height);
                if (s) picker.track(s.name,(c.x-s.x)/s.width,(c.y-s.y)/s.height);
            } else if (msg.copied) picker.dismissed();
            else if (msg.copyError) { picker.copying=false; picker.feedback="copy failed · try again"; }
            else if (msg.error) {
                Quickshell.execDetached(["notify-send","colour picker",msg.error]);
                picker.dismissed();
            } else if (msg.output === picker.output) picker.reading = msg.reading;
        } }
        onExited: (code,status) => { if (code) picker.dismissed(); }
    }
    Component.onCompleted: worker.exec(["python3","-B",Quickshell.shellPath("meter/picker.py")])

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: !!picker.frames[modelData.name]
            anchors { left: true; top: true; right: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "galaga-colour-picker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: picker.output === modelData.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Stage {
                id: page
                focus: true
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) picker.dismissed();
                    else if (e.key === Qt.Key_L && (e.modifiers & Qt.ControlModifier)) picker.locked = !picker.locked;
                    else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier) && (e.modifiers & Qt.AltModifier)) picker.request("image");
                    else if (e.key === Qt.Key_Return || (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier))) picker.request("text");
                    else return;
                    e.accepted = true;
                }
                Image { id: frozen; anchors.fill: parent; cache: false; source: picker.frames[overlay.modelData.name] ?? "" }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.CrossCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: e => picker.track(overlay.modelData.name,e.x/width,e.y/height)
                    onClicked: e => {
                        picker.track(overlay.modelData.name,e.x/width,e.y/height);
                        if (e.button === Qt.RightButton) picker.locked = !picker.locked;
                        else picker.request("text");
                    }
                }
                Item {
                    id: card
                    visible: picker.output === overlay.modelData.name
                    readonly property real px: picker.point.x*page.width
                    readonly property real py: picker.point.y*page.height
                    x: Math.max(0,px+width+18 < page.width ? px+18 : px-width-18)
                    y: Math.max(0,py+height+16 < page.height ? py+16 : py-height-16)
                    readonly property real gap: 9
                    readonly property real inset: lens.width + gap
                    readonly property real corner: Theme.corner(18)
                    width: Math.max(inset + details.implicitWidth + 28, controls.implicitWidth + 32)
                    height: controls.y + controls.implicitHeight + 14

                    // The quarter arc shares its centre with the loupe. The gap
                    // is transparent, so the captured desktop shows through it.
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Theme.s1; strokeColor: Theme.s3; strokeWidth: 1
                            startX: card.inset + card.corner; startY: 0
                            PathLine { x: card.width-card.corner; y: 0 }
                            PathQuad { controlX: card.width; controlY: 0; x: card.width; y: card.corner }
                            PathLine { x: card.width; y: card.height-card.corner }
                            PathQuad { controlX: card.width; controlY: card.height; x: card.width-card.corner; y: card.height }
                            PathLine { x: card.corner; y: card.height }
                            PathQuad { controlX: 0; controlY: card.height; x: 0; y: card.height-card.corner }
                            PathLine { x: 0; y: card.inset+card.corner }
                            PathQuad { controlX: 0; controlY: card.inset; x: card.corner; y: card.inset }
                            PathLine { x: lens.radius; y: card.inset }
                            PathArc { x: card.inset; y: lens.radius; radiusX: lens.radius+card.gap; radiusY: radiusX; direction: PathArc.Counterclockwise }
                            PathLine { x: card.inset; y: card.corner }
                            PathQuad { controlX: card.inset; controlY: 0; x: card.inset+card.corner; y: 0 }
                        }
                    }
                    ClippingRectangle {
                        id: lens
                        width: 121; height: width; radius: width/2
                        color: Theme.s2; border.color: Theme.grey; border.width: 1
                        contentInsideBorder: false
                        Image { anchors.fill: parent; smooth: false; cache: false; source: picker.reading?.tile ?? "" }
                        Rectangle {
                            anchors.centerIn: parent; width: picker.aperture*11; height: width
                            color: "transparent"; border.width: 2; border.color: "black"
                            Rectangle { anchors.fill: parent; anchors.margins: 1; color: "transparent"; border.color: "white" }
                        }
                    }
                    Column {
                        id: details
                        x: card.inset+14; y: 12; spacing: 7
                        Row {
                            spacing: 12
                            Ring { width: 16; height: 16; n: 12; dot: 3; on: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Num { text: "colour meter"; font.family: picker.dotFace; font.pixelSize: 30 }
                            SetButton { label: "display"; onHit: picker.displayInfo=!picker.displayInfo }
                            SetButton { label: "close"; onHit: picker.dismissed() }
                        }
                        Column {
                            spacing: 5
                            Lb { px: 10; text: picker.space === "capture" ? "capture rgb · unprofiled" : picker.space+" · assumed srgb source" }
                            Num { font.family: picker.dotFace; font.pixelSize: 28
                                text: !picker.reading ? "···" : picker.hex ? "#"+picker.reading.rgb.map(v=>v.toString(16).padStart(2,"0")).join("").toUpperCase() : picker.reading.rgb.join(" ") }
                            Lb { px: 11; text: picker.reading ? "r "+picker.reading.rgb[0]+"  g "+picker.reading.rgb[1]+"  b "+picker.reading.rgb[2] : " " }
                            Rectangle { width: 156; height: 18; radius: 3; border.color: Theme.grey
                                color: picker.reading ? Qt.rgba(picker.reading.swatch[0]/255,picker.reading.swatch[1]/255,picker.reading.swatch[2]/255,1) : Theme.s2 }
                            Lb { px: 10; text: picker.reading ? picker.output+" · "+picker.reading.x+","+picker.reading.y+" · "+picker.reading.footprint.join("×") : " " }
                        }
                    }
                    Column {
                        id: controls
                        x: 16; y: Math.max(card.inset, details.y+details.implicitHeight)+10
                        spacing: 8
                        Lb { visible: picker.displayInfo; px: 10; text: overlay.modelData.name+" · "+frozen.sourceSize.width+"×"+frozen.sourceSize.height+" capture pixels" }
                        Row {
                            spacing: 4
                            SetButton { label: picker.aperture+"×"+picker.aperture; onHit: { picker.aperture=picker.aperture===5 ? 1 : picker.aperture+2; picker.schedule(); } }
                            SetButton { label: picker.locked ? "unlock" : "lock"; onHit: picker.locked=!picker.locked }
                            SetButton { label: picker.hex ? "hex" : "decimal"; onHit: picker.hex=!picker.hex }
                        }
                        Row {
                            spacing: 4
                            SetButton { label:"copy text"; onHit: picker.request("text") }
                            SetButton { label:"copy swatch"; onHit: picker.request("image") }
                            SetButton { label: picker.space==="capture" ? "assume sRGB" : picker.space
                                onHit: { picker.space=picker.space==="capture" ? "sRGB" : picker.space==="sRGB" ? "Adobe RGB" : "capture"; picker.schedule(); } }
                        }
                        Lb { px: 10; text: picker.feedback || (picker.locked ? "locked · ctrl+l to follow · esc to close" : "click to copy · ctrl+l to lock · esc to close") }
                    }
                }
            }
        }
    }
}
