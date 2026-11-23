import QtQuick
import Quickshell
import qs
import qs.settings

Scope {
    id: root
    required property bool opened
    property var origin: null
    property int durationOverride: 0
    readonly property bool continuous: !!origin && Theme.state.barAt === "top"
    readonly property bool moving: Rules.moving && !Theme.perfLite
    property real progress: 0
    property real content: 0
    property real surface: 0
    property bool ready: false

    function update() {
        geometry.stop();
        contents.stop();
        alpha.stop();
        const target = opened ? 1 : 0;
        const override = durationOverride;
        durationOverride = 0;
        if (!moving) {
            progress = content = surface = target;
            return;
        }
        const total = continuous ? override || (opened ? 432 : 300) : Theme.t;
        const ratio = total / (opened ? 360 : 250);
        const hold = continuous && !opened && progress === 1 ? Math.round(25 * ratio) : 0;
        geometryPause.duration = hold;
        geometryMove.duration = Math.round((total - hold) * Math.abs(target - progress));
        geometryMove.to = target;
        geometry.start();
        if (continuous) {
            contentPause.duration = opened && content === 0 ? Math.round(100 * ratio) : 0;
            contentMove.duration = Math.round((opened ? 200 : 85) * ratio * Math.abs(target - content));
            contentMove.to = target;
            contents.start();

            const fade = Math.round(35 * ratio);
            alphaPause.duration = opened ? 0 : Math.max(0, hold + geometryMove.duration - fade);
            alphaMove.duration = Math.round(fade * Math.abs(target - surface));
            alphaMove.to = target;
            alpha.start();
        }
    }

    onOpenedChanged: if (ready) update()
    onMovingChanged: if (ready) update()
    Component.onCompleted: {
        ready = true;
        update();
    }

    SequentialAnimation {
        id: geometry
        PauseAnimation { id: geometryPause }
        NumberAnimation {
            id: geometryMove
            target: root
            property: "progress"
            easing.type: root.continuous ? Easing.Linear : Easing.BezierSpline
            easing.bezierCurve: Theme.glide
        }
    }
    SequentialAnimation {
        id: contents
        PauseAnimation { id: contentPause }
        NumberAnimation {
            id: contentMove
            target: root
            property: "content"
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
        }
    }
    SequentialAnimation {
        id: alpha
        PauseAnimation { id: alphaPause }
        NumberAnimation { id: alphaMove; target: root; property: "surface" }
    }
}
