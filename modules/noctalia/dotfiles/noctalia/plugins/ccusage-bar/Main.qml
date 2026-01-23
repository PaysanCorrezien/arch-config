import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    property bool isBusy: false
    property bool depsOk: true
    property bool barVisible: true
    property bool hasData: false
    property string lastError: ""

    property real currentCost: 0
    property int currentTokens: 0
    property string currentStart: ""
    property string currentEnd: ""
    property int currentRemainingSec: 0
    property int currentElapsedSec: 0
    property int currentDurationSec: 0
    property bool currentIsGap: false
    property int currentEntries: 0
    property int currentInputTokens: 0
    property int currentOutputTokens: 0
    property int currentCacheWriteTokens: 0
    property int currentCacheReadTokens: 0
    property string currentModels: ""

    readonly property string planLabel:
        pluginApi?.pluginSettings?.plan ??
        pluginApi?.manifest?.metadata?.defaultSettings?.plan ??
        "pro"
    property int sessionCount: 0
    property string topSessionsSummary: ""

    property real dayCost: 0
    property int dayTokens: 0
    property real weekCost: 0
    property int weekTokens: 0
    property real monthCost: 0
    property int monthTokens: 0
    property real totalCost: 0
    property int totalTokens: 0

    readonly property int refreshIntervalSeconds:
        pluginApi?.pluginSettings?.refreshIntervalSeconds ||
        pluginApi?.manifest?.metadata?.defaultSettings?.refreshIntervalSeconds ||
        60

    readonly property bool watcherEnabled:
        pluginApi?.pluginSettings?.watcherEnabled ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherEnabled ??
        false

    readonly property string watcherMessage:
        pluginApi?.pluginSettings?.watcherMessage ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherMessage ??
        "hi"

    readonly property int watcherCheckIntervalSeconds:
        pluginApi?.pluginSettings?.watcherCheckIntervalSeconds ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherCheckIntervalSeconds ??
        60

    readonly property int watcherRenewWindowSeconds:
        pluginApi?.pluginSettings?.watcherRenewWindowSeconds ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherRenewWindowSeconds ??
        120

    readonly property int watcherResetSeconds:
        pluginApi?.pluginSettings?.watcherResetSeconds ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherResetSeconds ??
        18000

    readonly property string watcherLastActivityFile:
        pluginApi?.pluginSettings?.watcherLastActivityFile ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherLastActivityFile ??
        "$HOME/.claude-last-activity"

    readonly property bool watcherUseFallback:
        pluginApi?.pluginSettings?.watcherUseFallback ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherUseFallback ??
        true

    readonly property bool watcherNotifyBeforeReset:
        pluginApi?.pluginSettings?.watcherNotifyBeforeReset ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherNotifyBeforeReset ??
        false

    readonly property bool watcherNotifyAfterReset:
        pluginApi?.pluginSettings?.watcherNotifyAfterReset ??
        pluginApi?.manifest?.metadata?.defaultSettings?.watcherNotifyAfterReset ??
        false

    property bool watcherCheckBusy: false
    property bool watcherRenewing: false
    property int watcherPrevRemaining: -1
    property string watcherPrevEndTime: ""
    property string watcherNotifiedBeforeEndTime: ""
    property string watcherNotifiedAfterEndTime: ""
    property string watcherRenewTargetEndTime: ""

    readonly property bool defaultShowInBar:
        pluginApi?.manifest?.metadata?.defaultSettings?.showInBar ?? true

    Timer {
        interval: root.refreshIntervalSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }

    Timer {
        id: watcherTimer
        interval: Math.max(5, root.watcherCheckIntervalSeconds) * 1000
        running: root.watcherEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkWatcher()
    }

    IpcHandler {
        target: "plugin:ccusage-bar"

        function toggle() {
            root.setBarVisible(!root.barVisible)
        }

        function show() {
            root.setBarVisible(true)
        }

        function hide() {
            root.setBarVisible(false)
        }

        function refresh() {
            root.refreshUsage()
        }

        function openPanel() {
            if (pluginApi && pluginApi.withCurrentScreen && pluginApi.openPanel) {
                pluginApi.withCurrentScreen(function(screen) {
                    pluginApi.openPanel(screen)
                })
                return
            }
            Logger.w("CCUsageBar", "Cannot open panel: pluginApi is unavailable")
        }

        function openSettings() {
            if (pluginApi && pluginApi.openSettings) {
                pluginApi.openSettings()
                return
            }
            settingsToggleProcess.exec({
                "command": ["qs", "-c", "noctalia-shell", "ipc", "call", "settings", "toggle"]
            })
        }
    }

    Component.onCompleted: syncSettings()
    onPluginApiChanged: syncSettings()
    onWatcherEnabledChanged: {
        if (!root.watcherEnabled) {
            root.watcherCheckBusy = false
            root.watcherNotifiedBeforeEndTime = ""
            root.watcherNotifiedAfterEndTime = ""
            root.watcherRenewTargetEndTime = ""
        }
    }

    function syncSettings() {
        if (!pluginApi) return
        const setting = pluginApi.pluginSettings?.showInBar
        if (setting === undefined || setting === null) {
            pluginApi.pluginSettings.showInBar = root.defaultShowInBar
            pluginApi.saveSettings()
        }
        root.barVisible = pluginApi.pluginSettings?.showInBar ?? root.defaultShowInBar
    }

    function setBarVisible(value) {
        root.barVisible = value
        if (pluginApi && pluginApi.pluginSettings) {
            pluginApi.pluginSettings.showInBar = value
            pluginApi.saveSettings()
        }
    }

    function refreshUsage() {
        if (root.isBusy) return
        root.isBusy = true
        root.lastError = ""
        depsProcess.exec({
            "command": ["sh", "-c", "command -v ccusage >/dev/null 2>&1 && command -v jq >/dev/null 2>&1"]
        })
    }

    function runUsageQuery() {
        const cmd =
            "now=$(date +%s); " +
            "today=$(date +%F); " +
            "week_start=$(date -d \"$(date +%w) days ago\" +%F); " +
            "month=$(date +%Y-%m); " +
            "blocks=$(ccusage blocks --json --offline --no-color 2>/dev/null || echo '{\"blocks\":[]}'); " +
            "daily=$(ccusage daily --json --offline --no-color 2>/dev/null || echo '{\"daily\":[]}'); " +
            "weekly=$(ccusage weekly --json --offline --no-color 2>/dev/null || echo '{\"weekly\":[]}'); " +
            "monthly=$(ccusage monthly --json --offline --no-color 2>/dev/null || echo '{\"monthly\":[]}'); " +
            "sessions=$(ccusage session --json --offline --no-color 2>/dev/null || echo '{\"sessions\":[]}'); " +
            "jq -n --argjson blocks \"$blocks\" --argjson daily \"$daily\" --argjson weekly \"$weekly\" " +
            "--argjson monthly \"$monthly\" --argjson sessions \"$sessions\" --arg today \"$today\" --arg week \"$week_start\" --arg month \"$month\" " +
            "--argjson now \"$now\" 'def to_epoch: (fromdateiso8601? // 0); " +
            "($blocks.blocks // []) as $b | " +
            "($b | map(. + {startEpoch:(.startTime|to_epoch), endEpoch:(.endTime|to_epoch)})) as $bx | " +
            "($bx | map(select(.startEpoch <= $now and .endEpoch > $now)) | .[0]) as $cur | " +
            "{currentCost: ($cur.costUSD // 0), " +
            " currentTokens: ($cur.totalTokens // 0), " +
            " currentStart: ($cur.startTime // \"\"), " +
            " currentEnd: ($cur.endTime // \"\"), " +
            " currentRemainingSec: (if $cur then ($cur.endEpoch - $now) else 0 end), " +
            " currentElapsedSec: (if $cur then ($now - $cur.startEpoch) else 0 end), " +
            " currentDurationSec: (if $cur then ($cur.endEpoch - $cur.startEpoch) else 0 end), " +
            " currentIsGap: ($cur.isGap // false), " +
            " currentEntries: ($cur.entries // 0), " +
            " currentInputTokens: ($cur.tokenCounts.inputTokens // 0), " +
            " currentOutputTokens: ($cur.tokenCounts.outputTokens // 0), " +
            " currentCacheWriteTokens: ($cur.tokenCounts.cacheCreationInputTokens // 0), " +
            " currentCacheReadTokens: ($cur.tokenCounts.cacheReadInputTokens // 0), " +
            " currentModels: (($cur.models // []) | join(\", \")), " +
            " dayCost: ((($daily.daily // []) | map(select(.date==$today)) | .[0].totalCost) // 0), " +
            " dayTokens: ((($daily.daily // []) | map(select(.date==$today)) | .[0].totalTokens) // 0), " +
            " weekCost: ((($weekly.weekly // []) | map(select(.week==$week)) | .[0].totalCost) // 0), " +
            " weekTokens: ((($weekly.weekly // []) | map(select(.week==$week)) | .[0].totalTokens) // 0), " +
            " monthCost: ((($monthly.monthly // []) | map(select(.month==$month)) | .[0].totalCost) // 0), " +
            " monthTokens: ((($monthly.monthly // []) | map(select(.month==$month)) | .[0].totalTokens) // 0), " +
            " totalCost: (((($monthly.monthly // []) | map(.totalCost) | add)) // 0), " +
            " totalTokens: (((($monthly.monthly // []) | map(.totalTokens) | add)) // 0), " +
            " sessionCount: ((($sessions.sessions // []) | length) // 0), " +
            " topSessionsSummary: ((($sessions.sessions // []) | sort_by(.totalCost) | reverse | .[0:3] | " +
            "   map((.sessionId // \"unknown\") + \" ($\" + ((.totalCost // 0) | tostring) + \")\") | join(\" | \")) // \"\") }'"

        usageProcess.exec({ "command": ["sh", "-c", cmd] })
    }

    function shellQuote(value) {
        if (value === null || value === undefined) return "''"
        const text = String(value)
        return "'" + text.replace(/'/g, "'\"'\"'") + "'"
    }

    function lastActivityShellInit() {
        const raw = root.watcherLastActivityFile || "$HOME/.claude-last-activity"
        const quoted = shellQuote(raw)
        return "last_activity_file=" + quoted + "; " +
            "last_activity_file=$(printf '%s' \"$last_activity_file\" | sed \"s|^~|$HOME|; s|\\\\$HOME|$HOME|g\"); "
    }

    function buildSecondsUntilResetCommand() {
        return "reset_file=/tmp/ccusage.md; " +
            "if [ -f \"$reset_file\" ]; then " +
            "reset_time=$(grep -Eo -m1 '([0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9:]+)?)' \"$reset_file\" 2>/dev/null || true); " +
            "if [ -n \"$reset_time\" ]; then " +
            "end_epoch=$(date -d \"$reset_time\" +%s 2>/dev/null) || end_epoch=''; " +
            "if [ -n \"$end_epoch\" ]; then " +
            "now=$(date +%s); remaining=$((end_epoch - now)); " +
            "if [ \"$remaining\" -lt 0 ]; then remaining=0; fi; " +
            "printf '%s|%s\n' \"$remaining\" \"$reset_time\"; exit 0; fi; fi; fi; " +
            "command -v ccusage >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 1; " +
            "json=$(ccusage blocks --json --active 2>/dev/null) || exit 1; " +
            "end_time=$(printf '%s' \"$json\" | jq -r '.blocks[0].endTime // empty') || exit 1; " +
            "if [ -z \"$end_time\" ]; then echo none; exit 0; fi; " +
            "end_epoch=$(date -d \"$end_time\" +%s 2>/dev/null) || exit 1; " +
            "now=$(date +%s); remaining=$((end_epoch - now)); " +
            "if [ \"$remaining\" -lt 0 ]; then remaining=0; fi; " +
            "printf '%s|%s\n' \"$remaining\" \"$end_time\";"
    }

    function buildFallbackCommand() {
        const resetSeconds = Math.max(0, root.watcherResetSeconds || 0)
        return lastActivityShellInit() +
            "now=$(date +%s); " +
            "if [ ! -f \"$last_activity_file\" ]; then echo renew; exit 0; fi; " +
            "last_activity=$(cat \"$last_activity_file\" 2>/dev/null || true); " +
            "if [ -z \"$last_activity\" ]; then echo renew; exit 0; fi; " +
            "elapsed=$((now - last_activity)); " +
            "if [ \"$elapsed\" -ge \"" + resetSeconds + "\" ]; then echo renew; else echo skip; fi;"
    }

    function buildRenewCommand() {
        const message = shellQuote(root.watcherMessage || "hi")
        return lastActivityShellInit() +
            "command -v claude >/dev/null 2>&1 || exit 2; " +
            "if printf '%s\n' " + message + " | claude >/dev/null 2>&1; then " +
            "date +%s > \"$last_activity_file\"; exit 0; fi; exit 1;"
    }

    function checkWatcher() {
        if (!root.watcherEnabled || root.watcherCheckBusy || root.watcherRenewing) return
        root.watcherCheckBusy = true
        watcherCheckProcess.exec({ "command": ["sh", "-c", buildSecondsUntilResetCommand()] })
    }

    function handleWatcherCheckResult(payload) {
        if (payload === "none" || payload.length === 0) {
            if (!root.watcherUseFallback) {
                root.watcherCheckBusy = false
                return
            }
            watcherFallbackProcess.exec({ "command": ["sh", "-c", buildFallbackCommand()] })
            return
        }

        const parts = payload.split("|")
        const remaining = parseInt(parts[0] || "0")
        const endTime = parts.slice(1).join("|")
        const windowSeconds = Math.max(0, root.watcherRenewWindowSeconds || 0)

        if (root.watcherNotifyBeforeReset && remaining > 0 && remaining <= windowSeconds) {
            if (endTime && endTime !== root.watcherNotifiedBeforeEndTime) {
                ToastService.showNotice("Claude reset in " + formatRemaining(remaining))
                root.watcherNotifiedBeforeEndTime = endTime
            }
        }

        if (remaining <= 0 && !root.watcherRenewing) {
            if (endTime && endTime !== root.watcherRenewTargetEndTime) {
                root.watcherPrevRemaining = remaining
                root.watcherPrevEndTime = endTime
                root.watcherRenewTargetEndTime = endTime
                root.startRenewal()
            }
        }

        root.watcherCheckBusy = false
    }

    function startRenewal() {
        if (!root.watcherEnabled || root.watcherRenewing) return
        root.watcherRenewing = true
        watcherRenewProcess.exec({ "command": ["sh", "-c", buildRenewCommand()] })
    }

    function formatRemaining(seconds) {
        const total = Math.max(0, seconds || 0)
        const mins = Math.floor(total / 60)
        const secs = total % 60
        if (mins <= 0) return secs + "s"
        return mins + "m " + secs + "s"
    }

    Process {
        id: depsProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.depsOk = false
                root.lastError = "Missing ccusage or jq"
                root.isBusy = false
                return
            }
            root.depsOk = true
            runUsageQuery()
        }
    }

    Process {
        id: usageProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.lastError = "ccusage failed to run"
                root.isBusy = false
                return
            }

            try {
                const payload = JSON.parse(String(usageProcess.stdout.text || "").trim() || "{}")
                root.currentCost = parseFloat(payload.currentCost || 0)
                root.currentTokens = parseInt(payload.currentTokens || 0)
                root.currentStart = payload.currentStart || ""
                root.currentEnd = payload.currentEnd || ""
                root.currentRemainingSec = parseInt(payload.currentRemainingSec || 0)
                root.currentElapsedSec = parseInt(payload.currentElapsedSec || 0)
                root.currentDurationSec = parseInt(payload.currentDurationSec || 0)
                root.currentIsGap = payload.currentIsGap === true
                root.currentEntries = parseInt(payload.currentEntries || 0)
                root.currentInputTokens = parseInt(payload.currentInputTokens || 0)
                root.currentOutputTokens = parseInt(payload.currentOutputTokens || 0)
                root.currentCacheWriteTokens = parseInt(payload.currentCacheWriteTokens || 0)
                root.currentCacheReadTokens = parseInt(payload.currentCacheReadTokens || 0)
                root.currentModels = payload.currentModels || ""

                root.dayCost = parseFloat(payload.dayCost || 0)
                root.dayTokens = parseInt(payload.dayTokens || 0)
                root.weekCost = parseFloat(payload.weekCost || 0)
                root.weekTokens = parseInt(payload.weekTokens || 0)
                root.monthCost = parseFloat(payload.monthCost || 0)
                root.monthTokens = parseInt(payload.monthTokens || 0)
                root.totalCost = parseFloat(payload.totalCost || 0)
                root.totalTokens = parseInt(payload.totalTokens || 0)
                root.sessionCount = parseInt(payload.sessionCount || 0)
                root.topSessionsSummary = payload.topSessionsSummary || ""
                root.hasData = true
            } catch (e) {
                root.lastError = "Failed to parse ccusage output"
            }

            root.isBusy = false
        }
    }

    Process {
        id: watcherCheckProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            const output = String(watcherCheckProcess.stdout.text || "").trim()
            if (exitCode !== 0) {
                root.watcherCheckBusy = false
                return
            }
            handleWatcherCheckResult(output)
        }
    }

    Process {
        id: watcherFallbackProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            const output = String(watcherFallbackProcess.stdout.text || "").trim()
            if (exitCode === 0 && output === "renew") {
                root.watcherPrevRemaining = -1
                root.watcherPrevEndTime = ""
                root.startRenewal()
            }
            root.watcherCheckBusy = false
        }
    }

    Process {
        id: watcherRenewProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.watcherRenewing = false
                ToastService.showError("Claude renewal failed")
                return
            }
            watcherVerifyProcess.exec({ "command": ["sh", "-c", buildSecondsUntilResetCommand()] })
        }
    }

    Process {
        id: watcherVerifyProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            const output = String(watcherVerifyProcess.stdout.text || "").trim()
            let renewed = false
            let remaining = 0
            if (exitCode === 0 && output && output !== "none") {
                const parts = output.split("|")
                remaining = parseInt(parts[0] || "0")
                const endTime = parts.slice(1).join("|")
                if (endTime && endTime !== root.watcherPrevEndTime) {
                    renewed = true
                } else if (remaining > root.watcherPrevRemaining) {
                    renewed = true
                }
            }

            if (renewed) {
                if (root.watcherNotifyAfterReset) {
                    ToastService.showNotice("Claude reset renewed")
                }
                root.watcherNotifiedAfterEndTime = root.watcherPrevEndTime
                root.watcherRenewTargetEndTime = ""
            } else {
                ToastService.showError("Claude renewal did not update reset timer")
            }

            root.watcherRenewing = false
        }
    }

    Process {
        id: settingsToggleProcess
    }
}
