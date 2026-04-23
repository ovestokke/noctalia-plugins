import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"

  readonly property var row: mainInstance?.primaryActiveRow
  readonly property bool hasActiveRow: row !== null && row !== undefined

  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName) * (mainInstance?.sizeScale() ?? 1)
  readonly property real capsuleWidth: {
    if (isVerticalBar || !hasActiveRow) return capsuleHeight
    return Math.max(capsuleHeight, contentRow.implicitWidth + Style.marginM * 2)
  }

  implicitWidth: capsuleWidth
  implicitHeight: capsuleHeight

  function rowElapsedLabel() {
    if (!hasActiveRow || !(mainInstance?.showElapsed ?? true)) return ""
    return mainInstance.formatElapsed(mainInstance.elapsedSeconds(row))
  }

  Rectangle {
    id: capsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.capsuleWidth
    height: root.capsuleHeight
    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    border.width: Style.capsuleBorderWidth
    border.color: Style.capsuleBorderColor

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NText {
        text: "π"
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        color: hasActiveRow ? mainInstance.statusColor(row.status) : Color.mOnSurface
      }

      Item {
        visible: hasActiveRow && !isVerticalBar
        implicitWidth: details.implicitWidth
        implicitHeight: details.implicitHeight

        RowLayout {
          id: details
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.marginS

          NIcon {
            id: spinner
            icon: "loader-2"
            pointSize: Style.fontSizeS
            color: mainInstance?.statusColor(row.status) ?? Color.mPrimary

            RotationAnimation on rotation {
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 950
              running: hasActiveRow
            }
          }

          NText {
            text: row.project
            pointSize: Style.fontSizeS
            color: Color.mOnSurface
            font.weight: Style.fontWeightMedium
            elide: Text.ElideRight
            Layout.maximumWidth: 120
          }

          NText {
            text: mainInstance?.statusLabel(row.status) ?? ""
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }

          NText {
            visible: (mainInstance?.showElapsed ?? true)
            text: rowElapsedLabel()
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            font.family: Settings.data.ui.fontFixed
          }

          NText {
            visible: (mainInstance?.showContext ?? true) && row.ctxPct !== null && row.ctxPct !== undefined
            text: row.ctxPct + "%"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": pluginApi?.tr("context.open-settings"),
        "action": "settings",
        "icon": "settings"
      },
      {
        "label": pluginApi?.tr("context.clear-completed"),
        "action": "clear-completed",
        "icon": "eraser",
        "enabled": (mainInstance?.completedSessions?.length ?? 0) > 0
      },
      {
        "label": pluginApi?.tr("context.clear-all"),
        "action": "clear-all",
        "icon": "trash",
        "enabled": (mainInstance?.hasAnyRows ?? false)
      }
    ]

    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)

      if (action === "settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest)
      } else if (action === "clear-completed") {
        mainInstance?.clearCompleted()
      } else if (action === "clear-all") {
        mainInstance?.clearAll()
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: (mouse) => {
      if (mouse.button === Qt.LeftButton) {
        if (pluginApi) {
          pluginApi.openPanel(root.screen, root)
        }
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen)
      }
    }
  }
}
