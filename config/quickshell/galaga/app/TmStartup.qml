import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services

// startup: what runs at login, from the two places that decide it, with a
// switch for each. The apps are the merged view of /etc/xdg/autostart and
// ~/.config/autostart -- a user file with the same name replaces the system
// one wholesale, so turning a system entry off writes the two-line stub
// (Hidden=true) the installer itself writes for the warp tray, and turning
// it back on deletes the stub; an entry that lives only in the user dir is
// edited in place instead. A stub carries no name or icon, so the row's
// name and icon fall back to the system file's. The services are systemd
// user units: the enabled and masked ones, plus disabled ones whose file
// lives in the user dir (every shipped unit would otherwise list). Masked
// means blocked from starting at all -- its switch unmasks, then enables.
// Nothing here starts or stops anything now; the switches set up the
// next login.
Item {
    id: pg

    property bool active: false
    property var apps: [] // { base, name, icon, on, src, hs, hu }
    property var svcs: [] // { unit, name, state, on }
    property bool loaded: false
    property bool busy: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    onActiveChanged: if (active) pg.refresh()
    Component.onCompleted: if (active) pg.refresh()

    function refresh() {
        if (pg.busy) { again.restart(); return; }
        pg.busy = true;
        listProc.running = true;
    }
    Timer { id: again; interval: 300; onTriggered: pg.refresh() }

    // one pass over both sources, tab-separated lines (names and
    // descriptions carry spaces, never tabs). Only the [Desktop Entry]
    // section of a desktop file is read -- getkey stops at the next header.
    readonly property string listScript: `
SYS=/etc/xdg/autostart
USR=$HOME/.config/autostart
getkey() {
  awk -v k="$2" '
    /^\\[/ { n++; if (n > 1) exit }
    n == 1 && index($0, k "=") == 1 { v = substr($0, length(k) + 2); sub(/[\\r ]+$/, "", v); print v; exit }
  ' "$1" 2>/dev/null
}
seen=""
for dir in "$SYS" "$USR"; do
  for f in "$dir"/*.desktop; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    case "
$seen
" in *"
$b
"*) continue ;; esac
    seen="$seen
$b"
    sf="$SYS/$b"; uf="$USR/$b"
    hs=0; hu=0
    [ -f "$sf" ] && hs=1
    [ -f "$uf" ] && hu=1
    if [ "$hu" = 1 ]; then ef="$uf"; else ef="$sf"; fi
    name=$(getkey "$ef" Name)
    icon=$(getkey "$ef" Icon)
    if [ "$hs" = 1 ]; then
      if [ -z "$name" ]; then name=$(getkey "$sf" Name); fi
      if [ -z "$icon" ]; then icon=$(getkey "$sf" Icon); fi
    fi
    hid=$(getkey "$ef" Hidden)
    gae=$(getkey "$ef" X-GNOME-Autostart-enabled)
    en=1
    if [ "$hid" = true ] || [ "$gae" = false ]; then en=0; fi
    if [ -z "$name" ]; then name=$(basename "$b" .desktop); fi
    src=system
    if [ "$hu" = 1 ] && [ "$hs" = 1 ]; then src="user override"; fi
    if [ "$hu" = 1 ] && [ "$hs" = 0 ]; then src=user; fi
    printf "xdg\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n" "$b" "$name" "$icon" "$en" "$src" "$hs" "$hu"
  done
done
systemctl --user list-unit-files --type=service --no-legend --no-pager 2>/dev/null | while read -r unit state rest; do
  case "$state" in
    enabled|masked) ;;
    disabled)
      if [ ! -f "$HOME/.config/systemd/user/$unit" ] && [ ! -f "/etc/systemd/user/$unit" ]; then continue; fi ;;
    *) continue ;;
  esac
  desc=$(systemctl --user show "$unit" -p Description --value 2>/dev/null)
  if [ -z "$desc" ]; then desc="$unit"; fi
  printf "svc\\t%s\\t%s\\t%s\\n" "$unit" "$desc" "$state"
done
`

    Process {
        id: listProc
        command: ["sh", "-c", pg.listScript]
        stdout: StdioCollector {
            onStreamFinished: {
                const apps = [], svcs = [];
                for (const line of text.split("\n")) {
                    if (!line) continue;
                    const p = line.split("\t");
                    if (p[0] === "xdg" && p.length >= 8)
                        apps.push({ base: p[1], name: p[2], icon: p[3], on: p[4] === "1", src: p[5], hs: p[6] === "1", hu: p[7] === "1" });
                    else if (p[0] === "svc" && p.length >= 4)
                        svcs.push({ unit: p[1], name: p[2], state: p[3], on: p[3] === "enabled" });
                }
                apps.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
                svcs.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
                pg.apps = apps;
                pg.svcs = svcs;
                pg.loaded = true;
                pg.busy = false;
            }
        }
        onExited: pg.busy = false
    }

    // a path as one shell word, for the file ops below
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    function xdgFlip(o, want) {
        const dir = Quickshell.env("HOME") + "/.config/autostart";
        const uf = dir + "/" + o.base;
        const sf = "/etc/xdg/autostart/" + o.base;
        let cmd = "";
        if (want) {
            if (o.hu && o.hs) cmd = "rm " + pg.shq(uf); // drop the override, the system entry goes live
            else if (o.hu) cmd = "sed -i -e '/^Hidden=true[[:space:]]*$/d' -e 's/^X-GNOME-Autostart-enabled=false[[:space:]]*$/X-GNOME-Autostart-enabled=true/' " + pg.shq(uf);
            else cmd = "mkdir -p " + pg.shq(dir) + " && sed -e '/^Hidden=true[[:space:]]*$/d' -e 's/^X-GNOME-Autostart-enabled=false[[:space:]]*$/X-GNOME-Autostart-enabled=true/' " + pg.shq(sf) + " > " + pg.shq(uf); // the system file hides itself: a cleaned user copy wins
        } else {
            if (o.hs) cmd = "mkdir -p " + pg.shq(dir) + " && printf '[Desktop Entry]\\nHidden=true\\n' > " + pg.shq(uf); // the installer's stub
            else cmd = "awk '\n"
                + "  /^\\[/ { n++; if (n == 2 && !done) { print \"Hidden=true\"; done = 1 } }\n"
                + "  n <= 1 && /^Hidden=/ { if (!done) { print \"Hidden=true\"; done = 1 } next }\n"
                + "  { print }\n"
                + "  END { if (!done) print \"Hidden=true\" }\n"
                + "' " + pg.shq(uf) + " > " + pg.shq(uf + ".tmp") + " && mv " + pg.shq(uf + ".tmp") + " " + pg.shq(uf);
        }
        Quickshell.execDetached(["sh", "-c", cmd]);
        again.restart();
    }

    function svcFlip(o, want) {
        let cmd = "";
        if (want && o.state === "masked") cmd = "systemctl --user unmask " + pg.shq(o.unit) + " && systemctl --user enable " + pg.shq(o.unit);
        else if (want) cmd = "systemctl --user enable " + pg.shq(o.unit);
        else cmd = "systemctl --user disable " + pg.shq(o.unit);
        Quickshell.execDetached(["sh", "-c", cmd]);
        again.restart();
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
                SetHead { text: "apps" }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: pg.apps
                            XdgRow { }
                        }
                    }
                    Lb { visible: pg.loaded && pg.apps.length === 0; px: 11; color: Theme.mute; text: "nothing here" }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "services" }
                SetCard {
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: pg.svcs
                            SvcRow { }
                        }
                    }
                    Lb { visible: pg.loaded && pg.svcs.length === 0; px: 11; color: Theme.mute; text: "nothing here" }
                }
            }
        }
    }

    component XdgRow: Rectangle {
        id: xrow
        required property var modelData
        readonly property var o: modelData
        readonly property string subText: o.src === "user" ? "autostart · added by you"
            : o.src === "user override" ? (o.on ? "autostart · system, your copy" : "autostart · system, turned off by you")
            : "autostart · system"
        width: parent ? parent.width : 0
        height: 62
        radius: Theme.corner(28)
        color: hov.hovered ? Theme.s3 : "transparent"
        Rectangle {
            id: xic
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: xrow.o.on ? Theme.fg : Theme.s3
            Text {
                anchors.centerIn: parent
                visible: ximg.status !== Image.Ready
                text: (xrow.o.name || "?").charAt(0).toUpperCase()
                font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                color: xrow.o.on ? Theme.ink : Theme.fg
            }
            Image {
                id: ximg
                anchors.centerIn: parent
                width: 24
                height: 24
                visible: status === Image.Ready
                source: xrow.o.icon ? Quickshell.iconPath(xrow.o.icon, "application-x-executable") : ""
            }
        }
        SetToggle {
            x: 64
            width: parent.width - 64
            anchors.verticalCenter: parent.verticalCenter
            label: xrow.o.name
            sub: xrow.subText
            on: xrow.o.on
            divider: false
            onFlip: want => pg.xdgFlip(xrow.o, want)
        }
        HoverHandler { id: hov }
    }

    component SvcRow: Rectangle {
        id: srow
        required property var modelData
        readonly property var o: modelData
        readonly property string subText: o.state === "masked" ? o.unit + " · masked — blocked from starting" : o.unit
        width: parent ? parent.width : 0
        height: 62
        radius: Theme.corner(28)
        color: hov.hovered ? Theme.s3 : "transparent"
        Rectangle {
            id: sic
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            radius: 22
            color: srow.o.on ? Theme.fg : Theme.s3
            Text {
                anchors.centerIn: parent
                text: (srow.o.name || "?").charAt(0).toUpperCase()
                font { family: Theme.ui; pixelSize: 17; weight: Font.DemiBold }
                color: srow.o.on ? Theme.ink : Theme.fg
            }
        }
        SetToggle {
            x: 64
            width: parent.width - 64
            anchors.verticalCenter: parent.verticalCenter
            label: srow.o.name
            sub: srow.subText
            on: srow.o.on
            divider: false
            onFlip: want => pg.svcFlip(srow.o, want)
        }
        HoverHandler { id: hov }
    }
}
