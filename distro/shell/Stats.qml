pragma Singleton
// CPU, memory and network status for the bar, read from /proc and /sys
// every few seconds.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpu: 0          // percent busy since the last read
    property real memUsedGiB: 0
    property bool online: false

    property var lastCpu: null   // [busy, total] jiffies

    function parse(text) {
        const lines = text.split("\n");
        let memTotal = 0, memAvailable = 0, up = false;
        for (const line of lines) {
            const f = line.trim().split(/\s+/);
            if (f[0] === "cpu") {
                const v = f.slice(1).map(Number);
                const idle = v[3] + (v[4] || 0);
                const total = v.reduce((a, b) => a + b, 0);
                if (lastCpu && total > lastCpu[1]) {
                    const busy = (total - idle) - lastCpu[0];
                    cpu = Math.round(100 * busy / (total - lastCpu[1]));
                }
                lastCpu = [total - idle, total];
            } else if (f[0] === "MemTotal:") {
                memTotal = Number(f[1]);
            } else if (f[0] === "MemAvailable:") {
                memAvailable = Number(f[1]);
            } else if (f[0] === "up") {
                up = true;
            }
        }
        memUsedGiB = (memTotal - memAvailable) / 1048576;
        online = up;
    }

    Process {
        id: read
        // The first line of /proc/stat, two lines of /proc/meminfo, and the
        // state of each network interface other than loopback.
        command: ["sh", "-c",
            "head -n1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; " +
            "for i in /sys/class/net/*; do [ \"${i##*/}\" = lo ] || cat \"$i/operstate\"; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: read.running = true
    }
}
