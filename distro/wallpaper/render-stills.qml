// Renders a still picture of each fractal, with the same shader and settings
// as the live wallpaper, for machines without a GPU to spare (the Mac VM, any
// VM without 3D). render-stills.sh runs it; the pictures land in
// distro/themes/fractal/stills/<fractal>.png.
//
// Each fractal is drawn once at full size into an offscreen texture and
// saved, so the window that hosts it can be any size.
import QtQuick
import Quickshell

ShellRoot {
    id: root

    settings.watchFiles: false

    readonly property string out: Quickshell.env("BTW_STILLS_OUT")
    readonly property int w: Number(Quickshell.env("BTW_STILLS_WIDTH")) || 2560
    readonly property int h: Number(Quickshell.env("BTW_STILLS_HEIGHT")) || 1600
    // The moment in the camera's orbit to capture, per fractal: picked so each
    // one shows its best side.
    readonly property var times: ({ mandelbulb: 14, mandelbox: 22, sierpinski: 8, menger: 30 })

    Settings {
        id: settings
    }

    property int index: 0
    readonly property var current: settings.fractals[index]

    FloatingWindow {
        visible: true
        title: "btw: rendering stills"
        implicitWidth: 320
        implicitHeight: 200
        color: "#07080a"

        ShaderEffect {
            id: fx
            width: root.w
            height: root.h
            visible: false
            property vector2d res: Qt.vector2d(root.w, root.h)
            property real time: root.times[root.current.id]
            property real hue: settings.defaults.hue
            property real glow: settings.defaults.glow
            property real dist: root.current.dist
            fragmentShader: settings.shader(root.current.id)
        }

        Timer {
            id: next
            interval: 400
            running: true
            onTriggered: {
                const id = root.current.id;
                fx.grabToImage(result => {
                    const file = root.out + "/" + id + ".png";
                    console.log(result.saveToFile(file) ? "saved " + file : "FAILED " + file);
                    if (root.index + 1 < settings.fractals.length) {
                        root.index++;
                        next.restart();
                    } else {
                        Qt.quit();
                    }
                }, Qt.size(root.w, root.h));
            }
        }
    }
}
