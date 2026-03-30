import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import QtQuick.Layouts
import "." as Tamagotchi

Item {
    id: root

    property var         pluginApi: null
    property ShellScreen screen

    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screen?.name ?? "")

    implicitHeight: capsuleHeight
    implicitWidth:  content.implicitWidth + Style.marginM * 2

		onPluginApiChanged: {
			if (pluginApi) {
            Tamagotchi.TamagotchiState.pluginApi = pluginApi
            Tamagotchi.TamagotchiState.load()
        }
    }

    readonly property int _minStat: Math.min(
        Tamagotchi.TamagotchiState.hunger,
        Tamagotchi.TamagotchiState.happiness,
        Tamagotchi.TamagotchiState.cleanliness
    )

    readonly property string _statIcon: {
        var ts = Tamagotchi.TamagotchiState
        var mn = Math.min(ts.hunger, ts.happiness, ts.cleanliness)
        if      (mn === ts.hunger)      return "🍗"
        else if (mn === ts.happiness)   return "💛"
        else                            return "🧼"
    }

    readonly property string _petEmoji: {
        var s = Tamagotchi.TamagotchiState.petState
        var map = {
            "idle": "🐸", 
            "sleeping": "😴",
						"sad": "😢",
						"dirty": "🤢"
        }
        return map[s] ?? "🐸"
    }

    readonly property color _alertColor: {
        if (_minStat < 20) return "#E24B4A"
        if (_minStat < 40) return "#EF9F27"
        return Color.mOnSurface
			}


    Timer {
        interval: 60000 // 1 minuto
        running:  true
        repeat:   true
        onTriggered: Tamagotchi.TamagotchiState.decay()
		}

    Timer {
        interval: 1000 
        running:  true
        repeat:   true
        onTriggered: Tamagotchi.TamagotchiState.updatePetState()
    }

    Rectangle {
        anchors.centerIn: parent
        height: capsuleHeight
        width:  root.implicitWidth
        radius: Style.radiusL
        color:  Color.mSurfaceVariant

        border.color: root._minStat < 20 ? "#E24B4A" : "transparent"
        border.width: root._minStat < 20 ? 1 : 0

        SequentialAnimation on border.width {
            running: root._minStat < 20
            loops:   Animation.Infinite
            NumberAnimation { to: 2; duration: 500 }
            NumberAnimation { to: 0; duration: 500 }
        }

        RowLayout {
            id: content
            anchors.centerIn: parent
						spacing: 5
						anchors.verticalCenter: parent.verticalCenter

            Text {
                text:           root._petEmoji
                font.pixelSize: 13
								color:          Color.mOnSurface
								Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text:           root._statIcon
                font.pixelSize: 11
                visible:        root._minStat < 60
                color:          root._alertColor
								Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text:           root._minStat + "%"
                font.pixelSize: 11
                color:          root._alertColor
								Layout.alignment: Qt.AlignVCenter

                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (pluginApi) {
								pluginApi.openPanel(root.screen, root, { width: 260, height: 180 })
            }
        }
    }
}
