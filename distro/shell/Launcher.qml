// The btw app menu: search, tabs, and a list of apps and power actions, laid
// out like the browser preview's launcher (desktop/). Keys: type to search,
// Up/Down to choose, Enter to open, Tab/Shift+Tab to change tab, Esc to close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    visible: AppMenu.open
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "btw-menu"
    color: Qt.rgba(0.016, 0.02, 0.024, 0.42)

    property string tab: "All"
    property int selected: 0
    readonly property var results: Apps.search(search.text, tab)
    // Results with "Apps" and "Power" headings between them when both show.
    readonly property var rows: {
        const out = [];
        let section = "";
        const headings = tab === "All" || search.text.trim() !== "";
        results.forEach((item, i) => {
            const group = item.power ? "Power" : "Apps";
            if (headings && group !== section) {
                section = group;
                out.push({ heading: group });
            }
            out.push({ item: item, index: i });
        });
        return out;
    }

    onResultsChanged: selected = Math.min(selected, Math.max(0, results.length - 1))
    onVisibleChanged: {
        if (!visible)
            return;
        Apps.reload();
        search.text = "";
        tab = "All";
        selected = 0;
        search.forceActiveFocus();
    }

    function close() {
        AppMenu.open = false;
    }

    function open(item) {
        close();
        Apps.launch(item);
    }

    function moveTab(step) {
        const names = Apps.tabs.map(t => t.name);
        tab = names[(names.indexOf(tab) + step + names.length) % names.length];
        selected = 0;
    }

    component Label: Text {
        color: Theme.foreground
        font.family: Theme.sans
        font.pixelSize: 14
    }

    // Clicking outside the menu closes it.
    MouseArea {
        anchors.fill: parent
        onClicked: win.close()
    }

    Rectangle {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.12)
        width: Math.min(620, parent.width - 32)
        height: Math.min(column.implicitHeight, parent.height * 0.74)
        radius: 14
        color: Qt.rgba(0.055, 0.071, 0.063, 0.97)
        border.color: Theme.accent
        border.width: 2
        clip: true

        // Swallow clicks so they don't reach the backdrop.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 2
            spacing: 0

            // Search
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                Layout.leftMargin: 16
                spacing: 10

                Label {
                    text: "▲"
                    color: Theme.accent
                    font.pixelSize: 18
                }
                TextInput {
                    id: search
                    Layout.fillWidth: true
                    color: Theme.foreground
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.background
                    font.family: Theme.sans
                    font.pixelSize: 17
                    focus: true
                    clip: true
                    onTextChanged: win.selected = 0

                    Label {
                        visible: !search.text
                        text: "Search apps and actions…"
                        color: Theme.muted
                        font.pixelSize: 17
                    }

                    Keys.onPressed: event => {
                        const n = win.results.length;
                        if (event.key === Qt.Key_Escape) {
                            win.close();
                        } else if (event.key === Qt.Key_Down) {
                            if (n) win.selected = (win.selected + 1) % n;
                        } else if (event.key === Qt.Key_Up) {
                            if (n) win.selected = (win.selected + n - 1) % n;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (n) win.open(win.results[win.selected]);
                        } else if (event.key === Qt.Key_Tab) {
                            win.moveTab(1);
                        } else if (event.key === Qt.Key_Backtab) {
                            win.moveTab(-1);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.line
            }

            // Tabs
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 4
                spacing: 6

                Repeater {
                    model: Apps.tabs
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: win.tab === modelData.name
                        width: tabLabel.implicitWidth + 22
                        height: 26
                        radius: 13
                        color: on ? Qt.rgba(0.24, 0.86, 0.59, 0.12) : "transparent"
                        border.color: on ? Theme.accent : Theme.line
                        Label {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData.name
                            color: parent.on ? Theme.accent : Theme.muted
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                win.tab = modelData.name;
                                win.selected = 0;
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Results
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 8
                implicitHeight: Math.max(contentHeight, empty.visible ? 72 : 0)
                Layout.preferredHeight: implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.rows
                currentIndex: win.rows.findIndex(r => r.item && r.index === win.selected)
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property var item: modelData.item
                    readonly property bool current: item !== undefined && modelData.index === win.selected
                    width: list.width
                    height: item ? 52 : 28

                    Label {
                        visible: !row.item
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: (row.modelData.heading || "").toUpperCase()
                        color: Theme.muted
                        font.pixelSize: 11
                        font.letterSpacing: 0.9
                    }

                    Rectangle {
                        visible: !!row.item
                        anchors.fill: parent
                        radius: 9
                        color: row.current ? Qt.rgba(0.24, 0.86, 0.59, 0.13) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            // The app's icon, or its first letter in a tile.
                            Rectangle {
                                implicitWidth: 36
                                implicitHeight: 36
                                radius: 9
                                color: Theme.raised
                                border.color: row.current ? Theme.accent : Theme.line
                                readonly property string iconPath: row.item && row.item.icon
                                    ? Quickshell.iconPath(row.item.icon, true) : ""
                                Image {
                                    anchors.centerIn: parent
                                    visible: parent.iconPath !== ""
                                    source: parent.iconPath
                                    sourceSize.width: 24
                                    sourceSize.height: 24
                                    width: 24
                                    height: 24
                                    asynchronous: true
                                }
                                Label {
                                    anchors.centerIn: parent
                                    visible: parent.iconPath === ""
                                    text: row.item ? (row.item.power ? "⏻" : row.item.name.charAt(0).toUpperCase()) : ""
                                    color: row.item && row.item.power ? Theme.amber : Theme.accent
                                    font.family: Theme.font
                                    font.bold: true
                                    font.pixelSize: 16
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Label {
                                    Layout.fillWidth: true
                                    text: row.item ? row.item.name : ""
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: row.item ? row.item.desc : ""
                                    color: Theme.muted
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: win.selected = row.modelData.index
                            onClicked: win.open(row.item)
                        }
                    }
                }

                Label {
                    id: empty
                    visible: win.results.length === 0
                    anchors.centerIn: parent
                    text: Apps.apps.length || search.text ? "Nothing matches “" + search.text + "”." : "Loading apps…"
                    color: Theme.muted
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.line
            }

            // Key hints
            Flow {
                Layout.fillWidth: true
                Layout.margins: 9
                Layout.leftMargin: 16
                spacing: 16
                Repeater {
                    model: [["↑↓", "choose"], ["Enter", "open"], ["Tab", "next tab"], ["Esc", "close"], ["Super+Enter", "terminal"]]
                    delegate: Label {
                        required property var modelData
                        textFormat: Text.StyledText
                        text: "<font color='" + Theme.foreground + "'>" + modelData[0] + "</font> " + modelData[1]
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
