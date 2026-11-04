pragma Singleton
// btw fractal theme for the shell. Same palette as desktop/theme.css and
// distro/themes/fractal/waybar.css.
import QtQuick
import Quickshell

Singleton {
    readonly property color background: "#07080a"
    readonly property color surface: "#121614"
    readonly property color raised: "#18201c"
    readonly property color foreground: "#e7efe9"
    readonly property color muted: "#8b978f"
    readonly property color line: "#24302a"
    readonly property color accent: "#3ddc97"
    readonly property color amber: "#e8a24a"

    // The bar is slightly see-through, like waybar's alpha(@background, 0.82).
    readonly property color barBackground: Qt.rgba(0.027, 0.031, 0.039, 0.82)

    readonly property string font: "IBM Plex Mono"
    readonly property string sans: "IBM Plex Sans"
    readonly property int fontSize: 13
    readonly property int barHeight: 30
}
