import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// lock: everything about the face -- the photo, a wallpaper of its own, the
// clock's shape, and what may show on it. The desktop's look stays on the
// appearance page; this page is the lock alone (and the greeter, which shares
// the face).
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    // profile photo: set copies the file next to galaga.json (state.avatar) and
    // to ~/.face; a ~/.face that was already there is backed up into the state
    // dir first, and clear brings it back (or removes ours). The lock reads
    // state.avatar; the greeter gets its copy from install.sh --greeter.
    property string photoMsg: ""
    function setPhoto() {
        const raw = photoIn.text.trim();
        const p = raw.startsWith("~/") ? Quickshell.env("HOME") + raw.slice(1) : raw;
        if (!p) { photoMsg = "type a path first"; return; }
        photoSet.exec(["sh", "-c",
            'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; mkdir -p "$st"; src="$1"; [ -f "$src" ] || { echo missing; exit 1; }\n' +
            'ext="${src##*.}"; case "$ext" in jpg|jpeg|png|webp|JPG|JPEG|PNG|WEBP) ;; *) ext=png ;; esac\n' +
            '[ -f "$HOME/.face" ] && [ ! -f "$st/face-backup" ] && cp "$HOME/.face" "$st/face-backup"\n' +
            'cp "$src" "$st/avatar.$ext" && cp "$src" "$HOME/.face" && printf "%s" "$st/avatar.$ext"',
            "galaga-photo", p]);
    }
    function clearPhoto() { photoClear.running = true; }
    Process {
        id: photoSet
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t && t !== "missing") { Theme.state.avatar = t; pg.photoMsg = ""; photoIn.text = ""; }
                else pg.photoMsg = "no such file";
            }
        }
    }
    Process {
        id: photoClear
        command: ["sh", "-c",
            'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; rm -f "$st"/avatar.*\n' +
            'if [ -f "$st/face-backup" ]; then mv "$st/face-backup" "$HOME/.face"; else rm -f "$HOME/.face"; fi']
        onExited: { Theme.state.avatar = ""; pg.photoMsg = ""; }
    }

    // the lock's own wallpaper: set copies the file next to galaga.json
    // (state.lockWall) and the face draws it instead of the desktop wallpaper;
    // the greeter gets its copy from install.sh --greeter. Clear -- the desktop
    // wallpaper again
    property string wallMsg: ""
    function setWall() {
        const raw = wallIn.text.trim();
        const p = raw.startsWith("~/") ? Quickshell.env("HOME") + raw.slice(1) : raw;
        if (!p) { wallMsg = "type a path first"; return; }
        lwSet.exec(["sh", "-c",
            'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; mkdir -p "$st"; src="$1"; [ -f "$src" ] || { echo missing; exit 1; }\n' +
            'ext="${src##*.}"; case "$ext" in jpg|jpeg|png|webp|JPG|JPEG|PNG|WEBP) ;; *) ext=jpg ;; esac\n' +
            'rm -f "$st"/lockwall.*\n' +
            'cp "$src" "$st/lockwall.$ext" && printf "%s" "$st/lockwall.$ext"',
            "galaga-lockwall", p]);
    }
    function clearWall() { lwClear.running = true; }
    Process {
        id: lwSet
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t && t !== "missing") { Theme.state.lockWall = t; pg.wallMsg = ""; wallIn.text = ""; }
                else pg.wallMsg = "no such file";
            }
        }
    }
    Process {
        id: lwClear
        command: ["sh", "-c", 'st="${XDG_STATE_HOME:-$HOME/.local/state}/rice"; rm -f "$st"/lockwall.*']
        onExited: { Theme.state.lockWall = ""; pg.wallMsg = ""; }
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

            // profile photo: a path field and a live preview -- the picker this
            // shell can stand behind (there is no file dialog in its toolkit).
            // Set -- the photo shows on the lock (and, after install.sh
            // --greeter, at boot); clear -- back to dots.
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "profile photo" }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 14
                        Item {
                            width: 72
                            height: 72
                            Ring { anchors.fill: parent; n: 24; dot: 3; f: 1 }
                            Item {
                                visible: pvImg.status === Image.Ready
                                anchors { fill: parent; margins: 12 }
                                layer.enabled: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: pvMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                                Image {
                                    id: pvImg
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(96, 96)
                                    source: {
                                        const t = photoIn.text.trim();
                                        const p = t.startsWith("~/") ? Quickshell.env("HOME") + t.slice(1) : t;
                                        return p ? "file://" + p : Theme.state.avatar ? "file://" + Theme.state.avatar : "";
                                    }
                                }
                            }
                            Rectangle { id: pvMask; anchors { fill: parent; margins: 12 } radius: width / 2; visible: false; layer.enabled: true }
                            Rectangle { visible: pvImg.status !== Image.Ready; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.fg }
                        }
                        Rectangle {
                            width: parent.width - 72 - 14 - (92 + 14) * 2
                            height: 52
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.corner(26)
                            color: Theme.s2
                            border { width: photoIn.activeFocus ? 1 : 0; color: Theme.fg }
                            Lb { id: photoL; x: 22; anchors.verticalCenter: parent.verticalCenter; text: "photo"; color: photoIn.activeFocus ? Theme.fg : Theme.grey }
                            TextInput {
                                id: photoIn
                                anchors { left: photoL.right; leftMargin: 18; right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                                font { family: Theme.ui; pixelSize: 15 }
                                color: Theme.fg
                                selectionColor: Theme.s3
                                clip: true
                                Text { visible: !photoIn.text; text: Theme.state.avatar || "~/Pictures/me.png"; font: photoIn.font; color: Theme.mute }
                                Keys.onPressed: e => {
                                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pg.setPhoto();
                                    else if (e.key === Qt.Key_Escape) photoIn.focus = false;
                                    else return;
                                    e.accepted = true;
                                }
                            }
                        }
                        SetButton { anchors.verticalCenter: parent.verticalCenter; label: "set"; onHit: pg.setPhoto() }
                        SetButton { anchors.verticalCenter: parent.verticalCenter; visible: !!Theme.state.avatar; label: "clear"; onHit: pg.clearPhoto() }
                    }
                    Lb { visible: !!pg.photoMsg; topPadding: 10; text: pg.photoMsg; px: 10; color: Theme.red }
                }
            }

            // the lock's own wallpaper: a path field and a preview, like the photo
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "wallpaper" }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 14
                        Item {
                            width: 92
                            height: 52
                            Rectangle { anchors.fill: parent; radius: Theme.corner(14); color: Theme.s2 }
                            Item {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: lwMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                                Image {
                                    id: lwImg
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(184, 104)
                                    source: {
                                        const t = wallIn.text.trim();
                                        const p = t.startsWith("~/") ? Quickshell.env("HOME") + t.slice(1) : t;
                                        return p ? "file://" + p : Theme.state.lockWall ? "file://" + Theme.state.lockWall : "";
                                    }
                                }
                            }
                            Rectangle { id: lwMask; anchors.fill: parent; radius: Theme.corner(14); visible: false; layer.enabled: true }
                            Lb { visible: lwImg.status !== Image.Ready; anchors.centerIn: parent; text: "wall"; px: 10; color: Theme.mute }
                        }
                        Rectangle {
                            width: parent.width - 92 - 14 - (92 + 14) * 2
                            height: 52
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.corner(26)
                            color: Theme.s2
                            border { width: wallIn.activeFocus ? 1 : 0; color: Theme.fg }
                            Lb { id: wallL; x: 22; anchors.verticalCenter: parent.verticalCenter; text: "wallpaper"; color: wallIn.activeFocus ? Theme.fg : Theme.grey }
                            TextInput {
                                id: wallIn
                                anchors { left: wallL.right; leftMargin: 18; right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                                font { family: Theme.ui; pixelSize: 15 }
                                color: Theme.fg
                                selectionColor: Theme.s3
                                clip: true
                                Text { visible: !wallIn.text; text: Theme.state.lockWall || "~/Pictures/lock.jpg"; font: wallIn.font; color: Theme.mute }
                                Keys.onPressed: e => {
                                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) pg.setWall();
                                    else if (e.key === Qt.Key_Escape) wallIn.focus = false;
                                    else return;
                                    e.accepted = true;
                                }
                            }
                        }
                        SetButton { anchors.verticalCenter: parent.verticalCenter; label: "set"; onHit: pg.setWall() }
                        SetButton { anchors.verticalCenter: parent.verticalCenter; visible: !!Theme.state.lockWall; label: "clear"; onHit: pg.clearWall() }
                    }
                    Lb { visible: !!pg.wallMsg; topPadding: 10; text: pg.wallMsg; px: 10; color: Theme.red }
                }
            }

            // the clock's shape: matrix -- the dotted time; stacked -- hours over
            // minutes; analogue -- dots and hands, like the nothing widget clocks
            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "clock" }
                SetCard {
                    SetPick {
                        label: "clock"
                        opts: ["matrix", "stacked", "analogue"]
                        cur: Theme.state.lockClock
                        divider: false
                        onPicked: i => Theme.state.lockClock = i
                    }
                    Lb { topPadding: 10; px: 10.5; text: "how the time sits on the face" }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "on the face" }
                SetCard {
                    SetToggle { label: "media + summary"; on: Theme.state.featLockMedia; onFlip: want => Theme.state.featLockMedia = want }
                    SetToggle { label: "hide length"; on: Theme.state.lockHideLen; onFlip: want => Theme.state.lockHideLen = want }
                    SetToggle { label: "one screen"; on: Theme.state.lockOneScreen; divider: false; onFlip: want => Theme.state.lockOneScreen = want }
                }
            }
        }
    }
}
