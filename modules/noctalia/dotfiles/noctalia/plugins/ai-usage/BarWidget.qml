import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property bool hovered: false

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  // Claude properties
  readonly property bool claudeEnabled: pluginApi?.mainInstance?.claudeEnabled ?? true
  readonly property bool showClaudeInBar: pluginApi?.mainInstance?.showClaudeInBar ?? true
  readonly property real fiveHourUtilization: pluginApi?.mainInstance?.fiveHourUtilization || 0
  readonly property int fiveHourRemainingSec: pluginApi?.mainInstance?.fiveHourRemainingSec || 0
  readonly property real sevenDayUtilization: pluginApi?.mainInstance?.sevenDayUtilization || 0
  readonly property string lastError: pluginApi?.mainInstance?.lastError || ""
  readonly property string claudePlanType: pluginApi?.mainInstance?.claudePlanType || ""
  readonly property bool showClaude: claudeEnabled && showClaudeInBar

  // Codex properties
  readonly property bool codexEnabled: pluginApi?.mainInstance?.codexEnabled ?? true
  readonly property bool showCodexInBar: pluginApi?.mainInstance?.showCodexInBar ?? true
  readonly property real codexPrimaryPercent: pluginApi?.mainInstance?.codexPrimaryPercent || 0
  readonly property real codexSecondaryPercent: pluginApi?.mainInstance?.codexSecondaryPercent || 0
  readonly property int codexPrimaryResetSec: pluginApi?.mainInstance?.codexPrimaryResetSec || 0
  readonly property int codexSecondaryResetSec: pluginApi?.mainInstance?.codexSecondaryResetSec || 0
  readonly property string codexPlanType: pluginApi?.mainInstance?.codexPlanType || ""
  readonly property string codexLastError: pluginApi?.mainInstance?.codexLastError || ""
  readonly property bool codexHasData: pluginApi?.mainInstance?.codexHasData ?? false
  readonly property bool codexConnected: pluginApi?.mainInstance?.codexConnected || false
  readonly property bool showCodex: codexEnabled && showCodexInBar

  // Widget is visible if either Claude or Codex should show in bar
  readonly property bool isVisible: showClaude || showCodex
  readonly property bool showBar: pluginApi?.mainInstance?.showBar ?? true

  implicitWidth: isVertical ? Style.capsuleHeight : layout.implicitWidth + Style.marginS * 2
  implicitHeight: isVertical ? layout.implicitHeight + Style.marginS * 2 : Style.capsuleHeight

  color: root.hovered ? Color.mHover : Style.capsuleColor
  radius: Style.radiusM
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth
  visible: root.isVisible && root.showBar
  opacity: root.isVisible && root.showBar ? 1.0 : 0.0

  Item {
    id: layout
    anchors.centerIn: parent
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    RowLayout {
      id: content
      spacing: Style.marginM

      // Claude section
      ColumnLayout {
        spacing: Style.marginXS
        visible: root.showClaude

        RowLayout {
          spacing: Style.marginS
          Layout.fillWidth: true

          Image {
            source: Qt.resolvedUrl("public/claude-ai.svg")
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            width: Math.round(Style.barFontSize * 1.2)
            height: width
            sourceSize.width: width
            sourceSize.height: height
            Layout.preferredWidth: width
            Layout.preferredHeight: height
          }

          NText {
            text: formatUtilization(root.fiveHourUtilization)
            color: root.hovered ? Color.mOnHover : Color.mOnSurface
            pointSize: Style.barFontSize
          }

          NText {
            text: formatRemaining(root.fiveHourRemainingSec)
            color: root.hovered ? Color.mOnHover : Color.mOnSurfaceVariant
            pointSize: Style.barFontSize
          }
        }

        Rectangle {
          id: claudeTrack
          width: barWidth()
          height: 4
          radius: 2
          color: Qt.alpha(Color.mOnSurfaceVariant, 0.2)

          Rectangle {
            width: Math.round(claudeTrack.width * (root.fiveHourUtilization / 100))
            height: claudeTrack.height
            radius: 2
            color: getBarColor(root.fiveHourUtilization)
          }
        }
      }

      // Codex section (only visible if enabled)
      ColumnLayout {
        spacing: Style.marginXS
        visible: root.showCodex

        RowLayout {
          spacing: Style.marginS
          Layout.fillWidth: true

          Image {
            source: Qt.resolvedUrl("public/openai-light.svg")
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            width: Math.round(Style.barFontSize * 1.2)
            height: width
            sourceSize.width: width
            sourceSize.height: height
            Layout.preferredWidth: width
            Layout.preferredHeight: height
          }

          NText {
            text: formatUtilization(root.codexPrimaryPercent)
            color: root.hovered ? Color.mOnHover : Color.mOnSurface
            pointSize: Style.barFontSize
          }

          NText {
            text: formatRemaining(root.codexPrimaryResetSec)
            color: root.hovered ? Color.mOnHover : Color.mOnSurfaceVariant
            pointSize: Style.barFontSize
            visible: root.codexPrimaryResetSec > 0
          }
        }

        Rectangle {
          id: openaiTrack
          width: barWidth()
          height: 4
          radius: 2
          color: Qt.alpha(Color.mOnSurfaceVariant, 0.2)

          Rectangle {
            width: Math.round(openaiTrack.width * (root.codexPrimaryPercent / 100))
            height: openaiTrack.height
            radius: 2
            color: getBarColor(root.codexPrimaryPercent)
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: {
        root.hovered = true
        buildTooltip()
      }
      onExited: {
        root.hovered = false
        TooltipService.hide()
      }
      onClicked: root.pluginApi?.openPanel(root.screen)
    }
  }

  function barWidth() {
    return Math.max(64, Math.round(Style.marginL * 7))
  }

  function getBarColor(utilization) {
    if (utilization >= 90) return Color.mError || "#f44336"
    if (utilization >= 70) return Color.mWarning || "#ff9800"
    return Color.mPrimary
  }

  function formatUtilization(value) {
    const pct = Math.max(0, Math.min(100, value || 0))
    return pct.toFixed(0) + "%"
  }

  function formatRemaining(seconds) {
    const safe = Math.max(0, seconds || 0)
    const hours = Math.floor(safe / 3600)
    const mins = Math.floor((safe % 3600) / 60)
    return hours + "h " + mins + "m"
  }

  function buildTooltip() {
    let tooltip = ""

    if (root.showClaude) {
      tooltip += "Claude" + (root.claudePlanType ? " [" + root.claudePlanType + "]" : "") + ":\n"
      tooltip += "  5-hour: " + formatUtilization(root.fiveHourUtilization) + "\n"
      tooltip += "  Weekly: " + formatUtilization(root.sevenDayUtilization) + "\n"
      tooltip += "  Resets in: " + formatRemaining(root.fiveHourRemainingSec)
      if (root.lastError) {
        tooltip += "\n  Error: " + root.lastError
      }
    }

    if (root.showCodex) {
      if (tooltip) tooltip += "\n\n"
      tooltip += "Codex" + (root.codexPlanType ? " [" + root.codexPlanType + "]" : "") + ":\n"
      tooltip += "  5-hour: " + formatUtilization(root.codexPrimaryPercent)
      if (root.codexPrimaryResetSec > 0) {
        tooltip += " (" + formatRemaining(root.codexPrimaryResetSec) + ")"
      }
      tooltip += "\n  Weekly: " + formatUtilization(root.codexSecondaryPercent)
      if (root.codexLastError) {
        tooltip += "\n  Error: " + root.codexLastError
      }
    }

    TooltipService.show(root, tooltip, BarService.getTooltipDirection())
  }
}
