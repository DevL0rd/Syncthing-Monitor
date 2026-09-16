import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import "../lib"
import "../lib/Highlight.js" as Highlight

Item {
    id: results

    property string query
    readonly property string needle: query.toLowerCase()

    function has(text) {
        return Highlight.matches(text, needle)
    }

    readonly property var folders: root.folders.filter(folder =>
        has(folder.label) || has(folder.id) || has(folder.path)
        || (root.folderErrors[folder.id] || []).some(error => has(error.path)))
    readonly property var devices: root.remoteDevices.filter(device => {
        const connection = root.deviceConnections[device.deviceID] || {}
        return has(device.name) || has(device.deviceID) || has(connection.address) || (device.addresses || []).some(address => has(address))
    })
    readonly property var attention: root.attentionItems.filter(item => has(item.title) || has(item.detail))
    readonly property var changes: root.activity.filter(entry => entry.kind !== "device" && (has(entry.path) || has(entry.label))).slice(0, 30)
    readonly property var actions: [
        { keywords: ["rescan", "scan", "refresh"], text: i18n("Rescan every folder"), icon: "view-refresh", run: () => root.middleClick(), visible: root.reachable },
        { keywords: ["pause", "pause all", "stop"], text: i18n("Pause all devices"), icon: "media-playback-pause", confirm: true, run: () => root.setGlobalPaused(true), visible: root.reachable && root.remoteDevices.length > 0 && !root.allDevicesPaused },
        { keywords: ["resume", "resume all", "start", "unpause"], text: i18n("Resume all devices"), icon: "media-playback-start", run: () => root.setGlobalPaused(false), visible: root.reachable && root.allDevicesPaused },
        { keywords: ["web", "web ui", "browser", "open syncthing", "gui", "settings"], text: i18n("Open the Syncthing web interface"), icon: "internet-web-browser", run: () => root.openWebInterface(), visible: root.baseUrl !== "" },
        { keywords: ["device id", "my id", "copy id", "share"], text: i18n("Copy this device's ID"), icon: "edit-copy", run: () => root.copy(root.myId), visible: root.myId !== "" },
        { keywords: ["reconnect", "retry", "connection"], text: i18n("Reconnect to Syncthing"), icon: "network-connect", run: () => root.reconnect(), visible: true },
        { keywords: ["configure", "settings", "options", "api key", "notifications"], text: i18n("Configure widget…"), icon: "configure", run: () => Plasmoid.internalAction("configure").trigger(), visible: true }
    ].filter(action => action.visible && action.keywords.some(word => word.indexOf(needle) >= 0 || (needle.length > 3 && needle.indexOf(word) >= 0)))

    readonly property int count: folders.length + devices.length + attention.length + changes.length + actions.length

    function activateFirst() {
        if (actions.length > 0 && !actions[0].confirm) {
            actions[0].run()
        } else if (folders.length > 0) {
            root.openFolder = folders[0].id
            root.tabKey = "folders"
        } else if (devices.length > 0) {
            root.openDevice = devices[0].deviceID
            root.tabKey = "devices"
        } else if (changes.length > 0) {
            root.openActivityLocation(changes[0])
        }
    }

    component SectionHeader: PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        opacity: 0.6
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: results.count === 0
        iconName: "edit-find"
        text: i18n("Nothing matches “%1”", results.query)
        explanation: i18n("Search by folder name, path or ID, device name, ID or address, a changed file, or an action like rescan or pause")
    }

    PopScroll {
        anchors.fill: parent
        visible: results.count > 0
        Component.onCompleted: column.spacing = Kirigami.Units.smallSpacing * 1.5

        SectionHeader {
            visible: results.actions.length > 0
            text: i18n("Actions")
        }
        Repeater {
            model: results.actions
            Loader {
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: modelData.confirm ? confirmAction : plainAction
                Component {
                    id: confirmAction
                    RowLayout {
                        PopConfirm {
                            label: modelData.text
                            iconName: modelData.icon
                            onConfirmed: modelData.run()
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
                Component {
                    id: plainAction
                    RowLayout {
                        PlasmaComponents.Button {
                            text: modelData.text
                            icon.name: modelData.icon
                            onClicked: modelData.run()
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }

        SectionHeader {
            visible: results.attention.length > 0
            text: i18n("Needs attention")
        }
        Repeater {
            model: results.attention
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5
                Kirigami.Icon {
                    source: modelData.icon
                    color: Kirigami.Theme.negativeTextColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents.Label {
                        text: Highlight.mark(modelData.title, results.query, Kirigami.Theme.highlightColor)
                        textFormat: Text.StyledText
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: Highlight.mark(modelData.detail, results.query, Kirigami.Theme.highlightColor)
                        textFormat: Text.StyledText
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }

        SectionHeader {
            visible: results.folders.length > 0
            text: i18np("%1 folder", "%1 folders", results.folders.length)
        }
        Repeater {
            model: results.folders
            FolderRow {
                required property var modelData
                folder: modelData
                query: results.query
            }
        }

        SectionHeader {
            visible: results.devices.length > 0
            text: i18np("%1 device", "%1 devices", results.devices.length)
        }
        Repeater {
            model: results.devices
            DeviceRow {
                required property var modelData
                device: modelData
                query: results.query
            }
        }

        SectionHeader {
            visible: results.changes.length > 0
            text: i18n("Recent changes")
        }
        Repeater {
            model: results.changes
            ActivityRow {
                required property var modelData
                entry: modelData
                query: results.query
            }
        }
    }
}
