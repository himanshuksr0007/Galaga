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
// (pipewire not restarted since install, featEq off in settings -> sound) alive is
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
        dropLinks();
        feedFor = "";
        if (dev && Pipewire.defaultAudioSink === node) Pipewire.preferredDefaultAudioSink = dev;
    }

    // the fed device's node vanished: the feed links died with it, so the
    // bookkeeping forgets them too. It came back while the chain is the
    // default: rebuild them (a bluetooth reconnect is the usual case --
    // the returning node is a new node and nothing else re-runs engage).
    onEngagedChanged: {
        if (!feedFor) return;
        if (!engaged) { linkedPairs = []; return; }
        if (alive && Pipewire.defaultAudioSink === node) ensureLinks(feedFor);
    }

    // a device whose eq is on becomes the default some other way (wireplumber
    // remembered it, a pick elsewhere) -- engage the chain in front of it.
    // the mirror image: the chain is the default but the device it feeds
    // became the plain default again (it vanished and wireplumber put it
    // back) -- re-engage so the chain is in front and the links rebuilt.
    function maybeAuto() {
        if (!alive) return;
        const d = Pipewire.defaultAudioSink;
        if (!d) return;
        if (d === node) {
            if (feedFor) ensureLinks(feedFor);
            return;
        }
        if (feedFor === d.name) { engage(d); return; }
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
        if (alive && store(dev.name).on) { engage(dev); return; }
        // a plain pick: the chain steps aside entirely -- it does not
        // keep feeding the previous device in the background, so exactly
        // one output is ever the output
        if (feedFor) { dropLinks(); feedFor = ""; }
        Pipewire.preferredDefaultAudioSink = dev;
    }

    function engage(dev) {
        if (!dev || dev === node) return;
        if (feedFor && feedFor !== dev.name) dropLinks();
        feedFor = dev.name;
        ensureLinks(dev.name);
        withDump(() => {
            if (feedFor !== dev.name) return;
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
            dropLinks();
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

    // ---- the feed links are ours, not wireplumber's ----
    // engage used to set target.object on galaga-eq-feed and trust the
    // session manager to route it to the device. On real hardware that
    // never happened: streams played into the chain (the visualiser on
    // its monitor kept beating) and the feed node sat with zero links --
    // silence at the device, speakers and bluetooth alike. So the shell
    // makes the two links itself with pw-link, reads a fresh pw-dump to
    // plan them (feed out ports paired to device in ports by channel),
    // and checks afterwards that they really landed. If they did not,
    // eq steps back out of the way -- device as plain default, a warning
    // in the log -- instead of sitting in the path swallowing the audio.
    // do not "simplify" this back to target.object.
    property var linkedPairs: [] // [{ outEp, inEp }] verified live
    property bool linkBusy: false
    property string linkWant: ""
    property var cyclePairs: [] // pairs of the in-flight link cycle
    property string cycleName: ""

    function chanToken(portName) {
        const parts = String(portName).split(/[_\- ]/);
        return (parts[parts.length - 1] ?? "").toUpperCase();
    }

    // plan the feed -> device pairs from a pw-dump snapshot: which ports
    // pair up (same audio.channel first, then same port name, then same
    // trailing channel token) and which pairs are already linked.
    // null when the feed or the device is not in the graph right now.
    function planLinks(objs, devName) {
        let feedId = -1, devId = -1;
        const ports = [], links = [];
        for (const o of objs) {
            const props = o.info?.props ?? {};
            if (o.type === "PipeWire:Interface:Node") {
                if (props["node.name"] === "galaga-eq-feed") feedId = o.id;
                else if (props["node.name"] === devName) devId = o.id;
            } else if (o.type === "PipeWire:Interface:Port") {
                ports.push({ id: o.id, node: props["node.id"], name: props["port.name"] ?? "",
                             dir: props["port.direction"] ?? o.info?.direction ?? "",
                             chan: props["audio.channel"] ?? "" });
            } else if (o.type === "PipeWire:Interface:Link") {
                const li = o.info ?? {};
                links.push({ outPort: li["output-port-id"] ?? props["link.output.port"],
                             inPort: li["input-port-id"] ?? props["link.input.port"] });
            }
        }
        if (feedId < 0 || devId < 0) return null;
        const outs = ports.filter(p => p.node === feedId && (p.dir === "out" || p.dir === "output"));
        const ins = ports.filter(p => p.node === devId && (p.dir === "in" || p.dir === "input"));
        const used = new Set();
        const pairs = [];
        for (const op of outs) {
            const ip = ins.find(p => !used.has(p.id) && op.chan && p.chan === op.chan)
                    ?? ins.find(p => !used.has(p.id) && p.name === op.name)
                    ?? ins.find(p => !used.has(p.id) && chanToken(p.name) === chanToken(op.name));
            if (!ip) continue;
            used.add(ip.id);
            pairs.push({ outId: op.id, inId: ip.id,
                         outEp: "galaga-eq-feed:" + op.name, inEp: devName + ":" + ip.name,
                         linked: links.some(l => l.outPort === op.id && l.inPort === ip.id) });
        }
        return { pairs };
    }

    function ensureLinks(name) {
        if (!name) return;
        linkWant = name;
        if (linkBusy) return;
        linkBusy = true;
        withDump(objs => linkStep(objs));
    }

    function linkStep(objs) {
        const name = linkWant;
        cycleName = name;
        const plan = planLinks(objs, name);
        // no plan: the device (or the chain) is not in this snapshot --
        // the verify pass below decides; it fails safe, never silent
        cyclePairs = plan ? plan.pairs : [];
        if (plan) {
            for (const p of plan.pairs)
                if (!p.linked) Quickshell.execDetached(["pw-link", p.outEp, p.inEp]);
        }
        verifyT.restart();
    }

    Timer { id: verifyT; interval: 350; onTriggered: root.verifyLinks() }

    // read the truth back: every pair of the cycle must show up as a real
    // link in a fresh snapshot, or eq disengages (see the note above)
    function verifyLinks() {
        withDump(objs => {
            const name = cycleName;
            linkBusy = false;
            if (name !== linkWant) { ensureLinks(linkWant); return; }
            if (feedFor !== name) { cyclePairs = []; return; }
            const plan = planLinks(objs, name);
            const ok = !!plan && cyclePairs.length > 0 && cyclePairs.every(p =>
                plan.pairs.some(q => q.outId === p.outId && q.inId === p.inId && q.linked));
            if (ok) {
                linkedPairs = cyclePairs.map(p => ({ outEp: p.outEp, inEp: p.inEp }));
            } else {
                console.warn("galaga eq: feed links to " + name + " did not land; eq disengaged, device left as plain default");
                unlinkPairs(cyclePairs);
                feedFor = "";
                const dev = Pipewire.nodes.values.find(n => n.name === name) ?? null;
                if (dev && Pipewire.defaultAudioSink === node) Pipewire.preferredDefaultAudioSink = dev;
            }
            cyclePairs = [];
        });
    }

    function unlinkPairs(pairs) {
        for (const p of pairs ?? [])
            Quickshell.execDetached(["pw-link", "-d", p.outEp, p.inEp]);
    }
    // tear down the verified links (eq off, device switch, chain gone).
    // endpoints are names, so this is safe to fire even when the device
    // node has already vanished -- pw-link just finds nothing to do.
    function dropLinks() {
        unlinkPairs(linkedPairs);
        linkedPairs = [];
    }

    // ---- pw-dump is the eyes for all of this: node ids for pw-cli (the
    // gains), ports and links for the feed wiring. one process, a queue
    // of callbacks waiting on the next snapshot; every snapshot also
    // refreshes the cached node ids ----
    property var ids: null // { eq, feed }
    property var dumpCbs: []
    property var dumpObjs: null
    function withDump(cb) {
        dumpCbs.push(cb);
        if (!dump.running) dump.running = true;
    }
    function scanDump(objs) {
        const got = {};
        for (const o of objs) {
            if (o.type !== "PipeWire:Interface:Node") continue;
            const nm = o.info?.props?.["node.name"];
            if (nm === "galaga-eq") got.eq = o.id;
            else if (nm === "galaga-eq-feed") got.feed = o.id;
        }
        if (got.eq !== undefined && got.feed !== undefined) ids = got;
    }
    Process {
        id: dump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dumpObjs = JSON.parse(text); } catch (e) { root.dumpObjs = null; }
                if (root.dumpObjs) root.scanDump(root.dumpObjs);
            }
        }
        onExited: {
            const cbs = root.dumpCbs;
            root.dumpCbs = [];
            const objs = root.dumpObjs;
            root.dumpObjs = null;
            if (objs) { for (const cb of cbs) cb(objs); }
            else root.linkBusy = false; // no snapshot, no cycle left hanging
        }
    }
}
