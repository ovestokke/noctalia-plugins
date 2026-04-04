import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null

    readonly property var  geometryPlaceholder:     panelContainer
    property real          contentPreferredWidth:   400 * Style.uiScaleRatio
    readonly property real maxHeight:               540 * Style.uiScaleRatio
    property real          contentPreferredHeight:  Math.min(contentColumn.implicitHeight + Style.marginL * 2, maxHeight)
    property bool          panelReady:              false
    readonly property bool allowAttach:             true

    Behavior on contentPreferredHeight {
        enabled: panelReady
        NumberAnimation { duration: 180; easing.type: Easing.InOutCubic }
    }

    Timer { id: readyTimer; interval: 400; repeat: false; onTriggered: panelReady = true }
    Component.onCompleted: readyTimer.start()

    property var cfg:      pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    readonly property var    mainInstance:    pluginApi?.mainInstance
    readonly property var    hosts:           mainInstance?.hosts            ?? []
    readonly property int    thresholdGood:   mainInstance?.thresholdGood    ?? 20
    readonly property int    thresholdWarning:mainInstance?.thresholdWarning ?? 70

    property int _activeHost:    0
    property int _windowMinutes: 30     // 10 | 30 | 60

    readonly property var _host: hosts[_activeHost] ?? null

    readonly property var _currentSamples: {
        void(_host?.samples)
        return _host ? _host.samplesInWindow(_windowMinutes) : []
    }

    readonly property var _currentRtts: _currentSamples.map(s => s.rtt)

    function statusColor(icon) {
        switch(icon) {
            case "good":    return Color.mPrimary
            case "warning": return Color.mTertiary
            case "critical":return Color.mError
            default:        return Color.mOnSurface
        }
    }

    function rttColor(rtt) {
        if (rtt < 0)                  return Color.mOnSurface
        if (rtt < thresholdGood)      return Color.mPrimary
        if (rtt < thresholdWarning)   return Color.mTertiary
        return Color.mError
    }

    function _threshY(thresh, maxVal, h) {
        if (maxVal <= 0 || h <= 0) return -1
        const pad      = maxVal * 0.12                  // curvePadding
        const norm     = (thresh + pad) / (maxVal + pad * 2)
        return h * (1.0 - norm)                         // flip: y=0 is top
    }

    anchors.fill: parent

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            id: contentColumn
            anchors { fill: parent; margins: Style.marginL }
            spacing: Style.marginM

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                NText { text: pluginApi?.tr("panel.title"); pointSize: Style.fontSizeL; font.weight: Font.Bold; color: Color.mOnSurface; Layout.alignment: Qt.AlignVCenter }
                Item  { Layout.fillWidth: true }

                NIconButton {
                    icon:        "settings"
                    tooltipText: pluginApi?.tr("menu.settings")
                    onClicked: {
                        const screen = pluginApi?.panelOpenScreen
                        if (screen) {
                            pluginApi.closePanel(screen)
                            Qt.callLater(() => BarService.openPluginSettings(screen, pluginApi.manifest))
                        }
                    }
                    Layout.alignment: Qt.AlignVCenter
                }
                NIconButton {
                    icon:        "x"
                    tooltipText: pluginApi?.tr("panel.close")
                    onClicked: { const s = pluginApi?.panelOpenScreen; if (s) pluginApi.closePanel(s) }
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Flickable {
                Layout.fillWidth: true
                implicitHeight:   tabBar.implicitHeight
                contentWidth:     tabBar.implicitWidth
                clip:             true
                flickableDirection: Flickable.HorizontalFlick

                NTabBar {
                    id: tabBar
                    color: "transparent"
                    currentIndex: root._activeHost

                    Repeater {
                        model: root.hosts
                        delegate: NTabButton {
                            required property int index
                            required property var modelData
                            text:     modelData.name
                            tabIndex: index
                            checked:  tabBar.currentIndex === index
                            onClicked: { root._activeHost = index }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                Repeater {
                    model: [
                        { labelKey: "panel.timings.10m", avg: root._host?.avg10m  ?? -1 },
                        { labelKey: "panel.timings.30m", avg: root._host?.avg30m  ?? -1 },
                        { labelKey: "panel.timings.1h",  avg: root._host?.avg60m  ?? -1 },
                        { labelKey: "panel.timings.last",avg: root._host?.lastRtt ?? -1 },
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight:   statCol.implicitHeight + Style.marginS * 2
                        radius:           Style.radiusM
                        color:            Color.mSurfaceVariant
                        border.color:     Qt.alpha(Color.mOnSurface, 0.08)
                        border.width:     1

                        readonly property real   _avg:    modelData.avg
                        readonly property bool   _hasVal: _avg >= 0
                        readonly property color  _col:    root.rttColor(_avg)

                        ColumnLayout {
                            id: statCol
                            anchors { fill: parent; margins: Style.marginS }
                            spacing: 2

                            NText {
                                text:  parent.parent._hasVal ? Math.round(parent.parent._avg) + " ms" : "—"
                                pointSize: Style.fontSizeL
                                font.weight: Font.Bold
                                color: parent.parent._col
                                Layout.alignment: Qt.AlignHCenter
                            }
                            NText {
                                text:      pluginApi?.tr(modelData.labelKey) ?? ""
                                pointSize: Style.fontSizeXS
                                color:     Color.mSecondary
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.marginXS

                NTabBar {
                    id: windowBar
                    currentIndex: root._windowMinutes === 10 ? 0 : root._windowMinutes === 30 ? 1 : 2
                    color: "transparent"

                    NTabButton { text: pluginApi?.tr("panel.timings.10m"); tabIndex: 0; checked: root._windowMinutes === 10;  onClicked: root._windowMinutes = 10  }
                    NTabButton { text: pluginApi?.tr("panel.timings.30m"); tabIndex: 1; checked: root._windowMinutes === 30;  onClicked: root._windowMinutes = 30  }
                    NTabButton { text: pluginApi?.tr("panel.timings.1h");  tabIndex: 2; checked: root._windowMinutes === 60;  onClicked: root._windowMinutes = 60  }
                }
            }

            NDivider { Layout.fillWidth: true; opacity: 0.4 }

            Item {
                Layout.fillWidth: true
                implicitHeight:   140 * Style.uiScaleRatio + timeRow.implicitHeight + Style.marginXS

                Item {
                    id: graphArea
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 140 * Style.uiScaleRatio

                    NGraph {
                        id: graph
                        anchors.fill: parent

                        values:         root._currentRtts
                        minValue:       0
                        maxValue:       root._currentRtts.length > 0
                                            ? Math.max(...root._currentRtts, root.thresholdWarning) * 1.15
                                            : root.thresholdWarning * 1.15
                        animateScale:   true
                        fill:           true
                        updateInterval: (mainInstance?.intervalSeconds ?? 5) * 1000

                        color: {
                            switch(root._host?.status ?? "unknown") {
                                case "good":    return Color.resolveColorKey(mainInstance?.colorGood     ?? "primary")
                                case "warning": return Color.resolveColorKey(mainInstance?.colorWarning  ?? "tertiary")
                                case "critical":return Color.resolveColorKey(mainInstance?.colorCritical ?? "error")
                                default:        return Color.mOnSurface
                            }
                        }
                    }

                    Repeater {
                        model: [
                            { thresh: root.thresholdGood,    colorKey: mainInstance?.colorGood    ?? "primary"  },
                            { thresh: root.thresholdWarning, colorKey: mainInstance?.colorWarning ?? "tertiary" },
                        ]
                        delegate: Item {
                            required property var modelData
                            anchors { left: parent.left; right: parent.right }

                            readonly property real  _y:   root._threshY(modelData.thresh, graph.maxValue, graph.height)
                            readonly property color _col: Color.resolveColorKey(modelData.colorKey)

                            visible: _y >= 0 && _y <= graph.height
                            y: _y

                            Row {
                                anchors { left: parent.left; right: labelBox.left; rightMargin: Style.marginXS }
                                spacing: 3
                                Repeater {
                                    model: Math.ceil(parent.width / 7)
                                    delegate: Rectangle { width: 4; height: 1; color: Qt.alpha(parent.parent.parent._col, 0.40) }
                                }
                            }

                            Rectangle {
                                id: labelBox
                                anchors.right: parent.right
                                y: -height / 2
                                implicitWidth:  threshLabel.implicitWidth + Style.marginXS * 2
                                implicitHeight: threshLabel.implicitHeight + 2
                                radius: Style.radiusXS
                                color:  Qt.alpha(parent._col, 0.12)
                                NText { id: threshLabel; anchors.centerIn: parent; text: modelData.thresh + "ms"; pointSize: Style.fontSizeXS * 0.85; color: parent.parent._col }
                            }
                        }
                    }

                    MouseArea {
                        id: graphHover
                        anchors.fill: parent
                        hoverEnabled: true

                        readonly property int _idx: {
                            const n = root._currentSamples.length
                            if (n < 2 || !containsMouse) return -1
                            return Math.max(0, Math.min(n - 1, Math.round(mouseX / width * (n - 1))))
                        }
                        readonly property var _sample: _idx >= 0 ? root._currentSamples[_idx] : null

                        Rectangle {
                            visible: graphHover._idx >= 0
                            x:       graphHover._idx >= 0
                                        ? (graphHover._idx / Math.max(root._currentSamples.length - 1, 1)) * parent.width - width / 2
                                        : 0
                            width:   1
                            height:  parent.height
                            color:   Qt.alpha(Color.mOnSurface, 0.25)

                            Rectangle {
                                readonly property string _label: {
                                    const s = graphHover._sample
                                    if (!s) return ""
                                    const d    = new Date(s.ts)
                                    const hms  = d.getHours().toString().padStart(2,"0") + ":" + d.getMinutes().toString().padStart(2,"0") + ":" + d.getSeconds().toString().padStart(2,"0")
                                    return `${s.rtt}ms · ${hms}`
                                }

                                readonly property real _rawX: -(implicitWidth / 2)
                                x: Math.max(-parent.x, Math.min(graphArea.width - parent.x - implicitWidth, _rawX))
                                y: Style.marginXS

                                implicitWidth:  bubbleText.implicitWidth + Style.marginS * 2
                                implicitHeight: bubbleText.implicitHeight + Style.marginXS * 2
                                radius: Style.radiusS
                                color:  Color.mSurfaceVariant
                                border.color: Qt.alpha(Color.mOnSurface, 0.15)
                                border.width: 1

                                NText { id: bubbleText; anchors.centerIn: parent; text: parent._label; pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                            }
                        }
                    }
                }

                Row {
                    id: timeRow
                    anchors { left: parent.left; right: parent.right; top: graphArea.bottom; topMargin: Style.marginXS }
                    visible: root._currentSamples.length >= 2

                    Repeater {
                        model: 3   // start · mid · end
                        delegate: Item {
                            required property int index
                            width:  timeRow.width / 3
                            height: timeLabel.implicitHeight

                            readonly property int _sIdx: {
                                const n = root._currentSamples.length
                                if (n < 2) return -1
                                return index === 0 ? 0 : index === 1 ? Math.floor(n / 2) : n - 1
                            }

                            NText {
                                id: timeLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: parent._sIdx >= 0

                                text: {
                                    const s = root._currentSamples[parent._sIdx]
                                    if (!s) return ""
                                    const d = new Date(s.ts)
                                    return d.getHours().toString().padStart(2,"0") + ":" + d.getMinutes().toString().padStart(2,"0")
                                }
                                pointSize: Style.fontSizeXS * 0.85
                                color:     Qt.alpha(Color.mSecondary, 0.6)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                NText {
                    text:      root._host ? root._host.address : ""
                    pointSize: Style.fontSizeXS
                    color:     Color.mSecondary
                    opacity:   0.6
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible:      root._host?.timedOut ?? false
                    implicitWidth:  timeoutLabel.implicitWidth + Style.marginM * 2
                    implicitHeight: timeoutLabel.implicitHeight + Style.marginXS * 2
                    radius:       Style.radiusS
                    color:        Qt.alpha(Color.mError, 0.12)
                    border.color: Color.mError
                    border.width: 1

                    NText {
                        id:        timeoutLabel
                        anchors.centerIn: parent
                        text:      pluginApi?.tr("widget.timedOut") ?? "Timed out"
                        pointSize: Style.fontSizeXS
                        color:     Color.mError
                    }
                }
            }
        }
    }
}
