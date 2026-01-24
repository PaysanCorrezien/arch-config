import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  property real contentPreferredWidth: 420 * Style.uiScaleRatio
  property real contentPreferredHeight: 580 * Style.uiScaleRatio

  // Access main instance data
  readonly property var mainInstance: pluginApi?.mainInstance

  // Claude properties
  readonly property bool claudeEnabled: mainInstance?.claudeEnabled ?? true
  readonly property real fiveHourUtilization: mainInstance?.fiveHourUtilization || 0
  readonly property int fiveHourRemainingSec: mainInstance?.fiveHourRemainingSec || 0
  readonly property string fiveHourResetsAt: mainInstance?.fiveHourResetsAt || ""
  readonly property real sevenDayUtilization: mainInstance?.sevenDayUtilization || 0
  readonly property string lastError: mainInstance?.lastError || ""
  readonly property string claudePlanType: mainInstance?.claudePlanType || ""

  // Codex properties
  readonly property bool codexEnabled: mainInstance?.codexEnabled ?? true
  readonly property real codexPrimaryPercent: mainInstance?.codexPrimaryPercent || 0
  readonly property real codexSecondaryPercent: mainInstance?.codexSecondaryPercent || 0
  readonly property int codexPrimaryResetSec: mainInstance?.codexPrimaryResetSec || 0
  readonly property int codexSecondaryResetSec: mainInstance?.codexSecondaryResetSec || 0
  readonly property string codexPlanType: mainInstance?.codexPlanType || ""
  readonly property string codexLastError: mainInstance?.codexLastError || ""
  readonly property bool codexConnected: mainInstance?.codexConnected ?? false

  anchors.fill: parent

  Component.onCompleted: {
    Logger.d("AIUsage", "Panel loaded claudePlanType=" + claudePlanType)
  }
  onMainInstanceChanged: {
    Logger.d("AIUsage", "Panel mainInstance=" + (mainInstance ? "set" : "null"))
  }
  onClaudePlanTypeChanged: {
    Logger.d("AIUsage", "Panel claudePlanType=" + claudePlanType)
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.marginL
      }
      spacing: Style.marginL

      // Header with icon
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          Layout.fillWidth: true
          text: "Usage Overview"
          pointSize: Style.fontSizeXL
          font.weight: Font.Bold
          color: Color.mOnSurface
        }

        NIconButton {
          icon: "refresh"
          onClicked: {
            if (mainInstance) {
              mainInstance.refreshUsage()
            }
          }
        }

        NIconButton {
          icon: "settings"
          onClicked: {
            if (pluginApi && pluginApi.openSettings) {
              pluginApi.openSettings()
            }
          }
        }
      }

      ProviderCard {
        title: "Claude"
        iconSource: Qt.resolvedUrl("public/claude-ai.svg")
        badgeVisible: claudePlanType !== ""
        badgeText: claudePlanType
        onBadgeVisibleChanged: {
          Logger.d("AIUsage", "Claude badge visible=" + badgeVisible + " text=" + badgeText)
        }
        onBadgeTextChanged: {
          Logger.d("AIUsage", "Claude badge text=" + badgeText)
        }
        errorText: lastError
        primaryPercent: fiveHourUtilization
        primaryRemainingSec: fiveHourRemainingSec
        primaryFooterText: fiveHourResetsAt
          ? ("Resets at: " + formatDateShort(fiveHourResetsAt))
          : "Reset time unknown"
        secondaryPercent: sevenDayUtilization
        secondaryTrailingText: "weekly limit"
        visible: root.claudeEnabled
      }

      ProviderCard {
        title: "Codex"
        iconSource: Qt.resolvedUrl("public/openai-light.svg")
        badgeVisible: true
        badgeText: root.codexConnected ? (root.codexPlanType || "connected") : "disconnected"
        badgeColor: root.codexConnected ? Color.mPrimary : Color.mError
        badgeTextColor: root.codexConnected ? Color.mOnPrimary : Color.mOnError
        errorText: root.codexLastError
        sectionsVisible: root.codexConnected
        primaryPercent: root.codexPrimaryPercent
        primaryRemainingSec: root.codexPrimaryResetSec
        secondaryPercent: root.codexSecondaryPercent
        secondaryRemainingSec: root.codexSecondaryResetSec
        visible: root.codexEnabled
      }

      // Spacer
      Item {
        Layout.fillHeight: true
      }
    }
  }

  // Helper functions
  function formatDateShort(dateString) {
    if (!dateString) return "—"
    try {
      const date = new Date(dateString)
      return date.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})
    } catch (e) {
      return dateString
    }
  }

}
