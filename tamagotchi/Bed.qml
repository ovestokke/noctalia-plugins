import QtQuick
import qs.Commons
import "." as Tamagotchi

Rectangle {
    id: root

    width: 64
    height: 64
    radius: 10
		color: !pressed ? Color.mPrimary : Color.mSecondary

    property bool pressed: false

    Behavior on color {
        ColorAnimation { duration: 150 }
    }

		Image {
				anchors.fill: parent
				anchors.margins: 6
				z: 10

				Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

				source: "assets/pillow.png"
				fillMode: Image.PreserveAspectFit
				smooth: false
			}

    MouseArea {
        anchors.fill: parent

        onPressed: root.pressed = true
        onReleased: {
            root.pressed = false
            Tamagotchi.TamagotchiState.sleep()
        }
    }
}
