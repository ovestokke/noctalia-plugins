import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property string editCodexbarPath: pluginApi?.pluginSettings?.codexbarPath || defaults.codexbarPath || "codexbar"
  property string editSource: pluginApi?.pluginSettings?.source || defaults.source || "cli"
  property string editProvider: pluginApi?.pluginSettings?.provider || defaults.provider || "all"
  property int editRefreshIntervalSec: pluginApi?.pluginSettings?.refreshIntervalSec || defaults.refreshIntervalSec || 120
  property bool editIncludeStatus: pluginApi?.pluginSettings?.includeStatus ?? defaults.includeStatus ?? false
  property bool editAutoRefresh: pluginApi?.pluginSettings?.autoRefresh ?? defaults.autoRefresh ?? true
  property string editInstallDir: pluginApi?.pluginSettings?.installDir || defaults.installDir || "~/.local/bin"

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
    pluginApi.mainInstance?.checkCli()
  }
}
