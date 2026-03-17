pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

QtObject {
  id: root

  property var devices: []
  property bool daemonAvailable: false
  property int pendingDeviceCount: 0
  property var pendingDevices: []

  property var mainDevice: null
  property string mainDeviceId: ""

  property string busctlCmd: ""
  readonly property var busctlOptions: ["busctl"]
  property int busctlOptionIndex: 0

  onDevicesChanged: {
    setMainDevice(root.mainDeviceId)
  }

  Component.onCompleted: {
    checkDaemon();
  }

  // Check if busctl is available
  function checkDaemon(): void {
    detectBusctlProc.running = true;
  }

  // Refresh the list of devices
  function refreshDevices(): void {
    getDevicesProc.running = true;
  }

  function setMainDevice(deviceId: string): void {
    root.mainDeviceId = deviceId;
    updateMainDevice(false);
  }

  function updateMainDevice(checkReachable) {
    let newMain;
    if (checkReachable) {
      newMain = devices.find((device) => device.id === root.mainDeviceId && device.reachable);
      if (newMain === undefined)
        newMain = devices.find((device) => device.reachable);
      if (newMain === undefined)
        newMain = devices.length === 0 ? null : devices[0];
    } else {
      newMain = devices.find((device) => device.id === root.mainDeviceId);
      if (newMain === undefined)
        newMain = devices.length === 0 ? null : devices[0];
    }

    if (root.mainDevice !== newMain) {
      root.mainDevice = newMain;
    }
  }

  function escapeObjectPath(id) {
    let result = "";
    for (let i = 0; i < id.length; i++) {
        const c = id.charCodeAt(i);
        if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39)) {
            result += id[i];
        } else {
            result += "_" + c.toString(16).padStart(2, "0");
        }
    }
    return result;
  }
  
  function getDevicePath(deviceId) {
    return "/ca/andyholmes/Valent/Device/" + escapeObjectPath(deviceId);
  }

  // Send a ping to a device
  function pingDevice(deviceId: string): void {
    const proc = pingComponent.createObject(root, { deviceId: deviceId });
    proc.running = true;
  }

  function triggerFindMyPhone(deviceId: string): void {
    const proc = findMyPhoneComponent.createObject(root, { deviceId: deviceId });
    proc.running = true;
  }

    function browseFiles(deviceId: string): void {
    const proc = browseFilesComponent.createObject(root, { deviceId: deviceId });
    proc.running = true;
  }

  // Share a file with a device
  function shareFile(deviceId: string, filePath: string): void {
    var proc = shareComponent.createObject(root, {
      deviceId: deviceId,
      filePath: filePath
    });
    proc.running = true;
  }

  function requestPairing(deviceId: string): void {
    const proc = requestPairingComponent.createObject(root, { deviceId: deviceId });
    proc.running = true;
  }

  function unpairDevice(deviceId: string): void {
    const proc = unpairingComponent.createObject(root, { deviceId: deviceId });
    proc.running = true;
  }

  property Process detectBusctlProc: Process {
    command: ["which", busctlOptions[busctlOptionIndex]]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.busctlCmd !== "") {
          root.daemonCheckProc.running = true
          return
        }

        let location = text.trim()
        if (location !== "") {
          root.busctlCmd = location
          root.daemonCheckProc.running = true
          Logger.i("Valent", "Found busctl command:", location)
        } else if (busctlOptionIndex < busctlOptions.length - 1) {
          busctlOptionIndex++
          detectBusctlProc.running = true
        }
      }
    }
  }

  // Check daemon
  property Process daemonCheckProc: Process {
    command: [busctlCmd, "--user", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.daemonAvailable = text.trim().includes("ca.andyholmes.Valent")
        if (root.daemonAvailable) {
          root.refreshDevices();
        } else {
          root.devices = []
          root.mainDevice = null
        }
      }
    }
  }

  // Get device list
  property Process getDevicesProc: Process {
    command: [busctlCmd, "--user", "--json=short", "call", "ca.andyholmes.Valent", "/ca/andyholmes/Valent", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
            const data = JSON.parse(text);
            const managedObjects = data.data?.[0] || {};
            const deviceIds = [];
            
            for (const path in managedObjects) {
                if (path.includes("/Device/")) {
                    const ifaces = managedObjects[path];
                    const devIface = ifaces["ca.andyholmes.Valent.Device"];
                    if (devIface) {
                        const id = devIface["Id"]?.data;
                        if (id) {
                            deviceIds.push(id);
                        }
                    }
                }
            }

            root.pendingDevices = [];
            root.pendingDeviceCount = deviceIds.length;

            deviceIds.forEach(deviceId => {
              const loader = deviceLoaderComponent.createObject(root, { deviceId: deviceId });
              loader.start();
            });
        } catch (e) {
            console.error(e);
        }
      }
    }
  }

  function extractVariant(val) {
      if (val === null || val === undefined)
          return null;
      if (typeof val !== "object")
          return val;
      if (Array.isArray(val) && val.length === 1)
          return extractVariant(val[0]);
      if (val.value !== undefined)
          return extractVariant(val.value);
      if (val.data !== undefined)
          return extractVariant(val.data);
      return val;
  }

  // Component that loads all info for a single device
  property Component deviceLoaderComponent: Component {
    QtObject {
      id: loader
      property string deviceId: ""
      property var deviceData: ({
        id: deviceId,
        name: "",
        reachable: false,
        paired: false,
        pairRequested: false,
        verificationKey: "",
        charging: false,
        battery: -1,
        cellularNetworkType: "",
        cellularNetworkStrength: -1,
        notificationIds: []
      })

      function start() {
        propsProc.running = true
      }

      property Process propsProc: Process {
        command: [busctlCmd, "--user", "--json=short", "call", "ca.andyholmes.Valent", getDevicePath(loader.deviceId), "org.freedesktop.DBus.Properties", "GetAll", "s", "ca.andyholmes.Valent.Device"]
        stdout: StdioCollector {
          onStreamFinished: {
            try {
                const data = JSON.parse(text);
                const props = data.data?.[0] || {};
                
                const state = extractVariant(props.State) || 0;
                
                loader.deviceData.name = extractVariant(props.Name) || loader.deviceId;
                loader.deviceData.reachable = (state & 1) !== 0; // stateConnected
                loader.deviceData.paired = (state & 2) !== 0; // statePaired
                loader.deviceData.pairRequested = (state & 8) !== 0; // statePairOutgoing
            } catch (e) {
                console.error(e);
            }

            if (loader.deviceData.paired) {
                batteryProc.running = true;
            } else {
                finalize();
            }
          }
        }
      }

      property Process batteryProc: Process {
        command: [busctlCmd, "--user", "--json=short", "call", "ca.andyholmes.Valent", getDevicePath(loader.deviceId), "org.gtk.Actions", "Describe", "s", "battery.state"]
        stdout: StdioCollector {
          onStreamFinished: {
            try {
                const data = JSON.parse(text);
                // Schema: (bgav)
                // "data": [[true, "", [{"type": "a{sv}", "data": {"charging": ...}}]]]
                const result = data.data?.[0];
                if (result) {
                    const stateArray = result[2];
                    if (stateArray && stateArray[0] && stateArray[0].data) {
                        const stateValue = stateArray[0].data;
                        loader.deviceData.battery = stateValue["percentage"]?.data ?? -1;
                        loader.deviceData.charging = stateValue["charging"]?.data ?? false;
                    }
                }
            } catch (e) {
                // Ignore parse errors, battery plugin might be disabled
            }
            connProc.running = true;
          }
        }
      }

      property Process connProc: Process {
        command: [busctlCmd, "--user", "--json=short", "call", "ca.andyholmes.Valent", getDevicePath(loader.deviceId), "org.gtk.Actions", "Describe", "s", "connectivity_report.state"]
        stdout: StdioCollector {
          onStreamFinished: {
            try {
                const data = JSON.parse(text);
                const result = data.data?.[0];
                if (result) {
                    const stateArray = result[2];
                    if (stateArray && stateArray[0] && stateArray[0].data) {
                        const stateValue = stateArray[0].data;
                        const signalStrengths = stateValue["signal-strengths"]?.data;
                        if (signalStrengths) {
                            const keys = Object.keys(signalStrengths);
                            if (keys.length > 0) {
                                const primarySim = signalStrengths[keys[0]]?.data;
                                if (primarySim) {
                                    loader.deviceData.cellularNetworkStrength = primarySim["signal-strength"]?.data ?? -1;
                                    loader.deviceData.cellularNetworkType = primarySim["network-type"]?.data ?? "";
                                }
                            }
                        }
                    }
                }
            } catch (e) {
                // Ignore parse errors, connectivity info might not be available
            }
            finalize();
          }
        }
      }


      function finalize() {
        root.pendingDevices = root.pendingDevices.concat([loader.deviceData]);

        if (root.pendingDevices.length === root.pendingDeviceCount) {
          let newDevices = root.pendingDevices
          newDevices.sort((a, b) => a.name.localeCompare(b.name))

          let prevMainDevice = root.devices.find((device) => device.id === root.mainDeviceId);
          let newMainDevice = newDevices.find((device) => device.id === root.mainDeviceId);

          let deviceNotReachableAnymore =
            prevMainDevice === undefined ||
            (
              (prevMainDevice?.reachable ?? false) &&
              !(newMainDevice?.reachable ?? false)
            ) ||
            (
              (prevMainDevice?.paired ?? false) &&
              !(newMainDevice?.paired ?? false)
            )

          root.devices = newDevices
          root.pendingDevices = []
          updateMainDevice(deviceNotReachableAnymore);
        }

        loader.destroy();
      }
    }
  }

  // Ping component
  property Component pingComponent: Component {
    Process {
      id: proc
      property string deviceId: ""
      command: [busctlCmd, "--user", "call", "ca.andyholmes.Valent", getDevicePath(deviceId), "org.gtk.Actions", "Activate", "sava{sv}", "ping.ping", 0, 0]
      stdout: StdioCollector {
        onStreamFinished: proc.destroy()
      }
    }
  }

  // FindMyPhone component
  property Component findMyPhoneComponent: Component {
    Process {
      id: proc
      property string deviceId: ""
      command: [busctlCmd, "--user", "call", "ca.andyholmes.Valent", getDevicePath(deviceId), "org.gtk.Actions", "Activate", "sava{sv}", "findmyphone.ring", 0, 0]
      stdout: StdioCollector {
        onStreamFinished: proc.destroy()
      }
    }
  }

  // SFTP Browse component
  property Component browseFilesComponent: Component {
    Process {
      id: proc
      property string deviceId: ""
      command: [busctlCmd, "--user", "call", "ca.andyholmes.Valent", getDevicePath(deviceId), "org.gtk.Actions", "Activate", "sava{sv}", "sftp.browse", 0, 0]
      stdout: StdioCollector {
        onStreamFinished: proc.destroy()
      }
    }
  }

  // Request Pairing Component
  property Component requestPairingComponent: Component {
    Process {
      id: proc
      property string deviceId: ""
      command: [busctlCmd, "--user", "call", "ca.andyholmes.Valent", getDevicePath(deviceId), "org.gtk.Actions", "Activate", "sava{sv}", "pair", 0, 0]
      stdout: StdioCollector {
        onStreamFinished: proc.destroy()
      }
    }
  }

  // Unpairing Component
  property Component unpairingComponent: Component {
    Process {
      id: proc
      property string deviceId: ""
      command: [busctlCmd, "--user", "call", "ca.andyholmes.Valent", getDevicePath(deviceId), "org.gtk.Actions", "Activate", "sava{sv}", "unpair", 0, 0]
      stdout: StdioCollector {
        onStreamFinished: {
          Valent.refreshDevices()
          proc.destroy()
        }
      }
    }
  }

  // Share file component
  property Component shareComponent: Component {
    Process {
      id: proc
      property string deviceId: ""
      property string filePath: ""
      command: [busctlCmd, "--user", "call", "ca.andyholmes.Valent", getDevicePath(deviceId), "org.gtk.Actions", "Activate", "sava{sv}", "share.uri", 1, "s", "file://" + filePath, 0]
      stdout: StdioCollector {
        onStreamFinished: {
          proc.destroy()
        }
      }
    }
  }

  // Periodic refresh timer
  property Timer refreshTimer: Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.checkDaemon()
  }
}