import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  property var activeSessions: []
  property var completedSessions: []

  property int nowMs: Date.now()

  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

  readonly property string size: pluginApi?.pluginSettings?.size ?? defaults.size ?? "medium"
  readonly property bool showPrompt: pluginApi?.pluginSettings?.showPrompt ?? defaults.showPrompt ?? true
  readonly property bool showElapsed: pluginApi?.pluginSettings?.showElapsed ?? defaults.showElapsed ?? true
  readonly property bool showContext: pluginApi?.pluginSettings?.showContext ?? defaults.showContext ?? true
  readonly property bool autoHideCompleted: pluginApi?.pluginSettings?.autoHideCompleted ?? defaults.autoHideCompleted ?? true
  readonly property int completedRetentionSeconds: pluginApi?.pluginSettings?.completedRetentionSeconds ?? defaults.completedRetentionSeconds ?? 120
  readonly property int maxRows: pluginApi?.pluginSettings?.maxRows ?? defaults.maxRows ?? 30
  readonly property string accentColor: pluginApi?.pluginSettings?.accentColor ?? defaults.accentColor ?? "primary"

  readonly property var activeRows: {
    var rows = activeSessions.slice()
    rows.sort(function(a, b) {
      return a.startedAt - b.startedAt
    })
    return rows
  }

  readonly property var recentCompletedRows: {
    var rows = completedSessions.slice()
    rows.sort(function(a, b) {
      return b.startedAt - a.startedAt
    })

    var budget = Math.max(0, maxRows - activeRows.length)
    if (budget <= 0) return []
    return rows.slice(0, budget)
  }

  readonly property var visibleRows: activeRows.concat(recentCompletedRows)

  readonly property var primaryActiveRow: activeRows.length > 0 ? activeRows[0] : null

  readonly property bool hasAnyRows: activeSessions.length > 0 || completedSessions.length > 0

  function _knownStatuses() {
    return ["thinking", "reading", "editing", "writing", "running", "searching", "done", "error"]
  }

  function _isKnownStatus(status) {
    return _knownStatuses().indexOf(status) !== -1
  }

  function _findIndex(rows, id) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id === id) return i
    }
    return -1
  }

  function _clampContext(value) {
    if (value === undefined || value === null || value === "") return null
    var n = Number(value)
    if (isNaN(n)) return null
    n = Math.round(n)
    if (n < 0) n = 0
    if (n > 100) n = 100
    return n
  }

  function _statusOrFallback(status) {
    return _isKnownStatus(status) ? status : "thinking"
  }

  function _applyRetention() {
    if (!autoHideCompleted) return

    var cutoff = nowMs - Math.max(0, completedRetentionSeconds) * 1000
    completedSessions = completedSessions.filter(function(row) {
      var doneAt = row.startedAt + (row.frozenElapsed ?? 0)
      return doneAt >= cutoff
    })
  }

  function _enforceMaxRows() {
    var budget = Math.max(0, maxRows - activeSessions.length)
    if (completedSessions.length > budget) {
      completedSessions = completedSessions
        .slice()
        .sort(function(a, b) { return b.startedAt - a.startedAt })
        .slice(0, budget)
    }
  }

  function updateSession(id, project, status, detail, prompt, ctxPct) {
    if (!id || !project) return

    var normalized = _statusOrFallback(status)
    var contextPct = _clampContext(ctxPct)

    var index = _findIndex(activeSessions, id)
    var rows = activeSessions.slice()

    if (index === -1) {
      var completedIndex = _findIndex(completedSessions, id)
      if (completedIndex !== -1) {
        var revived = completedSessions[completedIndex]
        completedSessions = completedSessions.filter(function(row) { return row.id !== id })

        revived.project = project
        revived.status = normalized
        revived.detail = detail || revived.detail || ""
        if (prompt !== undefined && prompt !== null && prompt !== "") revived.prompt = prompt
        revived.frozenElapsed = null
        revived.ctxPct = contextPct

        rows.push(revived)
      } else {
        rows.push({
                    id: id,
                    project: project,
                    status: normalized,
                    detail: detail || "",
                    prompt: prompt || "",
                    startedAt: Date.now(),
                    frozenElapsed: null,
                    ctxPct: contextPct
                  })
      }
    } else {
      var current = rows[index]
      current.project = project
      current.status = normalized
      current.detail = detail || current.detail || ""
      if (prompt !== undefined && prompt !== null && prompt !== "") {
        current.prompt = prompt
      }
      current.ctxPct = contextPct
      current.frozenElapsed = null
    }

    activeSessions = rows
  }

  function finishSession(id) {
    var index = _findIndex(activeSessions, id)
    if (index === -1) return

    var rows = activeSessions.slice()
    var row = rows[index]

    row.status = "done"
    row.frozenElapsed = Math.max(0, Date.now() - row.startedAt)

    rows.splice(index, 1)

    activeSessions = rows
    completedSessions = [row].concat(completedSessions.filter(function(existing) {
      return existing.id !== row.id
    }))

    _applyRetention()
    _enforceMaxRows()
  }

  function failSession(id, detail) {
    var index = _findIndex(activeSessions, id)
    if (index === -1) return

    var rows = activeSessions.slice()
    var row = rows[index]

    row.status = "error"
    if (detail !== undefined && detail !== null && detail !== "") {
      row.detail = detail
    }
    row.frozenElapsed = Math.max(0, Date.now() - row.startedAt)

    rows.splice(index, 1)

    activeSessions = rows
    completedSessions = [row].concat(completedSessions.filter(function(existing) {
      return existing.id !== row.id
    }))

    _applyRetention()
    _enforceMaxRows()
  }

  function removeSession(id) {
    activeSessions = activeSessions.filter(function(row) { return row.id !== id })
    completedSessions = completedSessions.filter(function(row) { return row.id !== id })
  }

  function clearAll() {
    activeSessions = []
    completedSessions = []
  }

  function clearCompleted() {
    completedSessions = []
  }

  function elapsedSeconds(row) {
    if (!row) return 0
    var elapsedMs = row.frozenElapsed !== null ? row.frozenElapsed : Math.max(0, nowMs - row.startedAt)
    return Math.floor(elapsedMs / 1000)
  }

  function formatElapsed(seconds) {
    var total = Math.max(0, seconds || 0)
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    var s = total % 60

    if (h > 0) {
      return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }
    return m + ":" + String(s).padStart(2, "0")
  }

  function statusLabel(status) {
    return pluginApi?.tr("status." + status) || status
  }

  function statusIcon(status) {
    switch (status) {
      case "thinking":
        return "brain"
      case "reading":
        return "book"
      case "editing":
        return "pencil"
      case "writing":
        return "file-text"
      case "running":
        return "player-play"
      case "searching":
        return "search"
      case "done":
        return "circle-check"
      case "error":
        return "alert-circle"
      default:
        return "activity"
    }
  }

  function sizeScale() {
    switch (size) {
      case "small":
        return 0.9
      case "large":
        return 1.15
      case "xlarge":
        return 1.3
      default:
        return 1.0
    }
  }

  function accentColorValue() {
    switch (accentColor) {
      case "secondary":
        return Color.mSecondary
      case "tertiary":
        return Color.mTertiary
      default:
        return Color.mPrimary
    }
  }

  function statusColor(status) {
    if (status === "error") return Color.mError
    if (status === "done") return accentColorValue()

    switch (status) {
      case "reading":
      case "searching":
        return Color.mSecondary
      default:
        return accentColorValue()
    }
  }

  function demoData() {
    function d(key) {
      return pluginApi?.tr("demo." + key) || ""
    }

    var base = Date.now()

    activeSessions = [
      {
        id: "pi-1",
        project: "pi-noctalia",
        status: "editing",
        detail: "Panel.qml",
        prompt: d("prompt-build-panel"),
        startedAt: base - 56000,
        frozenElapsed: null,
        ctxPct: 41
      },
      {
        id: "pi-2",
        project: "docs",
        status: "reading",
        detail: "IMPLEMENTATION_PLAN.md",
        prompt: d("prompt-confirm-model"),
        startedAt: base - 24000,
        frozenElapsed: null,
        ctxPct: 18
      }
    ]

    completedSessions = [
      {
        id: "pi-3",
        project: "pi-noctalia",
        status: "done",
        detail: "manifest.json",
        prompt: d("prompt-default-settings"),
        startedAt: base - 180000,
        frozenElapsed: 37000,
        ctxPct: 9
      },
      {
        id: "pi-4",
        project: "pi-noctalia",
        status: "error",
        detail: d("detail-unknown-status"),
        prompt: d("prompt-parse-status"),
        startedAt: base - 140000,
        frozenElapsed: 16000,
        ctxPct: 75
      }
    ]

    _applyRetention()
    _enforceMaxRows()
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      nowMs = Date.now()
      _applyRetention()
      _enforceMaxRows()
    }
  }

  IpcHandler {
    target: "plugin:pi-noctalia"

    function update(id: string, project: string, status: string, detail: string, prompt: string, ctxPct: string) {
      root.updateSession(id, project, status, detail, prompt, ctxPct)
    }

    function done(id: string) {
      root.finishSession(id)
    }

    function error(id: string, detail: string) {
      root.failSession(id, detail)
    }

    function remove(id: string) {
      root.removeSession(id)
    }

    function clear() {
      root.clearAll()
    }

    function demo() {
      root.demoData()
    }
  }
}
