pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// screen backlight, like caelestia -- the device is not hardcoded: whatever brightnessctl takes by default (the first backlight).
// Value -- from sysfs: inotify on it is silent, but writing to brightness sends a uevent change -- we wait for it from udev instead of polling.
// No backlight (desktop PC) -- dev empty, value 0. ponytail: external monitors over DDC (ddcutil, like caelestia) -- no
Singleton {
    id: root

    property string dev: ""       // /sys/class/backlight/<name>
    property real value: 0        // 0…1
    property int steps: 20        // scale divisions for the keys; glyph sets it from settings (Sys)
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
}
