import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "../providers/ProviderUtils.js" as ProviderUtils

Item {
    id: watcher
    visible: false
    width: 0
    height: 0

    property bool enabled: true
    property bool providerEnabled: true
    property string providerName: "Provider"
    property string cliCommand: ""
    property string message: "hi"
    property string lastResetTime: ""
    property string lastSkipKey: ""
    property bool renewing: false

    signal renewed()
    signal failed(string error)

    Component.onCompleted: Logger.i("AIUsage", "ResetWatcher loaded")

    function summarizeOutput(text) {
        const trimmed = String(text || "").trim()
        if (!trimmed) return ""
        if (trimmed.length > 200) return trimmed.slice(0, 200) + "..."
        return trimmed
    }

    function logSkip(reason, resetsAt, remainingSec) {
        const key = reason + "|" + (resetsAt || "<none>")
        if (key === lastSkipKey) return
        lastSkipKey = key
        Logger.d("AIUsage", providerName + " reset watcher skip=" + reason +
            " remaining=" + remainingSec +
            " resetAt=" + (resetsAt || "<none>"))
    }

    function maybeRenew(resetsAt, remainingSec) {
        if (!enabled || !providerEnabled) {
            if (remainingSec <= 0) logSkip("disabled", resetsAt, remainingSec)
            return
        }
        if (renewing) {
            if (remainingSec <= 0) logSkip("renewing", resetsAt, remainingSec)
            return
        }
        if (!cliCommand) {
            if (remainingSec <= 0) logSkip("missing-command", resetsAt, remainingSec)
            return
        }
        if (!resetsAt) {
            if (remainingSec <= 0) logSkip("missing-reset-at", resetsAt, remainingSec)
            return
        }
        if (remainingSec > 0) return
        if (lastResetTime && lastResetTime === resetsAt) {
            logSkip("already-triggered", resetsAt, remainingSec)
            return
        }
        trigger(resetsAt)
    }

    function trigger(resetsAt) {
        renewing = true
        lastResetTime = resetsAt || ""
        Logger.i("AIUsage", providerName + " reset watcher trigger resetAt=" + lastResetTime)
        Logger.d("AIUsage", providerName + " reset watcher send via=" + cliCommand +
            " messageLen=" + String(message || "").length)
        renewProcess.exec({
            "command": ["sh", "-c", "printf '%s\\n' " + ProviderUtils.shellQuote(message) +
                " | " + cliCommand + " 2>/dev/null"]
        })
    }

    Process {
        id: renewProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: function (exitCode) {
            watcher.renewing = false
            const outSummary = summarizeOutput(renewProcess.stdout.text || "")
            const errSummary = summarizeOutput(renewProcess.stderr.text || "")
            if (exitCode === 0) {
                Logger.i("AIUsage", providerName + " reset watcher succeeded")
                if (outSummary) {
                    Logger.d("AIUsage", providerName + " reset watcher stdout=" + outSummary)
                }
                ToastService.showNotice(providerName + " reset triggered - new window started")
                watcher.renewed()
            } else {
                Logger.w("AIUsage", providerName + " reset watcher failed exit=" + exitCode)
                if (errSummary) {
                    Logger.d("AIUsage", providerName + " reset watcher stderr=" + errSummary)
                }
                ToastService.showError("Failed to reset " + providerName + " session")
                watcher.failed("renewal failed")
            }
        }
    }
}
