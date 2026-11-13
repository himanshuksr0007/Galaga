import QtQuick
import qs
import qs.components
import qs.settings

// keyboard: the repeat half of Rules' input model (the pointer half is on the
// mouse page). Hold a key -- the preview runs the live values: first dot at
// once, a pause of delay ms, then rate dots a second.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

    property int n: 0 // how many "typed"; 0 -- key released
    Timer {
        running: pg.active
        repeat: true
        interval: pg.n === 0 ? 700 : pg.n === 1 ? delayS.v : 1000 / rateS.v
        onTriggered: pg.n = (pg.n + 1) % 41
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
                SetHead { text: "repeat" }
                SetCard {
                    Row {
                        width: parent.width
                        spacing: 20
                        Rectangle {
                            width: 72
                            height: 72
                            radius: Theme.corner(22)
                            color: pg.n ? Theme.fg : Theme.s1
                            border { width: 1; color: Theme.s2 }
                            Num { anchors.centerIn: parent; text: "A"; font.pixelSize: 38; color: pg.n ? Theme.ink : Theme.fg }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Row {
                                spacing: 5
                                Repeater {
                                    model: 40
                                    Rectangle {
                                        required property int index
                                        width: 11
                                        height: 11
                                        radius: 5.5
                                        color: index < pg.n ? Theme.fg : Theme.s2
                                    }
                                }
                            }
                            Lb { text: `hold a key · first, ${Math.round(delayS.v)} ms, then ${Math.round(rateS.v)} a second`; px: 11 }
                        }
                    }
                    SetSlider {
                        id: delayS
                        label: "delay"
                        from: 150; to: 600; step: 10
                        unit: "ms"
                        value: Rules.store.repeatDelay
                        onMoved: v => { Rules.store.repeatDelay = Math.round(v); Rules.input(); }
                    }
                    SetSlider {
                        id: rateS
                        label: "rate"
                        from: 10; to: 60
                        unit: "/s"
                        divider: false
                        value: Rules.store.repeatRate
                        onMoved: v => { Rules.store.repeatRate = Math.round(v); Rules.input(); }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "layout" }
                SetCard {
                    SetPick {
                        label: "layout switch"
                        opts: Rules.switches.map(s => s[0])
                        cur: Rules.store.kbSwitch
                        onPicked: i => { Rules.store.kbSwitch = i; Rules.input(); }
                    }
                    SetToggle {
                        label: "shell sets input"
                        sub: "off — input stays in your hypr config"
                        on: Rules.store.manageInput
                        divider: false
                        onFlip: want => { Rules.store.manageInput = want; if (want) Rules.input(); }
                    }
                }
            }
        }
    }
}
