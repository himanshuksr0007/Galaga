import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// the task manager: settings' sibling -- a real window in the shell's clothes,
// the same header discs, sidebar manners and hosting (the shell loads it on
// first use and unloads it on close, see shell.qml). Three pages: processes
// (what is running, grouped by app), performance (the machine at a glance)
// and startup (what launches at login). Opened by ctrl+shift+esc -- the
// windows combo -- or the app list's Task Manager entry (rice taskmgr).
FloatingWindow {
    id: win

    title: "Task Manager"
    width: 1180
    height: 780
    color: Theme.bg
    visible: false

    property string page: "processes"
    property real t: visible ? 1 : 0
    signal closeRequested

    Behavior on t { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }

    readonly property var heads: ({
        processes: ["PROCESSES", "what is running · grouped by app"],
        performance: ["PERFORMANCE", "cpu · memory · gpu · network · disk"],
        startup: ["STARTUP", "what launches at login"]
    })

    // while the window is up, SysStats samples in detail (its sampler
    // otherwise waits for a home screen or the deck): the performance
    // page reads it live, home or no home
    Binding { target: Sys; property: "taskMgrOpen"; value: win.visible }

    function open(p) {
        if (p && heads[p]) page = p;
        visible = true;
        Sounds.play("pop");
    }
    function close() {
        visible = false;
        Sounds.play("pop");
        closeRequested();
    }
    function toggle() { visible ? close() : open(); }
    function select(p) {
        if (page === p) return;
        page = p;
        Sounds.play("tick");
    }

    component Disc: Rectangle {
        property string glyph: ""
        property string glyphColor: "#F2F2F2"
        property bool ring: false
        signal hit
        width: 30
        height: 30
        radius: 15
        border { width: ring ? 1 : 0; color: Theme.s3 }
        Icon {
            anchors.centerIn: parent
            text: parent.glyph
            font.pixelSize: 14
            color: parent.glyphColor
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.hit() }
    }

    component NavRow: Item {
        property string pid: ""
        property string icon: ""
        property string label: ""
        readonly property bool sel: win.page === pid
        width: parent ? parent.width : 0
        height: 40
        Rectangle {
            anchors.fill: parent
            radius: Theme.corner(12)
            color: sel ? Theme.fg : Theme.s2
            opacity: sel ? 1 : (nhov.hovered ? 0.7 : 0)
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Icon {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: icon
            font.pixelSize: 19
            color: sel ? Theme.ink : Theme.grey
        }
        Text {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            text: label
            font { family: Theme.ui; pixelSize: 14 }
            color: sel ? Theme.ink : Theme.fg
        }
        HoverHandler { id: nhov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: win.select(pid) }
    }

    Item {
        anchors.fill: parent
        opacity: win.t
        focus: true
        Keys.onEscapePressed: win.close()

        // ---- header: discs + the word ----
        Item {
            id: hdr
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 62
            Row {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Disc {
                    color: "#D71921"
                    glyph: "\u{F0156}"
                    onHit: win.close()
                }
                Disc {
                    color: "#F2F2F2"
                    glyph: "\u{F0374}"
                    glyphColor: "#000000"
                    ring: true
                    onHit: Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/minimise.sh"])
                }
                Disc {
                    color: "#000000"
                    glyph: "\u{F0293}"
                    ring: true
                    onHit: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })"])
                }
            }
            Num {
                anchors.centerIn: parent
                text: "TASK MANAGER"
                font.pixelSize: 26
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.s2
            }
        }

        // ---- sidebar ----
        Rectangle {
            id: side
            anchors { left: parent.left; top: hdr.bottom; bottom: parent.bottom }
            width: 230
            color: Theme.s1
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 1
                color: Theme.s2
            }
            Column {
                x: 12
                y: 16
                width: parent.width - 24
                spacing: 4
                NavRow { pid: "processes"; icon: "\u{F0149}"; label: "processes" }
                NavRow { pid: "performance"; icon: "\u{F012A}"; label: "performance" }
                NavRow { pid: "startup"; icon: "\u{F14DE}"; label: "startup" }
            }
        }

        // ---- content ----
        Item {
            anchors { left: side.right; right: parent.right; top: hdr.bottom; bottom: parent.bottom }
            Item {
                id: stage
                anchors { fill: parent; leftMargin: 30; rightMargin: 30; topMargin: 24; bottomMargin: 20 }
                Num {
                    id: ptitle
                    text: win.heads[win.page][0]
                    font.pixelSize: 36
                }
                Lb {
                    anchors { left: ptitle.left; top: ptitle.bottom; topMargin: 6 }
                    text: win.heads[win.page][1]
                    px: 11.5
                }
                Item {
                    anchors { left: parent.left; right: parent.right; top: ptitle.bottom; topMargin: 52; bottom: parent.bottom }
                    TmProcesses { anchors.fill: parent; active: win.visible && win.page === "processes" }
                    TmPerf { anchors.fill: parent; active: win.visible && win.page === "performance" }
                    TmStartup { anchors.fill: parent; active: win.visible && win.page === "startup" }
                }
            }
        }
    }
}
