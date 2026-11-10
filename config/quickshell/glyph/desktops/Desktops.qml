import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// desktops: the workspaces overview -- 4-finger swipe up, or Super+Tab. One card per
// workspace that has windows (only those, Task View style): the workspace number in
// Doto, a scaled map of its windows in their real layout, and the windows as icon +
// title rows. Picking a card focuses that workspace. Windows on special workspaces
// (the minimised park) are not desktops and never appear here.
// Live screen capture (ScreencopyView) is deliberately not used: toplevel capture of
// windows on inactive workspaces is the unreliable case, and the map says the same
// thing in the shell's own line language. Geometry comes from the toplevels' IPC
// objects, refreshed on open exactly like the deck does.
PanelWindow {
    id: root

    property bool shown: false
    property real t: shown ? 1 : 0
    property int sel: 0

    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function open() {
        Hyprland.refreshToplevels(); // full re-query: fresh geometry and titles, not the event-fed snapshot
        sel = Math.max(0, desks.findIndex(d => d.id === activeId));
        shown = true;
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }
    function pick(id) {
        // through hyprctl, not the shell's Hyprland.dispatch: from here that
        // call closed the overview and changed nothing, while hyprctl is the
        // path minimise.sh proves every day -- same expression, working route
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = "${id}" })`]);
        close();
    }

    readonly property int activeId: Hyprland.focusedWorkspace?.id ?? -1

    // workspaces with at least one window, in id order; special workspaces have
    // negative ids and are excluded by construction
    readonly property var desks: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.toplevels.values.length > 0)
        .sort((a, b) => a.id - b.id)
        .map(w => ({
            id: w.id,
            name: w.name,
            wins: w.toplevels.values.map(t => {
                const o = t.lastIpcObject ?? {};
                const icon = DesktopEntries.heuristicLookup(o.class ?? "")?.icon;
                return {
                    title: t.title ?? "",
                    cls: o.class ?? "",
                    src: icon ? Quickshell.iconPath(icon, true) : "",
                    at: o.at ?? null,
                    size: o.size ?? null
                };
            })
        }))

    onDesksChanged: sel = Math.max(0, Math.min(sel, desks.length - 1))

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glyph-desktops"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // keyboard: Escape closes, arrows move the selection, Enter picks
    Item {
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) root.close();
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down) root.sel = Math.min(root.sel + 1, root.desks.length - 1);
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) root.sel = Math.max(root.sel - 1, 0);
            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.desks[root.sel]) root.pick(root.desks[root.sel].id);
        }
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 96, Math.max(348, Math.min(root.desks.length, 3) * 348))
        spacing: 26
        opacity: root.t

        transform: Translate { y: 24 * (1 - root.t) }

        Lb { anchors.horizontalCenter: parent.horizontalCenter; text: "desktops"; px: 13 }

        // empty state: no workspace has windows -- the overview still opens and closes cleanly
        Column {
            visible: root.desks.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Num { anchors.horizontalCenter: parent.horizontalCenter; text: "0"; font.pixelSize: 54; color: Theme.mute }
            Lb { anchors.horizontalCenter: parent.horizontalCenter; text: "no open desktops" }
        }

        Flow {
            visible: root.desks.length > 0
            width: parent.width
            spacing: 18

            Repeater {
                model: root.desks

                Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    readonly property bool current: modelData.id === root.activeId
                    // the selection alone gets the white frame; the current
                    // desktop is a dimmer frame plus its label, so the two
                    // never read as two selections
                    readonly property bool hot: card.index === root.sel

                    width: 330
                    height: 236
                    radius: 22
                    color: ma.containsMouse ? Theme.s2 : Theme.s1
                    border { width: hot ? 2 : 1; color: hot ? Theme.fg : current ? Theme.mute : Theme.s2 }

                    // the workspace's windows in their real layout, scaled into the map
                    Rectangle {
                        id: map
                        x: 14; y: 14
                        width: parent.width - 28
                        height: 104
                        radius: 14
                        color: Theme.s2
                        clip: true

                        // bounding box of the workspace's windows; falls back to a
                        // plain grid when a window reports no geometry
                        readonly property var box: {
                            const ws = card.modelData.wins.filter(w => w.at && w.size);
                            if (ws.length !== card.modelData.wins.length || !ws.length) return null;
                            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
                            for (const w of ws) {
                                x0 = Math.min(x0, w.at[0]); y0 = Math.min(y0, w.at[1]);
                                x1 = Math.max(x1, w.at[0] + w.size[0]); y1 = Math.max(y1, w.at[1] + w.size[1]);
                            }
                            return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
                        }
                        readonly property real fit: box ? Math.min((width - 16) / box.w, (height - 16) / box.h) : 0

                        Repeater {
                            model: card.modelData.wins
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property int cols: Math.ceil(Math.sqrt(card.modelData.wins.length))
                                x: map.box ? 8 + (modelData.at[0] - map.box.x) * map.fit + (map.width - 16 - map.box.w * map.fit) / 2
                                           : 8 + (index % cols) * ((map.width - 16) / cols)
                                y: map.box ? 8 + (modelData.at[1] - map.box.y) * map.fit + (map.height - 16 - map.box.h * map.fit) / 2
                                           : 8 + Math.floor(index / cols) * ((map.height - 16) / cols)
                                width: Math.max(10, map.box ? modelData.size[0] * map.fit - 2 : (map.width - 16) / cols - 2)
                                height: Math.max(8, map.box ? modelData.size[1] * map.fit - 2 : (map.height - 16) / cols - 2)
                                radius: 4
                                color: Theme.s3
                                border { width: 1; color: Theme.grey }
                            }
                        }
                    }

                    Row {
                        x: 18
                        y: map.y + map.height + 12
                        spacing: 12
                        Num { text: card.modelData.id; font.pixelSize: 30; color: card.current ? Theme.fg : Theme.grey }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Lb { text: (Theme.state.featDesktops && Theme.state.wsNames[String(card.modelData.id)]) || (card.current ? "current desktop" : "desktop"); px: 10 }
                            Lb { text: card.modelData.wins.length + (card.modelData.wins.length === 1 ? " window" : " windows"); px: 10; color: Theme.mute }
                        }
                    }

                    // first windows as icon + title rows; the rest is a count
                    Column {
                        x: 18
                        y: map.y + map.height + 52
                        width: parent.width - 36
                        spacing: 5
                        Repeater {
                            model: card.modelData.wins.slice(0, 2)
                            Row {
                                required property var modelData
                                spacing: 8
                                width: parent.width
                                Image { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; source: modelData.src; visible: !!modelData.src }
                                Text {
                                    width: parent.width - 22
                                    text: modelData.title || modelData.cls
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font { family: Theme.ui; pixelSize: 12 }
                                    color: Theme.grey
                                }
                            }
                        }
                        Lb { visible: card.modelData.wins.length > 2; text: "+ " + (card.modelData.wins.length - 2) + " more"; px: 10; color: Theme.mute }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.pick(card.modelData.id)
                    }
                }
            }
        }
    }
}
