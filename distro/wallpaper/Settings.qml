// The wallpaper's settings, shared by the wallpaper (shell.qml) and the
// Fractals app (fractals.qml) through ~/.config/btw/wallpaper.conf, one
// key=value per line. Both watch the file, so a change in the app shows on
// the wallpaper straight away. btw-wallpaper reads and writes it too.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // The fractals, with how far the camera orbits from each.
    readonly property var fractals: [
        { id: "mandelbulb", name: "Mandelbulb", blurb: "The power-8 bulb, a 3D Mandelbrot set", dist: 2.5 },
        { id: "mandelbox", name: "Mandelbox", blurb: "Folded boxes and spheres, endlessly nested", dist: 6.2 },
        { id: "sierpinski", name: "Sierpinski", blurb: "A tetrahedron of tetrahedra, all the way down", dist: 2.9 },
        { id: "menger", name: "Menger", blurb: "A sponge with holes in every hole", dist: 3.4 }
    ]
    readonly property var defaults: ({ fractal: "mandelbulb", mode: "live", hue: 0, glow: 1.15, speed: 1 })

    property string fractal: defaults.fractal
    property string mode: defaults.mode // "live" or "still"
    property real hue: defaults.hue // 0-1, shifts the mint/teal/amber ramp
    property real glow: defaults.glow // 0.4-2
    property real speed: defaults.speed // 0-3, how fast the camera orbits

    readonly property real dist: (fractals.find(f => f.id === fractal) || fractals[0]).dist
    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/btw/wallpaper.conf"

    function shader(id) {
        return Qt.resolvedUrl(id + ".frag.qsb");
    }

    // The still picture of a fractal, shown when the wallpaper can't be live.
    function still(id) {
        // BTW_STILLS points at a checkout's pictures while developing.
        return "file://" + (Quickshell.env("BTW_STILLS") || "/usr/share/backgrounds/btw") + "/" + id + ".png";
    }

    function clamp(v, lo, hi, fallback) {
        const n = Number(v);
        return isNaN(n) ? fallback : Math.min(hi, Math.max(lo, n));
    }

    function parse(text) {
        const v = Object.assign({}, defaults);
        for (const line of text.split("\n")) {
            const eq = line.indexOf("=");
            if (eq > 0)
                v[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
        }
        fractal = fractals.some(f => f.id === v.fractal) ? v.fractal : defaults.fractal;
        mode = v.mode === "still" ? "still" : "live";
        hue = clamp(v.hue, 0, 1, defaults.hue);
        glow = clamp(v.glow, 0.4, 2, defaults.glow);
        speed = clamp(v.speed, 0, 3, defaults.speed);
    }

    function save() {
        file.setText("# btw wallpaper (the Fractals app and btw-wallpaper write this)\n"
            + "fractal=" + fractal + "\nmode=" + mode + "\nhue=" + hue.toFixed(2)
            + "\nglow=" + glow.toFixed(2) + "\nspeed=" + speed.toFixed(2) + "\n");
    }

    function reset() {
        hue = defaults.hue;
        glow = defaults.glow;
        speed = defaults.speed;
        save();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        // No settings yet: write the defaults, so there's a file to watch
        // (a missing file can't be watched for changes).
        onLoadFailed: root.save()
    }
}
