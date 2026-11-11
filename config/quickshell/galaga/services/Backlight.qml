pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs

// screen backlight, like caelestia -- the device is not hardcoded: whatever brightnessctl takes by default (the first backlight).
// Value -- from sysfs: inotify on it is silent, but writing to brightness sends a uevent change -- we wait for it from udev instead of polling.
// No backlight (desktop PC) -- dev empty, value 0. ponytail: external monitors over DDC (ddcutil, like caelestia) -- no
Singleton {
    id: root

    property string dev: ""       // /sys/class/backlight/<name>
    property real value: 0        // 0…1
    property int steps: 20        // scale divisions for the keys; galaga sets it from settings (Sys)
    signal moved()                // every uevent, even if the value is the same (key at maximum) -- for the OSD

    function read() {
        cur.reload();
        const v = parseInt(cur.text());
        if (!isNaN(v)) value = v / (parseInt(max.text()) || 1);
    }
    // set value immediately, do not wait for brightnessctl and uevent; while our own writes are in flight, do not read their uevents -- sync will reconcile later
    // as a raw number, not a percentage: rounding to % would break step()'s grid (81 % -> up -> 99, not 100)
    function set(v) {
        const m = parseInt(max.text()) || 0;
        if (!m) return;
        const raw = Math.round(Math.max(0.01, Math.min(1, v)) * m);
        value = raw / m;
        sync.restart();
        Quickshell.execDetached(["brightnessctl", "-q", "-d", dev.slice(dev.lastIndexOf("/") + 1), "set", String(raw)]);
    }
    // keys: steps divisions by the 4th root (20 -- like brightnessctl -e4 5%), finer at the bottom of the scale. Step from the nearest
    // division, not from value: otherwise the fractional error accumulates (up to 399998 instead of 400000)
    function step(d) {
        set(Math.pow(Math.max(0, Math.min(steps, Math.round(Math.pow(value, 0.25) * steps) + d)) / steps, 4));
        moved();
        // a blip per key press, pitched the way the screen goes -- step() is
        // only called by the two GlobalShortcuts, so external changes (a panel
        // drag, another tool) stay silent, like the volume keys' tick rule
        Sounds.play(d > 0 ? "briup" : "bridown");
    }
    Timer { id: sync; interval: 300; onTriggered: root.read() }
    GlobalShortcut { appid: "shell"; name: "briUp"; description: "brightness +"; onPressed: root.step(1) }
    GlobalShortcut { appid: "shell"; name: "briDown"; description: "brightness -"; onPressed: root.step(-1) }

    FileView { id: cur; path: root.dev ? root.dev + "/brightness" : ""; blockAllReads: true; printErrors: false }
    FileView { id: max; path: root.dev ? root.dev + "/max_brightness" : ""; blockLoading: true; printErrors: false }

    // brightnessctl -m: "name,class,current,percent,maximum"
    Process {
        running: true
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim().split(",")[0];
                if (!name) return;
                root.dev = "/sys/class/backlight/" + name;
                root.read();
            }
        }
    }
    Process {
        running: !!root.dev
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        stdout: SplitParser { onRead: l => { if (l.includes(" change ")) { if (!sync.running) root.read(); root.moved(); } } }
    }

    // ---- an external monitor over DDC (ddcutil), after AMM021's rice_nothing: buses come in pairs
    // "I2C bus -> DRM_connector", external -- a connector without eDP. logind's udev rule gives the active
    // user rw on /dev/i2c-*, no sudo needed. There are no change events -- we keep our own value, check
    // getvcp on the shell's DDC cadence (Theme.ddcMs), and on a panel drag set it through one process ----
    property string ddcBus: ""      // /dev/i2c-N, empty -- no external monitor with DDC
    property real ddc: 0.5          // last known 0...1
    property bool ddcOk: false
    signal ddcMoved()
    readonly property string ddcBusNo: ddcBus.slice(ddcBus.lastIndexOf("-") + 1) // for --bus
    // --skip-ddc-checks on every call (Isaqdn03's find): detect already checked the buses, and ddcutil's
    // startup checks were half of every call -- reads 675 -> 310 ms, writes 370 -> 145 ms there
    readonly property var ddcArgs: ["--skip-ddc-checks", "--noverify", "--sleep-multiplier", "0.05", "--bus", ddcBusNo]
    // setvcp goes through one process: on slow monitors a write takes hundreds of ms, and parallel calls
    // (execDetached) finish out of order -- the result stuck at a random brightness from mid-drag and flickered.
    // We always set the latest value (ddcWant), and polling after our own write stays quiet until it has settled
    property int ddcWant: -1        // what to set, -1 -- nothing
    property real ddcSetAt: 0       // when the last write went: reading right after it isn't possible
    Timer {
        running: !!root.ddcBus
        interval: Theme.ddcMs
        repeat: true
        onTriggered: root.ddcRead()
    }
    function ddcRead() {
        if (!ddcBus) return;
        // our own write is read back only once it has had time to apply (slow panels need time)
        if (ddcWant >= 0 || (ddcSetAt && Date.now() - ddcSetAt < 1200))
            return;
        ddcGet.exec(["ddcutil", ...ddcArgs, "--brief", "getvcp", "10"]);
    }
    // a panel asking for a fresh value waits until its open is done (Isaqdn03): on NVIDIA ddcutil's I2C
    // holds the driver, and a window created meanwhile blocked the shell until the read was over (~600 ms)
    function ddcRefreshSoon() { ddcReadT.restart(); }
    Timer { id: ddcReadT; interval: Theme.t + 150; onTriggered: root.ddcRead() }
    Process {
        id: ddcGet
        stdout: StdioCollector {
            onStreamFinished: {
                // "VCP 10 C 50 100" -- code, type, current, maximum
                const p = text.trim().split(/\s+/);
                const v = parseFloat(p[3]), m = parseFloat(p[4]);
                if (!isNaN(v) && m > 0) {
                    root.ddc = v / m;
                    root.ddcOk = true;
                    root.ddcMoved();
                }
            }
        }
    }
    function setDdc(v) {
        if (!ddcBus)
            return;
        const val = Math.round(Math.max(0, Math.min(1, v)) * 100);
        ddc = val / 100;
        ddcOk = true;
        ddcMoved();
        ddcWant = val;
        ddcSetAt = Date.now();
        ddcPump();
    }
    function ddcPump() {
        if (ddcWant < 0 || ddcSet.running)
            return;
        const val = ddcWant;
        ddcWant = -1;
        ddcSetAt = Date.now();
        ddcSet.exec(["ddcutil", ...ddcArgs, "setvcp", "10", String(val)]);
    }
    Process {
        id: ddcSet
        onExited: root.ddcPump()   // values could arrive during the write -- set the next one right after
    }
    Process {
        running: true
        command: ["sh", "-c", "ddcutil --skip-ddc-checks detect 2>/dev/null | awk '/I2C bus/{b=$NF} /DRM_connector/{c=$NF} /EDID synopsis/{if (b && c && index(c, \"eDP\") == 0) {print b; exit}}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const bus = text.trim();
                if (bus.startsWith("/dev/i2c")) {
                    root.ddcBus = bus;
                    root.ddcRead();
                }
            }
        }
    }
}
