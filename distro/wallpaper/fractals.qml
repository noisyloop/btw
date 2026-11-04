// Fractals: btw's wallpaper app. Live previews of each fractal to pick from,
// sliders for hue, glow and motion, and a switch between the live wallpaper
// and the still picture. Every change is saved to ~/.config/btw/wallpaper.conf
// (Settings.qml), which the wallpaper watches, so it changes as you drag.
//
// btw-fractals opens it (`quickshell -n -p /usr/share/btw/wallpaper/fractals.qml`).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    Settings {
        id: settings
    }

    // Saving on every slider step would rewrite the file dozens of times a
    // second; save shortly after the last change instead.
    Timer {
        id: saveSoon
        interval: 120
        onTriggered: settings.save()
    }

    // Switching between live and still starts a different program.
    Process {
        id: restart
        command: ["btw-wallpaper", "start"]
    }

    function setMode(mode) {
        if (settings.mode === mode)
            return;
        settings.mode = mode;
        settings.save();
        restartSoon.restart();
    }
    Timer {
        id: restartSoon
        interval: 200
        onTriggered: restart.running = true
    }

    // The previews' own clock, so they move even when the wallpaper is still.
    property real clock: 8
    Timer {
        interval: 50
        running: win.visible
        repeat: true
        onTriggered: root.clock += 0.05 * Math.max(settings.speed, 0.4)
    }

    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software

    FloatingWindow {
        id: win
        title: "Fractals"
        visible: true
        color: Theme.background
        implicitWidth: 640
        implicitHeight: 600
        minimumSize: Qt.size(320, 260)
        onVisibleChanged: if (!visible) Qt.quit()

        component Label: Text {
            color: Theme.foreground
            font.family: Theme.sans
            font.pixelSize: 14
            wrapMode: Text.Wrap
        }

        // A slider in the theme: a line, a mint fill and a round handle.
        component Dial: Item {
            id: dial
            property string label
            property real from: 0
            property real to: 1
            property real value: 0
            property string shown: value.toFixed(2)
            signal moved(real value)
            Layout.fillWidth: true
            implicitHeight: 34

            Label {
                id: name
                width: 70
                anchors.verticalCenter: parent.verticalCenter
                text: dial.label
                color: Theme.muted
                font.pixelSize: 13
            }
            Item {
                id: track
                anchors.left: name.right
                anchors.right: out.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 20
                readonly property real frac: (dial.value - dial.from) / (dial.to - dial.from)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.line
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * track.frac
                    height: 4
                    radius: 2
                    color: Theme.accent
                }
                Rectangle {
                    x: track.frac * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
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
                        const f = Math.min(1, Math.max(0, (x - 6) / (track.width)));
                        dial.moved(dial.from + f * (dial.to - dial.from));
                    }
                    onPressed: e => set(e.x)
                    onPositionChanged: e => { if (pressed) set(e.x); }
                    onWheel: e => dial.moved(Math.min(dial.to, Math.max(dial.from,
                        dial.value + (e.angleDelta.y > 0 ? 1 : -1) * (dial.to - dial.from) / 40)))
                }
            }
            Text {
                id: out
                width: 44
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: dial.shown
                color: Theme.foreground
                font.family: Theme.font
                font.pixelSize: 13
            }
        }

        // A two-way switch: Live | Still.
        component Choice: Rectangle {
            id: choice
            property string text
            property bool on: false
            signal picked
            implicitWidth: choiceLabel.implicitWidth + 28
            implicitHeight: 30
            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : "transparent"
            border.color: on ? Theme.accent : Theme.line
            Text {
                id: choiceLabel
                anchors.centerIn: parent
                text: choice.text
                color: choice.on ? Theme.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: 13
                font.bold: choice.on
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: choice.picked()
            }
        }

        Flickable {
            id: page
            anchors.fill: parent
            contentHeight: column.implicitHeight + 40
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: column
                x: 20
                y: 20
                width: page.width - 40
                spacing: 14

                // Title
                RowLayout {
                    spacing: 10
                    Label {
                        text: "▲"
                        color: Theme.accent
                        font.pixelSize: 20
                    }
                    Label {
                        text: "Fractals"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: root.shaders
                        ? "Your wallpaper is a live, raymarched 3D fractal. Pick one and tune it; the wallpaper follows as you go."
                        : "This display has no GPU to draw fractals with, so the wallpaper is the still picture."
                    color: Theme.muted
                    font.pixelSize: 13
                }

                // The fractals, each with a live preview.
                GridLayout {
                    Layout.fillWidth: true
                    columns: Math.max(1, Math.min(4, Math.floor(column.width / 150)))
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: settings.fractals
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool on: settings.fractal === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: preview.height + text.implicitHeight + 22
                            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08) : Theme.surface
                            border.color: on ? Theme.accent : hover.containsMouse ? Theme.muted : Theme.line
                            border.width: on ? 2 : 1

                            Rectangle {
                                id: preview
                                x: 6
                                y: 6
                                width: parent.width - 12
                                height: Math.round(width * 0.62)
                                color: "#0a0d0c"
                                clip: true

                                ShaderEffect {
                                    anchors.fill: parent
                                    visible: root.shaders
                                    property vector2d res: Qt.vector2d(width, height)
                                    property real time: root.clock
                                    property real hue: settings.hue
                                    property real glow: settings.glow
                                    property real dist: card.modelData.dist
                                    fragmentShader: settings.shader(card.modelData.id)
                                    // Small previews: render at most 200 pixels wide.
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.textureSize: Qt.size(Math.min(width, 200), Math.min(width, 200) * height / Math.max(1, width))
                                }
                                Text {
                                    visible: !root.shaders
                                    anchors.centerIn: parent
                                    text: "▲"
                                    color: Theme.line
                                    font.pixelSize: 36
                                }
                            }
                            ColumnLayout {
                                id: text
                                anchors.top: preview.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 8
                                anchors.topMargin: 7
                                spacing: 2
                                Label {
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    color: card.on ? Theme.accent : Theme.foreground
                                    font.family: Theme.font
                                    font.bold: true
                                    font.pixelSize: 13
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: card.modelData.blurb
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    settings.fractal = card.modelData.id;
                                    settings.save();
                                    // Picking a fractal means wanting to see it move.
                                    if (root.shaders)
                                        root.setMode("live");
                                }
                            }
                        }
                    }
                }

                // Tuning
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 0
                    Dial {
                        label: "Hue"
                        value: settings.hue
                        onMoved: v => { settings.hue = v; saveSoon.restart(); }
                    }
                    Dial {
                        label: "Glow"
                        from: 0.4
                        to: 2
                        value: settings.glow
                        onMoved: v => { settings.glow = v; saveSoon.restart(); }
                    }
                    Dial {
                        label: "Motion"
                        from: 0
                        to: 3
                        value: settings.speed
                        shown: settings.speed < 0.02 ? "still" : settings.speed.toFixed(2) + "×"
                        onMoved: v => { settings.speed = v < 0.05 ? 0 : v; saveSoon.restart(); }
                    }
                }

                // Live or still, and reset
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: "Wallpaper"
                        color: Theme.muted
                        font.pixelSize: 13
                        Layout.preferredWidth: 82
                    }
                    Choice {
                        text: "Live"
                        on: settings.mode === "live"
                        visible: root.shaders
                        onPicked: root.setMode("live")
                    }
                    Choice {
                        text: "Still"
                        on: settings.mode === "still" || !root.shaders
                        onPicked: root.setMode("still")
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Choice {
                        text: "Reset"
                        onPicked: settings.reset()
                    }
                }
            }
        }
    }
}
