import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  // General settings
  property string editRefreshInterval: ""
  property bool editShowBar: true
  property bool editAutoResetEnabled: true

  // Claude settings
  property bool editClaudeEnabled: true
  property bool editShowClaudeInBar: true
  property bool editWatcherEnabled: true
  property string editWatcherMessage: "hi"

  // Codex settings
  property bool editCodexEnabled: true
  property bool editShowCodexInBar: true
  property string editCodexCredentialsPath: "$HOME/.codex/auth.json"
  property bool editCodexResetEnabled: false
  property string editCodexResetMessage: "hi"

  Component.onCompleted: updateFromSettings()
  onPluginApiChanged: if (pluginApi) updateFromSettings()

  function pickValue(value, fallback) {
    return (value === undefined || value === null) ? fallback : value
  }

  function updateFromSettings() {
    if (!pluginApi) return

    const defaults = pluginApi.manifest?.metadata?.defaultSettings || {}
    const settings = pluginApi.pluginSettings || {}

    editRefreshInterval = String(pickValue(settings.refreshIntervalSeconds,
      pickValue(defaults.refreshIntervalSeconds, 60)))
    editShowBar = pickValue(settings.showBar,
      pickValue(settings.showInBar, pickValue(defaults.showBar, pickValue(defaults.showInBar, true))))
    editAutoResetEnabled = pickValue(settings.autoResetEnabled,
      pickValue(defaults.autoResetEnabled, true))

    // Claude settings
    editClaudeEnabled = pickValue(settings.claudeEnabled, pickValue(defaults.claudeEnabled, true))
    editShowClaudeInBar = pickValue(settings.showClaudeInBar, pickValue(defaults.showClaudeInBar, true))
    editWatcherEnabled = pickValue(settings.claudeResetEnabled,
      pickValue(settings.watcherEnabled,
        pickValue(defaults.claudeResetEnabled, pickValue(defaults.watcherEnabled, true))))
    editWatcherMessage = settings.claudeResetMessage ||
      settings.watcherMessage ||
      defaults.claudeResetMessage ||
      defaults.watcherMessage ||
      "hi"

    // Codex settings (openaiEnabled/showOpenaiInBar are legacy)
    editCodexEnabled = pickValue(settings.codexEnabled,
      pickValue(defaults.codexEnabled, pickValue(settings.openaiEnabled, pickValue(defaults.openaiEnabled, true))))
    editShowCodexInBar = pickValue(settings.showCodexInBar,
      pickValue(defaults.showCodexInBar, pickValue(settings.showOpenaiInBar, pickValue(defaults.showOpenaiInBar, true))))
    editCodexCredentialsPath = settings.codexCredentialsPath || settings.openaiCredentialsPath || defaults.codexCredentialsPath || defaults.openaiCredentialsPath || "$HOME/.codex/auth.json"
    editCodexResetEnabled = pickValue(settings.codexResetEnabled, pickValue(defaults.codexResetEnabled, false))
    editCodexResetMessage = settings.codexResetMessage || defaults.codexResetMessage || "hi"
  }

  spacing: Style.marginM

  // General section
  NText {
    text: "General"
    font.weight: Font.DemiBold
    color: Color.mOnSurface
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Refresh interval (seconds)"
    description: "How often to fetch usage data"
    placeholderText: "60"
    text: root.editRefreshInterval
    onTextChanged: root.editRefreshInterval = text
    Layout.fillWidth: true
  }

  NToggle {
    label: "Show bar widget"
    description: "Display the usage widget in the bar"
    checked: root.editShowBar
    onToggled: root.editShowBar = checked
    Layout.fillWidth: true
  }

  NToggle {
    label: "Enable auto reset"
    description: "Allow CLI reset messages on window refresh"
    checked: root.editAutoResetEnabled
    onToggled: root.editAutoResetEnabled = checked
    Layout.fillWidth: true
  }

  NDivider { Layout.fillWidth: true }

  // Claude Code section
  NText {
    text: "Claude Code"
    font.weight: Font.DemiBold
    color: Color.mOnSurface
    Layout.fillWidth: true
  }

  NText {
    text: "Reads OAuth token from ~/.claude/.credentials.json"
    pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  NToggle {
    label: "Enable Claude tracking"
    description: "Track Claude Code API usage"
    checked: root.editClaudeEnabled
    onToggled: root.editClaudeEnabled = checked
    Layout.fillWidth: true
  }

  NToggle {
    label: "Show in bar"
    description: "Display Claude usage in the bar widget"
    checked: root.editShowClaudeInBar
    onToggled: root.editShowClaudeInBar = checked
    enabled: root.editClaudeEnabled
    Layout.fillWidth: true
  }

  NToggle {
    label: "Auto reset"
    description: "Send a message to Claude CLI when the 5-hour window resets"
    checked: root.editWatcherEnabled
    onToggled: root.editWatcherEnabled = checked
    enabled: root.editClaudeEnabled && root.editAutoResetEnabled
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Reset message"
    description: "Message sent to trigger a new window"
    placeholderText: "hi"
    text: root.editWatcherMessage
    onTextChanged: root.editWatcherMessage = text
    enabled: root.editClaudeEnabled && root.editAutoResetEnabled && root.editWatcherEnabled
    Layout.fillWidth: true
  }

  NDivider { Layout.fillWidth: true }

  // Codex section
  NText {
    text: "Codex (OpenAI)"
    font.weight: Font.DemiBold
    color: Color.mOnSurface
    Layout.fillWidth: true
  }

  NToggle {
    label: "Enable Codex tracking"
    description: "Track Codex/OpenAI API usage"
    checked: root.editCodexEnabled
    onToggled: root.editCodexEnabled = checked
    Layout.fillWidth: true
  }

  NToggle {
    label: "Show in bar"
    description: "Display Codex usage in the bar widget"
    checked: root.editShowCodexInBar
    onToggled: root.editShowCodexInBar = checked
    enabled: root.editCodexEnabled
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Credentials path"
    description: "Path to Codex auth.json file"
    placeholderText: "$HOME/.codex/auth.json"
    text: root.editCodexCredentialsPath
    onTextChanged: root.editCodexCredentialsPath = text
    enabled: root.editCodexEnabled
    Layout.fillWidth: true
  }

  NToggle {
    label: "Auto reset"
    description: "Send a message to Codex CLI when the 5-hour window resets"
    checked: root.editCodexResetEnabled
    onToggled: root.editCodexResetEnabled = checked
    enabled: root.editCodexEnabled && root.editAutoResetEnabled
    Layout.fillWidth: true
  }

  NTextInput {
    label: "Reset message"
    description: "Message sent to trigger a new window"
    placeholderText: "hi"
    text: root.editCodexResetMessage
    onTextChanged: root.editCodexResetMessage = text
    enabled: root.editCodexEnabled && root.editAutoResetEnabled && root.editCodexResetEnabled
    Layout.fillWidth: true
  }

  function saveSettings() {
    if (!pluginApi) return

    const defaults = pluginApi.manifest?.metadata?.defaultSettings || {}
    const refreshInterval = parseInt(root.editRefreshInterval)

    // General
    pluginApi.pluginSettings.refreshIntervalSeconds =
      isNaN(refreshInterval) ? (defaults.refreshIntervalSeconds || 60) : refreshInterval
    pluginApi.pluginSettings.showBar = root.editShowBar
    pluginApi.pluginSettings.showInBar = root.editShowBar // Legacy compat
    pluginApi.pluginSettings.autoResetEnabled = root.editAutoResetEnabled

    // Claude settings
    pluginApi.pluginSettings.claudeEnabled = root.editClaudeEnabled
    pluginApi.pluginSettings.showClaudeInBar = root.editShowClaudeInBar
    pluginApi.pluginSettings.claudeResetEnabled = root.editWatcherEnabled
    pluginApi.pluginSettings.claudeResetMessage =
      root.editWatcherMessage || defaults.claudeResetMessage || defaults.watcherMessage || "hi"
    pluginApi.pluginSettings.watcherEnabled = root.editWatcherEnabled
    pluginApi.pluginSettings.watcherMessage =
      root.editWatcherMessage || defaults.watcherMessage || "hi"

    // Codex settings
    pluginApi.pluginSettings.codexEnabled = root.editCodexEnabled
    pluginApi.pluginSettings.showCodexInBar = root.editShowCodexInBar
    pluginApi.pluginSettings.openaiEnabled = root.editCodexEnabled // Legacy compat
    pluginApi.pluginSettings.showOpenaiInBar = root.editShowCodexInBar // Legacy compat
    pluginApi.pluginSettings.codexCredentialsPath = root.editCodexCredentialsPath || "$HOME/.codex/auth.json"
    pluginApi.pluginSettings.openaiCredentialsPath = root.editCodexCredentialsPath // Legacy compat
    pluginApi.pluginSettings.codexResetEnabled = root.editCodexResetEnabled
    pluginApi.pluginSettings.codexResetMessage =
      root.editCodexResetMessage || defaults.codexResetMessage || "hi"

    pluginApi.saveSettings()
    if (pluginApi.mainInstance?.syncSettings) {
      pluginApi.mainInstance.syncSettings()
    }
    if (pluginApi.mainInstance?.refreshUsage) {
      pluginApi.mainInstance.refreshUsage()
    }
  }
}
