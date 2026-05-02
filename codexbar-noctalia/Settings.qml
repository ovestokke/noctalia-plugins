import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  readonly property var mainInstance: pluginApi?.mainInstance

  property string editCodexbarPath: pluginApi?.pluginSettings?.codexbarPath || defaults.codexbarPath || "codexbar"
  property string editSource: pluginApi?.pluginSettings?.source || defaults.source || "cli"
  property string editProvider: pluginApi?.pluginSettings?.provider || defaults.provider || "all"
  property int editRefreshIntervalSec: pluginApi?.pluginSettings?.refreshIntervalSec || defaults.refreshIntervalSec || 120
  property bool editIncludeStatus: pluginApi?.pluginSettings?.includeStatus ?? defaults.includeStatus ?? false
  property bool editAutoRefresh: pluginApi?.pluginSettings?.autoRefresh ?? defaults.autoRefresh ?? true
  property string editInstallDir: pluginApi?.pluginSettings?.installDir || defaults.installDir || "~/.local/bin"

  // Provider toggles: list of { id, enabled }
  property var editProviderToggles: []

  Component.onCompleted: {
    // Initialize provider toggles from mainInstance.allProviders
    syncProviderToggles()
  }

  function syncProviderToggles() {
    var src = mainInstance?.allProviders || []
    if (src.length > 0) {
      editProviderToggles = src.map(function(p) { return { id: p.id, enabled: p.enabled } })
    }
  }

  function enabledProviderIds() {
    var ids = []
    for (var i = 0; i < editProviderToggles.length; i++) {
      if (editProviderToggles[i].enabled) ids.push(editProviderToggles[i].id)
    }
    return ids
  }

  spacing: Style.marginM

  NText {
    text: pluginApi?.tr("settings.title")
    pointSize: Style.fontSizeXL
    font.weight: Style.fontWeightBold
  }

  NText {
    text: pluginApi?.tr("settings.description")
    color: Color.mOnSurfaceVariant
    wrapMode: Text.Wrap
    Layout.fillWidth: true
  }

  // ── Provider toggles ──
  NBox {
    Layout.fillWidth: true
    visible: editProviderToggles.length > 0

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      NText {
        text: pluginApi?.tr("settings.providers")
        font.weight: Style.fontWeightBold
        pointSize: Style.fontSizeM
      }

      NText {
        text: pluginApi?.tr("settings.providersDescription")
        color: Color.mOnSurfaceVariant
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        pointSize: Style.fontSizeXS
      }

      Repeater {
        model: editProviderToggles

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            text: modelData.id
            pointSize: Style.fontSizeS
            Layout.fillWidth: true
            color: modelData.enabled ? Color.mOnSurface : Color.mOnSurfaceVariant
          }

          NToggle {
            checked: modelData.enabled
            onToggled: function(checked) {
              var arr = editProviderToggles.slice()
              arr[index] = { id: modelData.id, enabled: checked }
              editProviderToggles = arr
            }
          }
        }
      }

      NText {
        text: pluginApi?.tr("settings.providersNote")
        color: Color.mOnSurfaceVariant
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        pointSize: Style.fontSizeXS
        visible: editProviderToggles.length > 0
      }
    }
  }

  // ── General settings ──
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.codexbarPath")
    description: pluginApi?.tr("settings.codexbarPathDescription")
    text: root.editCodexbarPath
    onTextChanged: root.editCodexbarPath = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.installDir")
    description: pluginApi?.tr("settings.installDirDescription")
    text: root.editInstallDir
    onTextChanged: root.editInstallDir = text
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.source")
    description: pluginApi?.tr("settings.sourceDescription")
    model: [
      { key: "cli", name: "cli" },
      { key: "api", name: "api" }
    ]
    currentKey: root.editSource
    onSelected: key => root.editSource = key
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.provider")
    description: pluginApi?.tr("settings.providerDescription")
    placeholderText: "all"
    text: root.editProvider
    onTextChanged: root.editProvider = text
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.autoRefresh")
    description: pluginApi?.tr("settings.autoRefreshDescription")
    checked: root.editAutoRefresh
    onToggled: checked => root.editAutoRefresh = checked
  }

  NLabel {
    label: pluginApi?.tr("settings.refreshInterval")
    description: root.editRefreshIntervalSec + "s"
  }

  NSlider {
    Layout.fillWidth: true
    from: 30
    to: 900
    stepSize: 30
    value: root.editRefreshIntervalSec
    onValueChanged: root.editRefreshIntervalSec = Math.round(value)
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.includeStatus")
    description: pluginApi?.tr("settings.includeStatusDescription")
    checked: root.editIncludeStatus
    onToggled: checked => root.editIncludeStatus = checked
  }

  function saveSettings() {
    if (!pluginApi) return
    pluginApi.pluginSettings.codexbarPath = root.editCodexbarPath
    pluginApi.pluginSettings.source = root.editSource
    pluginApi.pluginSettings.provider = root.editProvider
    pluginApi.pluginSettings.refreshIntervalSec = root.editRefreshIntervalSec
    pluginApi.pluginSettings.includeStatus = root.editIncludeStatus
    pluginApi.pluginSettings.autoRefresh = root.editAutoRefresh
    pluginApi.pluginSettings.installDir = root.editInstallDir
    pluginApi.saveSettings()

    // Save provider config to ~/.codexbar/config.json
    var ids = enabledProviderIds()
    if (mainInstance && editProviderToggles.length > 0) {
      mainInstance.saveProviderConfig(ids)
    }

    pluginApi.mainInstance?.checkCli()
  }
}
