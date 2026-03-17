import QtQuick
import Quickshell
import qs.Widgets
import "./Services"

NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    function getTooltip(device) {
        const batteryLabel = pluginApi?.tr("panel.card.battery") || "Battery";
        const stateLabel = pluginApi?.tr("control_center.state-label") || "State";

        const batteryLine = (device !== null && device.reachable && device.paired && device.battery !== -1) ? (batteryLabel + ": " + device.battery + "%\n") : "";

        const stateKey = ValentUtils.getConnectionStateKey(device, Valent.daemonAvailable);
        const stateValue = pluginApi?.tr(stateKey) || "Unknown";
        const stateLine = stateLabel + ": " + stateValue;

        return batteryLine + stateLine;
    }

    icon: ValentUtils.getConnectionStateIcon(Valent.mainDevice, Valent.daemonAvailable)
    tooltipText: getTooltip(Valent.mainDevice)

    onClicked: pluginApi?.togglePanel(screen, this)
}
