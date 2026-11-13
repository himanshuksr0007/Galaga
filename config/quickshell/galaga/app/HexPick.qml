import QtQuick
import qs
import qs.components

// the colour picker behind appearance's wells: a saturation/value square over
// the pure hue, a hue strip under it, and a hex field for typing the exact
// colour. It works on a draft — the system changes on "set", once, through
// Theme.setCustom; "reset" drops this one colour's custom and the palette's
// own value returns
Rectangle {
    id: hp

    property string key: ""
    property string label: ""
    property real h: 0
    property real sv: 1
    property real vv: 1
    readonly property color draft: Qt.hsva(h, sv, vv, 1)
    readonly property string draftHex: "#" + Theme.hex(draft)
    signal closed

    // the live value of a colour role as a "#hex" string: Theme.pal already
    // carries any custom colour on top of the palette
    function liveHex(key) {
        if (key.startsWith("a")) return "#" + Theme.hex(Theme.pal.ansi[Number(key.slice(1))]);
        return "#" + Theme.hex({ fg: Theme.fg, s1: Theme.s1, s2: Theme.s2, s3: Theme.s3, mute: Theme.mute, grey: Theme.grey, bg: Theme.bg, accent: Theme.accent, red: Theme.red }[key] ?? Theme.fg);
    }
    function open(k, name) {
        key = k;
        label = name;
        const c = Qt.color(liveHex(k));
        h = c.hsvHue < 0 ? 0 : c.hsvHue;
        sv = c.hsvSaturation;
        vv = c.hsvValue;
        hexIn.text = liveHex(k);
        visible = true;
        hexIn.forceActiveFocus();
    }
    function commit() { Theme.setCustom(key, draftHex); visible = false; closed(); }
    function drop() { Theme.setCustom(key, null); visible = false; closed(); }

    visible: false
    width: 400
    height: 446
    radius: Theme.corner(24)
    color: Theme.s1
    border { width: 1; color: Theme.s3 }
    Column {
        anchors { fill: parent; margins: 22 }
        spacing: 14
        Row {
            spacing: 10
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Theme.red }
            Lb { text: hp.label; px: 13; color: Theme.fg }
            Lb { text: Theme.state.custom[hp.key] ? "· your colour" : "· from the palette"; px: 10; color: Theme.mute }
        }
        Rectangle {
            id: svBox
            width: parent.width
            height: 186
            radius: Theme.corner(14)
            color: Qt.hsva(hp.h, 1, 1, 1)
            Rectangle {
                anchors.fill: parent
                radius: Theme.corner(14)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#FFFFFF" }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.corner(14)
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#000000" }
                }
            }
            Rectangle {
                x: hp.sv * parent.width - 9
                y: (1 - hp.vv) * parent.height - 9
                width: 18
                height: 18
                radius: 9
                color: hp.draft
                border { width: 2; color: "#FFFFFF" }
            }
            MouseArea {
                anchors.fill: parent
                onPressed: m => setSv(m)
                onPositionChanged: m => { if (pressed) setSv(m); }
                function setSv(m) {
                    hp.sv = Math.max(0, Math.min(1, m.x / width));
                    hp.vv = 1 - Math.max(0, Math.min(1, m.y / height));
                }
            }
        }
        Rectangle {
            width: parent.width
            height: 16
            radius: 8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#FF0000" }
                GradientStop { position: 0.17; color: "#FFFF00" }
                GradientStop { position: 0.33; color: "#00FF00" }
                GradientStop { position: 0.5; color: "#00FFFF" }
                GradientStop { position: 0.67; color: "#0000FF" }
                GradientStop { position: 0.83; color: "#FF00FF" }
                GradientStop { position: 1; color: "#FF0000" }
            }
            Rectangle {
                x: hp.h * parent.width - 4
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 22
                radius: 4
                color: Qt.hsva(hp.h, 1, 1, 1)
                border { width: 2; color: "#FFFFFF" }
            }
            MouseArea {
                anchors.fill: parent
                onPressed: m => hp.h = Math.max(0, Math.min(1, m.x / width))
                onPositionChanged: m => { if (pressed) hp.h = Math.max(0, Math.min(1, m.x / width)); }
            }
        }
        Row {
            spacing: 12
            Rectangle { width: 44; height: 44; radius: Theme.corner(12); color: hp.draft; border { width: 1; color: Theme.s3 } }
            Rectangle {
                width: 158
                height: 44
                radius: 22
                color: Theme.s2
                border { width: hexIn.activeFocus ? 1 : 0; color: Theme.fg }
                TextInput {
                    id: hexIn
                    anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    font { family: Theme.mono; pixelSize: 15 }
                    color: Theme.fg
                    selectionColor: Theme.s3
                    clip: true
                    onEditingFinished: {
                        const t = text.trim();
                        if (/^#?[0-9a-fA-F]{6}$/.test(t)) {
                            const c = Qt.color(t.startsWith("#") ? t : "#" + t);
                            hp.h = c.hsvHue < 0 ? 0 : c.hsvHue;
                            hp.sv = c.hsvSaturation;
                            hp.vv = c.hsvValue;
                        }
                        text = hp.draftHex;
                    }
                }
            }
            Lb { anchors.verticalCenter: parent.verticalCenter; text: "hex"; px: 10; color: Theme.mute }
        }
        Row {
            spacing: 10
            SetButton { label: "set"; onHit: hp.commit() }
            SetButton { visible: !!Theme.state.custom[hp.key]; label: "reset"; onHit: hp.drop() }
            SetButton { label: "cancel"; onHit: { hp.visible = false; hp.closed(); } }
        }
    }
    Keys.onEscapePressed: { visible = false; closed(); }
}
