import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// storage: df for the volumes, du for the big folders in home, and the two
// clean-outs that are always safe -- the trash and the pacman cache. Every
// number is read from the tools; an action only appears when its target
// exists and holds something.
Item {
    id: pg

    property bool active: false
    property var vols: []
    property var homeRows: []
    property int trashBytes: 0
    property int trashFiles: 0
    property int cacheBytes: 0
    property int cacheCount: 0
    property string paccache: ""
    property string err: ""
    property string okMsg: ""
    property string actErr: ""
    property string pendingMsg: ""

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    function human(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB";
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB";
        if (b >= 1024) return Math.round(b / 1024) + " KB";
        return b + " B";
    }
    function duBytes(v) {
        const m = /^([\d.]+)([KMGT])?$/.exec(String(v).trim());
        if (!m) return 0;
        const mult = { "K": 1024, "M": 1048576, "G": 1073741824, "T": 1099511627776 };
        return parseFloat(m[1]) * (m[2] ? mult[m[2]] : 1);
    }

    function emptyTrash() {
        if (act.running) return;
        pg.err = ""; pg.okMsg = ""; pg.actErr = "";
        pg.pendingMsg = "trash emptied";
        act.exec(["sh", "-c",
            "if command -v gio >/dev/null 2>&1; then gio trash --empty; " +
            "else t=\"$HOME/.local/share/Trash\"; find \"$t/files\" \"$t/info\" -mindepth 1 -delete 2>/dev/null; fi"]);
    }
    function clearCache() {
        if (act.running) return;
        pg.err = ""; pg.okMsg = ""; pg.actErr = "";
        pg.pendingMsg = "package cache cleared";
        act.exec(pg.paccache ? ["pkexec", "paccache", "-r"] : ["pkexec", "pacman", "-Sc", "--noconfirm"]);
    }
    function actDone(code) {
        if (code === 0) pg.okMsg = pg.pendingMsg;
        else {
            const lines = pg.actErr.trim().split("\n").filter(s => s.trim());
            pg.err = lines.length ? lines[lines.length - 1] : "the command failed — nothing was cleared";
        }
        pg.refresh();
    }

    function refresh() {
        if (!volProc.running) volProc.running = true;
        if (!homeProc.running) homeProc.running = true;
        if (!trashProc.running) trashProc.running = true;
        if (!cacheProc.running) cacheProc.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: volProc
        command: ["df", "-h", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivars"]
        stdout: StdioCollector { onStreamFinished: pg.parseDf(text) }
    }
    function parseDf(text) {
        const rows = [];
        const seen = {};
        for (const ln of text.split("\n")) {
            if (!ln.trim() || ln.startsWith("Filesystem")) continue;
            const f = ln.trim().split(/\s+/);
            if (f.length < 6 || seen[f[0]]) continue;
            seen[f[0]] = true;
            rows.push({ dev: f[0], size: f[1], used: f[2], avail: f[3],
                        pct: parseInt(f[4]) || 0,
                        mount: f.slice(5).join(" ").replace(/\\040/g, " ") });
        }
        pg.vols = rows;
    }
    Process {
        id: homeProc
        command: ["sh", "-c",
            "for d in \"$HOME/Downloads\" \"$HOME/Documents\" \"$HOME/Pictures\" \"$HOME/Videos\" \"$HOME/Music\" \"$HOME/.cache\"; " +
            "do [ -e \"$d\" ] && du -sh \"$d\" 2>/dev/null; done"]
        stdout: StdioCollector { onStreamFinished: pg.parseDu(text) }
    }
    function parseDu(text) {
        const rows = [];
        for (const ln of text.split("\n")) {
            const m = /^(\S+)\s+(.+)$/.exec(ln.trim());
            if (!m) continue;
            const base = m[2].split("/").pop();
            rows.push({ label: base === ".cache" ? "cache" : base.toLowerCase(),
                        path: m[2], size: m[1], bytes: pg.duBytes(m[1]) });
        }
        rows.sort((a, b) => b.bytes - a.bytes);
        pg.homeRows = rows;
    }
    Process {
        id: trashProc
        command: ["sh", "-c",
            "t=\"$HOME/.local/share/Trash\"; if [ -d \"$t\" ]; then " +
            "printf 'bytes %s\\n' \"$(du -sb \"$t\" 2>/dev/null | cut -f1)\"; " +
            "printf 'files %s\\n' \"$(find \"$t/files\" -mindepth 1 2>/dev/null | wc -l)\"; fi"]
        stdout: StdioCollector { onStreamFinished: pg.parseTrash(text) }
    }
    function parseTrash(text) {
        let b = 0, n = 0;
        for (const ln of text.split("\n")) {
            const f = ln.trim().split(/\s+/);
            if (f[0] === "bytes") b = parseInt(f[1]) || 0;
            else if (f[0] === "files") n = parseInt(f[1]) || 0;
        }
        pg.trashBytes = b; pg.trashFiles = n;
    }
    Process {
        id: cacheProc
        command: ["sh", "-c",
            "d=/var/cache/pacman/pkg; if [ -d \"$d\" ]; then " +
            "printf 'bytes %s\\n' \"$(du -sb \"$d\" 2>/dev/null | cut -f1)\"; " +
            "printf 'count %s\\n' \"$(find \"$d\" -name '*.pkg.tar*' 2>/dev/null | wc -l)\"; " +
            "printf 'paccache %s\\n' \"$(command -v paccache)\"; fi"]
        stdout: StdioCollector { onStreamFinished: pg.parseCache(text) }
    }
    function parseCache(text) {
        let b = 0, n = 0, pc = "";
        for (const ln of text.split("\n")) {
            const f = ln.trim().split(/\s+/);
            if (f[0] === "bytes") b = parseInt(f[1]) || 0;
            else if (f[0] === "count") n = parseInt(f[1]) || 0;
            else if (f[0] === "paccache") pc = f[1] || "";
        }
        pg.cacheBytes = b; pg.cacheCount = n; pg.paccache = pc;
    }
    Process {
        id: act
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

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "volumes" }
                SetCard {
                    Lb { visible: !pg.vols.length; text: "reading volumes…" }
                    Repeater {
                        model: pg.vols
                        Column {
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: 9
                            Item {
                                width: parent.width
                                height: 26
                                Text {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    text: modelData.mount
                                    font { family: Theme.ui; pixelSize: 15 }
                                    color: Theme.fg
                                }
                                Lb {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    text: modelData.used + " of " + modelData.size + " · " + modelData.avail + " free"
                                    px: 10.5
                                    color: Theme.mute
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 8
                                radius: 4
                                color: Theme.s3
                                Rectangle {
                                    width: parent.width * Math.min(modelData.pct, 100) / 100
                                    height: parent.height
                                    radius: 4
                                    color: modelData.pct >= 90 ? Theme.red : Theme.fg
                                }
                            }
                            Rectangle {
                                visible: index < pg.vols.length - 1
                                width: parent.width
                                height: 1
                                color: Theme.s2
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "in your home" }
                SetCard {
                    Lb { visible: !pg.homeRows.length; text: "measuring…" }
                    Repeater {
                        model: pg.homeRows
                        SetRow {
                            required property var modelData
                            required property int index
                            label: modelData.label
                            sub: modelData.path
                            value: modelData.size
                            divider: index < pg.homeRows.length - 1
                        }
                    }
                }
            }

            Column {
                visible: pg.trashFiles > 0 || pg.cacheCount > 0
                width: parent.width
                spacing: 10
                SetHead { text: "clear out" }
                SetCard {
                    SetRow {
                        visible: pg.trashFiles > 0
                        label: "trash"
                        sub: pg.trashFiles + (pg.trashFiles === 1 ? " item" : " items") + " · " + pg.human(pg.trashBytes) + " on disk"
                        divider: pg.cacheCount > 0
                        SetButton {
                            label: "empty"
                            danger: true
                            enabled: !act.running
                            opacity: act.running ? 0.4 : 1
                            onHit: pg.emptyTrash()
                        }
                    }
                    SetRow {
                        visible: pg.cacheCount > 0
                        label: "package cache"
                        sub: pg.cacheCount + " downloaded packages · " + pg.human(pg.cacheBytes) + " in /var/cache/pacman"
                        divider: false
                        SetButton {
                            label: "clear"
                            danger: true
                            enabled: !act.running
                            opacity: act.running ? 0.4 : 1
                            onHit: pg.clearCache()
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
            }
        }
    }
}
