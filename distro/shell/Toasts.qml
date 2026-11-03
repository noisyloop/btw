// Notification cards in the top-right corner, under the bar, styled like the
// mako config they replace. Hovering a card pauses its timer; clicking it runs
// the app's default action; × closes it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

PanelWindow {
    id: win

    visible: Notifications.popups.length > 0
    anchors {
        top: true
        right: true
    }
    margins {
        top: 10
        right: 10
    }
    // Sit below the bar without pushing windows aside.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "btw-notifications"
    color: "transparent"
    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight)

    component Label: Text {
        color: Theme.foreground
        font.family: Theme.sans
        font.pixelSize: 13
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        id: stack
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifications.popups
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var n: modelData
                readonly property bool critical: n.urgency === NotificationUrgency.Critical
                readonly property string icon: {
                    if (n.image)
                        return n.image;
                    if (!n.appIcon)
                        return "";
                    if (n.appIcon.startsWith("/") || n.appIcon.indexOf("://") > 0)
                        return n.appIcon.startsWith("/") ? "file://" + n.appIcon : n.appIcon;
                    return Quickshell.iconPath(n.appIcon, true);
                }

                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 24
                radius: 10
                color: Qt.rgba(0.055, 0.071, 0.063, 0.94)
                border.width: 2
                border.color: critical ? Theme.amber : Theme.accent

                Timer {
                    interval: Notifications.timeoutFor(card.n)
                    running: interval > 0 && !hover.containsMouse
                    onTriggered: card.n.expire()
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.activate(card.n)
                }

                RowLayout {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 12

                    Image {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        visible: card.icon !== "" && status !== Image.Error
                        source: card.icon
                        sourceSize.width: 72
                        sourceSize.height: 72
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: card.n.appName || "btw"
                                color: card.critical ? Theme.amber : Theme.muted
                                font.family: Theme.font
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                            Label {
                                text: "×"
                                color: closeArea.containsMouse ? Theme.foreground : Theme.muted
                                font.pixelSize: 16
                                MouseArea {
                                    id: closeArea
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: card.n.dismiss()
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: card.n.summary
                            font.weight: Font.DemiBold
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.n.body
                            textFormat: Text.StyledText
                            color: Qt.rgba(0.906, 0.937, 0.914, 0.85)
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        // Buttons for the app's actions, other than the default one.
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6
                            visible: actions.count > 0
                            Repeater {
                                id: actions
                                model: Notifications.actionsOf(card.n).filter(a => a.identifier !== "default" && a.text)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: actionLabel.implicitWidth + 20
                                    height: 26
                                    radius: 13
                                    color: actionArea.containsMouse ? Qt.rgba(0.24, 0.86, 0.59, 0.12) : "transparent"
                                    border.color: Theme.line
                                    Label {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: modelData.text
                                        font.pixelSize: 12
                                        wrapMode: Text.NoWrap
                                    }
                                    MouseArea {
                                        id: actionArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.invoke()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
