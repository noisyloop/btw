// btw's live wallpaper: the raymarched fractal from the browser preview, on
// the background layer of every display. btw-wallpaper starts it with
// `quickshell -p /usr/share/btw/wallpaper` and picks the fractal through
// BTW_FRACTAL (mandelbox, mandelbulb, sierpinski or menger).
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property var distances: ({ mandelbox: 6.2, mandelbulb: 2.5, sierpinski: 2.9, menger: 3.4 })
    readonly property string fractal: {
        const name = Quickshell.env("BTW_FRACTAL") || "mandelbulb";
        return name in distances ? name : "mandelbulb";
    }
    // Render resolution relative to the screen: raymarching every pixel is
    // costly, and the fractal is soft enough that half looks the same.
    readonly property real scale: Number(Quickshell.env("BTW_WALLPAPER_SCALE")) || 0.5
    // The camera's clock, shared by every display. Starts a little way in.
    property real clock: 8

    // ~30 frames a second is plenty for a camera this slow, and halves the
    // GPU time of following the display's refresh rate.
    Timer {
        interval: 33
        running: true
        repeat: true
        property double last: Date.now()
        onTriggered: {
            const now = Date.now();
            root.clock += Math.min(0.1, (now - last) / 1000);
            last = now;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "btw-wallpaper"
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "#07080a"

            ShaderEffect {
                anchors.fill: parent
                property vector2d res: Qt.vector2d(width, height)
                property real time: root.clock
                property real hue: 0.0
                property real glow: 1.15
                property real dist: root.distances[root.fractal]
                fragmentShader: Qt.resolvedUrl(root.fractal + ".frag.qsb")

                layer.enabled: true
                layer.smooth: true
                layer.textureSize: Qt.size(Math.max(1, width * root.scale), Math.max(1, height * root.scale))
            }
        }
    }
}
