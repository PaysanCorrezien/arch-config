import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

  Rectangle {
  id: root

  property string title: ""
  property url iconSource: ""
  property bool badgeVisible: false
  property string badgeText: ""
  property color badgeColor: Color.mPrimary
  property color badgeTextColor: Color.mOnPrimary
  property bool badgeTextAuto: true
  property string errorText: ""
  property bool sectionsVisible: true
  property string primaryLabel: "5-Hour Window"
  property real primaryPercent: 0
  property int primaryRemainingSec: 0
  property string primaryFooterText: ""
  property string secondaryLabel: "7-Day Window"
  property real secondaryPercent: 0
  property int secondaryRemainingSec: 0
  property string secondaryTrailingText: ""
  property bool showSecondary: true
  property int barHeight: 6
  property int iconSize: Math.round(24 * Style.uiScaleRatio)

  Layout.fillWidth: true
  Layout.preferredHeight: content.implicitHeight + Style.marginL * 2
  color: Color.mSurfaceVariant
  radius: Style.radiusL

  ColumnLayout {
    id: content
    anchors {
      fill: parent
      margins: Style.marginL
    }
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      Image {
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        Layout.preferredWidth: root.iconSize
        Layout.preferredHeight: root.iconSize
        sourceSize.width: root.iconSize
        sourceSize.height: root.iconSize
      }

      NText {
        text: root.title
        pointSize: Style.fontSizeL
        font.weight: Font.DemiBold
        color: Color.mOnSurface
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        opacity: root.badgeVisible ? 1 : 0
        Layout.preferredWidth: root.badgeVisible ? badgeWidth() : 0
        Layout.preferredHeight: root.badgeVisible ? badgeHeight() : 0
        color: root.badgeColor
        radius: Style.radiusS

        NText {
          id: badgeTextItem
          anchors.centerIn: parent
          text: root.badgeText
          pointSize: Style.fontSizeS
          color: badgeTextColorResolved()
          onContentWidthChanged: {
            Logger.d("AIUsage", "ProviderCard badge content title=" + root.title +
              " text=" + text +
              " width=" + contentWidth)
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: errorTextItem.implicitHeight + Style.marginS * 2
      color: Qt.alpha(Color.mError, 0.14)
      radius: Style.radiusS
      visible: root.errorText !== ""

      NText {
        id: errorTextItem
        anchors {
          fill: parent
          margins: Style.marginS
        }
        text: root.errorText
        pointSize: Style.fontSizeS
        color: Color.mError
        wrapMode: Text.WordWrap
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
      visible: root.sectionsVisible

      NText {
        text: root.primaryLabel
        pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
        color: Color.mOnSurface
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: formatUtilization(root.primaryPercent)
          pointSize: Style.fontSizeXL
          font.weight: Font.Bold
          color: getUtilizationColor(root.primaryPercent)
        }

        Item { Layout.fillWidth: true }

        NText {
          text: formatTimeRemaining(root.primaryRemainingSec)
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.barHeight
        radius: Math.max(1, Math.round(root.barHeight / 2))
        color: Qt.alpha(Color.mOnSurfaceVariant, 0.2)

        Rectangle {
          width: Math.max(0, Math.min(parent.width, parent.width * (root.primaryPercent / 100)))
          height: parent.height
          radius: Math.max(1, Math.round(root.barHeight / 2))
          color: getUtilizationColor(root.primaryPercent)
        }
      }

      NText {
        text: root.primaryFooterText
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        visible: root.primaryFooterText !== ""
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
      visible: root.sectionsVisible && root.showSecondary

      NText {
        text: root.secondaryLabel
        pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
        color: Color.mOnSurface
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: formatUtilization(root.secondaryPercent)
          pointSize: Style.fontSizeXL
          font.weight: Font.Bold
          color: getUtilizationColor(root.secondaryPercent)
        }

        Item { Layout.fillWidth: true }

        NText {
          text: trailingText(root.secondaryRemainingSec, root.secondaryTrailingText)
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.barHeight
        radius: Math.max(1, Math.round(root.barHeight / 2))
        color: Qt.alpha(Color.mOnSurfaceVariant, 0.2)

        Rectangle {
          width: Math.max(0, Math.min(parent.width, parent.width * (root.secondaryPercent / 100)))
          height: parent.height
          radius: Math.max(1, Math.round(root.barHeight / 2))
          color: getUtilizationColor(root.secondaryPercent)
        }
      }
    }
  }

  function formatUtilization(value) {
    const pct = Math.max(0, Math.min(100, value || 0))
    return pct.toFixed(0) + "%"
  }

  function getUtilizationColor(utilization) {
    if (utilization >= 90) return Color.mError || "#f44336"
    if (utilization >= 70) return Color.mWarning || "#ff9800"
    return Color.mPrimary
  }

  function formatTimeRemaining(seconds) {
    const safe = Math.max(0, seconds || 0)
    if (safe === 0) return "Reset time unknown"
    const hours = Math.floor(safe / 3600)
    const mins = Math.floor((safe % 3600) / 60)
    if (hours > 0) return hours + "h " + mins + "m remaining"
    return mins + "m remaining"
  }

  function trailingText(remainingSec, fallbackText) {
    if (remainingSec > 0) return formatTimeRemaining(remainingSec)
    if (fallbackText) return fallbackText
    return formatTimeRemaining(remainingSec)
  }

  function badgeWidth() {
    const textWidth = Math.ceil(badgeTextItem.contentWidth || 0)
    if (textWidth === 0 && root.badgeText) {
      const fontSize = badgeTextItem.font.pointSize || Style.fontSizeS
      const estimatedWidth = Math.ceil(root.badgeText.length * fontSize * 0.6)
      return estimatedWidth + Style.marginM * 2
    }
    return textWidth + Style.marginM * 2
  }

  function badgeHeight() {
    const textHeight = Math.ceil(badgeTextItem.contentHeight || badgeTextItem.implicitHeight || 0)
    return textHeight + Style.marginS
  }

  function badgeTextColorResolved() {
    if (!root.badgeTextAuto) {
      return root.badgeTextColor
    }
    const bg = root.badgeColor
    if (bg === undefined) {
      return Color.mOnSurface
    }
    const lum = (0.2126 * bg.r) + (0.7152 * bg.g) + (0.0722 * bg.b)
    return lum < 0.5 ? Color.mOnSurface : Color.mShadow
  }

  onBadgeTextChanged: {
    Logger.d("AIUsage", "ProviderCard badge title=" + title +
      " text=" + badgeText +
      " width=" + badgeTextItem.contentWidth +
      " bg=" + badgeColor +
      " fg=" + badgeTextColor +
      " textColor=" + badgeTextItem.color +
      " opacity=" + badgeTextItem.opacity +
      " enabled=" + badgeTextItem.enabled)
  }
}
