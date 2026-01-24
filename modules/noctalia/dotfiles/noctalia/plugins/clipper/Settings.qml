import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    // ToDo integration
    property bool todoPluginAvailable: false
    property bool enableTodoIntegration: false

    // Available card types
    readonly property var cardTypes: [
        { key: "Text", name: "Text" },
        { key: "Image", name: "Image" },
        { key: "Link", name: "Link" },
        { key: "Code", name: "Code" },
        { key: "Color", name: "Color" },
        { key: "Emoji", name: "Emoji" },
        { key: "File", name: "File" }
    ]

    // Available colors from Color scheme
    readonly property var colorOptions: [
        { key: "mPrimary", name: "Primary" },
        { key: "mOnPrimary", name: "On Primary" },
        { key: "mSecondary", name: "Secondary" },
        { key: "mOnSecondary", name: "On Secondary" },
        { key: "mTertiary", name: "Tertiary" },
        { key: "mOnTertiary", name: "On Tertiary" },
        { key: "mSurface", name: "Surface" },
        { key: "mOnSurface", name: "On Surface" },
        { key: "mSurfaceVariant", name: "Surface Variant" },
        { key: "mOnSurfaceVariant", name: "On Surface Variant" },
        { key: "mOutline", name: "Outline" },
        { key: "mError", name: "Error" },
        { key: "mOnError", name: "On Error" },
        { key: "mHover", name: "Hover" },
        { key: "mOnHover", name: "On Hover" },
        { key: "custom", name: "Custom..." }
    ]

    // Currently selected card type for editing
    property string selectedCardType: "Text"

    // Default colors per card type
    readonly property var defaultCardColors: {
        "Text": { bg: "mOutline", separator: "mSurface", fg: "mOnSurface" },
        "Image": { bg: "mTertiary", separator: "mSurface", fg: "mOnTertiary" },
        "Link": { bg: "mPrimary", separator: "mSurface", fg: "mOnPrimary" },
        "Code": { bg: "mSecondary", separator: "mSurface", fg: "mOnSecondary" },
        "Color": { bg: "mSecondary", separator: "mSurface", fg: "mOnSecondary" },
        "Emoji": { bg: "mHover", separator: "mSurface", fg: "mOnHover" },
        "File": { bg: "mError", separator: "mSurface", fg: "mOnError" }
    }

    // Current card colors (loaded from settings or defaults)
    property var cardColors: JSON.parse(JSON.stringify(defaultCardColors))

    // Custom color values (when "custom" is selected)
    property var customColors: {
        "Text": { bg: "#555555", separator: "#000000", fg: "#e9e4f0" },
        "Image": { bg: "#e0b7c9", separator: "#000000", fg: "#20161f" },
        "Link": { bg: "#c7a1d8", separator: "#000000", fg: "#1a151f" },
        "Code": { bg: "#a984c4", separator: "#000000", fg: "#f3edf7" },
        "Color": { bg: "#a984c4", separator: "#000000", fg: "#f3edf7" },
        "Emoji": { bg: "#e0b7c9", separator: "#000000", fg: "#20161f" },
        "File": { bg: "#e9899d", separator: "#000000", fg: "#1e1418" }
    }

    spacing: Style.marginM

    // Home directory for path resolution
    readonly property string homeDir: Quickshell.env("HOME") || ""

    // Check if ToDo plugin is installed and enabled
    FileView {
        id: pluginsConfigFile
        path: root.homeDir + "/.config/noctalia/plugins.json"
        printErrors: false
        watchChanges: true
        onLoaded: {
            try {
                const content = text();
                if (content && content.length > 0) {
                    const config = JSON.parse(content);
                    root.todoPluginAvailable = config?.states?.todo?.enabled === true;
                    Logger.i("clipper", "ToDo plugin available: " + root.todoPluginAvailable);
                }
            } catch (e) {
                Logger.e("clipper", "Failed to parse plugins.json: " + e);
                root.todoPluginAvailable = false;
            }
        }
        onFileChanged: {
            // Re-check when file changes
            try {
                const content = text();
                if (content && content.length > 0) {
                    const config = JSON.parse(content);
                    root.todoPluginAvailable = config?.states?.todo?.enabled === true;
                }
            } catch (e) {
                root.todoPluginAvailable = false;
            }
        }
    }

    Component.onCompleted: {
        // Load saved settings
        if (pluginApi?.pluginSettings?.cardColors) {
            try {
                cardColors = JSON.parse(JSON.stringify(pluginApi.pluginSettings.cardColors));
            } catch (e) {
                Logger.e("clipper", "Failed to load cardColors: " + e);
            }
        }
        if (pluginApi?.pluginSettings?.customColors) {
            try {
                customColors = JSON.parse(JSON.stringify(pluginApi.pluginSettings.customColors));
            } catch (e) {
                Logger.e("clipper", "Failed to load customColors: " + e);
            }
        }
        if (pluginApi?.pluginSettings?.enableTodoIntegration !== undefined) {
            enableTodoIntegration = pluginApi.pluginSettings.enableTodoIntegration;
        }
    }

    // Helper to get actual color value
    function getColorValue(colorKey, cardType, colorType) {
        if (colorKey === "custom") {
            return customColors[cardType]?.[colorType] || "#888888";
        }
        if (typeof Color !== "undefined" && Color[colorKey]) {
            return Color[colorKey];
        }
        return "#888888";
    }

    // Get current colors for preview
    function getPreviewBg() {
        return getColorValue(cardColors[selectedCardType]?.bg || "mOutline", selectedCardType, "bg");
    }
    function getPreviewSeparator() {
        return getColorValue(cardColors[selectedCardType]?.separator || "mSurface", selectedCardType, "separator");
    }
    function getPreviewFg() {
        return getColorValue(cardColors[selectedCardType]?.fg || "mOnSurface", selectedCardType, "fg");
    }

    // Tab Bar
    NTabBar {
        id: tabBar
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginM
        currentIndex: tabView.currentIndex
        distributeEvenly: true

        NTabButton {
            text: "Features"
            tabIndex: 0
            checked: tabBar.currentIndex === 0
        }

        NTabButton {
            text: "Appearance"
            tabIndex: 1
            checked: tabBar.currentIndex === 1
        }
    }

    // Tab Content
    NTabView {
        id: tabView
        Layout.fillWidth: true
        currentIndex: tabBar.currentIndex

        // ===== Features Tab =====
        ColumnLayout {
            spacing: Style.marginL

            // ToDo Integration Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                NText {
                    text: "Integrations"
                    font.bold: true
                    font.pointSize: Style.fontSizeL
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: todoIntegrationContent.implicitHeight + Style.marginL * 2
                    color: (typeof Color !== "undefined") ? Color.mSurfaceVariant : "#333333"
                    radius: Style.radiusM

                    ColumnLayout {
                        id: todoIntegrationContent
                        anchors.fill: parent
                        anchors.margins: Style.marginL
                        spacing: Style.marginM

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginM

                            NIcon {
                                icon: "checkbox"
                                pointSize: 18
                                color: (typeof Color !== "undefined") ? Color.mOnSurface : "#e9e4f0"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                NText {
                                    text: "ToDo Plugin Integration"
                                    font.bold: true
                                }

                                NText {
                                    text: root.todoPluginAvailable
                                        ? "Add clipboard items directly to your ToDo list"
                                        : "ToDo plugin is not installed"
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurfaceVariant : "#aaaaaa"
                                }
                            }

                            NToggle {
                                id: todoToggle
                                enabled: root.todoPluginAvailable
                                checked: root.enableTodoIntegration
                                onToggled: checked => {
                                    root.enableTodoIntegration = checked;
                                    root.saveSettings();
                                }
                            }
                        }

                        // Info box when ToDo not installed
                        Rectangle {
                            visible: !root.todoPluginAvailable
                            Layout.fillWidth: true
                            Layout.preferredHeight: infoText.implicitHeight + Style.marginM * 2
                            color: (typeof Color !== "undefined") ? Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.2) : "#442222"
                            radius: Style.radiusS

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Style.marginM
                                spacing: Style.marginS

                                NIcon {
                                    icon: "info-circle"
                                    pointSize: 14
                                    color: (typeof Color !== "undefined") ? Color.mError : "#e9899d"
                                }

                                NText {
                                    id: infoText
                                    Layout.fillWidth: true
                                    text: "Install the ToDo plugin from noctalia-plugins to enable this feature."
                                    wrapMode: Text.Wrap
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurface : "#e9e4f0"
                                }
                            }
                        }

                        // Feature description when available but not enabled
                        Rectangle {
                            visible: root.todoPluginAvailable && !root.enableTodoIntegration
                            Layout.fillWidth: true
                            Layout.preferredHeight: descContent.implicitHeight + Style.marginM * 2
                            color: (typeof Color !== "undefined") ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.15) : "#223344"
                            radius: Style.radiusS

                            ColumnLayout {
                                id: descContent
                                anchors.fill: parent
                                anchors.margins: Style.marginM
                                spacing: Style.marginS

                                NText {
                                    Layout.fillWidth: true
                                    text: "Enable to add clipboard items to your ToDo lists:"
                                    wrapMode: Text.Wrap
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurface : "#e9e4f0"
                                }

                                NText {
                                    Layout.fillWidth: true
                                    text: "• 'Add to ToDo' button on clipboard cards"
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurfaceVariant : "#aaaaaa"
                                }

                                NText {
                                    Layout.fillWidth: true
                                    text: "• Keyboard shortcuts to add selected text"
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurfaceVariant : "#aaaaaa"
                                }

                                NText {
                                    Layout.fillWidth: true
                                    text: "• Works with Text, Links and Code"
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurfaceVariant : "#aaaaaa"
                                }
                            }
                        }

                        // Keybind instructions when enabled
                        Rectangle {
                            visible: root.todoPluginAvailable && root.enableTodoIntegration
                            Layout.fillWidth: true
                            Layout.preferredHeight: keybindContent.implicitHeight + Style.marginM * 2
                            color: (typeof Color !== "undefined") ? Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.15) : "#223344"
                            radius: Style.radiusS

                            ColumnLayout {
                                id: keybindContent
                                anchors.fill: parent
                                anchors.margins: Style.marginM
                                spacing: Style.marginS

                                NText {
                                    Layout.fillWidth: true
                                    text: "Bind IPC calls to add selected text to pages 1-9:"
                                    wrapMode: Text.Wrap
                                    font.pointSize: Style.fontSizeS
                                    font.bold: true
                                    color: (typeof Color !== "undefined") ? Color.mOnSurface : "#e9e4f0"
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: codeText.implicitHeight + Style.marginS * 2
                                    color: (typeof Color !== "undefined") ? Qt.rgba(0, 0, 0, 0.3) : "#111111"
                                    radius: Style.radiusS

                                    NText {
                                        id: codeText
                                        anchors.fill: parent
                                        anchors.margins: Style.marginS
                                        text: "qs ipc call plugin:clipper addToTodo1\nqs ipc call plugin:clipper addToTodo2\n...\nqs ipc call plugin:clipper addToTodo9"
                                        wrapMode: Text.Wrap
                                        font.pointSize: Style.fontSizeS
                                        font.family: (typeof Style !== "undefined") ? Style.fontMonospace : "monospace"
                                        color: (typeof Color !== "undefined") ? Color.mOnSurfaceVariant : "#aaaaaa"
                                    }
                                }

                                NText {
                                    Layout.fillWidth: true
                                    text: "Select text → trigger keybind → added to ToDo page"
                                    wrapMode: Text.Wrap
                                    font.pointSize: Style.fontSizeS
                                    color: (typeof Color !== "undefined") ? Color.mOnSurfaceVariant : "#aaaaaa"
                                }
                            }
                        }
                    }
                }
            }

            // Future integrations placeholder
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        // ===== Appearance Tab =====
        ColumnLayout {
            spacing: Style.marginL

            // Card type selector
            NComboBox {
                Layout.fillWidth: true
                label: "Card Type"
                description: "Select card type to customize"
                model: root.cardTypes
                currentKey: root.selectedCardType
                onSelected: key => root.selectedCardType = key
            }

            // Live Preview
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                color: (typeof Color !== "undefined") ? Color.mSurfaceVariant : "#333333"
                radius: Style.radiusM

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS

                    NText {
                        text: "Preview"
                        font.bold: true
                        color: root.getPreviewFg()
                    }

                    // Preview card
                    Rectangle {
                        Layout.preferredWidth: 250
                        Layout.preferredHeight: 220
                        Layout.alignment: Qt.AlignHCenter
                        color: root.getPreviewBg()
                        radius: Style.radiusM
                        border.width: 2
                        border.color: root.getPreviewBg()

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Header
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                color: root.getPreviewBg()
                                radius: Style.radiusM

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: parent.radius
                                    color: parent.color
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    NIcon {
                                        icon: root.selectedCardType === "Image" ? "photo" :
                                              root.selectedCardType === "Link" ? "link" :
                                              root.selectedCardType === "Code" ? "code" :
                                              root.selectedCardType === "Color" ? "palette" :
                                              root.selectedCardType === "Emoji" ? "mood-smile" :
                                              root.selectedCardType === "File" ? "file" : "align-left"
                                        pointSize: 12
                                        color: root.getPreviewFg()
                                    }

                                    NText {
                                        text: root.selectedCardType
                                        font.bold: true
                                        color: root.getPreviewFg()
                                    }

                                    Item { Layout.fillWidth: true }

                                    NIcon {
                                        icon: "trash"
                                        pointSize: 12
                                        color: root.getPreviewFg()
                                    }
                                }
                            }

                            // Separator
                            Rectangle {
                                Layout.preferredWidth: parent.width - 10
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredHeight: 1
                                color: root.getPreviewSeparator()
                            }

                            // Content area
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: 8

                                NText {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    text: "Sample content preview..."
                                    wrapMode: Text.Wrap
                                    color: root.getPreviewFg()
                                    verticalAlignment: Text.AlignTop
                                }
                            }
                        }
                    }
                }
            }

            // Color settings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                NComboBox {
                    Layout.fillWidth: true
                    label: "Background Color"
                    description: "Card background color"
                    model: root.colorOptions
                    currentKey: root.cardColors[root.selectedCardType]?.bg || "mOutline"
                    onSelected: key => {
                        if (!root.cardColors[root.selectedCardType]) {
                            root.cardColors[root.selectedCardType] = {};
                        }
                        root.cardColors[root.selectedCardType].bg = key;
                        root.cardColorsChanged();
                    }
                }

                NColorPicker {
                    visible: root.cardColors[root.selectedCardType]?.bg === "custom"
                    Layout.preferredWidth: Style.sliderWidth
                    Layout.preferredHeight: Style.baseWidgetSize
                    selectedColor: root.customColors[root.selectedCardType]?.bg || "#888888"
                    onColorSelected: color => {
                        if (!root.customColors[root.selectedCardType]) {
                            root.customColors[root.selectedCardType] = {};
                        }
                        root.customColors[root.selectedCardType].bg = color.toString();
                        root.customColorsChanged();
                    }
                }

                NComboBox {
                    Layout.fillWidth: true
                    label: "Separator Color"
                    description: "Line between header and content"
                    model: root.colorOptions
                    currentKey: root.cardColors[root.selectedCardType]?.separator || "mSurface"
                    onSelected: key => {
                        if (!root.cardColors[root.selectedCardType]) {
                            root.cardColors[root.selectedCardType] = {};
                        }
                        root.cardColors[root.selectedCardType].separator = key;
                        root.cardColorsChanged();
                    }
                }

                NColorPicker {
                    visible: root.cardColors[root.selectedCardType]?.separator === "custom"
                    Layout.preferredWidth: Style.sliderWidth
                    Layout.preferredHeight: Style.baseWidgetSize
                    selectedColor: root.customColors[root.selectedCardType]?.separator || "#000000"
                    onColorSelected: color => {
                        if (!root.customColors[root.selectedCardType]) {
                            root.customColors[root.selectedCardType] = {};
                        }
                        root.customColors[root.selectedCardType].separator = color.toString();
                        root.customColorsChanged();
                    }
                }

                NComboBox {
                    Layout.fillWidth: true
                    label: "Foreground Color"
                    description: "Title, icons and content text color"
                    model: root.colorOptions
                    currentKey: root.cardColors[root.selectedCardType]?.fg || "mOnSurface"
                    onSelected: key => {
                        if (!root.cardColors[root.selectedCardType]) {
                            root.cardColors[root.selectedCardType] = {};
                        }
                        root.cardColors[root.selectedCardType].fg = key;
                        root.cardColorsChanged();
                    }
                }

                NColorPicker {
                    visible: root.cardColors[root.selectedCardType]?.fg === "custom"
                    Layout.preferredWidth: Style.sliderWidth
                    Layout.preferredHeight: Style.baseWidgetSize
                    selectedColor: root.customColors[root.selectedCardType]?.fg || "#e9e4f0"
                    onColorSelected: color => {
                        if (!root.customColors[root.selectedCardType]) {
                            root.customColors[root.selectedCardType] = {};
                        }
                        root.customColors[root.selectedCardType].fg = color.toString();
                        root.customColorsChanged();
                    }
                }
            }

            // Reset button
            NButton {
                Layout.alignment: Qt.AlignRight
                text: "Reset to Defaults"
                icon: "refresh"
                onClicked: {
                    root.cardColors = JSON.parse(JSON.stringify(root.defaultCardColors));
                    root.customColors = {
                        "Text": { bg: "#555555", separator: "#000000", fg: "#e9e4f0" },
                        "Image": { bg: "#e0b7c9", separator: "#000000", fg: "#20161f" },
                        "Link": { bg: "#c7a1d8", separator: "#000000", fg: "#1a151f" },
                        "Code": { bg: "#a984c4", separator: "#000000", fg: "#f3edf7" },
                        "Color": { bg: "#a984c4", separator: "#000000", fg: "#f3edf7" },
                        "Emoji": { bg: "#e0b7c9", separator: "#000000", fg: "#20161f" },
                        "File": { bg: "#e9899d", separator: "#000000", fg: "#1e1418" }
                    };
                }
            }
        }
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("clipper", "Cannot save settings: pluginApi is null");
            return;
        }

        pluginApi.pluginSettings.cardColors = JSON.parse(JSON.stringify(root.cardColors));
        pluginApi.pluginSettings.customColors = JSON.parse(JSON.stringify(root.customColors));
        pluginApi.pluginSettings.enableTodoIntegration = root.enableTodoIntegration;
        pluginApi.saveSettings();

        Logger.i("clipper", "Settings saved successfully");
    }
}
