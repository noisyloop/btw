// btw's live wallpaper: the raymarched fractal from the browser preview, on
// the background layer of every display. btw-wallpaper starts it with
// `quickshell -p /usr/share/btw/wallpaper`. The fractal, colors and motion
// come from Settings.qml (~/.config/btw/wallpaper.conf) and change live when
// the Fractals app edits them.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    Settings {
        id: settings
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
        running: settings.speed > 0
        repeat: true
        property double last: Date.now()
        onTriggered: {
            const now = Date.now();
            root.clock += Math.min(0.1, (now - last) / 1000) * settings.speed;
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
                property real hue: settings.hue
                property real glow: settings.glow
                property real dist: settings.dist
                fragmentShader: settings.shader(settings.fractal)

                layer.enabled: true
                layer.smooth: true
                layer.textureSize: Qt.size(Math.max(1, width * root.scale), Math.max(1, height * root.scale))
            }
        }
    }
}
