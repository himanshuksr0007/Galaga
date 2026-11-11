import QtQuick

// the wheel, by notches: notch(±1) per 120 of angle. A hi-res wheel sends 15 per
// click -- accumulate, or one click is eight steps.
// A MouseArea, not a WheelHandler: on the bar's pill the handler never got the
// wheel (it also checks the point against the window's geometry), the area does.
// The touchpad is not taken (scrollGestureEnabled) -- a swipe doesn't scroll these;
// buttons and hover pass through
MouseArea {
    signal notch(int d) // +1 -- wheel away from you
    property real acc: 0
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    scrollGestureEnabled: false
    onWheel: e => {
        const dy = (e.inverted ? -1 : 1) * (e.angleDelta.y || e.angleDelta.x); // natural scroll: away from you is still +1
        if (acc * dy < 0) acc = 0; // turned back mid-notch -- the remainder doesn't count
        acc += dy;
        while (Math.abs(acc) >= 120) {
            notch(Math.sign(acc));
            acc -= Math.sign(acc) * 120;
        }
    }
}
