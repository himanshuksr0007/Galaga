import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// alt+tab: this desktop's windows as a strip of cards, most recently used first
// (focusHistoryID, newest first). Hyprland runs binds before surfaces, so the
// alt+tab presses never reach this window -- each press arrives as the
// shell:switcher / shell:switcherback global and steps the selection. No bind
// claims alt's release, so the release lands here, on the focused surface, and
// commits: focus the picked window. Escape cancels, a click commits that card.
// Like the exposé, a card is icon, title and app name -- no live thumbnails.
PanelWindow {
    id: root

    property bool shown: false
    property real t: shown ? 1 : 0
    property int sel: 0

    Behavior on t { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

    function step(d) {
        if (!shown) {
            Hyprland.refreshToplevels(); // fresh focus history, like the exposé
            if (wins.length < 2) return; // nothing to switch between
            sel = d > 0 ? 1 : wins.length - 1;
            shown = true;
        } else {
            sel = (sel + d + wins.length) % wins.length;
        }
    }
    function commit() {
        if (!shown) return;
        const w = wins[sel];
        if (w) Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${w.addr}" })`);
        shown = false;
    }
    function cancel() { shown = false; }
    function pick(i) {
        const w = wins[i];
        if (!w) return;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${w.addr}" })`);
        shown = false;
    }

    // the focused workspace's windows, most recently focused first
    readonly property var wins: (Hyprland.focusedWorkspace?.toplevels.values ?? []).map(t => {
        const o = t.lastIpcObject ?? {};
        const cls = o.class ?? "";
        const entry = DesktopEntries.heuristicLookup(cls);
        return {
            addr: t.address,
            title: t.title || cls,
            app: entry?.name ?? cls,
            src: entry?.icon ? Quickshell.iconPath(entry.icon, true) : "",
            fh: o.focusHistoryID ?? -1
        };
    }).sort((a, b) => b.fh - a.fh)
    onWinsChanged: {
        sel = Math.max(0, Math.min(sel, wins.length - 1));
        if (shown && wins.length === 0) cancel();
    }

    visible: t > 0
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-switcher"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.t
        MouseArea { anchors.fill: parent; onClicked: root.cancel() }
    }

    Item {
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) root.cancel();
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.commit();
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.step(1);
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) root.step(-1);
            else return;
            e.accepted = true;
        }
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Alt) { root.commit(); e.accepted = true; }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 18
        opacity: root.t

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: row.width + 28
            height: row.height + 28
            radius: Theme.corner(28)
            color: Theme.s1
            border { width: 1; color: Theme.s2 }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 12

                Repeater {
                    model: root.wins

                    Rectangle {
                        id: card
                        required property var modelData
                        required property int index

                        readonly property bool hot: card.index === root.sel

                        width: 188
                        height: 106
                        radius: Theme.corner(20)
                        color: hot ? Theme.s2 : "transparent"
                        border { width: 1; color: hot ? Theme.fg : Theme.s2 }
                        scale: hot ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.t; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.glide } }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            spacing: 5

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 52
                                height: 52
                                radius: 15
                                color: Theme.s2
                                Image {
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    visible: status === Image.Ready
                                    source: card.modelData.src
                                    sourceSize: Qt.size(36, 36)
                                    layer.enabled: true
                                    layer.effect: Dm { step: 2 }
                                }
                                Icon { anchors.centerIn: parent; visible: !card.modelData.src; text: "\u{F05B0}"; font.pixelSize: 24; color: Theme.grey }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: card.modelData.title
                                textFormat: Text.PlainText
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                font { family: Theme.ui; pixelSize: 14; weight: Font.DemiBold }
                                color: Theme.fg
                            }
                            Lb { anchors.horizontalCenter: parent.horizontalCenter; text: card.modelData.app; px: 10 }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.sel = card.index
                            onClicked: root.pick(card.index)
                        }
                    }
                }
            }
        }

        Lb {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "tab -- next · release alt -- switch · esc -- cancel"
            px: 10
            color: Theme.mute
        }
    }
}
