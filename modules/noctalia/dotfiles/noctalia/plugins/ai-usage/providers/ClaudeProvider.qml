import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "ProviderUtils.js" as ProviderUtils
import "../watcher" as Watcher

Item {
    id: claude
    visible: false
    width: 0
    height: 0

    property bool enabled: true
    property bool showInBar: true
    property bool hasData: false
    property bool depsOk: true
    property bool isBusy: false
    property string lastError: ""

    property real fiveHourUtilization: 0
    property string fiveHourResetsAt: ""
    property int fiveHourRemainingSec: 0
    property real sevenDayUtilization: 0
    property string planType: ""

    property bool autoResetEnabled: true
    property bool resetEnabled: true
    property string resetMessage: "hi"
    property int resetWindowSec: 5 * 60 * 60
    property string autoResetResetsAt: ""
    property int autoResetRemainingSec: 0
    property bool autoResetFallback: false
    property alias watcherRenewing: resetWatcher.renewing

    Component.onCompleted: Logger.i("AIUsage", "ClaudeProvider loaded")

    function syncSettings(settings, defaults) {
        enabled = ProviderUtils.pick(settings, defaults, "claudeEnabled", true)
        showInBar = ProviderUtils.pick(settings, defaults, "showClaudeInBar", true)
        autoResetEnabled = ProviderUtils.pick(settings, defaults, "autoResetEnabled", true)
        resetEnabled = ProviderUtils.pick(settings, defaults, "claudeResetEnabled",
            ProviderUtils.pick(settings, defaults, "watcherEnabled", false))
        resetMessage = ProviderUtils.pick(settings, defaults, "claudeResetMessage",
            ProviderUtils.pick(settings, defaults, "watcherMessage", "hi"))

        resetWatcher.enabled = autoResetEnabled && resetEnabled
        resetWatcher.message = resetMessage
        resetWatcher.providerEnabled = enabled
        resetWatcher.providerName = "Claude"
        resetWatcher.cliCommand = "claude"

        if (!enabled) {
            clearUsage()
        }
        Logger.d("AIUsage", "Claude sync enabled=" + enabled +
            " showInBar=" + showInBar +
            " autoReset=" + (autoResetEnabled && resetEnabled))
    }

    function clearUsage() {
        fiveHourUtilization = 0
        fiveHourResetsAt = ""
        fiveHourRemainingSec = 0
        sevenDayUtilization = 0
        planType = ""
        lastError = ""
        hasData = false
        autoResetResetsAt = ""
        autoResetRemainingSec = 0
        autoResetFallback = false
    }

    function updateAutoResetTarget(resetsAt, remainingSec) {
        if (resetsAt) {
            autoResetFallback = false
            autoResetResetsAt = resetsAt
            autoResetRemainingSec = remainingSec
            Logger.d("AIUsage", "Claude auto-reset target resetAt=" +
                autoResetResetsAt + " remaining=" + autoResetRemainingSec)
            return
        }
        if (!autoResetResetsAt && resetWindowSec > 0) {
            autoResetFallback = true
            autoResetResetsAt = ProviderUtils.resetAtFromNow(resetWindowSec)
            autoResetRemainingSec = resetWindowSec
            Logger.d("AIUsage", "Claude auto-reset fallback resetAt=" +
                autoResetResetsAt + " windowSec=" + resetWindowSec)
        }
    }

    function scheduleFallbackReset() {
        if (resetWindowSec <= 0) return
        autoResetFallback = true
        autoResetResetsAt = ProviderUtils.resetAtFromNow(resetWindowSec)
        autoResetRemainingSec = resetWindowSec
        Logger.d("AIUsage", "Claude auto-reset scheduled resetAt=" +
            autoResetResetsAt + " windowSec=" + resetWindowSec)
    }

    function refresh() {
        if (!enabled) {
            clearUsage()
            Logger.d("AIUsage", "Claude refresh skipped (disabled)")
            return
        }
        if (isBusy) return
        isBusy = true
        lastError = ""
        Logger.d("AIUsage", "Claude refresh start")
        depsProcess.exec({
            "command": ["sh", "-c", "command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1"]
        })
    }

    function runUsageQuery() {
        const cmd =
            "token=$(jq -r '.claudeAiOauth.accessToken' ~/.claude/.credentials.json 2>/dev/null); " +
            "tier=$(jq -r '.claudeAiOauth.rateLimitTier // empty' ~/.claude/.credentials.json 2>/dev/null); " +
            "sub=$(jq -r '.claudeAiOauth.subscriptionType // empty' ~/.claude/.credentials.json 2>/dev/null); " +
            "if [ -z \"$token\" ] || [ \"$token\" = \"null\" ]; then " +
            "  echo '{\"error\":\"No access token found\"}'; exit 0; " +
            "fi; " +
            "response=$(curl -s -H \"Authorization: Bearer $token\" " +
            "  -H \"anthropic-beta: oauth-2025-04-20\" " +
            "  \"https://api.anthropic.com/api/oauth/usage\" 2>/dev/null); " +
            "if [ -z \"$response\" ]; then " +
            "  echo '{\"error\":\"Empty response from API\"}'; exit 0; " +
            "fi; " +
            "echo \"$response\" | jq -c --arg tier \"$tier\" --arg sub \"$sub\" '{ " +
            "  fiveHourUtilization: (.five_hour.utilization // 0), " +
            "  fiveHourResetsAt: (.five_hour.resets_at // \"\"), " +
            "  sevenDayUtilization: (.seven_day.utilization // 0), " +
            "  rateLimitTier: $tier, " +
            "  subscriptionType: $sub, " +
            "  error: (.error.message // null) " +
            "}'"

        usageProcess.exec({ "command": ["sh", "-c", cmd] })
    }

    Timer {
        id: remainingTimer
        interval: 1000
        running: claude.enabled
        repeat: true
        onTriggered: {
            if (claude.fiveHourRemainingSec > 0) {
                claude.fiveHourRemainingSec--
            }
            if (claude.autoResetRemainingSec > 0) {
                claude.autoResetRemainingSec--
            }
            resetWatcher.maybeRenew(claude.autoResetResetsAt, claude.autoResetRemainingSec)
        }
    }

    Process {
        id: depsProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                claude.depsOk = false
                claude.lastError = "Missing curl or jq"
                claude.isBusy = false
                Logger.w("AIUsage", "Claude deps check failed")
                return
            }
            claude.depsOk = true
            Logger.d("AIUsage", "Claude deps ok, querying usage")
            runUsageQuery()
        }
    }

    Process {
        id: usageProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            const rawOutput = String(usageProcess.stdout.text || "").trim()

            if (exitCode !== 0) {
                claude.lastError = "API request failed"
                claude.isBusy = false
                Logger.w("AIUsage", "Claude API request failed")
                return
            }

            try {
                const payload = JSON.parse(rawOutput || "{}")

                if (payload.error) {
                    claude.lastError = payload.error
                    claude.isBusy = false
                    Logger.w("AIUsage", "Claude API error: " + payload.error)
                    return
                }

                claude.fiveHourUtilization = parseFloat(payload.fiveHourUtilization || 0)
                claude.fiveHourResetsAt = payload.fiveHourResetsAt || ""
                claude.fiveHourRemainingSec = ProviderUtils.calculateRemainingSec(claude.fiveHourResetsAt)
                claude.updateAutoResetTarget(claude.fiveHourResetsAt, claude.fiveHourRemainingSec)
                claude.sevenDayUtilization = parseFloat(payload.sevenDayUtilization || 0)
                claude.planType = inferPlan(payload.rateLimitTier, payload.subscriptionType)
                claude.hasData = true
                Logger.d("AIUsage", "Claude plan tier=" + (payload.rateLimitTier || "") +
                    " sub=" + (payload.subscriptionType || "") +
                    " plan=" + claude.planType)
                Logger.d("AIUsage", "Claude usage updated 5h=" + claude.fiveHourUtilization +
                    " 7d=" + claude.sevenDayUtilization)
            } catch (e) {
                claude.lastError = "Failed to parse API response"
                Logger.e("AIUsage", "Claude parse error")
            }

            claude.isBusy = false
        }
    }

    Watcher.ResetWatcher {
        id: resetWatcher
        onRenewed: {
            if (claude.autoResetFallback) {
                claude.scheduleFallbackReset()
            }
            claude.refresh()
        }
    }

    function inferPlan(rateLimitTier, subscriptionType) {
        const tier = String(rateLimitTier || "").toLowerCase()
        const sub = String(subscriptionType || "").toLowerCase()
        if (tier.indexOf("max") >= 0 || sub === "max") return "Claude Max"
        if (tier.indexOf("pro") >= 0 || sub === "pro") return "Claude Pro"
        if (tier.indexOf("team") >= 0 || sub === "team") return "Claude Team"
        if (tier.indexOf("enterprise") >= 0 || sub === "enterprise") return "Claude Enterprise"
        if (sub === "free") return "Claude Free"
        if (tier.indexOf("default") >= 0 || tier.indexOf("claude_ai") >= 0) return "Claude"
        return rateLimitTier || subscriptionType || ""
    }
}
