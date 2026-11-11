pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs

// what the shell can know about an output device with no vendor protocol:
// the bluetooth device behind a bluez sink, the codec pipewire negotiated,
// and the one battery number bluez reports through upower. Everything is
// defensive -- a source that does not answer simply means the device page
// shows less, never something invented. Per-bud charge is not in here on
// purpose: only a vendor backend (Sys.ear for Nothing) knows it.
Singleton {
    id: root

    // bluez sinks are named bluez_output.<ADDR_with_underscores>.<profile>
    function btOf(node) {
        try {
            if (!node || !/^bluez_output/.test(node.name)) return null;
            const addr = (node.name.split(".")[1] ?? "").replace(/_/g, ":");
            return Bluetooth.devices.values.find(d => d.address === addr) ?? null;
        } catch (e) { return null; }
    }

    function codecOf(node) {
        try { return node?.properties?.["api.bluez5.codec"] ?? ""; }
        catch (e) { return ""; }
    }

    // the device's single reported charge, 0..100, or -1 when it reports none
    function batteryOf(node) {
        try {
            const bt = btOf(node);
            if (!bt) return -1;
            const key = bt.address.replace(/:/g, "_");
            const dev = UPower.devices.values.find(d => (d.nativePath ?? "").includes(key) || (!!bt.name && d.model === bt.name));
            return dev ? Math.round(dev.percentage * 100) : -1;
        } catch (e) { return -1; }
    }

    // a dropped-in photo for a device, the buds/<slug>.png convention the
    // buds card already uses (buds/Buds.qml) -- no file, no photo, the icon stays
    function slug(name) {
        return (name ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    }
}
