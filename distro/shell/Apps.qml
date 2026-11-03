pragma Singleton
// The apps and power actions in the app menu. Apps come from btw-apps (which
// reads the .desktop files) and start through btw-launch, run by Sway so they
// keep running if the shell restarts.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Menu tabs, in order, and the .desktop categories each one collects.
    readonly property var tabs: [
        { name: "All", categories: [] },
        { name: "Internet", categories: ["Network", "WebBrowser", "Email", "Chat"] },
        { name: "Media", categories: ["AudioVideo", "Audio", "Video", "Graphics"] },
        { name: "Office", categories: ["Office"] },
        { name: "Tools", categories: ["Utility", "Development", "TextEditor", "FileManager"] },
        { name: "System", categories: ["System", "Settings", "TerminalEmulator", "Monitor"] },
        { name: "Power", categories: [] }
    ]

    readonly property var power: [
        { id: "logout", name: "Log out", desc: "Leave the desktop for the console", tab: "Power", power: true, command: "exit" },
        { id: "restart", name: "Restart", desc: "Reboot btw", tab: "Power", power: true, command: "exec systemctl reboot" },
        { id: "shutdown", name: "Shut down", desc: "Power off btw", tab: "Power", power: true, command: "exec systemctl poweroff" }
    ]

    // [{ id, name, desc, icon, tab, keywords }] sorted by name.
    property var apps: []

    function tabFor(categories) {
        for (const t of tabs)
            for (const c of t.categories)
                if (categories.indexOf(c) >= 0)
                    return t.name;
        return "Tools";
    }

    function parse(text) {
        const list = [];
        for (const line of text.split("\n")) {
            const f = line.split("\t");
            if (f.length < 6 || !f[0])
                continue;
            const categories = f[4].split(";").filter(c => c);
            list.push({
                id: f[0],
                name: f[1],
                desc: f[2],
                icon: f[3],
                tab: tabFor(categories),
                keywords: f[5].replace(/;/g, " ")
            });
        }
        list.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
        apps = list;
    }

    // Apps and actions matching a search and a tab; apps first, then power.
    function search(query, tab) {
        const q = query.trim().toLowerCase();
        return apps.concat(power).filter(a =>
            (tab === "All" || a.tab === tab) &&
            (!q || (a.name + " " + a.desc + " " + a.id + " " + (a.keywords || "")).toLowerCase().indexOf(q) >= 0));
    }

    function launch(item) {
        if (item.power)
            Sway.dispatch(item.command);
        else if (/^[A-Za-z0-9._-]+$/.test(item.id))
            Sway.dispatch("exec btw-launch " + item.id);
    }

    // Reread the list each time the menu opens, so new installs show up.
    function reload() {
        if (!list.running)
            list.running = true;
    }

    Process {
        id: list
        command: ["btw-apps"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
}
