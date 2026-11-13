import QtQuick
import Quickshell
import qs
import qs.components
import qs.services

// notifications: the essential list. While the mode is on, only the picked apps
// arrive out loud (island, edge flash, sound); the rest still land in quick
// settings, muted, and critical notifications always come through (Notes.qml).
// The list is kept with the mode off.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    // installed apps for the picker -- built once the entry list settles, like
    // the launcher (DesktopEntries trickles in at startup)
    property var apps: []
    Timer {
        id: fAppsT
        interval: 300
        running: true
        onTriggered: pg.apps = DesktopEntries.applications.values.filter(e => !e.noDisplay)
            .map(e => ({ id: e.id, name: e.name, src: e.icon ? Quickshell.iconPath(e.icon, true) : "" }))
            .sort((a, b) => a.name.localeCompare(b.name))
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { fAppsT.restart(); }
    }
    property string query: ""
    readonly property var shown: apps.filter(a => !query || a.name.toLowerCase().includes(query))
    function flipApp(id) {
        const a = Theme.state.essentialApps.slice(), i = a.indexOf(id);
        if (i >= 0) a.splice(i, 1); else a.push(id);
        Theme.state.essentialApps = a;
        Sounds.play("tick");
    }

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
                SetHead { text: "essential" }
                SetCard {
                    SetToggle {
                        label: "essential only"
                        sub: Theme.state.featEssential ? `${Theme.state.essentialApps.length} picked` : "mode off — the list waits"
                        on: Theme.state.featEssential
                        divider: false
                        onFlip: want => Theme.state.featEssential = want
                    }
                    Lb {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 12
                        px: 10.5
                        text: "picked apps light the island, flash the edges and make the sound. everything else still arrives — muted, in quick settings. critical notifications always come through."
                    }
                    Lb {
                        visible: Theme.state.featEssential && Theme.state.essentialApps.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        topPadding: 8
                        px: 10.5
                        color: Theme.red
                        text: "nothing picked yet — with the mode on, everything but critical arrives muted"
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "apps" }
                Rectangle {
                    width: parent.width
                    height: 44
                    radius: Theme.corner(22)
                    color: Theme.s1
                    border { width: 1; color: Theme.s2 }
                    Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; font.pixelSize: 16; color: Theme.mute }
                    TextInput {
                        id: searchIn
                        anchors { left: parent.left; leftMargin: 42; right: parent.right; rightMargin: 16; top: parent.top; bottom: parent.bottom }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        selectionColor: Theme.s3
                        selectedTextColor: Theme.fg
                        font { family: Theme.ui; pixelSize: 14 }
                        clip: true
                        onTextChanged: pg.query = text.trim().toLowerCase()
                        Text {
                            visible: !searchIn.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search apps"
                            font { family: Theme.ui; pixelSize: 12 }
                            color: Theme.mute
                        }
                    }
                }
                SetCard {
                    pad: 8
                    Flickable {
                        width: parent.width
                        height: 336
                        clip: true
                        contentWidth: width
                        contentHeight: pickCol.height
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: pickCol
                            width: parent.width
                            Repeater {
                                model: pg.shown
                                Rectangle {
                                    id: prow
                                    required property var modelData
                                    readonly property bool on: Theme.state.essentialApps.includes(modelData.id)
                                    width: pickCol.width
                                    height: 48
                                    radius: Theme.corner(14)
                                    color: on ? Theme.s2 : "transparent"
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
                                    Text {
                                        x: 48
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 110
                                        elide: Text.ElideRight
                                        text: prow.modelData.name
                                        font { family: Theme.ui; pixelSize: 14 }
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
                                    TapHandler { onTapped: pg.flipApp(prow.modelData.id) }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }
                    Lb {
                        visible: pg.shown.length === 0 && pg.query !== ""
                        topPadding: 6
                        leftPadding: 12
                        text: "no app matches the search"
                        px: 10
                        color: Theme.mute
                    }
                }
            }
        }
    }
}
