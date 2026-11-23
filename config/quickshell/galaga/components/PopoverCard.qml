import QtQuick
import qs

Item {
    id: frame
    default property alias content: body.data
    required property PopoverMotion motion
    property real unit: 1
    property real radius: Theme.corner(36)
    property color color: Theme.s1
    readonly property bool continuous: motion.continuous
    readonly property real p: motion.progress
    readonly property real shape: continuous && motion.moving ? spring(p) : p
    readonly property real fade: continuous ? motion.content : p
    readonly property var origin: motion.origin
    readonly property real startX: ((origin?.x ?? 0) + (origin?.width ?? 0) / 2) / unit - x - 14
    readonly property real startY: ((origin?.y ?? 0) + (origin?.height ?? 0) / 2) / unit - y - 14

    // A short settling tail with a small underdamped overshoot.
    // Closing samples precisely the same geometry in the opposite direction.
    function spring(t) {
        if (t <= 0 || t >= 1) return t;
        const distance = Math.pow(t, 1.5);
        return Math.min(1.035, 1 - Math.exp(-9 * distance)
            * (Math.cos(9 * distance) + Math.sin(9 * distance)));
    }

    data: [
        Rectangle {
            id: backdrop
            readonly property real departure: Math.min(1, Math.max(0, frame.shape) / 0.45)
            readonly property color fill: frame.continuous && !Theme.light ? "#0d0d0d" : frame.color
            x: frame.continuous ? frame.startX * (1 - frame.shape) : 0
            y: frame.continuous ? frame.startY * (1 - frame.shape) : 0
            width: frame.continuous ? 28 + (frame.width - 28) * frame.shape : frame.width
            height: frame.continuous ? 28 + (frame.height - 28) * frame.shape : frame.height
            radius: frame.continuous ? 14 + (Theme.corner(26) - 14) * Math.min(1, frame.shape) : frame.radius
            opacity: frame.continuous ? frame.motion.surface : frame.p
            // Make the first small outline visible on the bar while letting
            // the glyph show through until the card has left its trigger.
            color: frame.continuous ? Theme.fade(fill, departure) : fill
            border.width: 1
            border.color: frame.continuous
                ? Theme.fade(Theme.light ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1),
                    0.08 + 0.52 * (1 - departure))
                : Theme.s2
        },
        Item {
            id: viewport
            x: backdrop.x
            y: backdrop.y
            width: backdrop.width
            height: backdrop.height
            clip: frame.continuous && frame.p < 1
            Item {
                id: body
                x: -viewport.x
                y: -viewport.y + (frame.continuous ? (frame.motion.opened ? -6 : -4) * (1 - frame.fade) : 0)
                width: frame.width
                height: frame.height
                visible: frame.fade > 0
                enabled: frame.motion.opened && frame.fade >= 0.5
                opacity: frame.fade
                scale: frame.continuous ? 1 - (frame.motion.opened ? 0.06 : 0.05) * (1 - frame.fade) : 1
            }
        }
    ]
}
