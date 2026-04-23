import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property string editSize: pluginApi?.pluginSettings?.size || defaults.size || "medium"
  property bool editShowPrompt: pluginApi?.pluginSettings?.showPrompt ?? defaults.showPrompt ?? true
  property bool editShowElapsed: pluginApi?.pluginSettings?.showElapsed ?? defaults.showElapsed ?? true
  property bool editShowContext: pluginApi?.pluginSettings?.showContext ?? defaults.showContext ?? true
  property bool editAutoHideCompleted: pluginApi?.pluginSettings?.autoHideCompleted ?? defaults.autoHideCompleted ?? true
  property int editCompletedRetentionSeconds: pluginApi?.pluginSettings?.completedRetentionSeconds || defaults.completedRetentionSeconds || 120
  property int editMaxRows: pluginApi?.pluginSettings?.maxRows || defaults.maxRows || 30
  property string editAccentColor: pluginApi?.pluginSettings?.accentColor || defaults.accentColor || "primary"

  spacing: Style.marginM

  function trf(key, arg1, arg2) {
    var value = pluginApi?.tr(key) || ""
    if (arg1 !== undefined) value = value.replace("%1", arg1)
    if (arg2 !== undefined) value = value.replace("%2", arg2)
    return value
  }

  NText {
    text: pluginApi?.tr("settings.title")
    pointSize: Style.fontSizeXL
    font.weight: Style.fontWeightBold
  }

  NText {
    text: pluginApi?.tr("settings.description")
    color: Color.mOnSurfaceVariant
    Layout.fillWidth: true
    wrapMode: Text.Wrap
  }

  NDivider {
    Layout.fillWidth: true
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.size")
    description: pluginApi?.tr("settings.size-description")
    model: [
      { key: "small", name: pluginApi?.tr("settings.size-small") },
      { key: "medium", name: pluginApi?.tr("settings.size-medium") },
      { key: "large", name: pluginApi?.tr("settings.size-large") },
      { key: "xlarge", name: pluginApi?.tr("settings.size-xlarge") }
    ]
    currentKey: root.editSize
    onSelected: key => root.editSize = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.accent-color")
    description: pluginApi?.tr("settings.accent-color-description")
    model: [
      { key: "primary", name: pluginApi?.tr("settings.accent-primary") },
      { key: "secondary", name: pluginApi?.tr("settings.accent-secondary") },
      { key: "tertiary", name: pluginApi?.tr("settings.accent-tertiary") }
    ]
    currentKey: root.editAccentColor
    onSelected: key => root.editAccentColor = key
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-prompt")
    description: pluginApi?.tr("settings.show-prompt-description")
    checked: root.editShowPrompt
    onToggled: checked => root.editShowPrompt = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-elapsed")
    description: pluginApi?.tr("settings.show-elapsed-description")
    checked: root.editShowElapsed
    onToggled: checked => root.editShowElapsed = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-context")
    description: pluginApi?.tr("settings.show-context-description")
    checked: root.editShowContext
    onToggled: checked => root.editShowContext = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.auto-hide-completed")
    description: pluginApi?.tr("settings.auto-hide-completed-description")
    checked: root.editAutoHideCompleted
    onToggled: checked => root.editAutoHideCompleted = checked
  }

  NLabel {
    label: pluginApi?.tr("settings.completed-retention")
    description: trf("settings.completed-retention-description", root.editCompletedRetentionSeconds)
  }

  NSlider {
    Layout.fillWidth: true
    enabled: root.editAutoHideCompleted
    from: 10
    to: 3600
    stepSize: 10
    value: root.editCompletedRetentionSeconds
    onValueChanged: root.editCompletedRetentionSeconds = Math.round(value)
  }

  NLabel {
    label: pluginApi?.tr("settings.max-rows")
    description: trf("settings.max-rows-description", root.editMaxRows)
  }

  NSlider {
    Layout.fillWidth: true
    from: 5
    to: 200
    stepSize: 1
    value: root.editMaxRows
    onValueChanged: root.editMaxRows = Math.round(value)
  }

  function saveSettings() {
    if (!pluginApi) return

    pluginApi.pluginSettings.size = root.editSize
    pluginApi.pluginSettings.showPrompt = root.editShowPrompt
    pluginApi.pluginSettings.showElapsed = root.editShowElapsed
    pluginApi.pluginSettings.showContext = root.editShowContext
    pluginApi.pluginSettings.autoHideCompleted = root.editAutoHideCompleted
    pluginApi.pluginSettings.completedRetentionSeconds = root.editCompletedRetentionSeconds
    pluginApi.pluginSettings.maxRows = root.editMaxRows
    pluginApi.pluginSettings.accentColor = root.editAccentColor

    pluginApi.saveSettings()
  }
}
