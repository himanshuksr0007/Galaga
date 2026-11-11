pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.services

// notifications: new -- island at the top and a Galaga flash, history -- cards in quick settings
Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values
    property var times: ({}) // id -> when it arrived: Notification has no time of its own
    signal arrived(var n)

    // progress of long tasks -- hint value (notify-send -h int:value:64 ...): the bottom Galaga strip
    readonly property var task: list.slice().reverse().find(n => n.hints?.value !== undefined) ?? null

    // essential mode (prefs FEATURES, off by default): only the picked apps arrive out loud --
    // the island, the edge flash. Everything is still tracked below, so quick settings keeps
    // the full history; the unpicked ones just arrive muted. Matching: the notification's
    // desktop-entry hint against the picked ids; senders that omit it fall back to the
    // entry whose name or icon the notification carries.
    readonly property bool essMode: Theme.state.featEssential
    function essential(n) {
        if (!root.essMode) return true;
        const ids = Theme.state.essentialApps;
        if (!ids.length) return false;
        if (n.desktopEntry && ids.includes(n.desktopEntry)) return true;
        return DesktopEntries.applications.values.some(a => ids.includes(a.id) && (a.name === n.appName || (!!a.icon && a.icon === n.appIcon)));
    }

    NotificationServer {
        id: server
        actionsSupported: true
        imageSupported: true
        keepOnReload: false
        onNotification: n => {
            n.tracked = true;
            root.times = Object.assign({}, root.times, { [n.id]: Date.now() });
            if ((!Theme.state.dnd || n.urgency === NotificationUrgency.Critical) && root.essential(n)) {
                root.arrived(n);
                Sounds.play("notify"); // here, not at a consumer: arrived is post-gating -- dnd and essential already decided
            }
        }
    }

    function clear() { for (const n of list.slice()) n.dismiss(); }
    function ago(n, now) {
        const m = Math.floor((now - (times[n.id] ?? now)) / 60000);
        return m < 1 ? "now" : m < 60 ? `${m} min` : `${Math.floor(m / 60)} h`;
    }

    // count -- into state: the lock writes "3 notifications". The newest few ride along
    // as plain fields (state.peek): the lock is a separate process and the state file is
    // the channel it already reads the count through -- its face shows them as a summary
    onListChanged: {
        if (Theme.state.unread !== list.length) Theme.state.unread = list.length;
        const pk = list.slice(-3).reverse().map(n => ({ app: n.appName || "app", summary: n.summary ?? "" }));
        if (JSON.stringify(pk) !== JSON.stringify(Theme.state.peek)) Theme.state.peek = pk;
    }
}
