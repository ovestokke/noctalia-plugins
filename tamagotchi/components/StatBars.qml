import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
    id: root
    spacing: 8
		width: parent.width


    property int hunger:      100
    property int happiness:   100
    property int cleanliness: 100
    property int energy:      100

    component Gauge: Item {
    id: root

    property int value: 75          
    property string icon: "🍗"

    width: 80
    height: 80

    readonly property real angle: (value / 100) * 360

    // Fondo
    Canvas {
        id: bg
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var r = width / 2
            ctx.beginPath()
            ctx.arc(r, r, r - 6, 0, 2 * Math.PI)
            ctx.strokeStyle = "rgba(255,255,255,0.1)"
            ctx.lineWidth = 8
            ctx.stroke()
        }
    }

    // Progreso
Canvas {
    id: fg
    anchors.fill: parent

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var r = width / 2
        var start = -Math.PI / 2
        var end = start + (root.angle * Math.PI / 180)

        ctx.beginPath()
        ctx.arc(r, r, r - 6, start, end)

        if (root.value < 25)
            ctx.strokeStyle = "#E24B4A"
        else if (root.value < 50)
            ctx.strokeStyle = "#EF9F27"
        else
            ctx.strokeStyle = "#1D9E75"

        ctx.lineWidth = 8
        ctx.lineCap = "round"
        ctx.stroke()
    }

    Connections {
        target: root
        function onAngleChanged() { fg.requestPaint() }
        function onValueChanged() { fg.requestPaint() }
    }
}

    // Icono central
    Text {
        anchors.centerIn: parent
        text: root.icon
        font.pixelSize: 24
    }

    // Texto %
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 4
        text: root.value + "%"
        font.pixelSize: 10
        color: "white"
    }
}
Item { Layout.fillWidth: true }
		Gauge { value: hunger;      icon: "🍗" }
		Item { Layout.fillWidth: true }
    Gauge { value: happiness;   icon: "😃" }
		Item { Layout.fillWidth: true }
    Gauge { value: cleanliness; icon: "🧼" }
		Item { Layout.fillWidth: true }
    Gauge { value: energy;      icon: "🛏️" }
		Item { Layout.fillWidth: true }
}
