import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// users: the machine's accounts, read from getent. Changes run through the
// shadow tools behind pkexec (useradd / usermod / userdel / chpasswd) and the
// list is re-read after every one -- nothing here keeps its own copy of the
// truth. An existing user's password is set in a terminal running passwd;
// the password itself never passes through this page.
Item {
    id: pg

    property bool active: false
    property var users: []
    property var pendingUsers: []
    property var loggedIn: []
    property string me: Quickshell.env("USER") || ""
    property string term: ""
    property string err: ""
    property string okMsg: ""
    property string pending: ""
    property string actOut: ""
    property string actErr: ""
    property bool addOpen: false
    property bool newAdmin: false

    readonly property var meUser: findUser(me)
    readonly property bool addValid: /^[a-z_][a-z0-9_-]*$/.test(newUser.value.trim())
        && newPass.value.length > 0 && newPass.value === newPass2.value

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    // one value into a shell script: wrap it in single quotes, escaping the
    // quotes it carries. Only the add-user flow builds a script at all (it
    // has to pipe into chpasswd); everything else passes plain argv.
    function esc(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function findUser(name) { for (const u of pg.users) if (u.name === name) return u; return null; }

    function run(tag, cmd) {
        if (act.running) return;
        pg.pending = tag; pg.err = ""; pg.okMsg = ""; pg.actOut = ""; pg.actErr = "";
        act.exec(cmd);
    }
    function addUser() {
        const uname = newUser.value.trim();
        const script = "useradd -m -s /bin/bash -c " + esc(newName.value.trim()) + " " + esc(uname)
            + (newAdmin ? " && usermod -aG wheel " + esc(uname) : "")
            + " && printf '%s:%s\\n' " + esc(uname) + " " + esc(newPass.value) + " | chpasswd";
        run("add", ["pkexec", "sh", "-c", script]);
    }
    function setAdmin(u, want) {
        run("admin", want ? ["pkexec", "usermod", "-aG", "wheel", u.name]
                          : ["pkexec", "gpasswd", "-d", u.name, "wheel"]);
    }
    function renameUser(u, name) {
        const n = name.trim();
        if (!n || n === u.full) return;
        run("rename", ["pkexec", "usermod", "-c", n, u.name]);
    }
    function removeUser(u, withHome) {
        if (pg.loggedIn.includes(u.name)) {
            pg.err = u.name + " is signed in — sign them out before removing the account";
            return;
        }
        run("remove", ["pkexec", "userdel"].concat(withHome ? ["-r"] : [], [u.name]));
    }
    function setPassword(u) {
        if (!pg.term) return;
        Sounds.play("tick");
        Quickshell.execDetached([pg.term, "-e", "sudo", "passwd", u.name]);
    }

    function refresh() {
        if (!passwdProc.running) passwdProc.running = true;
        if (!whoProc.running) whoProc.running = true;
        if (!pg.term && !termProc.running) termProc.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: passwdProc
        command: ["getent", "passwd"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const ln of text.split("\n")) {
                    if (!ln.trim()) continue;
                    const f = ln.split(":");
                    if (f.length < 4) continue;
                    const uid = parseInt(f[2]);
                    if (isNaN(uid) || (uid < 1000 && f[0] !== pg.me)) continue;
                    list.push({ name: f[0], uid: uid, full: (f[4] || "").split(",")[0],
                                you: f[0] === pg.me, admin: false });
                }
                pg.pendingUsers = list;
                if (!list.length) { pg.users = []; return; }
                const names = list.map(u => pg.esc(u.name)).join(" ");
                groupProc.exec(["sh", "-c",
                    "for u in " + names + "; do printf '%s|%s\\n' \"$u\" \"$(id -nG \"$u\" | tr ' ' ',')\"; done"]);
            }
        }
    }
    Process {
        id: groupProc
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const ln of text.split("\n")) {
                    const i = ln.indexOf("|");
                    if (i < 0) continue;
                    map[ln.slice(0, i)] = ln.slice(i + 1).split(",");
                }
                const list = pg.pendingUsers;
                for (const u of list) u.admin = (map[u.name] || []).includes("wheel");
                pg.users = list;
            }
        }
    }
    Process {
        id: whoProc
        command: ["who"]
        stdout: StdioCollector {
            onStreamFinished: pg.loggedIn = text.split("\n").map(s => s.trim().split(/\s+/)[0]).filter(s => s)
        }
    }
    Process {
        id: termProc
        command: ["sh", "-c", "command -v kitty || command -v xterm"]
        stdout: StdioCollector { onStreamFinished: pg.term = text.trim() }
    }
    Process {
        id: act
        stdout: StdioCollector { onStreamFinished: pg.actOut = text }
        stderr: StdioCollector { onStreamFinished: pg.actErr = text }
        onExited: code => pg.actDone(code)
    }
    function actDone(code) {
        const tag = pg.pending; pg.pending = "";
        if (code === 0) {
            pg.err = "";
            const done = { add: "account created", rename: "name updated",
                           admin: "admin rights updated", remove: "account removed" };
            if (tag === "add") {
                pg.addOpen = false; pg.newAdmin = false;
                newUser.value = ""; newName.value = ""; newPass.value = ""; newPass2.value = "";
            }
            if (done[tag]) pg.okMsg = done[tag];
        } else {
            const lines = pg.actErr.trim().split("\n").filter(s => s.trim());
            pg.err = lines.length ? lines[lines.length - 1] : "the command failed — nothing was changed";
        }
        pg.refresh();
    }

    component Avatar: Rectangle {
        property string letter: "?"
        width: 42
        height: 42
        radius: 21
        color: Theme.s3
        Text {
            anchors.centerIn: parent
            text: parent.letter.toUpperCase()
            font { family: Theme.mono; pixelSize: 17; weight: Font.DemiBold }
            color: Theme.fg
        }
    }
    component Badge: Rectangle {
        property string text: ""
        height: 19
        width: blbl.implicitWidth + 14
        radius: Theme.corner(9)
        color: Theme.s3
        Lb { id: blbl; anchors.centerIn: parent; text: parent.text; px: 9; color: Theme.grey }
    }
    component SetField: Item {
        property string label: ""
        property string hint: ""
        property alias value: inp.text
        property alias secret: inp.echoMode
        width: parent ? parent.width : 0
        height: 76
        Lb { text: label; px: 10.5; color: Theme.mute }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 44
            radius: Theme.corner(22)
            color: Theme.s2
            border { width: inp.activeFocus ? 1 : 0; color: Theme.fg }
            TextInput {
                id: inp
                anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                verticalAlignment: TextInput.AlignVCenter
                font { family: Theme.ui; pixelSize: 15 }
                color: Theme.fg
                selectionColor: Theme.s3
                clip: true
                Text {
                    visible: !inp.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: hint
                    font: inp.font
                    color: Theme.mute
                }
            }
        }
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
                SetHead { text: "you" }
                Lb { visible: !pg.meUser; text: "reading accounts…" }
                SetCard {
                    visible: pg.meUser !== null
                    Row {
                        width: parent.width
                        spacing: 14
                        Avatar { letter: pg.meUser ? pg.meUser.name.charAt(0) : "?" }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Row {
                                spacing: 8
                                Text {
                                    text: pg.meUser ? pg.meUser.name : ""
                                    font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold }
                                    color: Theme.fg
                                }
                                Badge { visible: pg.meUser !== null && pg.meUser.admin; text: "admin" }
                            }
                            Lb {
                                text: pg.meUser && pg.meUser.full ? pg.meUser.full : "no full name set"
                                px: 10.5
                                color: Theme.mute
                            }
                        }
                    }
                }
            }

            Lb {
                visible: pg.err !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: pg.err
                px: 11
                color: Theme.red
            }
            Lb {
                visible: pg.err === "" && pg.okMsg !== ""
                text: pg.okMsg
                px: 11
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "accounts" }
                Lb { visible: !pg.users.length; text: "no accounts found" }
                Repeater {
                    model: pg.users
                    SetCard {
                        id: ucard
                        required property var modelData
                        property bool editOpen: false
                        property bool armOpen: false
                        property bool delHome: true

                        Row {
                            width: parent.width
                            spacing: 14
                            Avatar { letter: modelData.name.charAt(0) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Row {
                                    spacing: 8
                                    Text {
                                        text: modelData.name
                                        font { family: Theme.ui; pixelSize: 15; weight: Font.DemiBold }
                                        color: Theme.fg
                                    }
                                    Badge { visible: modelData.you; text: "you" }
                                    Badge { visible: modelData.admin; text: "admin" }
                                }
                                Lb {
                                    text: modelData.full ? modelData.full : "no full name set"
                                    px: 10.5
                                    color: Theme.mute
                                }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.s2 }
                        SetRow {
                            label: "full name"
                            value: modelData.full
                            SetButton {
                                label: ucard.editOpen ? "cancel" : "edit"
                                onHit: { ucard.editOpen = !ucard.editOpen; if (ucard.editOpen) { renameIn.text = modelData.full; renameIn.forceActiveFocus(); } }
                            }
                        }
                        Item {
                            visible: ucard.editOpen
                            width: parent ? parent.width : 0
                            height: ucard.editOpen ? 64 : 0
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 12
                                Rectangle {
                                    width: parent.width - 108
                                    height: 44
                                    radius: Theme.corner(22)
                                    color: Theme.s2
                                    border { width: renameIn.activeFocus ? 1 : 0; color: Theme.fg }
                                    TextInput {
                                        id: renameIn
                                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        font { family: Theme.ui; pixelSize: 15 }
                                        color: Theme.fg
                                        selectionColor: Theme.s3
                                        clip: true
                                        onAccepted: pg.renameUser(modelData, text)
                                    }
                                }
                                SetButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "set"
                                    onHit: pg.renameUser(modelData, renameIn.text)
                                }
                            }
                        }
                        SetToggle {
                            visible: !modelData.you
                            label: "administrator"
                            sub: "wheel group — can use sudo and pkexec"
                            on: modelData.admin
                            onFlip: want => pg.setAdmin(modelData, want)
                        }
                        SetRow {
                            visible: modelData.you
                            label: "administrator"
                            sub: "your own admin rights are changed from another admin account"
                            value: modelData.admin ? "admin" : "standard"
                        }
                        SetRow {
                            visible: !modelData.you && pg.term !== ""
                            label: "password"
                            sub: "set in a terminal — it never passes through settings"
                            divider: true
                            SetButton {
                                label: "set password"
                                onHit: pg.setPassword(modelData)
                            }
                        }
                        SetRow {
                            visible: !modelData.you
                            label: "remove account"
                            sub: pg.loggedIn.includes(modelData.name) ? "signed in right now — removal is refused" : "the account goes; the home folder is your choice below"
                            divider: ucard.armOpen
                            SetButton {
                                label: ucard.armOpen ? "keep" : "remove"
                                danger: !ucard.armOpen
                                onHit: ucard.armOpen = !ucard.armOpen
                            }
                        }
                        Item {
                            visible: ucard.armOpen && !modelData.you
                            width: parent ? parent.width : 0
                            height: visible ? 118 : 0
                            Column {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                SetToggle {
                                    label: "delete the home folder too"
                                    sub: "documents, settings, everything in /home/" + modelData.name
                                    on: ucard.delHome
                                    divider: false
                                    onFlip: want => ucard.delHome = want
                                }
                                Row {
                                    anchors.right: parent.right
                                    spacing: 10
                                    SetButton { label: "cancel"; onHit: ucard.armOpen = false }
                                    SetButton {
                                        label: "remove " + modelData.name
                                        danger: true
                                        onHit: { const u = modelData; const dh = ucard.delHome; ucard.armOpen = false; pg.removeUser(u, dh); }
                                    }
                                }
                            }
                        }
                        SetRow {
                            visible: modelData.you
                            label: "remove account"
                            sub: "the account you're signed in with can't be removed"
                            divider: false
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "add user" }
                SetCard {
                    SetRow {
                        visible: !pg.addOpen
                        label: "new account"
                        sub: "account, home folder and password in one go"
                        chevron: true
                        clickable: true
                        divider: false
                        onHit: { pg.addOpen = true; newUser.forceActiveFocus(); }
                    }
                    Column {
                        visible: pg.addOpen
                        width: parent ? parent.width : 0
                        spacing: 4
                        SetField { id: newUser; label: "username"; hint: "lowercase — letters, digits, - and _" }
                        SetField { id: newName; label: "full name"; hint: "the name on the sign-in screen" }
                        SetField { id: newPass; label: "password"; secret: TextInput.Password }
                        SetField { id: newPass2; label: "password again"; secret: TextInput.Password }
                        SetToggle {
                            label: "administrator"
                            sub: "wheel group — can use sudo and pkexec"
                            on: pg.newAdmin
                            onFlip: want => pg.newAdmin = want
                        }
                        Lb {
                            visible: newUser.value !== "" && !/^[a-z_][a-z0-9_-]*$/.test(newUser.value.trim())
                            text: "usernames start with a letter or _ and stay lowercase"
                            px: 10.5
                            color: Theme.red
                        }
                        Lb {
                            visible: newPass.value !== "" && newPass2.value !== "" && newPass.value !== newPass2.value
                            text: "the passwords don't match"
                            px: 10.5
                            color: Theme.red
                        }
                        Item {
                            width: parent.width
                            height: 48
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 10
                                SetButton { label: "cancel"; onHit: pg.addOpen = false }
                                Rectangle {
                                    width: createLbl.implicitWidth + 32
                                    height: 32
                                    radius: Theme.corner(16)
                                    color: Theme.s2
                                    opacity: pg.addValid && !act.running ? 1 : 0.4
                                    Text {
                                        id: createLbl
                                        anchors.centerIn: parent
                                        text: "create account"
                                        font { family: Theme.ui; pixelSize: 13; weight: Font.DemiBold }
                                        color: Theme.fg
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: if (pg.addValid && !act.running) pg.addUser() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
