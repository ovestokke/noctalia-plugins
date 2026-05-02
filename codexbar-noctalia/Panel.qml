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
  property real contentPreferredWidth: 400 * Style.uiScaleRatio
  property real contentPreferredHeight: 480 * Style.uiScaleRatio
  readonly property bool allowAttach: true

  anchors.fill: parent

  function trf(key, arg1) {
    var value = pluginApi?.tr(key) || ""
    if (arg1 !== undefined) value = value.replace("%1", arg1)
    return value
  }

  function usageColor(pct) {
    if (pct >= 90) return Color.mError
    if (pct >= 70) return Color.mSecondary
    return Color.mPrimary
  }

  // ── Capsule progress bar (matches CodexBar Mac style) ──
  component UsageBar: Item {
    id: bar
    property real percent: 0
    property color fillColor: Color.mPrimary
    readonly property real barHeight: 6 * Style.uiScaleRatio

    implicitWidth: parent ? parent.width : 200
    implicitHeight: barHeight + 4 * Style.uiScaleRatio

    Rectangle {
      anchors.fill: parent
      anchors.margins: 2 * Style.uiScaleRatio
      radius: bar.barHeight / 2
      color: Color.mOutline

      Rectangle {
        readonly property real rawFill: parent.width * Math.min(1, Math.max(0, bar.percent / 100))
        width: rawFill < 1 ? 0 : rawFill
        height: parent.height
        radius: parent.radius
        color: bar.fillColor

        Behavior on color {
          ColorAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginS

      // ── Header ──
      RowLayout {
        Layout.fillWidth: true
        NText {
          text: pluginApi?.tr("panel.title")
          pointSize: Style.fontSizeXL
          font.weight: Style.fontWeightBold
          Layout.fillWidth: true
        }
        NIconButtonHot {
          icon: "refresh"
          tooltipText: pluginApi?.tr("panel.refresh")
          enabled: (mainInstance?.ready ?? false) && !(mainInstance?.refreshing ?? false)
          onClicked: mainInstance?.refreshUsage()
        }
      }

      // ── CLI status / errors (only shown when there's a problem) ──
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
            wrapMode: Text.Wrap; Layout.fillWidth: true
          }
          NText {
            visible: (mainInstance?.errorMessage || "") !== ""
            text: mainInstance?.errorMessage || ""
            color: Color.mError
            wrapMode: Text.Wrap; Layout.fillWidth: true
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

      // ── Provider list ──
      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: (mainInstance?.providerCount ?? 0) > 0
        clip: true
        model: mainInstance?.providers ?? []
        spacing: Style.marginM

        delegate: ColumnLayout {
          width: ListView.view.width
          spacing: Style.marginS

          // ── Provider header ──
          RowLayout {
            Layout.fillWidth: true
            NText {
              text: modelData.provider || "—"
              font.weight: Style.fontWeightBold
              pointSize: Style.fontSizeL
              Layout.fillWidth: true
            }
            NText {
              text: modelData.usage?.identity?.loginMethod || ""
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              visible: (modelData.usage?.identity?.loginMethod || "") !== ""
            }
            NText {
              text: modelData.usage?.identity?.accountEmail || modelData.usage?.accountEmail || ""
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              visible: (modelData.usage?.identity?.accountEmail || modelData.usage?.accountEmail || "") !== ""
            }
          }

          // ── Session metric (primary) ──
          ColumnLayout {
            Layout.fillWidth: true
            visible: modelData.usage?.primary !== undefined && modelData.usage?.primary !== null
            spacing: 4 * Style.uiScaleRatio

            RowLayout {
              Layout.fillWidth: true
              NText {
                text: pluginApi?.tr("panel.session")
                font.weight: Style.fontWeightMedium
                pointSize: Style.fontSizeS
              }
              Item { Layout.fillWidth: true }
              NText {
                text: (modelData.usage?.primary?.usedPercent ?? 0) + "% used"
                font.family: Settings.data.ui.fontFixed
                pointSize: Style.fontSizeXS
                color: usageColor(modelData.usage?.primary?.usedPercent ?? 0)
              }
            }

            UsageBar {
              Layout.fillWidth: true
              percent: modelData.usage?.primary?.usedPercent ?? 0
              fillColor: usageColor(modelData.usage?.primary?.usedPercent ?? 0)
            }

            RowLayout {
              Layout.fillWidth: true
              NText {
                text: modelData.usage?.primary?.resetDescription || ""
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                visible: (modelData.usage?.primary?.resetDescription || "") !== ""
              }
              Item { Layout.fillWidth: true }
              NText {
                text: Math.round((modelData.usage?.primary?.windowMinutes ?? 0) / 60) + "h window"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                visible: (modelData.usage?.primary?.windowMinutes ?? 0) > 0
              }
            }
          }

          // ── Weekly metric (secondary) ──
          ColumnLayout {
            Layout.fillWidth: true
            visible: modelData.usage?.secondary !== undefined && modelData.usage?.secondary !== null
            spacing: 4 * Style.uiScaleRatio

            RowLayout {
              Layout.fillWidth: true
              NText {
                text: pluginApi?.tr("panel.weekly")
                font.weight: Style.fontWeightMedium
                pointSize: Style.fontSizeS
              }
              Item { Layout.fillWidth: true }
              NText {
                text: (modelData.usage?.secondary?.usedPercent ?? 0) + "% used"
                font.family: Settings.data.ui.fontFixed
                pointSize: Style.fontSizeXS
                color: usageColor(modelData.usage?.secondary?.usedPercent ?? 0)
              }
            }

            UsageBar {
              Layout.fillWidth: true
              percent: modelData.usage?.secondary?.usedPercent ?? 0
              fillColor: usageColor(modelData.usage?.secondary?.usedPercent ?? 0)
            }

            RowLayout {
              Layout.fillWidth: true
              NText {
                text: modelData.usage?.secondary?.resetDescription || ""
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                visible: (modelData.usage?.secondary?.resetDescription || "") !== ""
              }
              Item { Layout.fillWidth: true }
              NText {
                text: Math.round((modelData.usage?.secondary?.windowMinutes ?? 0) / 60) + "h window"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                visible: (modelData.usage?.secondary?.windowMinutes ?? 0) > 0
              }
            }
          }

          // ── Tertiary metric (e.g. Sonnet) ──
          ColumnLayout {
            Layout.fillWidth: true
            visible: modelData.usage?.tertiary !== undefined && modelData.usage?.tertiary !== null
            spacing: 4 * Style.uiScaleRatio

            RowLayout {
              Layout.fillWidth: true
              NText {
                text: pluginApi?.tr("panel.tertiary")
                font.weight: Style.fontWeightMedium
                pointSize: Style.fontSizeS
              }
              Item { Layout.fillWidth: true }
              NText {
                text: (modelData.usage?.tertiary?.usedPercent ?? 0) + "% used"
                font.family: Settings.data.ui.fontFixed
                pointSize: Style.fontSizeXS
                color: usageColor(modelData.usage?.tertiary?.usedPercent ?? 0)
              }
            }

            UsageBar {
              Layout.fillWidth: true
              percent: modelData.usage?.tertiary?.usedPercent ?? 0
              fillColor: usageColor(modelData.usage?.tertiary?.usedPercent ?? 0)
            }
          }

          // ── Divider before credits ──
          NDivider {
            Layout.fillWidth: true
            visible: modelData.credits !== undefined && modelData.credits !== null
          }

          // ── Credits ──
          RowLayout {
            Layout.fillWidth: true
            visible: modelData.credits !== undefined && modelData.credits !== null
            NText {
              text: pluginApi?.tr("panel.credits")
              font.weight: Style.fontWeightMedium
              pointSize: Style.fontSizeS
            }
            Item { Layout.fillWidth: true }
            NText {
              text: (modelData.credits?.remaining ?? "—")
              font.family: Settings.data.ui.fontFixed
              pointSize: Style.fontSizeS
              color: (modelData.credits?.remaining ?? 1) <= 0 ? Color.mError : Color.mOnSurface
            }
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

          // ── Partial errors ──
          NText {
            Layout.fillWidth: true
            visible: (mainInstance?.providerErrorCount ?? 0) > 0
            text: root.trf("panel.providerErrors", mainInstance?.providerErrorCount ?? 0)
            color: Color.mSecondary
            pointSize: Style.fontSizeXS
            wrapMode: Text.Wrap
          }
        }
      }

      // ── Footer ──
      RowLayout {
        Layout.fillWidth: true
        NText {
          text: mainInstance?.currentVersion || ""
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          visible: (mainInstance?.currentVersion || "") !== ""
        }
        Item { Layout.fillWidth: true }
        NText {
          text: (mainInstance?.lastUpdate || "") !== "" ? pluginApi?.tr("panel.lastUpdate") + " " + (mainInstance?.lastUpdate || "") : ""
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
      }
    }
  }
}
