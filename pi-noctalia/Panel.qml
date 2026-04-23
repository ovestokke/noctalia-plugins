import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  readonly property var mainInstance: pluginApi?.mainInstance

  property real contentPreferredWidth: 440 * (mainInstance?.sizeScale() ?? 1) * Style.uiScaleRatio
  property real contentPreferredHeight: 520 * (mainInstance?.sizeScale() ?? 1) * Style.uiScaleRatio

  anchors.fill: parent

  function trf(key, arg1, arg2) {
    var value = pluginApi?.tr(key) || ""
    if (arg1 !== undefined) value = value.replace("%1", arg1)
    if (arg2 !== undefined) value = value.replace("%2", arg2)
    return value
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    NBox {
      anchors.fill: parent

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            text: "π"
            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightBold
            color: mainInstance?.accentColorValue() ?? Color.mPrimary
          }

          NText {
            text: pluginApi?.tr("panel.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NText {
            text: trf("panel.summary", (mainInstance?.activeSessions?.length ?? 0), (mainInstance?.completedSessions?.length ?? 0))
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: (mainInstance?.hasAnyRows ?? false)
          spacing: Style.marginS

          NButton {
            text: pluginApi?.tr("panel.clear-completed")
            icon: "eraser"
            enabled: (mainInstance?.completedSessions?.length ?? 0) > 0
            onClicked: mainInstance?.clearCompleted()
          }

          NButton {
            text: pluginApi?.tr("panel.clear-all")
            icon: "trash"
            enabled: (mainInstance?.hasAnyRows ?? false)
            onClicked: mainInstance?.clearAll()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Color.mOnSurface, 0.12)
          visible: (mainInstance?.hasAnyRows ?? false)
        }

        NText {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: !(mainInstance?.hasAnyRows ?? false)
          text: pluginApi?.tr("panel.empty")
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
        }

        Flickable {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: (mainInstance?.hasAnyRows ?? false)
          clip: true
          contentWidth: width
          contentHeight: rowsColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: rowsColumn
            width: parent.width
            spacing: Style.marginS

            Repeater {
              model: mainInstance?.visibleRows ?? []

              delegate: Rectangle {
                Layout.fillWidth: true
                implicitHeight: contentColumn.implicitHeight + Style.marginM * 2
                radius: Style.radiusM
                color: Qt.alpha(Color.mOnSurface, 0.04)
                border.width: 1
                border.color: Qt.alpha(Color.mOnSurface, 0.08)

                property var rowData: modelData

                ColumnLayout {
                  id: contentColumn
                  anchors.fill: parent
                  anchors.margins: Style.marginM
                  spacing: Style.marginXS

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NIcon {
                      icon: mainInstance?.statusIcon(rowData.status) ?? "activity"
                      pointSize: Style.fontSizeS
                      color: mainInstance?.statusColor(rowData.status) ?? Color.mPrimary
                    }

                    NText {
                      text: rowData.project
                      pointSize: Style.fontSizeS
                      color: Color.mOnSurface
                      font.weight: Style.fontWeightMedium
                    }

                    Rectangle {
                      radius: Style.radiusS
                      color: Qt.alpha(mainInstance?.statusColor(rowData.status) ?? Color.mPrimary, 0.16)
                      implicitHeight: statusText.implicitHeight + Style.marginXS
                      implicitWidth: statusText.implicitWidth + Style.marginS

                      NText {
                        id: statusText
                        anchors.centerIn: parent
                        text: mainInstance?.statusLabel(rowData.status) ?? rowData.status
                        pointSize: Style.fontSizeXS
                        color: mainInstance?.statusColor(rowData.status) ?? Color.mPrimary
                      }
                    }

                    Item {
                      Layout.fillWidth: true
                    }

                    NText {
                      visible: (mainInstance?.showContext ?? true) && rowData.ctxPct !== null && rowData.ctxPct !== undefined
                      text: rowData.ctxPct + "%"
                      pointSize: Style.fontSizeXS
                      color: Color.mOnSurfaceVariant
                    }

                    NText {
                      visible: mainInstance?.showElapsed ?? true
                      text: mainInstance?.formatElapsed(mainInstance?.elapsedSeconds(rowData)) ?? ""
                      pointSize: Style.fontSizeXS
                      color: Color.mOnSurfaceVariant
                      font.family: Settings.data.ui.fontFixed
                    }
                  }

                  NText {
                    visible: rowData.detail !== undefined && rowData.detail !== null && rowData.detail !== ""
                    text: rowData.detail
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                  }

                  NText {
                    visible: (mainInstance?.showPrompt ?? true) && rowData.prompt !== undefined && rowData.prompt !== null && rowData.prompt !== ""
                    text: trf("panel.prompt", rowData.prompt)
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
