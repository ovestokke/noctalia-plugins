import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System

Item {
    id: root

    // Plugin API (injected by PluginService)
    property var pluginApi: null
    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    // Required properties for bar widgets
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screen?.name)
    readonly property real contentWidth: row.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    readonly property color iconColor: Color.resolveColorKey(cfg.iconColor ?? defaults.iconColor ?? "none")

    implicitWidth: row.implicitWidth + Style.marginM * 2
    implicitHeight: Style.barHeight

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                icon: "burger"
                color: mouseArea.containsMouse ? Color.mOnHover : root.iconColor
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (pluginApi) {
                pluginApi.openPanel(root.screen, root);
            }
        }

        onEntered: {
            TooltipService.show(root, pluginApi?.tr("widget.tooltip"), BarService.getTooltipDirection());
        }

        onExited: {
            TooltipService.hide();
        }
    }
}
