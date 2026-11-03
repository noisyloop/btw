// The btw shell: btw's own desktop UI, written for Quickshell.
// So far: the top bar (a stand-in for waybar) and the app menu (for fuzzel).
// Notifications and the lock screen move here later.
//
// Run it with `quickshell -p /usr/share/btw/shell`, or switch to it with
// `btw-bar toggle` (Super+Shift+B).
//
// Only Sway.qml knows which compositor is running, so the shell can move to
// niri later by adding a file with the same properties.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    // One bar on each display.
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Launcher {}

    // btw-menu (Super+Space) runs `quickshell ipc -p <shell> call menu toggle`.
    IpcHandler {
        target: "menu"
        function toggle(): void {
            AppMenu.toggle();
        }
        function open(): void {
            AppMenu.open = true;
        }
        function close(): void {
            AppMenu.open = false;
        }
    }
}
