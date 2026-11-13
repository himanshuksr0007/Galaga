import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// apps: what pacman and flatpak say is installed, with sizes, and a working
// uninstall for both. Removal is pacman -Rns behind pkexec (it refuses when
// something needs the package -- that refusal is the safety net, and its
// output is shown verbatim) or flatpak uninstall, which handles its own
// permission prompt. The flatpak section exists only when flatpak does.
Item {
    id: pg

    property bool active: false
    property var pkgs: []
    property var pendingPkgs: []
    property var flats: []
    property var haveFlat: null
    property bool flatsLoaded: false
    property bool pkgsLoaded: false
    property string query: ""
    property string pendingName: ""
    property string actOut: ""
    property string actErr: ""
    property string resultText: ""
    property var resultOk: null

    readonly property var shownPkgs: pkgs.filter(p => !query || p.name.toLowerCase().includes(query))
    readonly property var shownFlats: flats.filter(f => !query || f.name.toLowerCase().includes(query) || f.id.toLowerCase().includes(query))

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    function human(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB";
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB";
        if (b >= 1024) return Math.round(b / 1024) + " KB";
        return b + " B";
    }
    function sumBytes(list) { let s = 0; for (const p of list) s += p.bytes || 0; return s; }
    function countsText() {
        let t = pkgs.length + (pkgs.length === 1 ? " package" : " packages");
        if (haveFlat === true) t += " · " + flats.length + (flats.length === 1 ? " flatpak" : " flatpaks");
        const total = sumBytes(pkgs) + sumBytes(flats);
        if (total > 0) t += " · " + human(total) + " installed";
        return t;
    }
    function sizeBytes(v) {
        const m = /^([\d.]+)\s*([KMGT]iB|B)$/.exec(String(v).trim());
        if (!m) return 0;
        const mult = { "B": 1, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824, "TiB": 1099511627776 };
        return parseFloat(m[1]) * (mult[m[2]] || 1);
    }
    function flatBytes(v) {
        const m = /^([\d.]+)\s*([KMGT]B|B)$/.exec(String(v).trim());
        if (!m) return 0;
        const mult = { "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12 };
        return parseFloat(m[1]) * (mult[m[2]] || 1);
    }

    function removePkg(p) {
        if (act.running) return;
        pg.pendingName = p.name; pg.resultOk = null; pg.actOut = ""; pg.actErr = "";
        act.exec(["pkexec", "pacman", "-Rns", "--noconfirm", p.name]);
    }
    function removeFlat(f) {
        if (act.running) return;
        pg.pendingName = f.name; pg.resultOk = null; pg.actOut = ""; pg.actErr = "";
        act.exec(["flatpak", "uninstall", "-y", f.id]);
    }
    function actDone(code) {
        pg.resultOk = code === 0;
        const all = (pg.actOut + "\n" + pg.actErr).split("\n").filter(s => s.trim());
        pg.resultText = all.slice(-10).join("\n");
        pg.refresh();
    }

    function refresh() {
        if (!qeProc.running && !qiProc.running) qeProc.running = true;
        if (haveFlat === null && !fvProc.running) fvProc.running = true;
        else if (haveFlat === true && !flProc.running) flProc.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Process {
        id: qeProc
        command: ["pacman", "-Qe"]
        stdout: StdioCollector { onStreamFinished: pg.parseQe(text) }
    }
    function parseQe(text) {
        const rows = [];
        for (const ln of text.split("\n")) {
            if (!ln.trim()) continue;
            const f = ln.trim().split(/\s+/);
            rows.push({ name: f[0], ver: f.slice(1).join(" "), bytes: 0 });
        }
        if (!rows.length) { pg.pkgs = []; pg.pkgsLoaded = true; return; }
        qiProc.exec(["pacman", "-Qi"].concat(rows.map(r => r.name)));
        pg.pendingPkgs = rows;
    }
    Process {
        id: qiProc
        stdout: StdioCollector { onStreamFinished: pg.parseQi(text) }
    }
    function parseQi(text) {
        const map = {};
        for (const block of text.split(/\n\s*\n/)) {
            let name = "", size = 0;
            for (const ln of block.split("\n")) {
                const i = ln.indexOf(" : ");
                if (i < 0) continue;
                const k = ln.slice(0, i).trim(), v = ln.slice(i + 3).trim();
                if (k === "Name") name = v;
                else if (k === "Installed Size") size = pg.sizeBytes(v);
            }
            if (name) map[name] = size;
        }
        const rows = pg.pendingPkgs;
        for (const r of rows) r.bytes = map[r.name] || 0;
        rows.sort((a, b) => a.name.localeCompare(b.name));
        pg.pkgs = rows;
        pg.pkgsLoaded = true;
    }
    Process {
        id: fvProc
        command: ["sh", "-c", "command -v flatpak"]
        stdout: StdioCollector { onStreamFinished: pg.flatDetected(text) }
    }
    function flatDetected(text) {
        pg.haveFlat = text.trim() !== "";
        if (pg.haveFlat && !flProc.running) flProc.running = true;
    }
    Process {
        id: flProc
        command: ["flatpak", "list", "--app", "--columns=application,name,version,size"]
        stdout: StdioCollector { onStreamFinished: pg.parseFlats(text) }
    }
    function parseFlats(text) {
        const rows = [];
        for (const ln of text.split("\n")) {
            if (!ln.trim()) continue;
            let f = ln.split("\t");
            if (f.length < 4) {
                const m = /^(\S+)\s+(.+?)\s+(\S+)\s+([\d.]+\s*[KMGT]B)$/.exec(ln.trim());
                if (!m) continue;
                f = [m[1], m[2], m[3], m[4]];
            }
            rows.push({ id: f[0].trim(), name: f[1].trim(), ver: f[2].trim(),
                        size: f[3].trim(), bytes: pg.flatBytes(f[3]) });
        }
        rows.sort((a, b) => a.name.localeCompare(b.name));
        pg.flats = rows;
        pg.flatsLoaded = true;
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

            Item {
                width: parent.width
                height: 30
                SetHead { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: "installed" }
                Lb {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: pg.countsText()
                    px: 11
                    color: Theme.mute
                }
            }

            SetCard {
                pad: 14
                Rectangle {
                    width: parent ? parent.width : 0
                    height: 40
                    radius: Theme.corner(20)
                    color: Theme.s2
                    Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "\u{F0349}"; font.pixelSize: 17; color: Theme.mute }
                    TextInput {
                        anchors { left: parent.left; leftMargin: 42; right: parent.right; rightMargin: 14; top: parent.top; bottom: parent.bottom }
                        verticalAlignment: TextInput.AlignVCenter
                        font { family: Theme.ui; pixelSize: 14 }
                        color: Theme.fg
                        selectionColor: Theme.s3
                        clip: true
                        onTextChanged: pg.query = text.trim().toLowerCase()
                        Text { visible: !parent.text; text: "search packages and flatpaks"; font: parent.font; color: Theme.mute }
                    }
                }
            }

            Column {
                visible: pg.resultOk !== null
                width: parent.width
                spacing: 10
                SetHead { text: "last removal" }
                SetCard {
                    SetRow {
                        label: pg.resultOk ? pg.pendingName + " removed" : "couldn't remove " + pg.pendingName
                        sub: pg.resultOk ? "the list below is already refreshed" : "the output says why"
                        divider: pg.resultText !== ""
                        SetButton { label: "dismiss"; onHit: pg.resultOk = null }
                    }
                    Text {
                        visible: pg.resultText !== ""
                        width: parent ? parent.width : 0
                        text: pg.resultText
                        font { family: Theme.mono; pixelSize: 11 }
                        color: Theme.grey
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "packages" }
                SetCard {
                    Lb { visible: !pg.pkgsLoaded; text: "reading packages…" }
                    Lb { visible: pg.pkgsLoaded && !pg.shownPkgs.length; text: pg.query ? "no packages match" : "no packages found" }
                    Repeater {
                        model: pg.shownPkgs
                        Column {
                            id: prow
                            required property var modelData
                            required property int index
                            property bool arm: false
                            width: parent.width
                            SetRow {
                                label: modelData.name
                                sub: "version " + modelData.ver
                                value: modelData.bytes > 0 ? pg.human(modelData.bytes) : ""
                                divider: true
                                SetButton {
                                    label: "remove"
                                    danger: true
                                    enabled: !act.running
                                    opacity: act.running ? 0.4 : 1
                                    onHit: prow.arm = true
                                }
                            }
                            Item {
                                visible: prow.arm
                                width: parent ? parent.width : 0
                                height: prow.arm ? 104 : 0
                                Column {
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Text {
                                        text: "remove " + modelData.name + "?"
                                        font { family: Theme.ui; pixelSize: 14; weight: Font.DemiBold }
                                        color: Theme.fg
                                    }
                                    Lb {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "if another package needs it, pacman refuses and says so — nothing breaks silently"
                                        px: 10.5
                                        color: Theme.mute
                                    }
                                    Row {
                                        anchors.right: parent.right
                                        spacing: 10
                                        SetButton { label: "cancel"; onHit: prow.arm = false }
                                        SetButton {
                                            label: "remove"
                                            danger: true
                                            onHit: { prow.arm = false; pg.removePkg(modelData); }
                                        }
                                    }
                                }
                                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.s2 }
                            }
                        }
                    }
                }
            }

            Column {
                visible: pg.haveFlat === true
                width: parent.width
                spacing: 10
                SetHead { text: "flatpak" }
                SetCard {
                    Lb { visible: !pg.flatsLoaded; text: "reading flatpaks…" }
                    Lb { visible: pg.flatsLoaded && !pg.shownFlats.length; text: pg.query ? "no flatpaks match" : "no flatpaks installed" }
                    Repeater {
                        model: pg.shownFlats
                        Column {
                            id: frow
                            required property var modelData
                            required property int index
                            property bool arm: false
                            width: parent.width
                            SetRow {
                                label: modelData.name
                                sub: modelData.id + (modelData.ver ? " · " + modelData.ver : "")
                                value: modelData.size
                                divider: true
                                SetButton {
                                    label: "remove"
                                    danger: true
                                    enabled: !act.running
                                    opacity: act.running ? 0.4 : 1
                                    onHit: frow.arm = true
                                }
                            }
                            Item {
                                visible: frow.arm
                                width: parent ? parent.width : 0
                                height: frow.arm ? 104 : 0
                                Column {
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Text {
                                        text: "remove " + modelData.name + "?"
                                        font { family: Theme.ui; pixelSize: 14; weight: Font.DemiBold }
                                        color: Theme.fg
                                    }
                                    Lb {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "the app and its data go; system-wide flatpaks ask for your password on their own"
                                        px: 10.5
                                        color: Theme.mute
                                    }
                                    Row {
                                        anchors.right: parent.right
                                        spacing: 10
                                        SetButton { label: "cancel"; onHit: frow.arm = false }
                                        SetButton {
                                            label: "remove"
                                            danger: true
                                            onHit: { frow.arm = false; pg.removeFlat(modelData); }
                                        }
                                    }
                                }
                                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.s2 }
                            }
                        }
                    }
                }
            }
        }
    }
}
