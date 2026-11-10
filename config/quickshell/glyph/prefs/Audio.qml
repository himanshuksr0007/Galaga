import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.components

// AUDIO page of prefs. Output and input side by side: a volume ring, mute, a live level row, then every
// device on the machine. The white pill is the default; click or ←→ moves it (Pipewire.preferredDefault*,
// which wireplumber remembers across reboots).
// The level meter is opt-in (Theme.state.audioMeter): it runs on PwNodePeakMonitor, which crashes
// quickshell 0.3.0 -- on 0.3.1+ turn it on here and it just works
Row {
    id: root

    property bool live: true // the meters capture only while the page is on screen
    readonly property var outs: devs(true)
    readonly property var ins: devs(false)
    readonly property string caption: `audio · pipewire · ${outs.length} out · ${ins.length} in`

    // hardware only (no app streams), grouped by card: "SSL 2+" + "Line Outputs 1/L + 2/R".
    // A duplex node (a virtual mic-and-speaker) is a sink and a source at once -- it goes in both lists
    function devs(out) {
        return Pipewire.nodes.values.filter(n => n.audio && !n.isStream && (out ? n.isSink : n.type & PwNodeType.Source))
            .map(n => Object.assign({ node: n }, split(n)))
            .sort((a, b) => a.card.localeCompare(b.card) || a.port.localeCompare(b.port));
    }
    function split(n) {
        const d = n.description || n.name, nick = (n.nickname || "").replace(/ #\d+$/, "");
        if (nick && d.startsWith(nick + " ")) return { card: nick, port: d.slice(nick.length + 1) };
        // HDMI: "GA102 … Digital Stereo (HDMI 2) [ED340CU S3]" -- the monitor is the name
        const bus = d.match(/\(((?:HDMI|DP)[^)]*)\)/);
        if (nick && d.includes(`[${nick}]`)) return { card: bus ? bus[1] : "", port: nick };
        return { card: "", port: d };
    }

    spacing: 70

    Side { out: true; label: "output"; node: Sys.sink; list: root.outs } // Sys tracks both
    Side { out: false; label: "input"; node: Sys.mic; list: root.ins }

    component Side: Column {
        id: side
        required property bool out
        required property string label
        required property var node // the default device
        required property var list
        readonly property int cur: list.findIndex(d => d.node === node)
        function pick(i) {
            const n = list[(i + list.length) % list.length]?.node;
            if (!n) return;
            if (out) Pipewire.preferredDefaultAudioSink = n;
            else Pipewire.preferredDefaultAudioSource = n;
        }

        width: 470
        spacing: 26

        // the peak monitor exists only when the meter is on (and the page is live):
        // not created at all otherwise -- on quickshell 0.3.0 creating it is the crash
        property real peakV: 0
        Loader {
            active: root.live && Theme.state.audioMeter
            sourceComponent: Component {
                PwNodePeakMonitor { node: side.node; onPeakChanged: side.peakV = peak; onNodeChanged: side.lv = 0 }
            }
        }
        // peak is ∛amplitude, so dB = 60·log10(peak); the row shows -60…0 dB → 1 + log10(peak). Above 1 when the node's
        // volume is software (quickshell divides by it). Jumps up on a peak, falls back slowly on the timer so a word stays
        // readable: in silence peak sits at 0 and peakChanged never fires
        readonly property real at: Math.max(0, Math.min(1, 1 + Math.log10(Math.max(peakV, 1e-9))))
        property real lv: 0
        onAtChanged: lv = Math.max(lv, at)
        Timer { interval: 33; repeat: true; running: root.live && side.lv > 0; onTriggered: side.lv = Math.max(side.at, side.lv - 0.03) }

        Row {
            spacing: 36
            Dial {
                enabled: !!side.node?.audio
                size: 200
                n: 48
                live: true
                label: side.label
                value: Math.round((side.node?.audio?.volume ?? 0) * 100)
                onMoved: v => {
                    if (side.out) side.node.audio.muted = false; // the mic stays muted: its gain isn't a reason to open it
                    side.node.audio.volume = v / 100;
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 22
                Toggle {
                    en
...[truncated 4911 chars]