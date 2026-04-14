import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  readonly property int refreshInterval: pluginApi?.pluginSettings?.refreshInterval ?? 3000

  property bool moniqueInstalled: false
  property string activeProfile: ""
  property var profiles: []
  property bool isRefreshing: false

  Timer {
    id: updateTimer
    interval: root.refreshInterval
    running: root.moniqueInstalled
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    checkInstalled()
  }

  function checkInstalled() {
    root.isRefreshing = true
    whichProcess.running = true
  }

  function refresh() {
    if (root.isRefreshing) return
    root.isRefreshing = true
    currentProfileProcess.running = true
  }

  function switchProfile(name) {
    switchProcess.profileName = name
    switchProcess.running = true
  }

  // Verifica che monique sia installato
  Process {
    id: whichProcess
    command: ["which", "monique"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      root.moniqueInstalled = (exitCode === 0)
      root.isRefreshing = false
      if (root.moniqueInstalled) {
        root.refresh()
        listProfilesProcess.running = true
        updateTimer.start()
      } else {
        Logger.w("Monique", "monique not found in PATH")
      }
    }
  }

  // Carica la lista dei profili
  Process {
    id: listProfilesProcess
    command: ["monique", "--list-profiles"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      if (exitCode === 0) {
        try {
          root.profiles = JSON.parse(String(listProfilesProcess.stdout.text || "[]").trim())
        } catch (e) {
          root.profiles = []
          Logger.w("Monique", "Failed to parse profiles: " + e)
        }
      }
    }
  }

  // Legge il profilo attivo
  Process {
    id: currentProfileProcess
    command: ["monique", "--current-profile"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      root.isRefreshing = false
      if (exitCode === 0) {
        root.activeProfile = String(currentProfileProcess.stdout.text || "").trim()
      } else {
        root.activeProfile = ""
      }
    }
  }

  // Esegue lo switch del profilo
  Process {
    id: switchProcess

    property string profileName: ""

    command: ["monique", "--switch-profile", profileName]
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.activeProfile = switchProcess.profileName
        ToastService.showNotice(
          pluginApi?.tr("toast.title"),
          pluginApi?.tr("toast.switched", { profile: switchProcess.profileName }),
          "device-desktop"
        )
      } else {
        var err = String(switchProcess.stderr.text || "").trim()
        Logger.e("Monique", "Switch failed: " + err)
        ToastService.showWarning(
          pluginApi?.tr("toast.title"),
          err || pluginApi?.tr("toast.error")
        )
      }
    }
  }
}
