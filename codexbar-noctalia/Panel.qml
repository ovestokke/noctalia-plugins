import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 420 * Style.uiScaleRatio
  property real contentPreferredHeight: 520 * Style.uiScaleRatio
  readonly property bool allowAttach: true

  anchors.fill: parent

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        NText {
          text: pluginApi?.tr("panel.title")
          pointSize: Style.fontSizeXL
          font.weight: Style.fontWeightBold
          Layout.fillWidth: true
        }
        NButton {
          text: pluginApi?.tr("panel.check")
          enabled: !(mainInstance?.checking ?? false)
          onClicked: mainInstance?.checkCli()
        }
        NButton {
          text: pluginApi?.tr("panel.refresh")
          enabled: mainInstance?.ready ?? false
          onClicked: mainInstance?.refreshUsage()
        }
      }

      NBox {
        Layout.fillWidth: true
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText {
            text: (mainInstance?.installed ?? false) ? pluginApi?.tr("panel.installed") : pluginApi?.tr("panel.notInstalled")
            color: (mainInstance?.ready ?? false) ? Color.mPrimary : Color.mError
            font.weight: Style.fontWeightBold
          }
          NText { text: pluginApi?.tr("panel.path") + ": " + ((mainInstance?.codexbarResolvedPath || mainInstance?.codexbarPath) ?? "") ; color: Color.mOnSurfaceVariant; wrapMode: Text.Wrap; Layout.fillWidth: true }
          NText { text: pluginApi?.tr("panel.current") + ": " + ((mainInstance?.currentVersion || "—")) ; color: Color.mOnSurfaceVariant }
          NText { text: pluginApi?.tr("panel.latest") + ": " + ((mainInstance?.latestVersion || "—")) ; color: Color.mOnSurfaceVariant }
          NText { visible: mainInstance?.updateAvailable ?? false; text: pluginApi?.tr("panel.updateAvailable"); color: Color.mSecondary }
          NText { visible: !(mainInstance?.runtimeOk ?? false) && (mainInstance?.installed ?? false); text: mainInstance?.dependencyHint || pluginApi?.tr("panel.runtimeBroken"); color: Color.mError; wrapMode: Text.Wrap; Layout.fillWidth: true }
          NText { visible: (mainInstance?.errorMessage || "") !== ""; text: mainInstance?.errorMessage || ""; color: Color.mError; wrapMode: Text.Wrap; Layout.fillWidth: true }

          RowLayout {
            Layout.fillWidth: true
            NButton {
              text: pluginApi?.tr("panel.install")
              visible: !(mainInstance?.installed ?? false)
              enabled: !(mainInstance?.installing ?? false)
              onClicked: mainInstance?.installCli()
            }
            NButton {
              text: pluginApi?.tr("panel.update")
              visible: mainInstance?.updateAvailable ?? false
              enabled: !(mainInstance?.installing ?? false)
              onClicked: mainInstance?.updateCli()
            }
          }
        }
      }

      NText {
        text: pluginApi?.tr("panel.providers")
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
      }

      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: mainInstance?.providers ?? []
        spacing: Style.marginS

        delegate: NBox {
          width: ListView.view.width
          implicitHeight: providerColumn.implicitHeight + Style.marginM * 2
          ColumnLayout {
            id: providerColumn
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginXS
            RowLayout {
              Layout.fillWidth: true
              NText { text: modelData.provider || "—"; font.weight: Style.fontWeightBold; Layout.fillWidth: true }
              NText { text: mainInstance?.usedLabel(modelData) ?? "—"; color: Color.mPrimary; font.family: Settings.data.ui.fontFixed }
            }
            NText { text: modelData.source || ""; color: Color.mOnSurfaceVariant }
            NText { visible: modelData.usage?.primary?.resetsAt !== undefined; text: pluginApi?.tr("panel.resets") + ": " + (modelData.usage?.primary?.resetsAt || "—"); color: Color.mOnSurfaceVariant; wrapMode: Text.Wrap; Layout.fillWidth: true }
            NText { visible: modelData.status?.description !== undefined; text: modelData.status?.description || ""; color: Color.mOnSurfaceVariant; wrapMode: Text.Wrap; Layout.fillWidth: true }
          }
        }
      }
    }
  }
}
