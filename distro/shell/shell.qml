// The btw shell: btw's own desktop UI, written for Quickshell.
// For now it is just the top bar, a stand-in for waybar. The app menu,
// notifications and lock screen move here later.
//
// Run it with `quickshell -p /usr/share/btw/shell`, or switch to it with
// `btw-bar toggle` (Super+Shift+B).
//
// Only Sway.qml knows which compositor is running, so the shell can move to
// niri later by adding a file with the same properties.
import QtQuick
import Quickshell

ShellRoot {
    // One bar on each display.
    Variants {
        model: Quickshell.screens
        Bar {}
    }
}
