pragma Singleton
// btw's notification service (in place of mako): it receives notifications
// from apps over D-Bus and keeps the ones on screen in `popups`, newest first.
// Toasts.qml draws them.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // At most this many on screen; older ones are let go when more arrive.
    readonly property int maxPopups: 4
    // How long a notification stays up when the app doesn't say.
    readonly property int defaultTimeout: 6000

    property var popups: []

    // Milliseconds to keep a notification up, or 0 to keep it until closed.
    // Critical ones (low battery, failures) stay until dismissed.
    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        const t = n.expireTimeout;
        if (!(t > 0))
            return defaultTimeout;
        // Quickshell reports the app's timeout in seconds; anything over 1000
        // must already be milliseconds.
        return Math.round(t > 1000 ? t : t * 1000);
    }

    // A notification's actions as a plain array (it's a QML list).
    function actionsOf(n) {
        const out = [];
        const list = n.actions || [];
        for (let i = 0; i < list.length; i++)
            out.push(list[i]);
        return out;
    }

    function remove(n) {
        popups = popups.filter(p => p !== n);
    }

    // The app's default action, if it has one (usually "open the thing").
    function activate(n) {
        for (const a of actionsOf(n)) {
            if (a.identifier === "default") {
                a.invoke();
                return;
            }
        }
        n.dismiss();
    }

    // In a window inside another desktop (btw-session sets BTW_IN_WINDOW), no
    // server: that desktop keeps its notifications. Otherwise btw, if it
    // started first, would take them from it until btw closed.
    readonly property bool inWindow: (Quickshell.env("BTW_IN_WINDOW") || "") !== ""

    LazyLoader {
        active: !root.inWindow

        NotificationServer {
            keepOnReload: false
            actionsSupported: true
            bodyMarkupSupported: true
            imageSupported: true

            onNotification: n => {
                n.tracked = true;
                n.closed.connect(() => root.remove(n));
                const shown = [n].concat(root.popups);
                for (const old of shown.slice(root.maxPopups))
                    old.expire();
                root.popups = shown.slice(0, root.maxPopups);
            }
        }
    }
}
