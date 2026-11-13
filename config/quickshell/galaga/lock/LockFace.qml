import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Networking
import Quickshell.Services.UPower
import qs
import qs.components
import qs.services

// the face of the lock -- and of the greeter (greet.qml): one drawing, two auth backends.
// lock: Doto clock across the full width, date and weather as labels, layout/network/battery and notification count in the corners.
// At the bottom an avatar in a ring of dots, name and a pill field: entered -- white dots, red caret. Wrong password -- everything red, the field shakes.
// The caller owns auth: { buffer, fail, busy, leaving, submit() } (lock.qml feeds it from PAM, greet.qml from Greetd).
// switcher (greeter only): the name becomes a bubble with a caret; a click lists the other users (users: [{ name, face }])
// and picking one fires userPicked -- the greeter then restarts auth for that user.
Item {
    id: root

    required property var auth
    property string layout: "en"

    // who is logging in. Lock: the session's own user and ~/.face. Greeter: the picked user, face resolved by greet.qml
    property string userName: Quickshell.env("USER")
    property string face: `file://${Quickshell.env("HOME")}/.face`
    // the custom profile photo (settings -> lock), as a file:// url: set -- the photo itself,
    // round-clipped inside the dot ring; empty -- the dotted face below, which stays the default
    property string photo: ""
    // true only on the session lock (LockSurface): media controls and the notification
    // summary live there. The greeter shares this face but has no session to read a
    // player or a summary from, so it leaves this false and its face is unchanged
    property bool session: false
    // the wallpaper behind the face: the session lock passes its own screen's (LockSurface);
    // empty -- the shared one, which is also all the greeter knows
    property string wallPath: ""
    // a wallpaper of the lock's own (settings -> lock): the session lock passes the state copy,
    // the greeter its synced one. Set and loadable -- it covers the desktop wallpaper
    property string lockWallUrl: ""
    // the clock's shape (settings -> lock): 0 matrix -- the dotted time as it always was,
    // 1 stacked -- hours over minutes, 2 analogue -- a ring of minute dots and two hands.
    // Stacked runs taller, so the lines under the clock shift down with it
    readonly property int clockStyle: Theme.state.lockClock
    readonly property real clockShift: clockStyle === 1 ? 56 : 0
    property bool switcher: false
    property var users: []
    property bool usersOpen: false
    signal userPicked(string name)

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var en: Qt.locale("en_US")
    readonly property var bat: UPower.displayDevice
    property bool blink: true
    Timer { running: true; interval: 500; repeat: true; onTriggered: root.blink = !root.blink }

    // appearance: t 0->1 linear, each element has its own phase with ease-out-quart (like glide): orb and clock, labels, avatar --
    // the ring lights up in a wave, the field grows from a dot. Auth accepted (auth.leaving) -- t back and faster, the caller finishes the exit
    property real t: 0
    Behavior on t { NumberAnimation { duration: root.auth.leaving ? 450 : 1100 } }
    Component.onCompleted: t = Qt.binding(() => root.auth.leaving ? 0 : 1)
    function ph(a, b) { const x = Math.max(0, Math.min(1, (t - a) / (b - a))); return 1 - Math.pow(1 - x, 4); }
    // hide the password's length (settings -> lock, off by default): three fixed dots that pulse
    // on each key instead of one dot per character. Off -- the dot count is the length, exactly
    readonly property bool hideLen: Theme.state.lockHideLen
    // power from the lock (AMM021's lock power menu): sleep, reboot, power off -- the session
    // lock only (session flag); the greeter face never shows it. Reboot and power off take a
    // second press within 5 s: a locked session can hold unsaved work. systemctl, as in power/
    // name, systemctl verb, icon, key -- the rows below and F10/F11/F12 both read this list
    readonly property var powerActs: [["sleep", "suspend", "\u{F0594}", "f10"], ["reboot", "reboot", "\u{F0709}", "f11"], ["power off", "poweroff", "\u{F0425}", "f12"]]
    property int armed: -1
    Timer { id: disarm; interval: 5000; onTriggered: root.armed = -1 }
    function powerAct(i) {
        if (i > 0 && armed !== i) { armed = i; disarm.restart(); return; }
        armed = -1;
        Quickshell.execDetached(["systemctl", powerActs[i][1]]);
    }
    // password check: a wave runs over the entered dots
    property real wave: 0
    NumberAnimation on wave { running: root.auth.busy; from: 0; to: 1; duration: 700; loops: Animation.Infinite }

    Stage {
        id: stage
        focus: true
        // type-anywhere: the password starts with the first key, no click. focus: true asks for it,
        // these take it -- first frame, and again if the surface ever (re)appears without it
        Component.onCompleted: forceActiveFocus()
        onVisibleChanged: if (visible) forceActiveFocus()

        Keys.onPressed: e => {
            if (root.usersOpen && e.key === Qt.Key_Escape) { root.usersOpen = false; e.accepted = true; return; }
            if (root.auth.leaving) return;
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.auth.submit();
            else if (e.key === Qt.Key_Escape) root.auth.buffer = "";
            else if (e.key === Qt.Key_Backspace) root.auth.buffer = root.auth.buffer.slice(0, -1);
            // F10/F11/F12 -- the power list below; a held key (auto-repeat) doesn't count as a press
            else if (root.session && e.key >= Qt.Key_F10 && e.key <= Qt.Key_F12) { if (!e.isAutoRepeat) root.powerAct(e.key - Qt.Key_F10); }
            // Ctrl/Alt/Super + key is a shortcut, never a password character (Shift alone is fine --
            // capitals are; numpad digits carry KeypadModifier, not one of these three)
            else if (e.text && e.text.charCodeAt(0) >= 32
                     && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { root.auth.buffer += e.text; root.auth.fail = false; }
            else return;
            e.accepted = true;
        }

        Item {
            opacity: root.ph(0, 0.6)
            Orb { visible: Theme.state.orb; x: stage.width - 720; y: stage.height - 580 }
            Wall { width: stage.width; height: stage.height; path: Theme.wallSrc(root.wallPath || Theme.state.wall) }
            // the lock's own wallpaper, plain and full-bleed over the desktop one;
            // not loadable -- invisible, and the desktop wallpaper shows as before
            Image {
                anchors.fill: parent
                visible: status === Image.Ready
                source: root.lockWallUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(1920, 1200)
            }
        }

        Lb {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 170
            text: root.en.toString(clock.date, "dddd · d MMMM")
            px: 14
            opacity: root.ph(0.15, 0.55)
            transform: Translate { y: 16 * (1 - root.ph(0.15, 0.55)) }
        }
        Row {
            visible: root.clockStyle === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: 230
            opacity: root.ph(0, 0.5)
            transform: Translate { y: -40 * (1 - root.ph(0, 0.5)) }
            Num { text: Theme.hh(clock.date); font.pixelSize: 400 }
            Num { text: ":"; font.pixelSize: 400; opacity: root.blink || !Theme.state.blink ? 1 : 0.2 }
            Num { text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 400 }
        }
        // stacked: hours over minutes, nothing-style -- the widget clocks on nothing phones
        Column {
            visible: root.clockStyle === 1
            anchors.horizontalCenter: parent.horizontalCenter
            y: 196
            spacing: -36
            opacity: root.ph(0, 0.5)
            transform: Translate { y: -40 * (1 - root.ph(0, 0.5)) }
            Num { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.hh(clock.date); font.pixelSize: 300 }
            Num { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatTime(clock.date, "mm"); font.pixelSize: 300 }
        }
        // analogue: sixty minute dots, twelve hour dots, two hands from the centre
        Item {
            visible: root.clockStyle === 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: 208
            width: 352
            height: 352
            opacity: root.ph(0, 0.5)
            Ring { anchors.fill: parent; n: 60; dot: 3; f: 1; on: Theme.s3 }
            Repeater {
                model: 12
                Rectangle {
                    required property int index
                    readonly property real a: index * Math.PI / 6
                    x: parent.width / 2 + Math.sin(a) * 158 - 4.5
                    y: parent.height / 2 - Math.cos(a) * 158 - 4.5
                    width: 9
                    height: 9
                    radius: 4.5
                    color: Theme.fg
                }
            }
            Rectangle {
                x: parent.width / 2 - 3.5
                y: parent.height / 2 - 100
                width: 7
                height: 100
                radius: 3.5
                color: Theme.fg
                transformOrigin: Item.Bottom
                rotation: ((clock.date.getHours() % 12) + clock.date.getMinutes() / 60) * 30
            }
            Rectangle {
                x: parent.width / 2 - 2.5
                y: parent.height / 2 - 148
                width: 5
                height: 148
                radius: 2.5
                color: Theme.fg
                transformOrigin: Item.Bottom
                rotation: clock.date.getMinutes() * 6
            }
            Rectangle {
                anchors.centerIn: parent
                width: 13
                height: 13
                radius: 6.5
                color: Theme.red
            }
        }
        Lb {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 600 + root.clockShift
            opacity: root.ph(0.25, 0.65)
            transform: Translate { y: 16 * (1 - root.ph(0.25, 0.65)) }
            text: [Weather.ok ? `${Math.round(Weather.now.temp)}° ${Weather.name(Weather.now.code)}` : "",
                   Media.player?.trackTitle ? `${Media.player.trackTitle} — ${Media.player.trackArtist}` : ""].filter(Boolean).join(" · ")
        }
        // the player, with controls -- session lock only (see session above): cover as
        // dots, the shared Controls row. On the lock surface the clicks land; in the
        // greeter this block never exists.
        Row {
            visible: root.session && Theme.state.featLockMedia && !!Media.player
            anchors.horizontalCenter: parent.horizontalCenter
            y: 646 + root.clockShift
            spacing: 18
            opacity: root.ph(0.35, 0.75)
            transform: Translate { y: 16 * (1 - root.ph(0.35, 0.75)) }
            Art { anchors.verticalCenter: parent.verticalCenter; width: 54; height: 54; url: Media.player?.trackArtUrl ?? ""; step: 3 }
            Controls { anchors.verticalCenter: parent.verticalCenter; size: 20; play: 46 }
        }

        Row {
            anchors { right: parent.right; rightMargin: 44 }
            y: 36
            spacing: 16
            opacity: root.ph(0.45, 0.85)
            Lb { anchors.verticalCenter: parent.verticalCenter; text: root.layout }
            Icon { anchors.verticalCenter: parent.verticalCenter; text: Networking.wifiEnabled ? "\u{F05A9}" : "\u{F05AA}"; font.pixelSize: 17 }
            Rectangle {
                visible: root.bat.isLaptopBattery
                anchors.verticalCenter: parent.verticalCenter
                width: 27
                height: 13
                radius: 7
                color: "transparent"
                border { width: 1.5; color: Theme.grey }
                Rectangle { x: 3; y: 3; width: (parent.width - 6) * root.bat.percentage; height: parent.height - 6; radius: 4; color: Theme.fg }
            }
            Lb { visible: root.bat.isLaptopBattery; anchors.verticalCenter: parent.verticalCenter; text: Math.round(root.bat.percentage * 100) }
        }
        Column {
            opacity: root.ph(0.45, 0.85)
            x: 44
            anchors { bottom: parent.bottom; bottomMargin: 44 }
            spacing: 28
            Column {
                visible: Theme.state.unread > 0
                spacing: 8
                Row {
                    spacing: 16
                    Icon { anchors.verticalCenter: parent.verticalCenter; text: "\u{F009A}"; font.pixelSize: 17 }
                    Lb { anchors.verticalCenter: parent.verticalCenter; text: `${Theme.state.unread} notifications` }
                }
                // the summary itself -- session lock only, like the player above
                Column {
                    visible: root.session && Theme.state.featLockMedia
                    spacing: 4
                    Repeater {
                        model: Theme.state.peek.slice(0, 2)
                        Lb {
                            required property var modelData
                            width: 560
                            elide: Text.ElideRight
                            text: `${modelData.app} · ${modelData.summary}`
                            px: 11
                            color: Theme.grey
                        }
                    }
                }
            }
            // power -- session lock only, like the summary: a click, or F10 F11 F12
            // (see the keys above). Three chips in a row: an icon disc, the name,
            // and the shortcut as a key cap, so the keys are on the face, not
            // only in the handler. (Built as plain rectangles with explicit
            // heights -- the earlier rows were Row delegates and rendered
            // nowhere on the real lock, label only.)
            Column {
                visible: root.session
                spacing: 10
                Lb { text: "power"; color: Theme.grey }
                Row {
                    spacing: 10
                    Repeater {
                        model: root.powerActs
                        Rectangle {
                            id: chip
                            required property var modelData
                            required property int index
                            readonly property bool arm: root.armed === index
                            width: crow.width + 26
                            height: 38
                            radius: Theme.corner(19)
                            color: arm ? Theme.red : Theme.s1
                            border { width: 1; color: arm ? Theme.red : Theme.s2 }
                            Row {
                                id: crow
                                anchors.centerIn: parent
                                spacing: 9
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: chip.arm ? Theme.fg : Theme.s2
                                    Icon { anchors.centerIn: parent; text: chip.modelData[2]; font.pixelSize: 14; color: chip.arm ? Theme.red : Theme.fg }
                                }
                                Lb { anchors.verticalCenter: parent.verticalCenter; text: chip.arm ? `press again` : chip.modelData[0]; color: chip.arm ? Theme.ink : Theme.fg }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: kcap.width + 12
                                    height: 20
                                    radius: Theme.corner(6)
                                    color: "transparent"
                                    border { width: 1; color: chip.arm ? Theme.ink : Theme.s3 }
                                    Lb { id: kcap; anchors.centerIn: parent; text: chip.modelData[3]; px: 10; color: chip.arm ? Theme.ink : Theme.grey }
                                }
                            }
                            MouseArea { anchors.fill: parent; enabled: !root.auth.leaving; onClicked: root.powerAct(index) }
                        }
                    }
                }
            }
        }

        Column {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 120 }
            spacing: 16

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96
                height: 96
                opacity: root.ph(0.3, 0.7)
                transform: Translate { y: 24 * (1 - root.ph(0.3, 0.7)) }
                Ring { anchors.fill: parent; n: 32; f: root.t > 0.35 ? 1 : 0 } // lights up and fades in a wave around the circle
                // face as dots, like covers; no file -- Art gradient
                Art { visible: photoImg.status !== Image.Ready; anchors { fill: parent; margins: 18 } url: root.face; step: 3 }
                // the custom photo, round-clipped (the shot card's mask pattern); wins over the dots when it loads
                Item {
                    visible: photoImg.status === Image.Ready
                    anchors { fill: parent; margins: 18 }
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: faceMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                    Image {
                        id: photoImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: root.photo
                        sourceSize: Qt.size(192, 192)
                        asynchronous: true
                    }
                }
                Rectangle { id: faceMask; anchors { fill: parent; margins: 18 } radius: width / 2; visible: false; layer.enabled: true }
            }
            Text {
                visible: !root.switcher
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.userName
                font { family: Theme.ui; pixelSize: 22 }
                color: Theme.fg
                opacity: root.ph(0.4, 0.75)
                transform: Translate { y: 16 * (1 - root.ph(0.4, 0.75)) }
            }

            // greeter only: the name in a bubble, caret beside it. Click -- the other users drop down; pick one and auth restarts for them
            Item {
                visible: root.switcher
                anchors.horizontalCenter: parent.horizontalCenter
                width: bubbleRow.width + 44
                height: 48
                opacity: root.ph(0.4, 0.75)
                transform: Translate { y: 16 * (1 - root.ph(0.4, 0.75)) }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.s2
                    border { width: 1; color: root.usersOpen ? Theme.fg : Theme.s3 }
                }
                Row {
                    id: bubbleRow
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.userName
                        font { family: Theme.ui; pixelSize: 22 }
                        color: Theme.fg
                    }
                    // caret, drawn: no font here is guaranteed to carry a chevron
                    Item {
                        visible: root.users.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 9
                        rotation: root.usersOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 180 } }
                        Rectangle { x: 0; y: 3; width: 9; height: 2.4; radius: 1.2; color: Theme.fg; rotation: 42 }
                        Rectangle { x: 5; y: 3; width: 9; height: 2.4; radius: 1.2; color: Theme.fg; rotation: -42 }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: if (root.users.length > 0) root.usersOpen = !root.usersOpen }
            }
            Column {
                visible: root.switcher && root.usersOpen && root.users.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Repeater {
                    model: root.users
                    Rectangle {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 300
                        height: 48
                        radius: Theme.corner(24)
                        color: pick.containsMouse ? Theme.s3 : Theme.s2
                        border { width: 1; color: Theme.s3 }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            font { family: Theme.ui; pixelSize: 18 }
                            color: Theme.fg
                        }
                        MouseArea {
                            id: pick
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.usersOpen = false; root.userPicked(modelData.name); }
                        }
                    }
                }
            }

            // field: one white dot per entered character and the caret -- nothing pre-rendered,
            // so the dot count is always the password length (empty field -- no dots at all).
            // With "hide length" on: three fixed dots once typing starts, pulsing per key
            Rectangle {
                id: pwd
                anchors.horizontalCenter: parent.horizontalCenter
                width: 58 + (380 - 58) * root.ph(0.5, 0.9) // grows from a dot into a pill
                height: 58
                radius: Theme.corner(29)
                opacity: root.ph(0.45, 0.6)
                color: Theme.s1
                border { width: 1; color: root.auth.fail ? Theme.red : Theme.s3 }

                Row {
                    anchors.centerIn: parent
                    spacing: 14
                    opacity: root.ph(0.75, 1)
                    Repeater {
                        id: typed
                        model: root.hideLen ? (root.auth.buffer.length ? 3 : 0) : Math.min(root.auth.buffer.length, 16)
                        // a new dot clicks in; while auth is thinking -- a wave runs over the dots
                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 11
                            height: 11
                            radius: 5.5
                            color: root.auth.fail ? Theme.red : Theme.fg
                            opacity: root.auth.busy && Math.abs(root.wave * (typed.count + 2) - 1 - index) > 1.2 ? 0.3 : 1
                            NumberAnimation on scale { from: 0.2; to: 1; duration: 180; easing.type: Easing.OutCubic }
                            // hide length: the three fixed dots pulse on each key instead
                            SequentialAnimation on scale {
                                id: pulse
                                running: false
                                NumberAnimation { to: 0.55; duration: 50 }
                                NumberAnimation { to: 1; duration: 160; easing.type: Easing.OutCubic }
                            }
                            Connections {
                                target: root.auth
                                function onBufferChanged() { if (root.hideLen && root.auth.buffer.length) pulse.restart(); }
                            }
                        }
                    }
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 2; height: 24; color: Theme.red; opacity: root.blink ? 1 : 0 }
                }

                SequentialAnimation {
                    id: shake
                    loops: 2
                    NumberAnimation { target: pwd; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
                    NumberAnimation { target: pwd; property: "anchors.horizontalCenterOffset"; to: 10; duration: 80 }
                    NumberAnimation { target: pwd; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
                }
                Connections {
                    target: root.auth
                    function onFailChanged() { if (root.auth.fail) shake.restart(); }
                }
            }
            Lb {
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: root.ph(0.8, 1)
                text: root.auth.busy ? "checking…" : root.auth.fail ? (root.auth.msg || "wrong password · try again") : "enter password"
                color: root.auth.fail ? Theme.red : Theme.grey
            }
        }
    }
}
