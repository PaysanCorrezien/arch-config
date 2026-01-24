import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ProviderUtils.js" as ProviderUtils
import "../watcher" as Watcher

Item {
    id: codex
    visible: false
    width: 0
    height: 0

    property bool enabled: true
    property bool showInBar: true
    property bool hasData: false
    property bool depsOk: true
    property bool isBusy: false
    property string lastError: ""

    property bool connected: false
    property string credentialsPath: "$HOME/.codex/auth.json"
    property real primaryPercent: 0
    property real secondaryPercent: 0
    property int primaryResetSec: 0
    property int secondaryResetSec: 0
    property string planType: "unknown"
    property bool autoResetEnabled: true
    property bool resetEnabled: false
    property string resetMessage: "hi"
    property int resetWindowSec: 5 * 60 * 60
    property string autoResetResetsAt: ""
    property int autoResetRemainingSec: 0
    property bool autoResetFallback: false

    Component.onCompleted: Logger.i("AIUsage", "CodexProvider loaded")

    function syncSettings(settings, defaults) {
        enabled = ProviderUtils.pick(settings, defaults, "codexEnabled",
            ProviderUtils.pick(settings, defaults, "openaiEnabled", true))
        showInBar = ProviderUtils.pick(settings, defaults, "showCodexInBar",
            ProviderUtils.pick(settings, defaults, "showOpenaiInBar", true))
        credentialsPath =
            settings.codexCredentialsPath ||
            settings.openaiCredentialsPath ||
            (defaults ? defaults.codexCredentialsPath : null) ||
            (defaults ? defaults.openaiCredentialsPath : null) ||
            "$HOME/.codex/auth.json"

        autoResetEnabled = ProviderUtils.pick(settings, defaults, "autoResetEnabled", true)
        resetEnabled = ProviderUtils.pick(settings, defaults, "codexResetEnabled", false)
        resetMessage = ProviderUtils.pick(settings, defaults, "codexResetMessage", "hi")

        resetWatcher.enabled = autoResetEnabled && resetEnabled
        resetWatcher.message = resetMessage
        resetWatcher.providerEnabled = enabled
        resetWatcher.providerName = "Codex"
        resetWatcher.cliCommand = "codex"

        if (!enabled) {
            clearUsage()
        }
        Logger.d("AIUsage", "Codex sync enabled=" + enabled +
            " showInBar=" + showInBar +
            " credentialsPath=" + credentialsPath +
            " autoReset=" + (autoResetEnabled && resetEnabled))
    }

    function clearUsage() {
        primaryPercent = 0
        secondaryPercent = 0
        primaryResetSec = 0
        secondaryResetSec = 0
        planType = ""
        connected = false
        hasData = false
        lastError = ""
        autoResetResetsAt = ""
        autoResetRemainingSec = 0
        autoResetFallback = false
    }

    function updateAutoResetTarget(resetSec) {
        const safe = parseInt(resetSec || 0)
        if (safe > 0) {
            autoResetFallback = false
            autoResetRemainingSec = safe
            autoResetResetsAt = ProviderUtils.resetAtFromNow(safe)
            Logger.d("AIUsage", "Codex auto-reset target resetAt=" +
                autoResetResetsAt + " remaining=" + autoResetRemainingSec)
            return
        }
        if (!autoResetResetsAt && resetWindowSec > 0) {
            autoResetFallback = true
            autoResetRemainingSec = resetWindowSec
            autoResetResetsAt = ProviderUtils.resetAtFromNow(resetWindowSec)
            Logger.d("AIUsage", "Codex auto-reset fallback resetAt=" +
                autoResetResetsAt + " windowSec=" + resetWindowSec)
        }
    }

    function scheduleFallbackReset() {
        if (resetWindowSec <= 0) return
        autoResetFallback = true
        autoResetResetsAt = ProviderUtils.resetAtFromNow(resetWindowSec)
        autoResetRemainingSec = resetWindowSec
        Logger.d("AIUsage", "Codex auto-reset scheduled resetAt=" +
            autoResetResetsAt + " windowSec=" + resetWindowSec)
    }

    function refresh() {
        if (!enabled) {
            clearUsage()
            Logger.d("AIUsage", "Codex refresh skipped (disabled)")
            return
        }
        if (isBusy) return
        isBusy = true
        lastError = ""
        Logger.d("AIUsage", "Codex refresh start")
        depsProcess.exec({
            "command": ["sh", "-c", "command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1"]
        })
    }

    function runUsageQuery() {
        const credPath = credentialsPath

        const cmd =
            "cred_path=\"" + credPath + "\"; " +
            "cred_path=$(eval echo \"$cred_path\"); " +
            "if [ ! -f \"$cred_path\" ]; then " +
            "  echo '{\"error\":\"Credentials file not found at '$cred_path'\"}'; exit 0; " +
            "fi; " +
            "token=$(jq -r '.tokens.access_token // empty' \"$cred_path\" 2>/dev/null); " +
            "account_id=$(jq -r '.tokens.account_id // empty' \"$cred_path\" 2>/dev/null); " +
            "if [ -z \"$token\" ]; then " +
            "  echo '{\"error\":\"No access token found. Run codex to authenticate.\"}'; exit 0; " +
            "fi; " +
            "response=$(curl -s -w '\\n%{http_code}' " +
            "  -H \"Authorization: Bearer $token\" " +
            "  -H \"ChatGPT-Account-Id: $account_id\" " +
            "  -H \"User-Agent: ai-usage\" " +
            "  -H \"Accept: application/json\" " +
            "  'https://chatgpt.com/backend-api/wham/usage' 2>/dev/null); " +
            "http_code=$(echo \"$response\" | tail -n1); " +
            "body=$(echo \"$response\" | sed '$d'); " +
            "if [ \"$http_code\" != \"200\" ]; then " +
            "  error_msg=$(echo \"$body\" | jq -r '.detail // \"Token expired. Run codex to re-authenticate.\"' 2>/dev/null); " +
            "  echo '{\"error\":\"'\"$error_msg\"'\"}'; exit 0; " +
            "fi; " +
            "plan=$(echo \"$body\" | jq -r '.plan_type // \"unknown\"'); " +
            "primary_pct=$(echo \"$body\" | jq -r '.rate_limit.primary_window.used_percent // 0'); " +
            "primary_reset=$(echo \"$body\" | jq -r '.rate_limit.primary_window.reset_after_seconds // 0'); " +
            "secondary_pct=$(echo \"$body\" | jq -r '.rate_limit.secondary_window.used_percent // 0'); " +
            "secondary_reset=$(echo \"$body\" | jq -r '.rate_limit.secondary_window.reset_after_seconds // 0'); " +
            "echo '{\"connected\":true,\"planType\":\"'\"$plan\"'\",\"primaryPercent\":'\"$primary_pct\"',\"primaryResetSec\":'\"$primary_reset\"',\"secondaryPercent\":'\"$secondary_pct\"',\"secondaryResetSec\":'\"$secondary_reset\"',\"error\":null}'"

        usageProcess.exec({ "command": ["sh", "-c", cmd] })
    }

    Timer {
        id: resetTimer
        interval: 1000
        running: codex.enabled && resetWatcher.enabled
        repeat: true
        onTriggered: {
            if (codex.autoResetRemainingSec > 0) {
                codex.autoResetRemainingSec--
            }
            resetWatcher.maybeRenew(codex.autoResetResetsAt, codex.autoResetRemainingSec)
        }
    }

    Process {
        id: depsProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                codex.depsOk = false
                codex.lastError = "Missing curl or jq"
                codex.isBusy = false
                Logger.w("AIUsage", "Codex deps check failed")
                return
            }
            codex.depsOk = true
            Logger.d("AIUsage", "Codex deps ok, querying usage")
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
                codex.lastError = "Codex API request failed"
                codex.isBusy = false
                Logger.w("AIUsage", "Codex API request failed")
                return
            }

            try {
                const payload = JSON.parse(rawOutput || "{}")

                if (payload.error) {
                    codex.lastError = payload.error
                    codex.connected = false
                    codex.isBusy = false
                    Logger.w("AIUsage", "Codex API error: " + payload.error)
                    return
                }

                codex.connected = payload.connected || false
                codex.primaryPercent = ProviderUtils.clampPercent(payload.primaryPercent)
                codex.primaryResetSec = parseInt(payload.primaryResetSec || 0)
                codex.secondaryPercent = ProviderUtils.clampPercent(payload.secondaryPercent)
                codex.secondaryResetSec = parseInt(payload.secondaryResetSec || 0)
                codex.planType = payload.planType || "unknown"
                codex.hasData = true
                codex.lastError = ""
                codex.updateAutoResetTarget(codex.primaryResetSec)
                Logger.d("AIUsage", "Codex usage updated 5h=" + codex.primaryPercent +
                    " 7d=" + codex.secondaryPercent +
                    " plan=" + codex.planType)
            } catch (e) {
                codex.lastError = "Failed to parse Codex response"
                Logger.e("AIUsage", "Codex parse error")
            }

            codex.isBusy = false
        }
    }

    Watcher.ResetWatcher {
        id: resetWatcher
        onRenewed: {
            if (codex.autoResetFallback) {
                codex.scheduleFallbackReset()
            }
            codex.refresh()
        }
    }
}
