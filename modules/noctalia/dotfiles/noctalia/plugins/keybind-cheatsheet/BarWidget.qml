import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  readonly property string barPosition: Settings.getBarPositionForScreen(screen.name)
  readonly property bool barIsVertical: barPosition === "left" || barPosition === "right"

  implicitWidth: Style.getCapsuleHeightForScreen(screen.name)
  implicitHeight: Style.getCapsuleHeightForScreen(screen.name)

  color: Style.capsuleColor
  radius: Style.radiusL

  Connections {
    target: Color
    function onMOnHoverChanged() { }
    function onMOnSurfaceChanged() { }
  }

  NIcon {
    id: contentIcon
    anchors.centerIn: parent
    icon: "keyboard"
    applyUiScale: false
    color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      root.color = Color.mHover;
    }

    onExited: {
      root.color = Style.capsuleColor;
    }

    onClicked: {
      if (pluginApi) {
        // Set flag to trigger parser in Main.qml
        pluginApi.pluginSettings.triggerToggle = Date.now();
        pluginApi.saveSettings();
      }
    }
  }
}
