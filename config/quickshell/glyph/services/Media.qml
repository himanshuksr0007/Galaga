pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// the player to show: a playing one, else a paused one that has a track,
// else the first. The middle step matters -- mpris-proxy (execs.lua) parks
// an always-empty player for the bluetooth speaker in the list, and plain
// "first" landed on it the moment playback paused: every surface went to
// "Nothing on" and the controls talked to the empty player. A paused
// player keeps its title, art and length, so it stays the shown one.
// No lyrics lookup: nothing showed the text, but every track title was
// being sent to lrclib.net
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players.find(p => p.trackTitle) ?? players[0] ?? null
    readonly property bool playing: player?.isPlaying ?? false
    property real position: 0

    function time(s) {
        s = Math.max(0, Math.floor(s || 0));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // the mpris position has to be polled
    Timer {
        running: root.playing
        interval: 500
        repeat: true
        onTriggered: root.position = root.player?.position ?? 0
    }

    // new track -- position at once, don't wait for the poll
    readonly property string track: player ? `${player.trackArtist}\n${player.trackTitle}` : ""
    onTrackChanged: position = player?.position ?? 0
}
