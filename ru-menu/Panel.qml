import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: root

    // https://stackoverflow.com/questions/4156434/javascript-get-the-first-day-of-the-week-from-current-date
    function getMonday(d) {
        d = new Date(d);
        var day = d.getDay(), diff = d.getDate() - day + (day == 0 ? -6 : 1); // adjust when day is sunday
        return new Date(d.setDate(diff));
    }

    function getWeekFormat(d) {
        const date = d.getUTCDate().toString().padStart(2, '0') + "/" + (d.getUTCMonth() + 1).toString().padStart(2, '0') + "/" + d.getUTCFullYear();
        return pluginApi?.tr("panel.week-format", {
            date: date
        });
    }

    function getMenuUrl(d) {
        const day = d.getUTCDate().toString().padStart(2, '0');
        const month = (d.getUTCMonth() + 1).toString().padStart(2, '0');
        const year = d.getUTCFullYear().toString().slice(-2);
        return "https://www.uclouvain.be/fr/system/files/uclouvain_assetmanager/groups/cms-editors-resto-u/" + day + month + year + ".jpeg";
    }

    // Plugin API (injected by PluginPanelSlot)
    property var pluginApi: null

    // SmartPanel properties (required for panel behavior)
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    // Preferred dimensions
    property real contentPreferredWidth: 500 * Style.uiScaleRatio
    property real contentPreferredHeight: 540 * Style.uiScaleRatio

    property date currentMonday: getMonday(new Date())
    property string dateString: getWeekFormat(currentMonday)

    anchors.fill: parent

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            id: dateSelector

            anchors {
                fill: parent
                margins: Style.marginM
            }
            spacing: Style.marginM
            Rectangle {
                id: headerRect
                radius: Style.marginM
                Layout.preferredWidth: parent.width
                Layout.preferredHeight: 40 * Style.uiScaleRatio
                color: "transparent"
                border.color: Color.mPrimary

                NButton {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.marginM
                    anchors.verticalCenter: parent.verticalCenter

                    width: 20 * Style.uiScaleRatio
                    height: 20 * Style.uiScaleRatio

                    NIcon {
                        icon: "caret-left"
                        anchors.centerIn: parent
                    }

                    onClicked: {
                        currentMonday = getMonday(new Date(currentMonday.setDate(currentMonday.getDate() - 7)));
                        dateString = getWeekFormat(currentMonday);
                        menuImage.loaded = false;
                        menuImage.source = getMenuUrl(currentMonday);
                        loadingOverlay.visible = true;
                        errorOverlay.visible = false;
                        rotationAnimation.running = true;
                    }
                }

                NText {
                    anchors.centerIn: parent
                    text: dateString
                }

                NButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.marginM
                    anchors.verticalCenter: parent.verticalCenter

                    width: 20 * Style.uiScaleRatio
                    height: 20 * Style.uiScaleRatio

                    NIcon {
                        icon: "caret-right"
                        anchors.centerIn: parent
                    }

                    onClicked: {
                        currentMonday = getMonday(new Date(currentMonday.setDate(currentMonday.getDate() + 7)));
                        dateString = getWeekFormat(currentMonday);
                        menuImage.loaded = false;
                        menuImage.source = getMenuUrl(currentMonday);
                        loadingOverlay.visible = true;
                        errorOverlay.visible = false;
                        rotationAnimation.running = true;
                    }
                }
            }

            Item {
                id: imageContainer
                Layout.fillWidth: true
                Layout.fillHeight: true

                NBox {
                    id: loadingOverlay
                    anchors.centerIn: parent
                    visible: !menuImage.loaded
                    color: "transparent"

                    NIcon {
                        icon: "refresh"
                        font.pixelSize: 48
                        anchors.centerIn: parent
                        RotationAnimation on rotation {
                            id: rotationAnimation
                            loops: Animation.Infinite
                            duration: 1000
                            from: 0
                            to: 360
                        }
                    }
                }

                NBox {
                    id: errorOverlay
                    anchors.centerIn: parent
                    visible: false
                    color: "transparent"

                    NText {
                        text: pluginApi?.tr("panel.error.no-menu")
                        anchors.centerIn: parent
                    }
                }

                Image {
                    id: menuImage
                    property bool loaded: false
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: getMenuUrl(currentMonday)
                    cache: true
                    asynchronous: true

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            loaded = true;
                            rotationAnimation.running = false;
                            loadingOverlay.visible = false;
                            errorOverlay.visible = false;
                        } else if (status === Image.Error) {
                            loaded = false;
                            rotationAnimation.running = false;
                            loadingOverlay.visible = false;
                            errorOverlay.visible = true;
                        }
                    }
                }
            }
        }
    }
}
