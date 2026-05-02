import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

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
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property bool ready: mainInstance?.ready ?? false
  readonly property bool busy: (mainInstance?.checking ?? false) || (mainInstance?.refreshing ?? false) || (mainInstance?.installing ?? false)
  readonly property string label: {
    if (!mainInstance?.installed) return pluginApi?.tr("widget.missing")
    if (!(mainInstance?.runtimeOk ?? false)) return pluginApi?.tr("widget.broken")
    if ((mainInstance?.providerCount ?? 0) <= 0) return pluginApi?.tr("widget.empty")
    return mainInstance.providerLabel(mainInstance.primaryProvider) + " " + mainInstance.usedLabel(mainInstance.primaryProvider)
  }

  implicitWidth: isVerticalBar ? capsuleHeight : Math.max(capsuleHeight, contentRow.implicitWidth + Style.marginM * 2)
  implicitHeight: capsuleHeight

  Rectangle {
    id: capsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.implicitWidth
    height: root.implicitHeight
    radius: Style.radiusL
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    border.width: Style.capsuleBorderWidth
    border.color: Style.capsuleBorderColor

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.marginS

      NIcon {
        icon: busy ? "loader-2" : "sparkles"
        pointSize: Style.fontSizeM
        color: ready ? Color.mPrimary : Color.mError

        RotationAnimation on rotation {
          loops: Animation.Infinite
          from: 0
          to: 360
          duration: 950
          running: busy
        }
      }

      NText {
        visible: !root.isVerticalBar
        text: root.label
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
        font.weight: Style.fontWeightMedium
        elide: Text.ElideRight
        Layout.maximumWidth: 160
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu
    model: [
      { "label": pluginApi?.tr("context.refresh"), "action": "refresh", "icon": "refresh", "enabled": mainInstance?.ready ?? false },
      { "label": pluginApi?.tr("context.check"), "action": "check", "icon": "search" },
      { "label": pluginApi?.tr("context.settings"), "action": "settings", "icon": "settings" }
    ]
    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)
      if (action === "refresh") mainInstance?.refreshUsage()
      else if (action === "check") mainInstance?.checkCli()
      else if (action === "settings") BarService.openPluginSettings(screen, pluginApi.manifest)
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: (mouse) => {
      if (mouse.button === Qt.LeftButton) pluginApi?.togglePanel(root.screen, root)
      else if (mouse.button === Qt.RightButton) PanelService.showContextMenu(contextMenu, root, screen)
    }
  }
}
