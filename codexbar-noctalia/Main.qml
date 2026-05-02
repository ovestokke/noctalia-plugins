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
  property var providers: []
  property string errorMessage: ""
  property string lastUpdate: ""

  readonly property bool ready: installed && runtimeOk
  readonly property int providerCount: providers.length
  readonly property var primaryProvider: providerCount > 0 ? providers[0] : null
  readonly property real primaryUsedPercent: primaryProvider?.usage?.primary?.usedPercent ?? -1

  Component.onCompleted: checkCli()

  Timer {
    interval: Math.max(30, root.refreshIntervalSec) * 1000
    running: root.autoRefresh
    repeat: true
    onTriggered: root.refreshUsage()
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

  function shellQuote(value) {
    var s = String(value === undefined || value === null ? "" : value)
    return "'" + s.replace(/'/g, "'\\''") + "'"
  }

  function expandedInstallDir() {
    if (installDir.indexOf("~/") === 0) return "$HOME/" + installDir.substring(2)
    if (installDir === "~") return "$HOME"
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

  function refreshUsage() {
    if (!ready || refreshing) return
    refreshing = true
    errorMessage = ""

    var args = [effectiveCodexbarPath(), "usage", "--source", source, "--provider", provider, "--format", "json", "--json-only"]
    if (includeStatus) args.push("--status")
    usageProcess.command = args
    usageProcess.running = true
  }

  function applyCliStatus(text) {
    try {
      var data = JSON.parse(String(text).trim())
      if (data.ok === false) {
        errorMessage = data.error || pluginApi?.tr("errors.checkFailed")
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
      if (ready) refreshUsage()
    } catch (e) {
      errorMessage = pluginApi?.tr("errors.parseStatus") + ": " + e.message
      Logger.e("CodexBarNoctalia", errorMessage)
    }
  }

  function applyUsage(text) {
    try {
      var data = JSON.parse(String(text).trim())
      providers = Array.isArray(data) ? data : [data]
      lastUpdate = Qt.formatTime(new Date(), "HH:mm")
    } catch (e) {
      errorMessage = pluginApi?.tr("errors.parseUsage") + ": " + e.message
      Logger.e("CodexBarNoctalia", errorMessage)
    }
  }

  function providerLabel(row) {
    if (!row) return pluginApi?.tr("widget.name") || ""
    return row.provider || row.usage?.identity?.providerID || pluginApi?.tr("widget.name") || ""
  }

  function usedLabel(row) {
    var pct = row?.usage?.primary?.usedPercent
    if (pct === undefined || pct === null) return "—"
    return Math.round(Number(pct)) + "%"
  }

  Process {
    id: cliCheckProcess
    stdout: StdioCollector {
      onStreamFinished: root.applyCliStatus(this.text)
    }
    stderr: StdioCollector { id: cliCheckStderr }
    onExited: (exitCode, exitStatus) => {
      root.checking = false
      if (exitCode !== 0) {
        root.errorMessage = root.errorMessage || cliCheckStderr.text.trim() || pluginApi?.tr("errors.checkFailed")
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
        root.errorMessage = root.errorMessage || cliInstallStderr.text.trim() || pluginApi?.tr("errors.installFailed")
        Logger.w("CodexBarNoctalia", root.errorMessage)
        root.checkCli()
      }
    }
  }

  Process {
    id: usageProcess
    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text.trim()) root.applyUsage(this.text)
      }
    }
    stderr: StdioCollector { id: usageStderr }
    onExited: (exitCode, exitStatus) => {
      root.refreshing = false
      if (exitCode !== 0) {
        root.errorMessage = root.errorMessage || usageStderr.text.trim() || pluginApi?.tr("errors.usageFailed")
        Logger.w("CodexBarNoctalia", root.errorMessage)
      }
    }
  }
}
