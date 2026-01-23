import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  // Local state - initialized from saved settings
  property string editRefreshInterval: ""
  property bool editShowInBar: true
  property bool editWatcherEnabled: false
  property string editWatcherMessage: "hi"
  property int editWatcherCheckInterval: 60
  property int editWatcherRenewWindow: 120
  property int editWatcherResetSeconds: 18000
  property string editWatcherLastActivityFile: "$HOME/.claude-last-activity"
  property bool editWatcherUseFallback: true
  property bool editWatcherNotifyBeforeReset: false
  property bool editWatcherNotifyAfterReset: false

  Component.onCompleted: {
    Logger.i("CCUsageBar", "Settings UI loaded")
    updateFromSettings()
  }

  onPluginApiChanged: {
    if (pluginApi) {
      updateFromSettings()
    }
  }

  function pickValue(value, fallback) {
    return (value === undefined || value === null) ? fallback : value
  }

  function updateFromSettings() {
    if (!pluginApi) return

    const defaults = (pluginApi.manifest &&
      pluginApi.manifest.metadata &&
      pluginApi.manifest.metadata.defaultSettings) ? pluginApi.manifest.metadata.defaultSettings : {}
    const settings = pluginApi.pluginSettings || {}

    editRefreshInterval = String(pickValue(settings.refreshIntervalSeconds,
      pickValue(defaults.refreshIntervalSeconds, 60)))
    editShowInBar = pickValue(settings.showInBar, pickValue(defaults.showInBar, true))
    editWatcherEnabled = pickValue(settings.watcherEnabled, pickValue(defaults.watcherEnabled, false))
    editWatcherMessage = settings.watcherMessage || defaults.watcherMessage || "hi"
    editWatcherCheckInterval = pickValue(settings.watcherCheckIntervalSeconds,
      pickValue(defaults.watcherCheckIntervalSeconds, 60))
    editWatcherRenewWindow = pickValue(settings.watcherRenewWindowSeconds,
      pickValue(defaults.watcherRenewWindowSeconds, 120))
    editWatcherResetSeconds = pickValue(settings.watcherResetSeconds,
      pickValue(defaults.watcherResetSeconds, 18000))
    editWatcherLastActivityFile = settings.watcherLastActivityFile ||
      defaults.watcherLastActivityFile || "$HOME/.claude-last-activity"
    editWatcherUseFallback = pickValue(settings.watcherUseFallback, pickValue(defaults.watcherUseFallback, true))
    editWatcherNotifyBeforeReset = pickValue(settings.watcherNotifyBeforeReset,
      pickValue(defaults.watcherNotifyBeforeReset, false))
    editWatcherNotifyAfterReset = pickValue(settings.watcherNotifyAfterReset,
      pickValue(defaults.watcherNotifyAfterReset, false))
  }

  spacing: Style.marginM

  NToggle {
    label: "Show Claude Code bar"
    description: "Toggle the Claude Code usage widget in the bar"
    checked: root.editShowInBar
    onToggled: root.editShowInBar = checked
    Layout.fillWidth: true
  }

  NDivider { Layout.fillWidth: true }

  NTextInput {
    label: "Refresh interval (seconds)"
    description: "How often to poll ccusage"
    placeholderText: "60"
    text: root.editRefreshInterval
    onTextChanged: root.editRefreshInterval = text
    Layout.fillWidth: true
  }

  NDivider { Layout.fillWidth: true }

  NText {
    text: "Watcher"
    font.weight: Font.DemiBold
    color: Color.mOnSurface
    Layout.fillWidth: true
  }

  NToggle {
    label: "Enable watcher"
    description: "Keep the Claude session alive by sending a renewal message"
    checked: root.editWatcherEnabled
    onToggled: root.editWatcherEnabled = checked
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Claude reset message"
    description: "Message sent to Claude when renewing the session"
    placeholderText: "hi"
    text: root.editWatcherMessage
    onTextChanged: root.editWatcherMessage = text
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Check reset interval (seconds)"
    description: "How often to check the reset timer"
    placeholderText: "60"
    text: String(root.editWatcherCheckInterval)
    onTextChanged: {
      const val = parseInt(text)
      if (!isNaN(val)) root.editWatcherCheckInterval = val
    }
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Renew window (seconds)"
    description: "How close to reset before sending renewal/notifications"
    placeholderText: "120"
    text: String(root.editWatcherRenewWindow)
    onTextChanged: {
      const val = parseInt(text)
      if (!isNaN(val)) root.editWatcherRenewWindow = val
    }
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Fallback reset seconds"
    description: "Renew if no active block and last activity exceeds this"
    placeholderText: "18000"
    text: String(root.editWatcherResetSeconds)
    onTextChanged: {
      const val = parseInt(text)
      if (!isNaN(val)) root.editWatcherResetSeconds = val
    }
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Last activity file"
    description: "Where the watcher stores the last renewal time"
    placeholderText: "$HOME/.claude-last-activity"
    text: root.editWatcherLastActivityFile
    onTextChanged: root.editWatcherLastActivityFile = text
    Layout.fillWidth: true
  }

  NToggle {
    label: "Use fallback renewals"
    description: "Fallback when ccusage does not expose an active block"
    checked: root.editWatcherUseFallback
    onToggled: root.editWatcherUseFallback = checked
    Layout.fillWidth: true
  }

  NToggle {
    label: "Notify before reset"
    description: "Show a toast when the reset window is close"
    checked: root.editWatcherNotifyBeforeReset
    onToggled: root.editWatcherNotifyBeforeReset = checked
    Layout.fillWidth: true
  }

  NToggle {
    label: "Notify after reset"
    description: "Show a toast when the reset time is reached"
    checked: root.editWatcherNotifyAfterReset
    onToggled: root.editWatcherNotifyAfterReset = checked
    Layout.fillWidth: true
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("CCUsageBar", "Cannot save settings: pluginApi is null")
      return
    }

    const defaults = (pluginApi.manifest &&
      pluginApi.manifest.metadata &&
      pluginApi.manifest.metadata.defaultSettings) ? pluginApi.manifest.metadata.defaultSettings : {}
    const refreshInterval = parseInt(root.editRefreshInterval)

    pluginApi.pluginSettings.showInBar = root.editShowInBar
    pluginApi.pluginSettings.refreshIntervalSeconds =
      isNaN(refreshInterval) ? (defaults.refreshIntervalSeconds || 60) : refreshInterval
    pluginApi.pluginSettings.watcherEnabled = root.editWatcherEnabled
    pluginApi.pluginSettings.watcherMessage = root.editWatcherMessage || (defaults.watcherMessage || "hi")
    pluginApi.pluginSettings.watcherCheckIntervalSeconds =
      isNaN(root.editWatcherCheckInterval) ? (defaults.watcherCheckIntervalSeconds || 60) : root.editWatcherCheckInterval
    pluginApi.pluginSettings.watcherRenewWindowSeconds =
      isNaN(root.editWatcherRenewWindow) ? (defaults.watcherRenewWindowSeconds || 120) : root.editWatcherRenewWindow
    pluginApi.pluginSettings.watcherResetSeconds =
      isNaN(root.editWatcherResetSeconds) ? (defaults.watcherResetSeconds || 18000) : root.editWatcherResetSeconds
    pluginApi.pluginSettings.watcherLastActivityFile =
      root.editWatcherLastActivityFile || (defaults.watcherLastActivityFile || "$HOME/.claude-last-activity")
    pluginApi.pluginSettings.watcherUseFallback = root.editWatcherUseFallback
    pluginApi.pluginSettings.watcherNotifyBeforeReset = root.editWatcherNotifyBeforeReset
    pluginApi.pluginSettings.watcherNotifyAfterReset = root.editWatcherNotifyAfterReset

    pluginApi.saveSettings()
    if (pluginApi.mainInstance && pluginApi.mainInstance.syncSettings) {
      pluginApi.mainInstance.syncSettings()
    }
    if (pluginApi.mainInstance && pluginApi.mainInstance.refreshUsage) {
      pluginApi.mainInstance.refreshUsage()
    }
    Logger.i("CCUsageBar", "Settings saved successfully")
  }
}
