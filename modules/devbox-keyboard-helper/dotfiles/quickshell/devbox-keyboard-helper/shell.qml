import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var shortcuts: []
    property string searchText: ""
    readonly property var visibleShortcuts: {
        const needle = searchText.trim().toLocaleLowerCase();
        if (!needle)
            return shortcuts;

        return shortcuts.filter((entry) => {
            return (entry.keys + " " + entry.label + " " + entry.category).toLocaleLowerCase().includes(needle);
        });
    }

    FileView {
        id: shortcutData

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/devbox-keyboard-shortcuts.json"
        blockLoading: true
        onLoaded: {
            try {
                root.shortcuts = JSON.parse(text()).shortcuts || [];
            } catch (error) {
                root.shortcuts = [];
                console.warn("Could not read the shortcut list:", error);
            }
        }
    }

    IpcHandler {
        target: "keyboard-shortcuts"

        function close() {
            Qt.quit();
        }
    }

    FloatingWindow {
        id: window

        title: "Keyboard shortcuts"
        visible: true
        implicitWidth: 1040
        implicitHeight: 720
        minimumSize: Qt.size(720, 480)
        color: "#11151d"
        onClosed: Qt.quit()
        Component.onCompleted: search.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: "#11151d"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Keyboard shortcuts"
                            color: "#f2f4f8"
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.shortcuts.length + " global shortcuts configured in Plasma"
                            color: "#9ba7b8"
                            font.pixelSize: 13
                        }

                    }

                    TextField {
                        id: search

                        Layout.preferredWidth: 300
                        placeholderText: "Search shortcuts…"
                        selectByMouse: true
                        onTextChanged: root.searchText = text
                        Keys.onEscapePressed: window.close()
                    }

                    Button {
                        text: "Close"
                        onClicked: window.close()
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#2b3442"
                }

                ScrollView {
                    id: scroll

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    GridLayout {
                        id: grid

                        width: scroll.availableWidth
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 10

                        Repeater {
                            model: root.visibleShortcuts

                            delegate: Rectangle {
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: content.implicitHeight + 24
                                radius: 10
                                color: "#1a2230"
                                border.width: 1
                                border.color: "#293548"

                                ColumnLayout {
                                    id: content

                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            color: "#e8edf5"
                                            font.pixelSize: 14
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.category
                                            color: "#8fa0b7"
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }

                                    }

                                    Text {
                                        text: modelData.keys
                                        color: "#8ed4ff"
                                        font.family: "monospace"
                                        font.pixelSize: 13
                                        wrapMode: Text.Wrap
                                    }

                                }

                            }

                        }

                        Text {
                            visible: root.visibleShortcuts.length === 0
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            text: root.shortcuts.length === 0 ? "No active shortcuts were found in Plasma’s global shortcut settings." : "No shortcuts match this search."
                            color: "#9ba7b8"
                            font.pixelSize: 15
                            horizontalAlignment: Text.AlignHCenter
                            padding: 40
                        }

                    }

                }

                Text {
                    Layout.fillWidth: true
                    text: "Esc closes this window"
                    color: "#748197"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignRight
                }

            }

        }

    }

}
