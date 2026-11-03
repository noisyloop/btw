pragma Singleton
// What the shell needs from the compositor, read from Sway over swaymsg.
// Everything else in the shell goes through these properties and functions,
// so a Niri.qml with the same ones can replace this file later.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Workspaces 1-5 always show, like waybar's persistent-workspaces.
    readonly property var persistent: [1, 2, 3, 4, 5]

    // [{ num, name, focused, urgent }] sorted by number.
    property var workspaces: persistent.map(n => ({ num: n, name: String(n), focused: n === 1, urgent: false }))
    // Title of the focused window, or "" on an empty workspace.
    property string title: ""

    // Runs a Sway command, e.g. "workspace number 2" or "exec fuzzel".
    function dispatch(command) {
        const p = runner.createObject(root, { command: ["swaymsg", command] });
        p.running = true;
    }

    function focusWorkspace(num) {
        dispatch("workspace number " + num);
    }

    // A short-lived process for each command, removed once it exits.
    Component {
        id: runner
        Process {
            onExited: destroy()
        }
    }

    // --- reading state ----------------------------------------------------

    function parseWorkspaces(text) {
        let list;
        try {
            list = JSON.parse(text);
        } catch (e) {
            return;
        }
        const byNum = {};
        for (const n of persistent)
            byNum[n] = { num: n, name: String(n), focused: false, urgent: false };
        for (const ws of list) {
            const num = ws.num >= 0 ? ws.num : 1000 + Object.keys(byNum).length;
            byNum[num] = { num: num, name: ws.name, focused: ws.focused, urgent: ws.urgent };
        }
        workspaces = Object.values(byNum).sort((a, b) => a.num - b.num);
    }

    function focusedName(node) {
        if (node.focused)
            // Only windows have titles; a focused workspace or output is empty.
            return node.type === "con" || node.type === "floating_con" ? (node.name || "") : "";
        for (const child of (node.nodes || []).concat(node.floating_nodes || [])) {
            const name = focusedName(child);
            if (name !== null)
                return name;
        }
        return null;
    }

    function parseTree(text) {
        let tree;
        try {
            tree = JSON.parse(text);
        } catch (e) {
            return;
        }
        title = focusedName(tree) || "";
    }

    function refresh() {
        if (!getWorkspaces.running)
            getWorkspaces.running = true;
        if (!getTree.running)
            getTree.running = true;
    }

    Process {
        id: getWorkspaces
        command: ["swaymsg", "-r", "-t", "get_workspaces"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseWorkspaces(text)
        }
    }

    Process {
        id: getTree
        command: ["swaymsg", "-r", "-t", "get_tree"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseTree(text)
        }
    }

    // Sway prints an event whenever workspaces or windows change. The events
    // span several lines, so any output just schedules a fresh read.
    Process {
        id: events
        command: ["swaymsg", "-m", "-r", "-t", "subscribe", "[\"workspace\", \"window\"]"]
        running: true
        stdout: SplitParser {
            onRead: data => debounce.restart()
        }
        // If swaymsg drops out (Sway restarting), reconnect.
        onExited: reconnect.start()
    }

    Timer {
        id: debounce
        interval: 40
        onTriggered: root.refresh()
    }

    Timer {
        id: reconnect
        interval: 1000
        onTriggered: {
            events.running = true;
            root.refresh();
        }
    }
}
