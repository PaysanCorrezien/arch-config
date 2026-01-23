import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  property real contentPreferredWidth: 600 * Style.uiScaleRatio
  property real contentPreferredHeight: 500 * Style.uiScaleRatio

  // Access main instance data
  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property real currentCost: mainInstance?.currentCost || 0
  readonly property int currentTokens: mainInstance?.currentTokens || 0
  readonly property int currentRemainingSec: mainInstance?.currentRemainingSec || 0
  readonly property int currentElapsedSec: mainInstance?.currentElapsedSec || 0
  readonly property int currentDurationSec: mainInstance?.currentDurationSec || 0
  readonly property string currentStart: mainInstance?.currentStart || ""
  readonly property string currentEnd: mainInstance?.currentEnd || ""
  readonly property bool currentIsGap: mainInstance?.currentIsGap || false
  readonly property string planLabel: mainInstance?.planLabel || ""
  readonly property real dayCost: mainInstance?.dayCost || 0
  readonly property int dayTokens: mainInstance?.dayTokens || 0
  readonly property real weekCost: mainInstance?.weekCost || 0
  readonly property int weekTokens: mainInstance?.weekTokens || 0
  readonly property real monthCost: mainInstance?.monthCost || 0
  readonly property int monthTokens: mainInstance?.monthTokens || 0
  readonly property real totalCost: mainInstance?.totalCost || 0
  readonly property int totalTokens: mainInstance?.totalTokens || 0
  readonly property string lastError: mainInstance?.lastError || ""

  anchors.fill: parent

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

        Image {
          source: Qt.resolvedUrl("claude-ai.svg")
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          Layout.preferredWidth: 48 * Style.uiScaleRatio
          Layout.preferredHeight: 48 * Style.uiScaleRatio
          sourceSize.width: 48 * Style.uiScaleRatio
          sourceSize.height: 48 * Style.uiScaleRatio
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: "Claude Code Usage"
            pointSize: Style.fontSizeXL
            font.weight: Font.Bold
            color: Color.mOnSurface
          }

          NText {
            text: "Plan: " + planLabel
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }
        }

        NIconButton {
          icon: "refresh"
          onClicked: {
            if (mainInstance) {
              mainInstance.refreshUsage()
            }
          }
        }
      }

      // Error message
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: errorText.implicitHeight + Style.marginM * 2
        color: Color.mErrorContainer
        radius: Style.radiusM
        visible: lastError !== ""

        NText {
          id: errorText
          anchors {
            fill: parent
            margins: Style.marginM
          }
          text: "Error: " + lastError
          color: Color.mOnErrorContainer
          wrapMode: Text.WordWrap
        }
      }

      // Current Period Section
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: currentPeriodContent.implicitHeight + Style.marginL * 2
        color: Color.mSurfaceVariant
        radius: Style.radiusL

        ColumnLayout {
          id: currentPeriodContent
          anchors {
            fill: parent
            margins: Style.marginL
          }
          spacing: Style.marginM

          NText {
            text: "Current Period"
            pointSize: Style.fontSizeL
            font.weight: Font.DemiBold
            color: Color.mOnSurface
          }

          // Cost and time
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: formatCost(currentCost)
              pointSize: Style.fontSizeXL
              font.weight: Font.Bold
              color: Color.mPrimary
            }

            Item { Layout.fillWidth: true }

            NText {
              text: formatTimeRemaining(currentRemainingSec)
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
            }
          }

          // Progress bar
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            radius: 4
            color: Qt.alpha(Color.mOnSurfaceVariant, 0.2)

            Rectangle {
              width: Math.max(0, Math.min(parent.width, parent.width * progressValue))
              height: parent.height
              radius: 4
              color: Color.mPrimary
            }
          }

          // Tokens
          NText {
            text: "Tokens: " + formatTokens(currentTokens)
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
          }

          // Period dates
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            ColumnLayout {
              spacing: Style.marginXS

              NText {
                text: "Start: " + (currentStart ? formatDateShort(currentStart) : "—")
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: "End: " + (currentEnd ? formatDateShort(currentEnd) : "—")
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
              }
            }
          }
        }
      }

      // Usage Statistics
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: statsContent.implicitHeight + Style.marginL * 2
        color: Color.mSurfaceVariant
        radius: Style.radiusL

        ColumnLayout {
          id: statsContent
          anchors {
            fill: parent
            margins: Style.marginL
          }
          spacing: Style.marginM

          NText {
            text: "Usage Statistics"
            pointSize: Style.fontSizeL
            font.weight: Font.DemiBold
            color: Color.mOnSurface
          }

          // Daily
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: "Today:"
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
              Layout.preferredWidth: 100
            }

            NText {
              text: formatCost(dayCost) + " • " + formatTokens(dayTokens)
              pointSize: Style.fontSizeM
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
          }

          // Weekly
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: "This Week:"
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
              Layout.preferredWidth: 100
            }

            NText {
              text: formatCost(weekCost) + " • " + formatTokens(weekTokens)
              pointSize: Style.fontSizeM
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
          }

          // Monthly
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: "This Month:"
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
              Layout.preferredWidth: 100
            }

            NText {
              text: formatCost(monthCost) + " • " + formatTokens(monthTokens)
              pointSize: Style.fontSizeM
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
          }

          // Total
          NDivider { Layout.fillWidth: true }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              text: "Total:"
              pointSize: Style.fontSizeM
              font.weight: Font.DemiBold
              color: Color.mOnSurface
              Layout.preferredWidth: 100
            }

            NText {
              text: formatCost(totalCost) + " • " + formatTokens(totalTokens)
              pointSize: Style.fontSizeM
              font.weight: Font.DemiBold
              color: Color.mPrimary
              Layout.fillWidth: true
            }
          }
        }
      }

      // Spacer
      Item {
        Layout.fillHeight: true
      }
    }
  }

  // Helper functions
  function formatCost(cost) {
    const value = isNaN(cost) ? 0 : cost
    if (value >= 100) return "$" + value.toFixed(0)
    if (value >= 10) return "$" + value.toFixed(1)
    return "$" + value.toFixed(2)
  }

  function formatTokens(tokens) {
    const val = tokens || 0
    if (val >= 1000000) return (val / 1000000).toFixed(2) + "M"
    if (val >= 1000) return (val / 1000).toFixed(1) + "K"
    return val.toString()
  }

  function formatTimeRemaining(seconds) {
    const safe = Math.max(0, seconds || 0)
    if (safe === 0) return "Reset time unknown"
    const hours = Math.floor(safe / 3600)
    const mins = Math.floor((safe % 3600) / 60)
    if (hours > 0) return hours + "h " + mins + "m remaining"
    return mins + "m remaining"
  }

  function formatDateShort(dateString) {
    if (!dateString) return "—"
    try {
      const date = new Date(dateString)
      return date.toLocaleDateString() + " " + date.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})
    } catch (e) {
      return dateString
    }
  }

  readonly property real progressValue: {
    if (!currentDurationSec || currentDurationSec <= 0) return 0
    if (currentIsGap) return 0
    return Math.max(0, Math.min(1, currentElapsedSec / currentDurationSec))
  }
}
