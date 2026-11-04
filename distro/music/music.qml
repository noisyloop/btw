// Music: btw's small music player. Plays the songs in ~/Music (or the files
// and folders it's given), with search, shuffle and repeat. Settings (volume,
// shuffle, repeat) are saved to ~/.config/btw/music.conf.
//
// btw-music opens it (`quickshell -p /usr/share/btw/music/music.qml`) and,
// when it's already open, hands it new files through Quickshell's IPC
// (`quickshell ipc -p ... call music open <paths>`).
//
// Keys: Space play/pause, Enter play the selected song, Up/Down select,
// Left/Right seek 5 s, Ctrl+Left/Right previous/next, / or Ctrl+F search,
// Esc clear the search.
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    settings.watchFiles: false

    readonly property string home: Quickshell.env("HOME")
    readonly property string library: Quickshell.env("BTW_MUSIC_DIR")
        || Quickshell.env("XDG_MUSIC_DIR") || home + "/Music"
    readonly property var extensions: ["mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma", "alac", "aiff", "ape", "mka"]

    // Everything loaded, as file paths, and the indices of those the search
    // lets through (the list on screen).
    property var tracks: []
    property var shown: []
    property int current: -1 // index into tracks
    property var history: [] // played before, for Previous while shuffling
    property string query: ""
    property string status: "" // a short line under the controls
    property bool scanning: false
    property string source: library // what's loaded: the library, or "files"

    // Saved settings.
    property real volume: 0.7
    property bool shuffle: false
    property string repeat: "all" // "off", "all" or "one"

    function title(path) {
        if (!path)
            return "";
        const name = path.slice(path.lastIndexOf("/") + 1);
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.slice(0, dot) : name;
    }
    function folder(path) {
        if (!path)
            return "";
        let dir = path.slice(0, path.lastIndexOf("/"));
        if (dir.startsWith(library + "/"))
            dir = dir.slice(library.length + 1);
        else if (dir === library)
            dir = "";
        else if (dir.startsWith(home + "/"))
            dir = "~" + dir.slice(home.length);
        return dir;
    }
    function clock(ms) {
        if (!(ms > 0))
            return "0:00";
        const s = Math.floor(ms / 1000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    function filter() {
        const q = query.toLowerCase().trim();
        const out = [];
        for (let i = 0; i < tracks.length; i++) {
            if (!q || tracks[i].toLowerCase().indexOf(q) !== -1)
                out.push(i);
        }
        shown = out;
        list.currentIndex = Math.max(0, shown.indexOf(current));
    }
    onQueryChanged: filter()

    // Loads songs: the library (no paths), or files and folders.
    property bool playWhenLoaded: false
    function load(paths, play) {
        const list = paths.length ? paths : [library];
        source = paths.length ? "files" : library;
        playWhenLoaded = play;
        found = [];
        scanning = true;
        status = "Looking for music…";
        const names = [];
        for (const e of extensions)
            names.push("-iname", "*." + e, "-o");
        names.pop();
        scan.command = ["find", "-L", ...list, "-type", "f", "(", ...names, ")"];
        scan.running = true;
    }
    property var found: []
    Process {
        id: scan
        stdout: SplitParser {
            onRead: line => root.found.push(line)
        }
        onExited: (code, exitStatus) => {
            const playing = root.current >= 0 ? root.tracks[root.current] : "";
            root.shown = []; // its indices are into the old list
            root.tracks = root.found.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" }));
            root.found = [];
            root.scanning = false;
            root.history = [];
            root.current = root.tracks.indexOf(playing);
            root.filter();
            if (root.tracks.length === 0)
                root.status = root.source === "files" ? "No music in what was opened."
                    : "No music in " + root.library.replace(root.home, "~") + " yet. Put some there, or drop files here.";
            else
                root.status = "";
            if (root.playWhenLoaded && root.tracks.length)
                root.play(0);
        }
    }

    function play(i) {
        if (i < 0 || i >= tracks.length)
            return;
        if (current >= 0 && current !== i)
            history.push(current);
        current = i;
        status = "";
        player.source = "file://" + tracks[i].split("/").map(encodeURIComponent).join("/");
        player.play();
        list.currentIndex = Math.max(0, shown.indexOf(i));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    function toggle() {
        if (current < 0)
            play(shown.length ? shown[Math.max(0, list.currentIndex)] : 0);
        else if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else
            player.play();
    }
    // The next song in the list on screen, or a random one; -1 at the end.
    function following(wrap) {
        if (!shown.length)
            return -1;
        if (shuffle) {
            if (shown.length === 1)
                return shown[0];
            let pick;
            do
                pick = shown[Math.floor(Math.random() * shown.length)];
            while (pick === current);
            return pick;
        }
        const at = shown.indexOf(current);
        if (at + 1 < shown.length)
            return shown[at + 1];
        return wrap ? shown[0] : -1;
    }
    function next() {
        play(following(true));
    }
    function previous() {
        if (player.position > 3000 || current < 0) {
            player.position = 0;
            return;
        }
        if (shuffle && history.length) {
            const back = history.pop();
            current = -1; // so play() doesn't push the one we're leaving
            play(back);
            return;
        }
        const at = shown.indexOf(current);
        play(shown[at > 0 ? at - 1 : shown.length - 1]);
    }
    function ended() {
        if (repeat === "one") {
            player.position = 0;
            player.play();
            return;
        }
        const n = following(repeat === "all");
        if (n >= 0)
            play(n);
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            volume: root.volume
        }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) root.ended()
        onErrorOccurred: (error, errorString) => {
            root.status = "Can't play " + root.title(root.tracks[root.current] || "") + ": " + errorString;
            skip.restart();
        }
    }
    // After an error, move on rather than stop.
    Timer {
        id: skip
        interval: 1500
        onTriggered: {
            const n = root.following(false);
            if (n >= 0 && n !== root.current)
                root.play(n);
        }
    }

    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState

    // The song's tags. Qt reads a file's own tags, but Ogg and Opus keep them
    // on the audio stream, which Qt doesn't read; ffprobe (from ffmpeg, which
    // Qt Multimedia uses) reads both.
    property var tags: ({})
    onCurrentChanged: {
        tags = {};
        wave = [];
        probe.running = false;
        measure.running = false;
        if (current < 0)
            return;
        const path = tracks[current];
        probe.found = {};
        probe.path = path;
        probe.command = ["ffprobe", "-v", "quiet", "-show_entries", "format_tags:stream_tags",
            "-of", "default=noprint_wrappers=1", path];
        probe.running = true;
        measure.found = [];
        measure.path = path;
        measure.command = ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vn", "-ac", "1", "-af",
            "aresample=8000,asetnsamples=n=400:p=0,astats=metadata=1:reset=1,"
            + "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-", "-f", "null", "-"];
        measure.running = true;
    }

    // The song's waveform: how loud it is every 50 ms, 0 (-60 dB or quieter)
    // to 1 (0 dB), measured by ffmpeg when the song starts. It shows the song
    // moving past the playhead even when there's no sound to hear.
    property var wave: []
    Process {
        id: measure
        property var found: []
        property string path
        stdout: SplitParser {
            onRead: line => {
                const eq = line.indexOf("RMS_level=");
                if (eq < 0)
                    return;
                const db = Number(line.slice(eq + 10));
                measure.found.push(isNaN(db) ? 0 : Math.min(1, Math.max(0, (db + 60) / 60)));
            }
        }
        onExited: (code, exitStatus) => {
            if (path === root.tracks[root.current])
                root.wave = found;
            found = [];
        }
    }
    Process {
        id: probe
        property var found: ({})
        property string path
        stdout: SplitParser {
            onRead: line => {
                const m = /^TAG:([^=]+)=(.*)$/.exec(line);
                if (m && m[2] && !(m[1].toLowerCase() in probe.found))
                    probe.found[m[1].toLowerCase()] = m[2];
            }
        }
        onExited: (code, exitStatus) => {
            if (path === root.tracks[root.current])
                root.tags = found;
        }
    }
    function tag(qt, name) {
        return player.metaData.stringValue(qt) || tags[name] || "";
    }
    readonly property string nowTitle: {
        const t = tag(MediaMetaData.Title, "title");
        return t || (current >= 0 ? title(tracks[current]) : "Nothing playing");
    }
    readonly property string nowBy: {
        const parts = [tag(MediaMetaData.ContributingArtist, "artist") || tag(MediaMetaData.AlbumArtist, "album_artist"),
            tag(MediaMetaData.AlbumTitle, "album")].filter(s => s);
        return parts.length ? parts.join(" · ") : (current >= 0 ? folder(tracks[current]) : "");
    }

    // ~/.config/btw/music.conf: key=value lines.
    FileView {
        id: conf
        path: (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config") + "/btw/music.conf"
        printErrors: false
        onLoaded: {
            for (const line of text().split("\n")) {
                const eq = line.indexOf("=");
                if (eq <= 0)
                    continue;
                const k = line.slice(0, eq).trim(), v = line.slice(eq + 1).trim();
                if (k === "volume" && !isNaN(Number(v)))
                    root.volume = Math.min(1, Math.max(0, Number(v)));
                else if (k === "shuffle")
                    root.shuffle = v === "yes";
                else if (k === "repeat" && ["off", "all", "one"].includes(v))
                    root.repeat = v;
            }
        }
    }
    function save() {
        saveSoon.restart();
    }
    Timer {
        id: saveSoon
        interval: 300
        onTriggered: conf.setText("# btw music player\nvolume=" + root.volume.toFixed(2)
            + "\nshuffle=" + (root.shuffle ? "yes" : "no") + "\nrepeat=" + root.repeat + "\n")
    }

    IpcHandler {
        target: "music"
        // Paths separated by newlines; nothing means the library.
        function open(paths: string): void {
            root.load(paths.split("\n").filter(p => p), true);
            win.raise();
        }
        function toggle(): void { root.toggle(); }
        function next(): void { root.next(); }
        function previous(): void { root.previous(); }
    }
    // Brings the window to the front (Sway focuses it on request).
    Process {
        id: focus
        command: ["swaymsg", "-q", "[title=\"^Music$\"] focus"]
    }

    Component.onCompleted: {
        const opened = (Quickshell.env("BTW_MUSIC_OPEN") || "").split("\n").filter(p => p);
        load(opened, opened.length > 0);
    }

    FloatingWindow {
        id: win
        title: "Music"
        visible: true
        color: Theme.background
        implicitWidth: 480
        implicitHeight: 640
        minimumSize: Qt.size(340, 380)
        onVisibleChanged: if (!visible) Qt.quit()
        function raise() {
            focus.running = true;
        }

        component Label: Text {
            color: Theme.foreground
            font.family: Theme.sans
            font.pixelSize: 14
            elide: Text.ElideRight
        }

        // A round button with a text glyph, or a drawn icon: play, pause,
        // previous, next. Those are drawn because fonts show ⏮ ⏸ ⏭ as emoji.
        component Button: Rectangle {
            id: button
            property string glyph
            property string icon
            property bool on: false
            property bool big: false
            signal clicked
            implicitWidth: big ? 52 : 36
            implicitHeight: implicitWidth
            radius: width / 2
            color: big ? Theme.accent : press.containsMouse ? Theme.raised : "transparent"
            border.color: big ? Theme.accent : on ? Theme.accent : Theme.line
            readonly property color ink: big ? Theme.background : on ? Theme.accent : Theme.foreground
            Text {
                anchors.centerIn: parent
                visible: button.icon === ""
                text: button.glyph
                color: button.ink
                font.family: Theme.font
                font.pixelSize: button.big ? 20 : 14
                font.bold: button.big || button.on
            }
            Canvas {
                id: drawn
                anchors.centerIn: parent
                width: button.big ? 20 : 14
                height: width
                visible: button.icon !== ""
                onPaint: {
                    const c = getContext("2d"), w = width, h = height;
                    c.reset();
                    c.fillStyle = button.ink;
                    const tri = (x0, x1) => { // pointing from x0 to x1
                        c.beginPath();
                        c.moveTo(x0, 0);
                        c.lineTo(x1, h / 2);
                        c.lineTo(x0, h);
                        c.closePath();
                        c.fill();
                    };
                    if (button.icon === "play")
                        tri(w * 0.15, w);
                    else if (button.icon === "pause") {
                        c.fillRect(w * 0.12, 0, w * 0.28, h);
                        c.fillRect(w * 0.6, 0, w * 0.28, h);
                    } else if (button.icon === "next") {
                        tri(0, w * 0.8);
                        c.fillRect(w * 0.8, 0, w * 0.2, h);
                    } else if (button.icon === "previous") {
                        c.fillRect(0, 0, w * 0.2, h);
                        tri(w, w * 0.2);
                    }
                }
                Connections {
                    target: button
                    function onIconChanged() { drawn.requestPaint(); }
                    function onInkChanged() { drawn.requestPaint(); }
                }
            }
            MouseArea {
                id: press
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: button.clicked()
            }
        }

        // A slider in the theme (as in Fractals): a line, a mint fill, a handle.
        component Bar: Item {
            id: bar
            property real value: 0 // 0-1
            signal moved(real value)
            implicitHeight: 20
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Theme.line
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * bar.value
                height: 4
                radius: 2
                color: Theme.accent
            }
            Rectangle {
                x: bar.value * (parent.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 7
                color: Theme.foreground
                border.color: Theme.accent
                border.width: drag.pressed ? 4 : 2
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                function set(x) {
                    bar.moved(Math.min(1, Math.max(0, (x - 6) / bar.width)));
                }
                onPressed: e => set(e.x)
                onPositionChanged: e => { if (pressed) set(e.x); }
                onWheel: e => bar.moved(Math.min(1, Math.max(0, bar.value + (e.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                if (e.key === Qt.Key_Space && !search.activeFocus) root.toggle();
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (root.shown.length) root.play(root.shown[Math.max(0, list.currentIndex)]);
                } else if (e.key === Qt.Key_Down) list.incrementCurrentIndex();
                else if (e.key === Qt.Key_Up) list.decrementCurrentIndex();
                else if (e.key === Qt.Key_Right && ctrl) root.next();
                else if (e.key === Qt.Key_Left && ctrl) root.previous();
                else if (e.key === Qt.Key_Right && !search.activeFocus) player.position = Math.min(player.duration, player.position + 5000);
                else if (e.key === Qt.Key_Left && !search.activeFocus) player.position = Math.max(0, player.position - 5000);
                else if (e.key === Qt.Key_Slash || (e.key === Qt.Key_F && ctrl)) search.forceActiveFocus();
                else if (e.key === Qt.Key_Escape) { search.text = ""; parent.forceActiveFocus(); }
                else return;
                e.accepted = true;
            }

            // Files and folders dropped from a file manager.
            DropArea {
                anchors.fill: parent
                onDropped: drop => {
                    const paths = drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, "")));
                    if (paths.length) root.load(paths, true);
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                // Now playing.
                Label {
                    Layout.fillWidth: true
                    text: root.nowTitle
                    font.pixelSize: 20
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
                    text: root.nowBy
                    color: Theme.muted
                    font.pixelSize: 13
                    visible: text !== ""
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: root.clock(player.position)
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    // The waveform, which is also the seek bar; a plain bar
                    // until it's measured (or if it can't be).
                    Item {
                        id: waveform
                        Layout.fillWidth: true
                        implicitHeight: root.wave.length ? 48 : 20
                        readonly property real progress: player.duration > 0 ? player.position / player.duration : 0
                        readonly property bool measured: root.wave.length > 0
                        Accessible.role: Accessible.Slider
                        Accessible.name: "Position " + root.clock(player.position) + " of " + root.clock(player.duration)

                        // The loudest moment in each bar's stretch of the song.
                        readonly property var bars: {
                            const n = Math.max(1, Math.floor(width / 3)), w = root.wave, out = [];
                            for (let i = 0; i < n; i++) {
                                const a = Math.floor(i * w.length / n), b = Math.max(a + 1, Math.floor((i + 1) * w.length / n));
                                let m = 0;
                                for (let j = a; j < b && j < w.length; j++)
                                    m = Math.max(m, w[j]);
                                out.push(m);
                            }
                            return out;
                        }
                        component Bars: Canvas {
                            property color ink
                            width: waveform.width
                            height: waveform.height
                            onPaint: {
                                const c = getContext("2d");
                                c.reset();
                                c.fillStyle = ink;
                                const bars = waveform.bars;
                                for (let i = 0; i < bars.length; i++) {
                                    const h = Math.max(2, bars[i] * height);
                                    c.fillRect(i * 3, (height - h) / 2, 2, h);
                                }
                            }
                            Connections {
                                target: waveform
                                function onBarsChanged() { requestPaint(); }
                            }
                        }
                        Bars {
                            visible: waveform.measured
                            ink: Theme.line
                        }
                        // The part already played, in mint.
                        Item {
                            visible: waveform.measured
                            width: waveform.width * waveform.progress
                            height: waveform.height
                            clip: true
                            Bars {
                                ink: Theme.accent
                            }
                        }
                        Rectangle {
                            visible: waveform.measured
                            x: Math.min(waveform.width - width, waveform.width * waveform.progress)
                            width: 2
                            height: waveform.height
                            color: Theme.foreground
                        }
                        Bar {
                            visible: !waveform.measured
                            anchors.fill: parent
                            value: waveform.progress
                            onMoved: v => { if (player.seekable) player.position = v * player.duration; }
                        }
                        MouseArea {
                            visible: waveform.measured
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function seek(x) {
                                if (player.seekable)
                                    player.position = Math.min(1, Math.max(0, x / width)) * player.duration;
                            }
                            onPressed: e => seek(e.x)
                            onPositionChanged: e => { if (pressed) seek(e.x); }
                        }
                    }
                    Text {
                        text: root.clock(player.duration)
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button {
                        glyph: "⤮"
                        on: root.shuffle
                        onClicked: { root.shuffle = !root.shuffle; root.save(); }
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        icon: "previous"
                        onClicked: root.previous()
                    }
                    Button {
                        big: true
                        icon: root.playing ? "pause" : "play"
                        onClicked: root.toggle()
                    }
                    Button {
                        icon: "next"
                        onClicked: root.next()
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        glyph: root.repeat === "one" ? "↻1" : "↻"
                        on: root.repeat !== "off"
                        onClicked: {
                            root.repeat = { off: "all", all: "one", one: "off" }[root.repeat];
                            root.save();
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: "vol"
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Bar {
                        Layout.fillWidth: true
                        value: root.volume
                        onMoved: v => { root.volume = v; root.save(); }
                    }
                    Text {
                        text: Math.round(root.volume * 100)
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                        Layout.preferredWidth: 26
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.status
                    color: Theme.amber
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    visible: text !== ""
                }

                // Search.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    color: Theme.surface
                    border.color: search.activeFocus ? Theme.accent : Theme.line
                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.foreground
                        selectionColor: Theme.accent
                        font.family: Theme.sans
                        font.pixelSize: 14
                        clip: true
                        onTextChanged: root.query = text
                        Keys.onReturnPressed: { if (root.shown.length) root.play(root.shown[Math.max(0, list.currentIndex)]); }
                        Keys.onDownPressed: list.incrementCurrentIndex()
                        Keys.onUpPressed: list.decrementCurrentIndex()
                        Keys.onEscapePressed: { text = ""; parent.parent.parent.forceActiveFocus(); }
                    }
                    Text {
                        anchors.fill: search
                        verticalAlignment: Text.AlignVCenter
                        text: root.scanning ? "Looking for music…"
                            : "Search " + root.tracks.length + (root.tracks.length === 1 ? " song" : " songs")
                            + (root.source === "files" ? "" : " in " + root.library.replace(root.home, "~"))
                        color: Theme.muted
                        font: search.font
                        visible: search.text === ""
                        elide: Text.ElideRight
                    }
                }

                // The songs.
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.shown
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    delegate: Rectangle {
                        id: row
                        required property int modelData
                        required property int index
                        readonly property bool isCurrent: modelData === root.current
                        width: list.width
                        height: 44
                        color: ListView.isCurrentItem ? Theme.raised : hover.containsMouse ? Theme.surface : "transparent"
                        Rectangle {
                            width: 3
                            height: parent.height
                            color: Theme.accent
                            visible: row.isCurrent
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                width: parent.width
                                text: (row.isCurrent && root.playing ? "▶ " : "") + root.title(root.tracks[row.modelData])
                                color: row.isCurrent ? Theme.accent : Theme.foreground
                                font.bold: row.isCurrent
                            }
                            Label {
                                width: parent.width
                                text: root.folder(root.tracks[row.modelData])
                                color: Theme.muted
                                font.pixelSize: 12
                                visible: text !== ""
                            }
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: list.currentIndex = row.index
                            onDoubleClicked: root.play(row.modelData)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Double-click to play · Space pause · / search · drop files here"
                    color: Theme.muted
                    font.family: Theme.sans
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
