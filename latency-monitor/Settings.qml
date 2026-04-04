import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null
    property var cfg:      pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    property int    valueIntervalSeconds:  cfg.intervalSeconds  ?? defaults.intervalSeconds  ?? 5
    property int    valueThresholdGood:    cfg.thresholdGood    ?? defaults.thresholdGood    ?? 20
    property int    valueThresholdWarning: cfg.thresholdWarning ?? defaults.thresholdWarning ?? 70
    property bool   valueShowHostName:     cfg.showHostName     ?? defaults.showHostName     ?? true
    property string valueBarHost:          cfg.barHost          ?? defaults.barHost          ?? "worst"
    property string valueColorGood:        cfg.colorGood        ?? defaults.colorGood        ?? "primary"
    property string valueColorWarning:     cfg.colorWarning     ?? defaults.colorWarning     ?? "tertiary"
    property string valueColorCritical:    cfg.colorCritical    ?? defaults.colorCritical    ?? "error"

    ListModel { id: hostModel }

    property bool _hostsLoaded: false

    function _loadHosts() {
        if (_hostsLoaded) return
        hostModel.clear()
        try {
            const raw  = cfg.hosts ?? defaults.hosts ?? "[]"
            const arr  = typeof raw === "string" ? JSON.parse(raw) : raw
            for (const h of arr) hostModel.append({ hname: h.name, haddress: h.address })
        } catch(e) {
            hostModel.append({ hname: "Cloudflare", haddress: "1.1.1.1" })
            hostModel.append({ hname: "Google",     haddress: "8.8.8.8"  })
        }
        _hostsLoaded = true
    }

    function _hostsToJson() {
        const arr = []
        for (let i = 0; i < hostModel.count; i++)
            arr.push({ name: hostModel.get(i).hname, address: hostModel.get(i).haddress })
        return JSON.stringify(arr)
    }

    Component.onCompleted: _loadHosts()

    spacing: Style.marginL

    NHeader {
        label:       pluginApi?.tr("settings.hosts.header")
        description: pluginApi?.tr("settings.hosts.desc")
    }

    Repeater {
        model: hostModel

        delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            required property int    index
            required property string hname
            required property string haddress

            NTextInput {
                Layout.preferredWidth: 120 * Style.uiScaleRatio
                label:           index === 0 ? pluginApi?.tr("settings.hosts.name") : ""
                placeholderText: "Name"
                text:            hname
                onTextChanged:   hostModel.setProperty(index, "hname", text)
            }

            NTextInput {
                Layout.fillWidth: true
                label:           index === 0 ? pluginApi?.tr("settings.hosts.address") : ""
                placeholderText: "IP / hostname"
                text:            haddress
                onTextChanged:   hostModel.setProperty(index, "haddress", text)
            }

            NIconButton {
                Layout.alignment:  Qt.AlignBottom
                Layout.bottomMargin: Style.marginS
                icon:        "trash"
                tooltipText: pluginApi?.tr("settings.hosts.remove")
                enabled:     hostModel.count > 1
                onClicked:   hostModel.remove(index)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        property string _name:    ""
        property string _address: ""

        NTextInput {
            id:              addNameField
            Layout.preferredWidth: 120 * Style.uiScaleRatio
            placeholderText: pluginApi?.tr("settings.hosts.namePlaceholder") ?? "Name"
            onTextChanged:   parent._name = text
        }

        NTextInput {
            id:              addAddrField
            Layout.fillWidth: true
            placeholderText: pluginApi?.tr("settings.hosts.addressPlaceholder") ?? "1.1.1.1"
            onTextChanged:   parent._address = text
        }

        NIconButton {
            Layout.alignment:  Qt.AlignBottom
            Layout.bottomMargin: Style.marginS
            icon:        "plus"
            tooltipText: pluginApi?.tr("settings.hosts.add")
            enabled:     parent._name.trim() !== "" && parent._address.trim() !== ""
            onClicked: {
                hostModel.append({ hname: parent._name.trim(), haddress: parent._address.trim() })
                addNameField.text = ""; addAddrField.text = ""
                parent._name = ""; parent._address = ""
            }
        }
    }

    NComboBox {
        Layout.fillWidth: true
        label:      pluginApi?.tr("settings.barHost.label")
        description: pluginApi?.tr("settings.barHost.desc")
        currentKey: root.valueBarHost
        model: {
            const base = [{ key: "worst", name: pluginApi?.tr("settings.barHost.worst") }]
            for (let i = 0; i < hostModel.count; i++)
                base.push({ key: hostModel.get(i).hname, name: hostModel.get(i).hname })
            return base
        }
        onSelected: key => root.valueBarHost = key
    }

    NDivider { Layout.fillWidth: true }

    NHeader {
        label:       pluginApi?.tr("settings.interval.header")
        description: pluginApi?.tr("settings.interval.desc")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
            text:      pluginApi?.tr("settings.interval.label")
            pointSize: Style.fontSizeS
            color:     Color.mOnSurface
            Layout.fillWidth: true
        }

        NText {
            text:      root.valueIntervalSeconds + " s"
            pointSize: Style.fontSizeS
            color:     Color.mSecondary
            font.family: "monospace"
        }
    }

    NSlider {
        Layout.fillWidth: true
        from:      1
        to:        30
        stepSize:  1
        value:     root.valueIntervalSeconds
        onMoved:   root.valueIntervalSeconds = Math.round(value)
    }

    NDivider { Layout.fillWidth: true }

    NHeader {
        label:       pluginApi?.tr("settings.thresholds.header")
        description: pluginApi?.tr("settings.thresholds.desc")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        NText { text: pluginApi?.tr("settings.thresholds.good"); pointSize: Style.fontSizeS; color: Color.mOnSurface; Layout.fillWidth: true }
        NText { text: root.valueThresholdGood + " ms"; pointSize: Style.fontSizeS; color: Color.resolveColorKey(root.valueColorGood ?? "primary"); font.family: "monospace" }
    }
    NSlider {
        Layout.fillWidth: true
        from:     5
        to:       100
        stepSize: 5
        value:    root.valueThresholdGood
        onMoved:  root.valueThresholdGood = Math.round(value)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        NText { text: pluginApi?.tr("settings.thresholds.warning"); pointSize: Style.fontSizeS; color: Color.mOnSurface; Layout.fillWidth: true }
        NText { text: root.valueThresholdWarning + " ms"; pointSize: Style.fontSizeS; color: Color.resolveColorKey(root.valueColorWarning ?? "tertiary"); font.family: "monospace" }
    }
    NSlider {
        Layout.fillWidth: true
        from:     root.valueThresholdGood + 5   // can't go below good threshold
        to:       500
        stepSize: 5
        value:    root.valueThresholdWarning
        onMoved:  root.valueThresholdWarning = Math.round(value)
    }

    NDivider { Layout.fillWidth: true }

    NHeader {
        label: pluginApi?.tr("settings.display.header")
        Layout.bottomMargin: -Style.marginM
    }

    NToggle {
        Layout.fillWidth: true
        label:       pluginApi?.tr("settings.showHostName.label")
        description: pluginApi?.tr("settings.showHostName.desc")
        checked:     root.valueShowHostName
        onToggled:   checked => root.valueShowHostName = checked
    }

    NColorChoice {
        label:      pluginApi?.tr("settings.colorGood.label")
        currentKey: root.valueColorGood
        onSelected: key => root.valueColorGood = key
    }

    NColorChoice {
        label:      pluginApi?.tr("settings.colorWarning.label")
        currentKey: root.valueColorWarning
        onSelected: key => root.valueColorWarning = key
    }

    NColorChoice {
        label:      pluginApi?.tr("settings.colorCritical.label")
        currentKey: root.valueColorCritical
        onSelected: key => root.valueColorCritical = key
    }

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.hosts            = root._hostsToJson()
        pluginApi.pluginSettings.intervalSeconds  = root.valueIntervalSeconds
        pluginApi.pluginSettings.thresholdGood    = root.valueThresholdGood
        pluginApi.pluginSettings.thresholdWarning = root.valueThresholdWarning
        pluginApi.pluginSettings.showHostName     = root.valueShowHostName
        pluginApi.pluginSettings.barHost          = root.valueBarHost
        pluginApi.pluginSettings.colorGood        = root.valueColorGood
        pluginApi.pluginSettings.colorWarning     = root.valueColorWarning
        pluginApi.pluginSettings.colorCritical    = root.valueColorCritical
        pluginApi.saveSettings()
        Logger.d("LatencyMonitor", "Settings saved")
    }
}
