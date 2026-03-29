import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool keyboardActive: false

    // --- Initial state check ---
    Process {
        id: stateChecker
        command: ["gsettings", "get", "org.gnome.desktop.a11y.applications", "screen-keyboard-enabled"]
        stdout: SplitParser {
            onRead: data => {
                root.keyboardActive = data.trim() === "true"
            }
        }
        Component.onCompleted: running = true
    }

    // --- Live monitor ---
    Process {
        id: stateMonitor
        command: ["dconf", "watch", "/org/gnome/desktop/a11y/applications/screen-keyboard-enabled"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                let trimmed = data.trim()
                if (trimmed === "true" || trimmed === "false") {
                    root.keyboardActive = trimmed === "true"
                }
            }
        }
    }

    // --- Toggle ---
    Process {
        id: toggleProcess
    }

    function toggleKeyboard() {
        toggleProcess.command = ["gsettings", "set", "org.gnome.desktop.a11y.applications", "screen-keyboard-enabled", root.keyboardActive ? "false" : "true"]
        toggleProcess.running = true
    }
}
