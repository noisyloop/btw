pragma Singleton
// Whether the app menu is open. The bar's ▲ btw button, Super+Space (through
// btw-menu and the "menu" IPC target in shell.qml) and the menu itself all go
// through here.
import QtQuick
import Quickshell

Singleton {
    property bool open: false

    function toggle() {
        open = !open;
    }
}
