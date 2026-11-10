pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs.services
import qs.settings

// what the bar, quick settings, Glyph and the lock touch: sound, brightness, layout, recording, night light, airplane mode, caffeine, vpn
Singleton {
    id: root

    // deck (bottom panel) open -- SysStats needs detailed polling, as on an empty workspace (Home)
    property bool deckOpen: false
    // wallpaper picker open -- home changes the wallpaper immediately, without a wave: the picker already showed it
    property bool wallOpen: false

    // ---- sound ----
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var mic: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.mic] }
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property bool micOn: !(mic?.audio?.muted ?? true)
    function setVol(v) {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
        Sounds.play("tick"); // every caller is a hand: the quick slider, the bar/home wheel, the keys below
    }
    // volume keys from the shell, like the brightness ones (services/Backlight): the shell sets
    // the value itself, so the level, the Glyph strip and the tick always agree -- and a change
    // nobody asked for (an app, wireplumber) stays silent, which a wpctl bind could never tell
    // apart. Step and ceiling match hypr/variables.lua (volumeStep 5, volumeMax 100)
    function stepVol(d) { setVol(vol + d * 0.05); }
    GlobalShortcut { appid: "shell"; name: "volUp"; description: "volume +"; onPressed: root.stepVol(1) }
    GlobalShortcut { appid: "shell"; name: "volDown"; description: "volume -"; onPressed: root.stepVol(-1) }
    // someone is listening to the microphone -- the center of the bar mark turns red
    PwNodeLinkTracker { id: micUse; node: root.mic }
    readonly property bool live: rec || micUse.linkGroups.length > 0

    // ---- brightness: shared with demonshot Backlight (the device is found by brightnessctl) ----
    readonly property real bri: Backlight.value
    readonly property bool hasBri: !!Backlight.dev // no backlight (desktop PC with a monitor) -- no brightness controls
    function setBri(v) { Backlight.set(v); }
    // brightness of the monitor the panel was opened on: built-in -- the backlight, external -- DDC.
    // The panel lives on one screen, but Super+A and a hot-edge peek open it "on" Hyprland's focus
    property string panelMon: ""
    readonly property bool panelBriExternal: panelMon !== "" && !panelMon.startsWith("eDP")
    readonly property real panelBri: panelBriExternal ? Backlight.ddc : Backlight.value
    function setPanelBri(v) { panelBriExternal ? Backlight.setDdc(v) : Backlight.set(v); }
    Binding { target: Backlight; property: "steps"; value: Theme.state.briSteps }

    // ---- layout: start -- the main keyboard from hyprctl, then the activelayout event ----
    property string kbd: ""
    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector { onStreamFinished: root.kbd = JSON.parse(this.text).keyboards.find(k => k.main)?.active_keymap ?? "" }
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "activelayout") root.kbd = e.data.slice(e.data.lastIndexOf(",") + 1); }
    }
    readonly property string layout: kbd.slice(0, 2).toLowerCase() // "English (US)" → en

    // ---- recording and airplane mode: hypr keybinds toggle them too, hence polling. Night light -- shared with demonshot, in its rules.json
    // ponytail: pgrep on the shell's check cadence (Theme.sysPollMs); if it becomes noticeable -- watch processes via systemd-run --scope ----
    property bool rec: false
    readonly property bool night: Rules.store.night
    property bool air: false
    Process {
        id: poll
        command: ["sh", "-c", "pgrep -f '^gpu-screen-recorder' >/dev/null && echo rec; "
                            + "rfkill -rno SOFT | grep -qv '^blocked' || echo air"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rec = text.includes("rec");
                root.air = text.includes("air");
            }
        }
    }
    Timer { running: true; repeat: true; interval: Theme.sysPollMs; triggeredOnStart: true; onTriggered: poll.running = true }

    function sh(c) { Quickshell.execDetached(["sh", "-c", c]); }
    // recording settings from Theme.state (quick/Rec) -> gpu-screen-recorder flags; the screenshot tool takes them too
    readonly property var recFps: [30, 60, 120]
    function recArgs() {
        const st = Theme.state;
        const a = ["", "default_output", "default_input", "default_output|default_input"][st.recAudio];
        return `-f ${st.recFps} -q ${["medium", "high", "very_high", "ultra"][st.recQuality]} -cursor ${st.recCursor ? "yes" : "no"}` + (a ? ` -a "${a}"` : "");
    }
    // second time -- stop. Region -- slurp; selection canceled -- gsr does not start, rec fixes the polling
    function toggleRec() {
        const w = Theme.state.recArea ? `-w region -region "$(slurp -f %wx%h+%x+%y)"` : `-w ${Hyprland.focusedMonitor?.name ?? "screen"}`;
        sh(`pkill -INT -f '^gpu-screen-recorder' || exec gpu-screen-recorder ${w} ${recArgs()} -o "$(xdg-user-dir VIDEOS)/rec-$(date +%F_%H-%M-%S).mp4"`);
        rec = !rec;
    }
    function toggleNight() { Rules.store.night = !night; Rules.night(); }
    function toggleAir() { Quickshell.execDetached(["rfkill", air ? "unblock" : "block", "all"]); air = !air; }
    function toggleMic() { if (mic?.audio) mic.audio.muted = !mic.audio.muted; }

    // ---- Nothing / CMF earbuds: ANC and charge via ./ear (their RFCOMM protocol). We ask when quick settings opens.
    // ponytail: we recognize by name, like Gadgetbridge; not Nothing -- ear will not reply, ear stays null ----
    readonly property var buds: Bluetooth.devices.values.find(d => d.connected && /^(nothing|cmf|ear)\b/i.test(d.name)) ?? null
    property var ear: null // {mode, l, r, case?}
    onBudsChanged: ear = null
    // right after connecting the channel is not ready yet -- ask every 2 s until they reply. ponytail: a non-Nothing with a similar
    // name will keep being polled while connected
    Timer { interval: 2000; repeat: true; running: !!root.buds && !root.ear; onTriggered: root.earRun([]) }
    readonly property var ancModes: [[5, "off"], [7, "transp"], [3, "low"], [2, "mid"], [1, "high"], [4, "auto"]]
    property var earNext: null
    function earRun(a) {
        if (!buds) return;
        const c = [Quickshell.shellPath("ear"), buds.address, ...a];
        if (earP.running) earNext = c;
        else { earP.command = c; earP.running = true; }
    }
    function setAnc(m) { ear = Object.assign({}, ear, { mode: m }); earRun(["mode", m]); }
    Process {
        id: earP
        stdout: StdioCollector { onStreamFinished: { try { root.ear = JSON.parse(text); } catch (e) { root.ear = null; } } }
        onExited: if (root.earNext) { command = root.earNext; root.earNext = null; running = true; }
    }

    // ---- Bluetooth does not reconnect devices itself when the adapter comes back
    // on (pill, airplane mode, rfkill). BlueZ drops the connections first and only
    // then powers the adapter down (Connected:false 40-90 ms before Powered:false),
    // so a snapshot taken at switch-off is always empty. The connected list is
    // therefore written half a second late: switch-off cancels the pending write,
    // and btResume keeps what was there before. Turned a device off by hand, or
    // the buds went back in their case -- half a second later the list takes it ----
    readonly property var btOn: Bluetooth.devices.values.filter(d => d.connected).map(d => d.address)
    property var btResume: []
    onBtOnChanged: btKeep.restart()
    Timer { id: btKeep; interval: 500; running: true; onTriggered: if (Bluetooth.defaultAdapter?.enabled && !btResumeT.running) root.btResume = root.btOn }
    Connections {
        target: Bluetooth.defaultAdapter
        function onEnabledChanged() { if (Bluetooth.defaultAdapter.enabled) btResumeT.restart(); else { btKeep.stop(); btResumeT.stop(); } }
    }
    // the adapter needs a moment after power-on
    Timer { id: btResumeT; interval: 1500; onTriggered: { for (const d of Bluetooth.devices.values) if (root.btResume.includes(d.address) && !d.connected) d.connect(); } }

    // ---- caffeine: do not sleep. The inhibitor needs a live window -- an invisible 0x0 one, as in demonshot ----
    property bool caffeine: false
    IdleInhibitor {
        enabled: root.caffeine
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "glyph-caffeine"
            mask: Region {}
        }
    }

    // ---- vpn: clash verge through its tray items, as agreed in demonshot.
    // ponytail: labels are English (language: en in verge); another language -- change the strings ----
    readonly property var verge: SystemTray.items.values.find(i => i.title === "clash-verge" || i.id.includes("clash-verge")) ?? null
    QsMenuOpener { id: vmenu; menu: root.verge?.menu ?? null }
    readonly property var vpnItems: ["System Proxy", "TUN Mode"]
    function vpnItem(l) { return vmenu.children.values.find(e => e.text.startsWith(l)) ?? null; }
    readonly property bool vpn: vpnItems.some(l => vpnItem(l)?.checkState === Qt.Checked)
    property var queue: []
    function toggleVpn() {
        if (!verge) return Quickshell.execDetached(["clash-verge"]); // asleep -- wake it
        queue = vpn ? vpnItems.filter(l => vpnItem(l)?.checkState === Qt.Checked) : vpnItems;
        presser.start();
    }
    // verge rebuilds the menu after every press -- one at a time
    Timer {
        id: presser
        interval: 350
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const [l, ...rest] = root.queue;
            root.queue = rest;
            if (l) root.vpnItem(l)?.triggered();
            if (!rest.length) stop();
        }
    }
}
