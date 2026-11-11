import QtQuick
import QtMultimedia
import qs

// the players behind services/Sounds, in their own file on purpose: Sounds
// loads this through a Loader, so a machine without the QtMultimedia QML
// module (package qt6-multimedia) loses the sounds, never the shell.
// One SoundEffect per sound, decoded up front -- play() is then a trigger,
// no process spawn, no latency worth naming. The wavs are our own
// (tools/make_sounds.py), quiet by construction; the volume setting scales
// them once more.
Item {
    id: fx

    readonly property real vol: Theme.state.soundVol / 100
    function play(name) { byName[name]?.play(); }

    SoundEffect { id: popFx; source: Qt.resolvedUrl("../assets/sounds/pop.wav"); volume: fx.vol }
    SoundEffect { id: tickFx; source: Qt.resolvedUrl("../assets/sounds/tick.wav"); volume: fx.vol }
    SoundEffect { id: lockFx; source: Qt.resolvedUrl("../assets/sounds/lock.wav"); volume: fx.vol }
    SoundEffect { id: unlockFx; source: Qt.resolvedUrl("../assets/sounds/unlock.wav"); volume: fx.vol }
    SoundEffect { id: notifyFx; source: Qt.resolvedUrl("../assets/sounds/notify.wav"); volume: fx.vol }
    SoundEffect { id: shotFx; source: Qt.resolvedUrl("../assets/sounds/shot.wav"); volume: fx.vol }
    SoundEffect { id: chargeFx; source: Qt.resolvedUrl("../assets/sounds/charge.wav"); volume: fx.vol }
    SoundEffect { id: closeFx; source: Qt.resolvedUrl("../assets/sounds/close.wav"); volume: fx.vol }
    SoundEffect { id: briupFx; source: Qt.resolvedUrl("../assets/sounds/briup.wav"); volume: fx.vol }
    SoundEffect { id: bridownFx; source: Qt.resolvedUrl("../assets/sounds/bridown.wav"); volume: fx.vol }

    readonly property var byName: ({ pop: popFx, tick: tickFx, lock: lockFx, unlock: unlockFx,
                                     notify: notifyFx, shot: shotFx, charge: chargeFx,
                                     close: closeFx, briup: briupFx, bridown: bridownFx })
}
