import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  readonly property string codexbarPath: pluginApi?.pluginSettings?.codexbarPath || defaults.codexbarPath || "codexbar"
  readonly property string source: pluginApi?.pluginSettings?.source || defaults.source || "cli"
  readonly property string provider: pluginApi?.pluginSettings?.provider || defaults.provider || "all"
  readonly property int refreshIntervalSec: pluginApi?.pluginSettings?.refreshIntervalSec || defaults.refreshIntervalSec || 120
  readonly property bool includeStatus: pluginApi?.pluginSettings?.includeStatus ?? defaults.includeStatus ?? false
  readonly property bool autoRefresh: pluginApi?.pluginSettings?.autoRefresh ?? defaults.autoRefresh ?? true
  readonly property string installDir: pluginApi?.pluginSettings?.installDir || defaults.installDir || "~/.local/bin"
  readonly property string helperPath: (pluginApi?.pluginDir || "") + "/scripts/codexbar-cli-manager.sh"

  property bool checking: false
  property bool refreshing: false
  property bool installing: false
  property bool installed: false
  property bool runtimeOk: false
  property bool updateAvailable: false
  property string codexbarResolvedPath: ""
  property string currentVersion: ""
  property string latestVersion: ""
  property string dependencyHint: ""
  property var missingLibraries: []
  property var configuredProviders: []
  property var usageQueue: []
  property string currentUsageProvider: ""
  property var providers: []
  property var providerErrors: []
  property string errorMessage: ""
  property string lastUpdate: ""
  property bool configParsed: false
  property bool usageHadRows: false
  property bool usageHadError: false
  property bool usageParsed: false
  property bool usageTimedOut: false

  readonly property bool ready: installed && runtimeOk
  readonly property int providerCount: providers.length
  readonly property int providerErrorCount: providerErrors.length
  readonly property var primaryProvider: providerCount > 0 ? providers[0] : null
  readonly property real primaryUsedPercent: primaryProvider?.usage?.primary?.usedPercent ?? -1

  Component.onCompleted: checkCli()

  Timer {
    interval: Math.max(30, root.refreshIntervalSec) * 1000
    running: root.autoRefresh
    repeat: true
    onTriggered: root.refreshUsage()
  }

  Timer {
    id: usageTimeoutTimer
    interval: 45000
    repeat: false
    onTriggered: {
      if (!root.refreshing || !usageProcess.running) return
      root.usageTimedOut = true
      usageProcess.running = false
      Logger.w("CodexBarNoctalia", root.trText("errors.usageTimeout") + ": " + root.currentUsageProvider)
    }
  }

  IpcHandler {
    target: "plugin:codexbar-noctalia"

    function check() { root.checkCli() }
    function refresh() { root.refreshUsage() }
    function install() { root.installCli() }
    function update() { root.updateCli() }

    function toggle() {
      if (root.pluginApi) {
        root.pluginApi.withCurrentScreen(screen => root.pluginApi.togglePanel(screen))
      }
    }
  }

  function trText(key) {
    return pluginApi?.tr(key) || key
  }

  function shellQuote(value) {
    var s = String(value === undefined || value === null ? "" : value)
    return "'" + s.replace(/'/g, "'\\''") + "'"
  }

  function expandedInstallDir() {
    return installDir
  }

  function helperCommand(action) {
    return "CODEXBAR_INSTALL_DIR=" + shellQuote(expandedInstallDir()) + " CODEXBAR_PATH=" + shellQuote(codexbarPath) + " " + shellQuote(helperPath) + " " + action + " --json"
  }

  function checkCli() {
    if (checking || installing) return
    checking = true
    errorMessage = ""
    cliCheckProcess.command = ["sh", "-lc", helperCommand("check")]
    cliCheckProcess.running = true
  }

  function installCli() {
    if (installing) return
    installing = true
    errorMessage = ""
    cliInstallProcess.command = ["sh", "-lc", helperCommand("install")]
    cliInstallProcess.running = true
  }

  function updateCli() {
    if (installing) return
    installing = true
    errorMessage = ""
    cliInstallProcess.command = ["sh", "-lc", helperCommand("update")]
    cliInstallProcess.running = true
  }

  function effectiveCodexbarPath() {
    return codexbarResolvedPath || codexbarPath
  }

  function selectedProvider() {
    var value = String(provider || "").trim()
    return value || "all"
  }

  function refreshUsage() {
    if (!ready || refreshing) return

    refreshing = true
    configParsed = false
    usageHadRows = false
    usageHadError = false
    usageParsed = false
    usageTimedOut = false
    currentUsageProvider = ""
    usageQueue = []
    providers = []
    providerErrors = []
    errorMessage = ""

    var selected = selectedProvider()
    if (selected === "all") {
      configProcess.command = [effectiveCodexbarPath(), "config", "dump", "--format", "json"]
      configProcess.running = true
    } else {
      startUsageQueue([selected])
    }
  }

  function startUsageQueue(queue) {
    var unique = []
    for (var i = 0; i < queue.length; i++) {
      var id = String(queue[i] || "").trim()
      if (id && unique.indexOf(id) === -1) unique.push(id)
    }

    configuredProviders = unique
    usageQueue = unique

    if (usageQueue.length === 0) {
      finishUsageRefresh(trText("errors.noConfiguredProviders"))
      return
    }

    startNextUsageProvider()
  }

  function startNextUsageProvider() {
    usageTimeoutTimer.stop()

    if (usageQueue.length === 0) {
      finishUsageRefresh("")
      return
    }

    currentUsageProvider = usageQueue[0]
    usageQueue = usageQueue.slice(1)
    usageHadRows = false
    usageHadError = false
    usageParsed = false
    usageTimedOut = false

    var args = [effectiveCodexbarPath(), "usage", "--source", source, "--provider", currentUsageProvider, "--format", "json", "--json-only"]
    if (includeStatus) args.push("--status")
    usageProcess.command = args
    usageTimeoutTimer.restart()
    usageProcess.running = true
  }

  function finishUsageRefresh(message) {
    usageTimeoutTimer.stop()
    refreshing = false
    currentUsageProvider = ""

    if (providers.length > 0) {
      lastUpdate = Qt.formatTime(new Date(), "HH:mm")
      if (providerErrors.length > 0) {
        errorMessage = trText("errors.providerFailures").replace("%1", providerErrors.length)
      } else {
        errorMessage = ""
      }
    } else if (message) {
      errorMessage = message
    } else if (providerErrors.length > 0) {
      errorMessage = errorText(providerErrors[0]) || trText("errors.usageFailed")
    } else {
      errorMessage = trText("errors.usageEmpty")
    }
  }

  function resetCliStatus(message) {
    installed = false
    runtimeOk = false
    updateAvailable = false
    codexbarResolvedPath = ""
    currentVersion = ""
    latestVersion = ""
    dependencyHint = ""
    missingLibraries = []
    configuredProviders = []
    usageQueue = []
    currentUsageProvider = ""
    providers = []
    providerErrors = []
    if (message) errorMessage = message
  }

  function applyCliStatus(text) {
    try {
      var trimmed = String(text).trim()
      if (!trimmed) return
      var data = JSON.parse(trimmed)
      if (data.ok === false) {
        resetCliStatus(data.error || trText("errors.checkFailed"))
        return
      }
      installed = data.installed ?? false
      runtimeOk = data.runtimeOk ?? false
      updateAvailable = data.updateAvailable ?? false
      codexbarResolvedPath = data.path || ""
      currentVersion = data.currentVersion || ""
      latestVersion = data.latestVersion || ""
      missingLibraries = data.missingLibraries || []
      dependencyHint = data.dependencyHint || ""
      if (!(installed && runtimeOk)) {
        providers = []
        providerErrors = []
      }
      if (installed && runtimeOk) refreshUsage()
    } catch (e) {
      errorMessage = trText("errors.parseStatus") + ": " + e.message
      Logger.e("CodexBarNoctalia", errorMessage)
    }
  }

  function configuredProviderIds(data) {
    var ids = []
    var list = data?.providers

    if (Array.isArray(list)) {
      for (var i = 0; i < list.length; i++) {
        var row = list[i]
        if (row?.enabled === true && row?.id) ids.push(String(row.id))
      }
    } else if (list && typeof list === "object") {
      for (var key in list) {
        var value = list[key]
        if (value === true || value?.enabled === true) ids.push(String(value?.id || key))
      }
    }

    if (Array.isArray(data?.enabledProviders)) {
      for (var j = 0; j < data.enabledProviders.length; j++) ids.push(String(data.enabledProviders[j]))
    }

    return ids
  }

  function applyConfig(text) {
    try {
      var trimmed = String(text).trim()
      if (!trimmed) {
        finishUsageRefresh(trText("errors.configEmpty"))
        return
      }
      var data = JSON.parse(trimmed)
      configParsed = true
      startUsageQueue(configuredProviderIds(data))
    } catch (e) {
      finishUsageRefresh(trText("errors.parseConfig") + ": " + e.message)
      Logger.e("CodexBarNoctalia", errorMessage)
    }
  }

  function parseJsonDocuments(text) {
    var trimmed = String(text).trim()
    if (!trimmed) return []

    try {
      return [JSON.parse(trimmed)]
    } catch (wholeError) {
      var docs = []
      var lines = trimmed.split(/\r?\n/)
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        docs.push(JSON.parse(line))
      }
      return docs
    }
  }

  function errorText(row) {
    return row?.error?.message || row?.message || ""
  }

  function providerError(providerId, message) {
    return {
      "provider": providerId || currentUsageProvider || "",
      "source": source,
      "error": {
        "message": message || trText("errors.usageFailed")
      }
    }
  }

  function appendProviderError(providerId, message) {
    providerErrors = providerErrors.concat([providerError(providerId, message)])
  }

  function applyUsage(text) {
    try {
      var docs = parseJsonDocuments(text)
      var rows = []
      for (var i = 0; i < docs.length; i++) {
        if (Array.isArray(docs[i])) rows = rows.concat(docs[i])
        else if (docs[i]) rows.push(docs[i])
      }

      var goodRows = []
      var badRows = []
      for (var j = 0; j < rows.length; j++) {
        var row = rows[j]
        if (!row || typeof row !== "object") continue
        if (row.error) badRows.push(row)
        else if (row.provider && row.usage) goodRows.push(row)
      }

      usageParsed = true
      usageHadRows = goodRows.length > 0
      usageHadError = badRows.length > 0
      if (goodRows.length > 0) providers = providers.concat(goodRows)
      if (badRows.length > 0) providerErrors = providerErrors.concat(badRows)
      if (goodRows.length === 0 && badRows.length === 0) {
        usageHadError = true
        appendProviderError(currentUsageProvider, trText("errors.usageEmpty"))
      }
    } catch (e) {
      usageParsed = false
      usageHadRows = false
      usageHadError = true
      appendProviderError(currentUsageProvider, trText("errors.parseUsage") + ": " + e.message)
      Logger.e("CodexBarNoctalia", errorText(providerErrors[providerErrors.length - 1]))
    }
  }

  function providerLabel(row) {
    if (!row) return trText("widget.name")
    return row.provider || row.usage?.identity?.providerID || trText("widget.name")
  }

  function usedLabel(row) {
    var pct = row?.usage?.primary?.usedPercent
    if (pct === undefined || pct === null) return "—"
    var number = Number(pct)
    if (isNaN(number)) return "—"
    return Math.round(number) + "%"
  }

  Process {
    id: cliCheckProcess
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text.trim()) root.applyCliStatus(this.text)
      }
    }
    stderr: StdioCollector { id: cliCheckStderr }
    onExited: (exitCode, exitStatus) => {
      root.checking = false
      if (exitCode !== 0) {
        root.errorMessage = cliCheckStderr.text.trim() || root.errorMessage || root.trText("errors.checkFailed")
        Logger.w("CodexBarNoctalia", root.errorMessage)
      }
    }
  }

  Process {
    id: cliInstallProcess
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text.trim()) root.applyCliStatus(this.text)
      }
    }
    stderr: StdioCollector { id: cliInstallStderr }
    onExited: (exitCode, exitStatus) => {
      root.installing = false
      if (exitCode !== 0) {
        root.errorMessage = cliInstallStderr.text.trim() || root.errorMessage || root.trText("errors.installFailed")
        Logger.w("CodexBarNoctalia", root.errorMessage)
      }
    }
  }

  Process {
    id: configProcess
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.refreshing && this.text.trim()) root.applyConfig(this.text)
      }
    }
    stderr: StdioCollector { id: configStderr }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0 && root.refreshing && !root.configParsed) {
        root.finishUsageRefresh(configStderr.text.trim() || root.trText("errors.configFailed"))
        Logger.w("CodexBarNoctalia", root.errorMessage)
      } else if (exitCode === 0 && root.refreshing && !root.configParsed && !usageProcess.running) {
        root.finishUsageRefresh(root.trText("errors.configEmpty"))
      }
    }
  }

  Process {
    id: usageProcess
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.usageTimedOut && this.text.trim()) root.applyUsage(this.text)
      }
    }
    stderr: StdioCollector { id: usageStderr }
    onExited: (exitCode, exitStatus) => {
      usageTimeoutTimer.stop()

      if (root.usageTimedOut) {
        root.appendProviderError(root.currentUsageProvider, root.trText("errors.usageTimeout"))
      } else if (exitCode !== 0 && !root.usageHadRows && !root.usageHadError) {
        root.appendProviderError(root.currentUsageProvider, usageStderr.text.trim() || root.trText("errors.usageFailed"))
      } else if (exitCode === 0 && !root.usageParsed) {
        root.appendProviderError(root.currentUsageProvider, root.trText("errors.usageEmpty"))
      }

      root.usageTimedOut = false
      if (root.refreshing) root.startNextUsageProvider()
    }
  }
}
