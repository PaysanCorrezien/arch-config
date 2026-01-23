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

  readonly property real currentCost: pluginApi?.mainInstance?.currentCost || 0
  readonly property int currentTokens: pluginApi?.mainInstance?.currentTokens || 0
  readonly property int currentRemainingSec: pluginApi?.mainInstance?.currentRemainingSec || 0
  readonly property int currentElapsedSec: pluginApi?.mainInstance?.currentElapsedSec || 0
  readonly property int currentDurationSec: pluginApi?.mainInstance?.currentDurationSec || 0
  readonly property bool currentIsGap: pluginApi?.mainInstance?.currentIsGap || false
  readonly property string lastError: pluginApi?.mainInstance?.lastError || ""
  readonly property string planLabel: pluginApi?.mainInstance?.planLabel || ""

  readonly property bool isVisible: pluginApi?.mainInstance?.barVisible ?? true

  implicitWidth: isVertical ? Style.capsuleHeight : layout.implicitWidth + Style.marginS * 2
  implicitHeight: isVertical ? layout.implicitHeight + Style.marginS * 2 : Style.capsuleHeight

  color: root.hovered ? Color.mHover : Style.capsuleColor
  radius: Style.radiusM
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth
  visible: root.isVisible
  opacity: root.isVisible ? 1.0 : 0.0

  Item {
    id: layout
    anchors.centerIn: parent
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    ColumnLayout {
      id: content
      spacing: Style.marginXS

      RowLayout {
        spacing: Style.marginS
        Layout.fillWidth: true

        Image {
          source: Qt.resolvedUrl("claude-ai.svg")
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
          text: formatPercent(root.currentElapsedSec, root.currentDurationSec)
          color: root.hovered ? Color.mOnHover : Color.mOnSurface
          pointSize: Style.barFontSize
        }

        NText {
          text: formatRemaining(root.currentRemainingSec)
          color: root.hovered ? Color.mOnHover : Color.mOnSurfaceVariant
          pointSize: Style.barFontSize
        }
      }

      Rectangle {
        id: currentTrack
        width: barWidth()
        height: 4
        radius: 2
        color: Qt.alpha(Color.mOnSurfaceVariant, 0.2)

        Rectangle {
          width: Math.round(currentTrack.width * progress(root.currentElapsedSec, root.currentDurationSec))
          height: currentTrack.height
          radius: 2
          color: Color.mPrimary
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

  function progress(value, max) {
    if (!max || max <= 0) return 0
    return Math.max(0, Math.min(1, value / max))
  }

  function formatPercent(value, max) {
    if (!max || max <= 0) return "0%"
    const pct = Math.max(0, Math.min(999, (value / max) * 100))
    return pct.toFixed(0) + "%"
  }

  function formatRemaining(seconds) {
    const safe = Math.max(0, seconds || 0)
    const hours = Math.floor(safe / 3600)
    const mins = Math.floor((safe % 3600) / 60)
    return hours + "h " + mins + "m"
  }

  function formatCost(cost) {
    const value = isNaN(cost) ? 0 : cost
    return "$" + value.toFixed(value >= 100 ? 0 : (value >= 10 ? 1 : 2))
  }

  function buildTooltip() {
    const costLine = "Current: " + formatCost(root.currentCost)
    const planLine = root.planLabel ? ("Plan: " + root.planLabel) : "Plan: Unknown"
    const tokenLine = "Tokens: " + (root.currentTokens || 0)
    const resetLine = "Reset in: " + formatRemaining(root.currentRemainingSec)
    const gapLine = root.currentIsGap ? "\nNo usage yet in this period" : ""
    const errorLine = root.lastError ? ("\n" + root.lastError) : ""
    TooltipService.show(root, costLine + "\n" + planLine + "\n" + tokenLine + "\n" + resetLine + gapLine + errorLine, BarService.getTooltipDirection())
  }
}
