import QtQuick
import ".." as Tamagotchi

Item {
    id: root

    property int frameH: 64
    property int frameW: 64

    property int spriteH: 40
    property int spriteW: 40

    implicitWidth:  frameW
    implicitHeight: frameH

    readonly property var _imageMap: ({
        "idle":     "../assets/sapo_idle.png",
        "sleeping": "../assets/sapo_sleeping.png",

        "sad":      "../assets/sapo_sad.png",
        "dirty":    "../assets/sapo_tired.png",
        "hungry":   "../assets/sapo_tired.png",
        "tired":    "../assets/sapo_tired.png",
        "angry":    "../assets/sapo_angry.png"
    })

		readonly property var _spriteStates: ["idle","sad", "dirty", "hungry", "tired", "angry"]

    Image {
        id: sprite
        anchors.centerIn: parent

        width:  root.frameW
        height: root.frameH

        property string currentState: Tamagotchi.TamagotchiState.petState

        source: root._imageMap[currentState] ?? "../assets/sapo_idle.png"

        fillMode: Image.PreserveAspectFit
        smooth: false

        sourceClipRect: {
            if (Tamagotchi.TamagotchiState.eating && root._spriteStates.includes(currentState)) {
                return Qt.rect(root.spriteW, 0, root.spriteW, root.spriteH)
            }
            return Qt.rect(0, 0, root.spriteW, root.spriteH)
        }
    }
}
