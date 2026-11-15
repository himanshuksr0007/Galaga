import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// software update: checkupdates for the repos, the AUR helper (yay, else
// paru) for the rest. Nothing here claims the system is current until a
// check has actually run in this session, and installing happens in a
// terminal -- password prompts and package conflicts belong where the
// user can see and answer them, not in a blind background upgrade.
// Without checkupdates there is no page at all, just the offer to
// install pacman-contrib, which brings it.
Item {
    id: pg

    property bool active: false
    property bool detDone: false
    property bool haveCU: false
    property string helper: ""
    property string term: ""
    property var repoRows: []
    property var aurRows: []
    property bool checked: false
    property bool checking: false
    property string checkErr: ""
    property string repoErr: ""
    property string actOut: ""
    property string actErr: ""
    property string actLog: ""
    property var actOk: null
    // the rice itself: the clone this shell runs from ("" when the config
    // dir is not inside one), and what the check found there
    property string dots: ""
    property int gitNew: -1 // new commits waiting; -1: not checked, or couldn't be
    property var gitRows: []
    property string gitErr: ""
    property bool pkgLegDone: false
    property bool gitLegDone: true

    readonly property int total: repoRows.length + aurRows.length

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    function parseUpdates(text) {
        const rows = [];
        for (const ln of text.split("\n")) {
            const f = ln.trim().split(/\s+/);
            if (f.length >= 4 && f[2] === "->") rows.push({ name: f[0], cur: f[1], next: f[3] });
        }
        return rows;
    }
    function check() {
        if (pg.checking || repoProc.running || aurProc.running) return;
        pg.checking = true; pg.checked = false; pg.checkErr = "";
        pg.repoRows = []; pg.aurRows = []; pg.repoErr = "";
        pg.pkgLegDone = false;
        pg.gitNew = -1; pg.gitRows = []; pg.gitErr = "";
        pg.gitLegDone = !pg.dots;
        if (pg.dots) gitFetch.exec(["git", "-C", pg.dots, "fetch", "--quiet", "origin"]);
        repoProc.running = true;
    }
    function repoDone(code) {
        if (code === 1) {
            const lines = pg.repoErr.trim().split("\n").filter(s => s.trim());
            pg.checkErr = lines.length ? lines[lines.length - 1] : "checkupdates couldn't read the package databases";
        }
        if (pg.helper) aurProc.exec([pg.helper, "-Qua"]);
        else finishCheck();
    }
    // a check is two legs -- the packages and the rice -- and is only
    // done when both have answered
    function legDone() { if (pg.pkgLegDone && pg.gitLegDone) { pg.checking = false; pg.checked = true; } }
    function finishCheck() { pg.pkgLegDone = true; legDone(); }
    function parseGit(text) {
        const lines = text.split("\n").filter(s => s.trim());
        const n = parseInt(lines[0]);
        pg.gitNew = isNaN(n) ? -1 : n;
        pg.gitRows = isNaN(n) ? [] : lines.slice(1);
        if (isNaN(n) && !pg.gitErr) pg.gitErr = "the clone has no upstream to compare with";
    }
    function galagaInTerminal() {
        if (!pg.term || !pg.dots) return;
        Sounds.play("tick");
        const cmd = "cd '" + pg.dots + "' && ./install.sh --update"
            + "; echo; echo 'press enter to close'; read -r _";
        Quickshell.execDetached([pg.term, "-e", "sh", "-c", cmd]);
    }
    function installContrib() {
        if (act.running) return;
        pg.actOk = null; pg.actLog = ""; pg.actOut = ""; pg.actErr = "";
        act.exec(["pkexec", "pacman", "-S", "--noconfirm", "pacman-contrib"]);
    }
    function actDone(code) {
        pg.actOk = code === 0;
        const all = (pg.actOut + "\n" + pg.actErr).split("\n").filter(s => s.trim());
        pg.actLog = all.slice(-8).join("\n");
        if (code === 0 && !detProc.running) detProc.running = true;
    }
    function updateInTerminal() {
        if (!pg.term) return;
        Sounds.play("tick");
        const cmd = (pg.helper ? pg.helper + " -Syu" : "sudo pacman -Syu")
            + "; echo; echo 'press enter to close'; read -r _";
        Quickshell.execDetached([pg.term, "-e", "sh", "-c", cmd]);
    }

    function detect() { if (!detProc.running) detProc.running = true; }
    onActiveChanged: if (active) detect()
    Component.onCompleted: detect()

    Process {
        id: detProc
        command: ["sh", "-c",
            "for c in checkupdates yay paru; do " +
            "if command -v $c >/dev/null 2>&1; then echo \"$c 1\"; else echo \"$c 0\"; fi; done; " +
            "printf 'term %s\\n' \"$(command -v kitty || command -v xterm)\"; " +
            "printf 'dots %s\\n' \"$(git -C \"$HOME/.config/quickshell/galaga\" rev-parse --show-toplevel 2>/dev/null)\""]
        stdout: StdioCollector { onStreamFinished: pg.parseDetect(text) }
    }
    function parseDetect(text) {
        const map = {};
        for (const ln of text.split("\n")) {
            const i = ln.indexOf(" ");
            if (i < 0) continue;
            map[ln.slice(0, i)] = ln.slice(i + 1).trim();
        }
        pg.haveCU = map.checkupdates === "1";
        pg.helper = map.yay === "1" ? "yay" : (map.paru === "1" ? "paru" : "");
        pg.term = map.term || "";
        pg.dots = map.dots || "";
        pg.detDone = true;
    }
    Process {
        id: repoProc
        command: ["checkupdates"]
        stdout: StdioCollector { onStreamFinished: pg.repoRows = pg.parseUpdates(text) }
        stderr: StdioCollector { onStreamFinished: pg.repoErr = text }
        onExited: code => pg.repoDone(code)
    }
    Process {
        id: aurProc
        stdout: StdioCollector { onStreamFinished: pg.aurRows = pg.parseUpdates(text) }
        onExited: code => pg.finishCheck()
    }
    // the rice leg: fetch first (a stale origin ref would under-report,
    // and a failed fetch must never read as "up to date"), then count
    // and list what the upstream has that this checkout doesn't
    Process {
        id: gitFetch
        stderr: StdioCollector { onStreamFinished: pg.gitErr = text }
        onExited: code => {
            if (code === 0) gitRead.exec(["sh", "-c",
                "git -C \"$0\" rev-list --count 'HEAD..@{upstream}' 2>/dev/null; " +
                "git -C \"$0\" log --format=%s 'HEAD..@{upstream}' 2>/dev/null | head -5", pg.dots]);
            else { pg.gitLegDone = true; pg.legDone(); }
        }
    }
    Process {
        id: gitRead
        stdout: StdioCollector { onStreamFinished: pg.parseGit(text) }
        onExited: code => { pg.gitLegDone = true; pg.legDone(); }
    }
    Process {
        id: act
        stdout: StdioCollector { onStreamFinished: pg.actOut = text }
        stderr: StdioCollector { onStreamFinished: pg.actErr = text }
        onExited: code => pg.actDone(code)
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

            Lb { visible: !pg.detDone; text: "reading the machine…" }

            Column {
                visible: pg.detDone && !pg.haveCU
                width: parent.width
                spacing: 10
                SetHead { text: "updates" }
                SetCard {
                    SetRow {
                        label: "checkupdates isn't installed"
                        sub: "it ships in pacman-contrib and does the checking — no checker, no update page"
                        divider: false
                        SetButton {
                            label: "install pacman-contrib"
                            enabled: !act.running
                            opacity: act.running ? 0.4 : 1
                            onHit: pg.installContrib()
                        }
                    }
                }
                SetCard {
                    visible: pg.actOk !== null
                    SetRow {
                        label: pg.actOk ? "pacman-contrib installed" : "the install didn't finish"
                        sub: pg.actOk ? "the checker is ready — this page re-reads itself" : "the output says why"
                        divider: pg.actLog !== ""
                        SetButton { label: "dismiss"; onHit: pg.actOk = null }
                    }
                    Text {
                        visible: pg.actLog !== ""
                        width: parent ? parent.width : 0
                        text: pg.actLog
                        font { family: Theme.mono; pixelSize: 11 }
                        color: Theme.grey
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            Column {
                visible: pg.detDone && pg.haveCU && pg.dots !== ""
                width: parent.width
                spacing: 10
                SetHead { text: "galaga" }
                SetCard {
                    SetRow {
                        label: pg.gitNew > 0 ? pg.gitNew + (pg.gitNew === 1 ? " new commit" : " new commits")
                            : pg.gitNew === 0 ? "up to date"
                            : "the rice itself"
                        sub: pg.checking ? "asking the repository"
                            : pg.gitNew > 0 ? "waiting upstream of this checkout, newest first"
                            : pg.gitNew === 0 ? "checked with the repository just now"
                            : "this checkout's own updates — checked with everything else"
                        divider: pg.gitRows.length > 0
                    }
                    Repeater {
                        model: pg.gitRows
                        SetRow {
                            required property var modelData
                            required property int index
                            label: modelData
                            divider: index < pg.gitRows.length - 1
                        }
                    }
                }
                Lb {
                    visible: pg.gitNew < 0 && pg.checked && pg.gitErr !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pg.gitErr.trim().split("\n").filter(s => s.trim()).slice(-1)[0] ?? ""
                    px: 11
                    color: Theme.red
                }
            }

            Column {
                visible: pg.detDone && pg.haveCU
                width: parent.width
                spacing: 10
                SetHead { text: "updates" }
                SetCard {
                    SetRow {
                        label: pg.checking ? "checking…"
                            : !pg.checked ? "not checked yet"
                            : pg.total > 0 ? pg.total + (pg.total === 1 ? " update available" : " updates available")
                            : pg.gitNew > 0 ? "the packages are up to date"
                            : "everything is up to date"
                        sub: pg.checking ? "asking the repositories" + (pg.helper ? " and the aur" : "")
                            : !pg.checked ? "this page never guesses — run a check"
                            : pg.total > 0 ? "from the repositories" + (pg.aurRows.length ? " and the aur" : "")
                            : pg.gitNew > 0 ? "the news is the rice, above"
                            : "checked just now, in this session"
                        divider: false
                        SetButton {
                            label: "check for updates"
                            enabled: !pg.checking
                            opacity: pg.checking ? 0.4 : 1
                            onHit: pg.check()
                        }
                    }
                }
                Lb {
                    visible: pg.checkErr !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pg.checkErr
                    px: 11
                    color: Theme.red
                }
            }

            Column {
                visible: pg.repoRows.length > 0
                width: parent.width
                spacing: 10
                SetHead { text: "repositories" }
                SetCard {
                    Repeater {
                        model: pg.repoRows
                        SetRow {
                            required property var modelData
                            required property int index
                            label: modelData.name
                            value: modelData.cur + " → " + modelData.next
                            divider: index < pg.repoRows.length - 1
                        }
                    }
                }
            }

            Column {
                visible: pg.aurRows.length > 0
                width: parent.width
                spacing: 10
                SetHead { text: "aur · " + pg.helper }
                SetCard {
                    Repeater {
                        model: pg.aurRows
                        SetRow {
                            required property var modelData
                            required property int index
                            label: modelData.name
                            value: modelData.cur + " → " + modelData.next
                            divider: index < pg.aurRows.length - 1
                        }
                    }
                }
            }

            Column {
                visible: pg.checked && (pg.total > 0 || pg.gitNew > 0)
                width: parent.width
                spacing: 10
                SetHead { text: "install" }
                SetCard {
                    visible: pg.term !== ""
                    SetRow {
                        visible: pg.gitNew > 0
                        label: "update galaga"
                        sub: "pulls the newest version and refreshes what changed — in a terminal"
                        divider: pg.total > 0
                        SetButton {
                            label: "update in terminal"
                            onHit: pg.galagaInTerminal()
                        }
                    }
                    SetRow {
                        visible: pg.total > 0
                        label: "update everything"
                        sub: "runs in a terminal — the password prompt and any conflicts stay where you can answer them"
                        divider: false
                        SetButton {
                            label: "update in terminal"
                            onHit: pg.updateInTerminal()
                        }
                    }
                }
                Lb {
                    visible: pg.term === ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "updates are waiting, but no terminal (kitty or xterm) was found to run them in"
                    px: 11
                    color: Theme.mute
                }
            }
        }
    }
}
