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
  property real contentPreferredHeight: 560 * Style.uiScaleRatio
  readonly property bool allowAttach: true

  anchors.fill: parent

  function trf(key, arg1) {
    var value = pluginApi?.tr(key) || ""
    if (arg1 !== undefined) value = value.replace("%1", arg1)
    return value
  }

  function gaugeColor(pct) {
    if (pct >= 90) return Color.mError
    if (pct >= 70) return Color.mSecondary
    return Color.mPrimary
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // ── Header ──
      RowLayout {
        Layout.fillWidth: true
        NText {
          text: pluginApi?.tr("panel.title")
          pointSize: Style.fontSizeXL
          font.weight: Style.fontWeightBold
          Layout.fillWidth: true
        }
        NText {
          visible: (mainInstance?.lastUpdate || "") !== ""
          text: (mainInstance?.lastUpdate || "")
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
        NIconButtonHot {
          icon: "search"
          tooltipText: pluginApi?.tr("panel.check")
          enabled: !(mainInstance?.checking ?? false) && !(mainInstance?.installing ?? false)
          onClicked: mainInstance?.checkCli()
        }
        NIconButtonHot {
          icon: "refresh"
          tooltipText: pluginApi?.tr("panel.refresh")
          enabled: (mainInstance?.ready ?? false) && !(mainInstance?.refreshing ?? false)
          onClicked: mainInstance?.refreshUsage()
        }
      }

      // ── CLI Status ──
      NBox {
        Layout.fillWidth: true
        visible: !(mainInstance?.installed ?? false) || !(mainInstance?.runtimeOk ?? false) || (mainInstance?.errorMessage || "") !== "" || (mainInstance?.updateAvailable ?? false)
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText {
            visible: !(mainInstance?.installed ?? false)
            text: pluginApi?.tr("panel.notInstalled")
            color: Color.mError
            font.weight: Style.fontWeightBold
          }
          NText {
            visible: (mainInstance?.installed ?? false) && !(mainInstance?.runtimeOk ?? false)
            text: mainInstance?.dependencyHint || pluginApi?.tr("panel.runtimeBroken")
            color: Color.mError
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
          NText {
            visible: (mainInstance?.errorMessage || "") !== ""
            text: mainInstance?.errorMessage || ""
            color: Color.mError
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
          NText {
            visible: mainInstance?.updateAvailable ?? false
            text: pluginApi?.tr("panel.updateAvailable")
            color: Color.mSecondary
          }

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

      // ── Loading state ──
      NText {
        Layout.fillWidth: true
        visible: mainInstance?.refreshing ?? false
        text: pluginApi?.tr("panel.refreshing")
        color: Color.mOnSurfaceVariant
      }

      // ── No providers ──
      NText {
        Layout.fillWidth: true
        visible: !(mainInstance?.refreshing ?? false) && (mainInstance?.ready ?? false) && (mainInstance?.providerCount ?? 0) === 0
        text: pluginApi?.tr("panel.noProviders")
        color: Color.mOnSurfaceVariant
        wrapMode: Text.Wrap
      }

      // ── Partial errors ──
      NText {
        Layout.fillWidth: true
        visible: (mainInstance?.providerErrorCount ?? 0) > 0 && (mainInstance?.providerCount ?? 0) > 0
        text: root.trf("panel.providerErrors", mainInstance?.providerErrorCount ?? 0)
        color: Color.mSecondary
        wrapMode: Text.Wrap
      }

      // ── Provider list ──
      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: (mainInstance?.providerCount ?? 0) > 0
        clip: true
        model: mainInstance?.providers ?? []
        spacing: Style.marginS

        delegate: NBox {
          width: ListView.view.width
          implicitHeight: provCol.implicitHeight + Style.marginM * 2

          ColumnLayout {
            id: provCol
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS

            // Provider header row
            RowLayout {
              Layout.fillWidth: true
              NText {
                text: modelData.provider || "—"
                font.weight: Style.fontWeightBold
                pointSize: Style.fontSizeL
                Layout.fillWidth: true
              }
              NText {
                text: modelData.source || ""
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
              }
            }

            // ── Primary usage ──
            RowLayout {
              Layout.fillWidth: true
              visible: modelData.usage?.primary !== undefined && modelData.usage?.primary !== null
              spacing: Style.marginM

              NCircleStat {
                ratio: (modelData.usage?.primary?.usedPercent ?? 0) / 100
                fillColor: gaugeColor(modelData.usage?.primary?.usedPercent ?? 0)
                icon: "sparkles"
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                NText {
                  text: (modelData.usage?.primary?.usedPercent ?? 0) + "%"
                  font.weight: Style.fontWeightBold
                  pointSize: Style.fontSizeL
                  color: gaugeColor(modelData.usage?.primary?.usedPercent ?? 0)
                }
                NText {
                  text: modelData.usage?.primary?.resetDescription || ""
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeXS
                  visible: (modelData.usage?.primary?.resetDescription || "") !== ""
                }
                NText {
                  text: Math.round((modelData.usage?.primary?.windowMinutes ?? 0) / 60) + "h window"
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeXS
                  visible: (modelData.usage?.primary?.windowMinutes ?? 0) > 0
                }
              }
            }

            // ── Secondary usage ──
            RowLayout {
              Layout.fillWidth: true
              visible: modelData.usage?.secondary !== undefined && modelData.usage?.secondary !== null
              spacing: Style.marginM

              NLinearGauge {
                orientation: Qt.Horizontal
                ratio: (modelData.usage?.secondary?.usedPercent ?? 0) / 100
                fillColor: gaugeColor(modelData.usage?.secondary?.usedPercent ?? 0)
                Layout.fillWidth: true
                Layout.preferredHeight: 8 * Style.uiScaleRatio
              }

              NText {
                text: (modelData.usage?.secondary?.usedPercent ?? 0) + "%"
                font.family: Settings.data.ui.fontFixed
                pointSize: Style.fontSizeS
                color: gaugeColor(modelData.usage?.secondary?.usedPercent ?? 0)
                Layout.minimumWidth: 36
              }
            }
            NText {
              Layout.fillWidth: true
              visible: modelData.usage?.secondary !== undefined && modelData.usage?.secondary !== null
              text: (modelData.usage?.secondary?.resetDescription || "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
            }

            // ── Credits ──
            RowLayout {
              Layout.fillWidth: true
              visible: modelData.credits !== undefined && modelData.credits !== null
              NText {
                text: pluginApi?.tr("panel.credits") + ":"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeXS
              }
              NText {
                text: (modelData.credits?.remaining ?? "—")
                font.family: Settings.data.ui.fontFixed
                pointSize: Style.fontSizeXS
                color: (modelData.credits?.remaining ?? 1) <= 0 ? Color.mError : Color.mOnSurface
              }
            }

            // ── Account ──
            NText {
              Layout.fillWidth: true
              visible: (modelData.usage?.accountEmail || modelData.usage?.identity?.accountEmail || "") !== ""
              text: (modelData.usage?.accountEmail || modelData.usage?.identity?.accountEmail || "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              wrapMode: Text.Wrap
            }

            // ── Status page info ──
            NText {
              Layout.fillWidth: true
              visible: (modelData.status?.description || "") !== ""
              text: modelData.status?.description || ""
              color: Color.mOnSurfaceVariant
              wrapMode: Text.Wrap
              pointSize: Style.fontSizeXS
            }
          }
        }
      }
    }
  }
}
