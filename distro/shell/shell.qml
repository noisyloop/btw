// The btw shell: btw's own desktop UI, written for Quickshell.
// So far: the top bar (in place of waybar), the app menu (fuzzel) and
// notifications (mako). The lock screen comes next.
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
    // Installed files change only when btw is updated, and the new files land
    // one at a time; a reload halfway through fails ("File not found").
    // Changes apply the next time btw starts (as for the wallpaper).
    settings.watchFiles: false

    // One bar on each display.
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Launcher {}
    Toasts {}

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
