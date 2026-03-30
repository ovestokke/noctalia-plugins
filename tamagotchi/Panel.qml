import QtQuick
import QtQuick.Layouts
import QtMultimedia
import qs.Commons
import "." as Tamagotchi
import "./components"

Item {
    id: root

    property var pluginApi: null

		property real contentPreferredWidth: 400 * Style.uiScaleRatio
		property real contentPreferredHeight: 430 * Style.uiScaleRatio
  


		ColumnLayout {
        anchors.fill:    parent
				anchors.margins: 8
				spacing:         30

				StatBars {
						Layout.fillWidth: true
						hunger:      Tamagotchi.TamagotchiState.hunger
						happiness:   Tamagotchi.TamagotchiState.happiness
						cleanliness: Tamagotchi.TamagotchiState.cleanliness
						energy:      Tamagotchi.TamagotchiState.energy
				}


				Item {
						Layout.fillWidth: true
						Layout.preferredHeight: 350   

						Pet {
								anchors.centerIn: parent
						}

						RowLayout {
								anchors.left: parent.left
								anchors.right: parent.right

								Item { Layout.fillWidth: true }  
								Bed {}
								Item { Layout.fillWidth: true }  
								Food {}
								Item { Layout.fillWidth: true }  
								Soap {}
								Item { Layout.fillWidth: true }  
						}
				}

				Ball {
						Layout.alignment: Qt.AlignHCenter
				}

        // DebugButtons {
        //     Layout.alignment: Qt.AlignHCenter
        // }
    }
}
