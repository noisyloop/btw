// The btw top bar: menu button and workspaces on the left, the focused
// window's title in the middle, status and clock on the right. It matches the
// waybar layout so the two can be compared side by side.
import QtQuick
import QtQuick.Layouts
import Quickshell

PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.barBackground

    component Label: Text {
        color: Theme.foreground
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        verticalAlignment: Text.AlignVCenter
    }

    // Bottom border, like waybar's border-bottom.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.line
    }

    RowLayout {
        id: left
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Label {
            text: "▲ btw"
            color: Theme.accent
            font.bold: true
            Layout.fillHeight: true
            leftPadding: 12
            rightPadding: 12
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: AppMenu.toggle()
            }
        }

        Repeater {
            model: Sway.workspaces
            // Flat square tabs, like waybar's: the current one lit in mint
            // with a bar underneath.
            delegate: Rectangle {
                id: tab
                required property var modelData
                readonly property color mark: modelData.focused ? Theme.accent : modelData.urgent ? Theme.amber : "transparent"
                Layout.fillHeight: true
                Layout.preferredWidth: Math.max(Theme.barHeight, name.implicitWidth + 20)
                color: modelData.focused ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                     : hover.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08) : "transparent"

                Label {
                    id: name
                    anchors.centerIn: parent
                    text: tab.modelData.name
                    font.bold: tab.modelData.focused
                    color: tab.modelData.focused ? Theme.accent : tab.modelData.urgent ? Theme.amber
                         : hover.containsMouse ? Theme.foreground : Theme.muted
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    color: tab.mark
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Sway.focusWorkspace(tab.modelData.num)
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        // Stay clear of both sides, however long the title is.
        width: Math.min(implicitWidth, parent.width - 2 * Math.max(left.width, right.width) - 24)
        text: Sway.title
        color: Theme.muted
        elide: Text.ElideRight
    }

    RowLayout {
        id: right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Label {
            text: "cpu " + Stats.cpu + "%"
            leftPadding: 8
            rightPadding: 8
        }
        Label {
            text: "mem " + Stats.memUsedGiB.toFixed(1) + "G"
            leftPadding: 8
            rightPadding: 8
        }
        Label {
            text: Stats.online ? "wired" : "offline"
            leftPadding: 8
            rightPadding: 8
        }
        Label {
            id: clock
            color: Theme.amber
            leftPadding: 12
            rightPadding: 12
            text: Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm")
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm")
            }
        }
    }
}
