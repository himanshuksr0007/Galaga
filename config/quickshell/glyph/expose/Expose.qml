import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// exposé: every window on the CURRENT desktop, tiled as cards -- the sibling of the
// desktops overview (same chrome, one level down). Super+` or the shell:expose
// shortcut. Click a card (or arrows + Enter) to focus that window and close;
// right-click closes the window itself; Escape just closes. Like the overview,
// there are no live thumbnails: a card is the window's icon, title and real size,
// which is the same information in the shell's own line language. Cards settle in
// with a stagger, in the shell's glide. Off: prefs FEATURES -> exposé.
PanelWindow {
    id: root

    property bool shown: false
    property real t: shown ? 1 : 0
    property int sel: 0

    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function open() {
        Hyprland.refreshToplevels(); // fresh titles and geometry, like the deck and the overview
        sel = Math.max(0, wins.findIndex(w => w.addr === activeAddr));
        shown = true;
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    function pick(i) {
        const w = wins[i];
        if (!w) return;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${w.addr}" })`);
        close();
    }
    function kill(i) {
        const w = wins[i];
        if (w) Hyprland.dispatch(`hl.dsp.window.close({ window = "address:0x${w.addr}" })`);
    }

    readonly property string activeAddr: ToplevelManager.activeToplevel?.address ?? ""
    readonly property int wsId: Hyprland.focusedWorkspace?.id ?? -1

    // the focused workspace's windows, in the model's order (stacking, roughly)
    readonly property var wins: (Hyprland.focusedWorkspace?.toplevels.values ?? []).map(t => {
        const o = t.lastIpcObject ?? {};
        const cls = o.class ?? "";
        const entry = DesktopEntries.heuristicLookup(cls);
        return {
            addr: t.address,
            title: t.title || cls,
            app: entry?.name ?? cls,
            src: entry?.icon ? Quickshell.iconPath(entry.icon, true) : "",
            size: o.size ?? null,
            floating: !!o.floating
        };
    })
    onWinsChanged: sel = Math.max(0, Math.min(sel, wins.length - 1))

    // grid geometry for the arrow keys: as many 318-wide cards as the flow fits
    readonly property int cols: Math.max(1, Math.floor((Math.min(width - 96, 3 * 336)) / 336))

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-expose"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Item {
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) root.close();
            else if (e.key === Qt.Key_Right) root.sel = Math.min(root.sel + 1, root.wins.length - 1);
            else if (e.key === Qt.Key_Left) root.sel = Math.max(root.sel - 1, 0);
            else if (e.key === Qt.Key_Down) root.sel = Math.min(root.sel + root.cols, root.wins.length - 1);
            else if (e.key === Qt.Key_Up) root.sel = Math.max(root.sel - root.cols, 0);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.pick(root.sel);
            else return;
            e.accepted = true;
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 96, Math.max(336, Math.min(root.wins.length, 3) * 336))
        spacing: 26
        opacity: root.t

        Lb { anchors.horizontalCenter: parent.horizontalCenter; text: `exposé · desktop ${root.wsId}`; px: 13 }

        Column {
            visible: root.wins.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Num { anchors.horizontalCenter: parent.horizontalCenter; text: "0"; font.pixelSize: 54; color: Theme.mute }
            Lb { anchors.horizontalCenter: parent.horizontalCenter; text: "no windows here" }
        }

        Flow {
            visible: root.wins.length > 0
            width: parent.width
            spacing: 18

            Repeater {
                model: root.wins

                Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    readonly property bool current: modelData.addr === root.activeAddr
                    readonly property bool hot: card.index === root.sel || ma.containsMouse
                    // staggered settle: each card takes its slice of the root glide
                    readonly property real ph: { const x = Math.max(0, Math.min(1, root.t * 1.5 - card.index * 0.07)); return 1 - Math.pow(1 - x, 3); }

                    width: 318
                    height: 188
                    radius: Theme.corner(22)
                    color: Theme.s1
                    border { width: 1; color: hot || current ? Theme.fg : Theme.s2 }
                    opacity: ph
                    transform: [
                        Translate { y: 20 * (1 - card.ph) },
                        Scale { origin.x: card.width / 2; origin.y: card.height / 2; xScale: 0.94 + 0.06 * card.ph; yScale: 0.94 + 0.06 * card.ph }
                    ]

                    Rectangle {
                        x: 18
                        y: 18
                        width: 56
                        height: 56
                        radius: 16
                        color: Theme.s2
                        Image {
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            visible: status === Image.Ready
                            source: card.modelData.src
                            sourceSize: Qt.size(32, 32)
                            layer.enabled: true
                            layer.effect: Dm { step: 2 }
                        }
                        Icon { anchors.centerIn: parent; visible: !card.modelData.src; text: "\u{F05B0}"; font.pixelSize: 24; color: Theme.grey }
                    }
                    Column {
                        anchors { left: parent.left; leftMargin: 90; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 20 }
                        spacing: 4
                        Text {
                            width: parent.width
                            text: card.modelData.title
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font { family: Theme.ui; pixelSize: 16; weight: Font.DemiBold }
                            color: Theme.fg
                        }
                        Lb { text: card.modelData.app; px: 10 }
                    }
                    Row {
                        anchors { left: parent.left; leftMargin: 18; bottom: parent.bottom; bottomMargin: 16 }
                        spacing: 10
                        Lb { visible: card.current; text: "focused"; px: 10; color: Theme.fg }
                        Lb { visible: card.modelData.floating; text: "floating"; px: 10 }
                        Lb { text: card.modelData.size ? `${card.modelData.size[0]}×${card.modelData.size[1]}` : ""; px: 10; color: Theme.mute }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) root.kill(card.index);
                            else root.pick(card.index);
                        }
                    }
                }
            }
        }

        Lb {
            visible: root.wins.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: "click -- focus · right-click -- close window · esc -- back"
            px: 10
            color: Theme.mute
        }
    }
}
