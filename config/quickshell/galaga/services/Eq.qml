pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs

// system eq: a pipewire filter chain (52-galaga-eq.conf, linked by the
// installer) with three biquads -- low shelf, peaking, high shelf. When a
// device's eq is on, the chain feeds that device and becomes the default
// sink; off, the device is the default itself and the chain sits parked.
// The honest shape of it: the pc shapes the sound, not the device -- the
// device page says so. Gains are the graph's own live controls, written
// with pw-cli set-param on the node's Props ("lo:Gain" and friends, in
// decibels) -- verified live: no restart, no relink, no gap. Settings are
// per device (Theme.state.eqDev, by sink node name), so the speaker keeps
// its bass and the buds keep theirs. If the chain node is not in the graph
// (pipewire not restarted since install, featEq off in prefs) alive is
// false and every eq surface hides itself -- no dead controls.
Singleton {
    id: root

    readonly property var node: Pipewire.nodes.values.find(n => n.name === "galaga-eq") ?? null
    readonly property bool alive: !!node && Theme.state.featEq
    // the device the chain currently feeds ("" -- parked)
    property string feedFor: ""
    readonly property var engaged: feedFor ? Pipewire.nodes.values.find(n => n.name === feedFor) ?? null : null

    function store(name) {
        const s = Theme.state.eqDev[name];
        return { on: !!s?.on, lo: s?.lo ?? 0, mid: s?.mid ?? 0, hi: s?.hi ?? 0 };
    }
    function save(name, s) {
        const all = Object.assign({}, Theme.state.eqDev);
        all[name] = s;
        Theme.state.eqDev = all;
    }

    // featEq switched off (or the chain vanished) while engaged -- hand the
    // device back as the plain default
    onAliveChanged: {
        if (alive || !feedFor) return;
        const dev = engaged;
        feedFor = "";
        if (dev && Pipewire.defaultAudioSink === node) Pipewire.preferredDefaultAudioSink = dev;
    }

    // a device whose eq is on becomes the default some other way (wireplumber
    // remembered it, a pick elsewhere) -- engage the chain in front of it
    function maybeAuto() {
        if (!alive) return;
        const d = Pipewire.defaultAudioSink;
        if (!d || d === node || feedFor === d.name) return;
        if (store(d.name).on) engage(d);
    }
    Component.onCompleted: maybeAuto()
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root.maybeAuto(); }
    }

    // what the output rows call instead of setting the default themselves:
    // eq on -- the chain in front, eq off -- the device itself
    function pick(dev) {
        if (!dev || dev === node) return;
        if (alive && store(dev.name).on) engage(dev);
        else Pipewire.preferredDefaultAudioSink = dev;
    }

    function engage(dev) {
        if (!dev || dev === node) return;
        feedFor = dev.name;
        withIds(() => {
            Quickshell.execDetached(["pw-cli", "set-param", String(ids.feed), "Props", `{ target.object = "${dev.name}" }`]);
            pushGains(dev.name);
            Pipewire.preferredDefaultAudioSink = node;
        });
    }

    function setOn(dev, on) {
        const s = store(dev.name);
        s.on = on;
        save(dev.name, s);
        if (on) engage(dev);
        else if (feedFor === dev.name) {
            feedFor = "";
            if (Pipewire.defaultAudioSink === node) Pipewire.preferredDefaultAudioSink = dev;
        }
    }

    function setBand(name, band, db) {
        const s = store(name);
        s[band] = db;
        save(name, s);
        if (feedFor === name) gainT.restart();
    }
    function setPreset(name, lo, mid, hi) {
        const s = store(name);
        s.lo = lo; s.mid = mid; s.hi = hi;
        save(name, s);
        if (feedFor === name) gainT.restart();
    }
    Timer { id: gainT; interval: 120; onTriggered: root.pushGains(root.feedFor) }

    function pushGains(name) {
        if (!ids || !name) return;
        const s = store(name);
        const f = v => Number(v).toFixed(1);
        Quickshell.execDetached(["pw-cli", "set-param", String(ids.eq), "Props",
            `{ params = [ "lo:Gain", ${f(s.lo)}, "mid:Gain", ${f(s.mid)}, "hi:Gain", ${f(s.hi)} ] }`]);
    }

    // ---- pw-cli works by numeric id; the ids come from one pw-dump, the
    // same ask-and-parse-JSON shape as the ear helper in Sys ----
    property var ids: null // { eq, feed }
    property var afterIds: null
    function withIds(cb) {
        if (ids) { cb(); return; }
        afterIds = cb;
        if (!dump.running) dump.running = true;
    }
    Process {
        id: dump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const got = {};
                    for (const o of JSON.parse(text)) {
                        const nm = o.info?.props?.["node.name"];
                        if (nm === "galaga-eq") got.eq = o.id;
                        else if (nm === "galaga-eq-feed") got.feed = o.id;
                    }
                    if (got.eq !== undefined && got.feed !== undefined) root.ids = got;
                } catch (e) { }
            }
        }
        onExited: {
            const cb = root.afterIds;
            root.afterIds = null;
            if (cb && root.ids) cb();
        }
    }
}
