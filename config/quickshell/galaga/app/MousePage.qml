import QtQuick
import qs
import qs.components
import qs.settings

// mouse & touchpad: the pointer half of Rules' input model, moved out of Prefs'
// INPUT page. Rules.input() writes two levels and the cards follow it exactly --
// the top-level keywords (sensitivity, accel profile, natural scroll, scroll
// factor) are the mouse's; the touchpad table holds the pad's own four.
Item {
    id: pg

    property bool active: false

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.t; easing { type: Easing.Bezier; bezierCurve: Theme.glide } } }
    transform: Translate { y: (1 - pg.opacity) * 12 }

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

            SetCard {
                visible: !Rules.store.manageInput
                Lb {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    px: 11
                    text: "the shell isn't applying input settings — turn on shell sets input on the keyboard page, and these take over"
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "mouse" }
                SetCard {
                    SetSlider {
                        label: "pointer speed"
                        from: -100; to: 100; step: 5
                        value: Rules.store.sens
                        onMoved: v => { Rules.store.sens = v; Rules.input(); }
                    }
                    SetSlider {
                        label: "scroll speed"
                        from: 50; to: 200; step: 10
                        unit: "%"
                        value: Rules.store.mouseScroll
                        onMoved: v => { Rules.store.mouseScroll = v; Rules.input(); }
                    }
                    SetToggle {
                        label: "natural scroll"
                        on: Rules.store.mouseNatural
                        onFlip: want => { Rules.store.mouseNatural = want; Rules.input(); }
                    }
                    SetToggle {
                        label: "flat accel"
                        sub: "accel profile · flat instead of adaptive"
                        on: Rules.store.flat
                        divider: false
                        onFlip: want => { Rules.store.flat = want; Rules.input(); }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 10
                SetHead { text: "touchpad" }
                SetCard {
                    SetSlider {
                        label: "scroll speed"
                        from: 10; to: 100; step: 5
                        unit: "%"
                        value: Rules.store.scroll
                        onMoved: v => { Rules.store.scroll = v; Rules.input(); }
                    }
                    SetToggle {
                        label: "natural scroll"
                        on: Rules.store.natural
                        onFlip: want => { Rules.store.natural = want; Rules.input(); }
                    }
                    SetToggle {
                        label: "tap to click"
                        on: Rules.store.tap
                        onFlip: want => { Rules.store.tap = want; Rules.input(); }
                    }
                    SetToggle {
                        label: "off while typing"
                        on: Rules.store.typingOff
                        divider: false
                        onFlip: want => { Rules.store.typingOff = want; Rules.input(); }
                    }
                }
            }
        }
    }
}
