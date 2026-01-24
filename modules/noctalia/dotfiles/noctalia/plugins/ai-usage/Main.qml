import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "providers" as Providers

Item {
    id: root

    property var pluginApi: null
    property bool showBar: true

    // Claude bindings exposed to the bar/panel
    property alias claudeEnabled: claudeProvider.enabled
    property alias showClaudeInBar: claudeProvider.showInBar
    property alias fiveHourUtilization: claudeProvider.fiveHourUtilization
    property alias fiveHourResetsAt: claudeProvider.fiveHourResetsAt
    property alias fiveHourRemainingSec: claudeProvider.fiveHourRemainingSec
    property alias sevenDayUtilization: claudeProvider.sevenDayUtilization
    property alias lastError: claudeProvider.lastError
    readonly property string claudePlanType: claudeProvider.planType
    property alias claudeHasData: claudeProvider.hasData
    property alias watcherRenewing: claudeProvider.watcherRenewing

    // Codex bindings exposed to the bar/panel
    property alias codexEnabled: codexProvider.enabled
    property alias showCodexInBar: codexProvider.showInBar
    property alias codexPrimaryPercent: codexProvider.primaryPercent
    property alias codexSecondaryPercent: codexProvider.secondaryPercent
    property alias codexPrimaryResetSec: codexProvider.primaryResetSec
    property alias codexSecondaryResetSec: codexProvider.secondaryResetSec
    property alias codexPlanType: codexProvider.planType
    property alias codexHasData: codexProvider.hasData
    property alias codexLastError: codexProvider.lastError
    property alias codexConnected: codexProvider.connected

    property bool isBusy: claudeProvider.isBusy || codexProvider.isBusy
    property bool depsOk: claudeProvider.depsOk && codexProvider.depsOk
    property bool hasData: claudeProvider.hasData || codexProvider.hasData

    readonly property int refreshIntervalSeconds:
        pluginApi?.pluginSettings?.refreshIntervalSeconds ??
        pluginApi?.manifest?.metadata?.defaultSettings?.refreshIntervalSeconds ??
        60

    Timer {
        interval: root.refreshIntervalSeconds * 1000
        running: !!root.pluginApi
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }

    IpcHandler {
        target: "plugin:ai-usage"

        function refresh() {
            root.refreshUsage()
        }

        function openPanel() {
            if (pluginApi && pluginApi.withCurrentScreen && pluginApi.openPanel) {
                pluginApi.withCurrentScreen(function(screen) {
                    pluginApi.openPanel(screen)
                })
            }
        }

        function openSettings() {
            if (pluginApi && pluginApi.openSettings) {
                pluginApi.openSettings()
            }
        }
    }

    Component.onCompleted: {
        Logger.i("AIUsage", "Main loaded")
        syncSettings()
    }
    onPluginApiChanged: {
        Logger.d("AIUsage", "pluginApi changed")
        syncSettings()
    }

    function syncSettings() {
        if (!pluginApi) return
        const settings = pluginApi.pluginSettings || {}
        const defaults = pluginApi.manifest?.metadata?.defaultSettings || {}

        root.showBar =
            settings.showBar ??
            defaults.showBar ??
            settings.showInBar ??
            defaults.showInBar ??
            true

        claudeProvider.syncSettings(settings, defaults)
        codexProvider.syncSettings(settings, defaults)
        Logger.d("AIUsage", "syncSettings showBar=" + root.showBar +
            " claudeEnabled=" + claudeProvider.enabled +
            " codexEnabled=" + codexProvider.enabled)
    }

    function refreshUsage() {
        Logger.d("AIUsage", "refreshUsage claudeEnabled=" + claudeProvider.enabled +
            " codexEnabled=" + codexProvider.enabled)
        claudeProvider.refresh()
        codexProvider.refresh()
    }

    Providers.ClaudeProvider {
        id: claudeProvider
    }

    Providers.CodexProvider {
        id: codexProvider
    }
}
