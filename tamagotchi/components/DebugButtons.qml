import QtQuick
import QtQuick.Layouts
import qs.Commons
import ".." as Tamagotchi

Row {
    id: root
    spacing: 10

    component ActionBtn: Rectangle {
        id: btn
        property string icon:    "●"
        property string label:   "Acción"
        property var    action
        property bool   enabled: true

        width:  60
        height: 56
        radius: 12
        color: {
            if (!enabled) return Qt.rgba(1,1,1,0.04)
            if (_pressed) return Qt.rgba(1,1,1,0.22)
            if (_hovered) return Qt.rgba(1,1,1,0.15)
            return Qt.rgba(1,1,1,0.09)
        }
        border.color: Qt.rgba(1,1,1, enabled ? 0.12 : 0.05)
        border.width: 1
        opacity: enabled ? 1.0 : 0.4

        property bool _hovered: false
        property bool _pressed: false

        Behavior on color   { ColorAnimation  { duration: 120 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        scale: _pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

        Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           btn.icon
                font.pixelSize: 20
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:           btn.label
                font.pixelSize: 9
                color:          Style.colorOnSurfaceVariant ?? "#aaaaaa"
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered:  btn._hovered = true
            onExited:   { btn._hovered = false; btn._pressed = false }
            onPressed:  if (btn.enabled) btn._pressed = true
            onReleased: {
                btn._pressed = false
                if (btn.enabled && containsMouse && btn.action) {
                    btn.action()
                }
            }
        }
    }

    ActionBtn {
        icon:   "🍗"
        label:  "-10 Comer"
        action: function() { Tamagotchi.TamagotchiState.feed(-10) }
    }

    ActionBtn {
        icon:   "🎮"
        label:  "-10 Jugar"
        action: function() { Tamagotchi.TamagotchiState.happiness += -10 }
    }

    ActionBtn {
        icon:   "🧼"
        label:  "-10 Limpieza"
        action: function() { Tamagotchi.TamagotchiState.clean(-10) }
    }

    ActionBtn {
        icon:   Tamagotchi.TamagotchiState.petState === "sleeping" ? "☀️" : "💤"
        label:  "-10 Dormir"
        action: function() { Tamagotchi.TamagotchiState.energy += -10 }
    }
}
