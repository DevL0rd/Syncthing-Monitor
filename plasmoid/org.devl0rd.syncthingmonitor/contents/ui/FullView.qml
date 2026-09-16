import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "lib"

Item {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 13
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.preferredHeight: Kirigami.Units.gridUnit * 36

    readonly property var tabDefs: [
        { key: "overview", label: i18n("Overview"), file: "OverviewTab.qml" },
        { key: "folders", label: i18n("Folders"), file: "FoldersTab.qml" },
        { key: "devices", label: i18n("Devices"), file: "DevicesTab.qml" },
        { key: "activity", label: i18n("Activity"), file: "ActivityTab.qml" }
    ]

    Loader {
        id: loader
        anchors.fill: parent
        active: root.popupAlive
        sourceComponent: shellComponent
        onLoaded: if (root.expanded) item.focusSearch()
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded && loader.item)
                loader.item.focusSearch()
        }
    }

    Component {
        id: shellComponent

        PopupShell {
            id: shell

            readonly property int tabIndex: Math.max(0, full.tabDefs.findIndex(tab => tab.key === root.tabKey))

            anchors.fill: parent
            icon: "folder-sync"
            title: root.overallTitle()
            subtitle: root.overallSubtitle()
            statusColor: root.stateColor
            statusText: root.overallTitle()
            searchPlaceholder: i18n("Search folders, devices, files, actions…")
            tabs: full.tabDefs.map(tab => ({
                key: tab.key,
                label: tab.label,
                badge: tab.key === "overview" && root.attentionCount > 0 ? root.attentionCount + ""
                     : tab.key === "folders" && root.folders.length > 0 ? root.folders.length + ""
                     : tab.key === "devices" && root.remoteDevices.length > 0 ? root.connectedDevices + "/" + root.remoteDevices.length
                     : ""
            }))
            currentTab: tabIndex
            matchCount: results.item ? results.item.count : -1
            onTabActivated: index => root.tabKey = full.tabDefs[index].key
            onCloseRequested: root.expanded = false
            onSearchAccepted: if (results.item) results.item.activateFirst()

            Connections {
                target: root
                function onTabKeyChanged() { if (shell.searchText !== "") shell.clearSearch() }
            }

            headerActions: [
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Rescan every folder")
                    enabled: root.reachable
                    onClicked: root.middleClick()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                },
                ConfirmToolButton {
                    iconName: root.allDevicesPaused ? "media-playback-start" : "media-playback-pause"
                    text: root.allDevicesPaused ? i18n("Resume all devices") : i18n("Pause all devices")
                    confirmText: i18n("Click again to pause every device")
                    needsConfirm: !root.allDevicesPaused
                    enabled: root.reachable && root.remoteDevices.length > 0 && !root.globalActionPending
                    onConfirmed: root.setGlobalPaused(!root.allDevicesPaused)
                },
                PlasmaComponents.ToolButton {
                    icon.name: "internet-web-browser"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Open the Syncthing web interface")
                    enabled: root.baseUrl !== ""
                    onClicked: root.openWebInterface()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                },
                PlasmaComponents.ToolButton {
                    icon.name: "configure"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Configure…")
                    onClicked: Plasmoid.internalAction("configure").trigger()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                }
            ]

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Loader {
                        id: tabLoader
                        anchors.fill: parent
                        visible: shell.searchText === "" && root.setupError === "" && root.reachable
                        active: shell.searchText === ""
                        source: Qt.resolvedUrl("tabs/" + full.tabDefs[shell.tabIndex].file)
                        opacity: status === Loader.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                    }

                    Loader {
                        id: results
                        anchors.fill: parent
                        visible: root.setupError === "" && root.reachable
                        active: shell.searchText !== ""
                        source: Qt.resolvedUrl("tabs/SearchResults.qml")
                        onLoaded: item.query = Qt.binding(() => shell.searchText.trim())
                    }

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: root.setupError !== "" || !root.reachable
                        iconName: root.setupError !== "" ? "configure" : "network-disconnect"
                        text: root.setupError !== "" ? i18n("Syncthing was not found") : i18n("Syncthing is not responding")
                        explanation: root.setupError !== "" ? root.setupError
                            : root.lastError !== "" ? root.lastError : i18n("Waiting for the Syncthing API")
                        helpfulAction: QQC2.Action {
                            icon.name: root.setupError !== "" ? "configure" : "view-refresh"
                            text: root.setupError !== "" ? i18n("Configure…") : i18n("Retry")
                            onTriggered: root.setupError !== "" ? Plasmoid.internalAction("configure").trigger() : root.reconnect()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: messageLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                    visible: opacity > 0
                    opacity: root.message !== "" ? 1 : 0
                    radius: height / 2
                    color: Qt.alpha(root.messageError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor, 0.18)
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                    PlasmaComponents.Label {
                        id: messageLabel
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.largeSpacing * 2
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.message
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Label {
                        text: root.versionText !== ""
                            ? i18n("Syncthing %1 · up %2", root.versionText, root.formatUptime(root.uptimeSeconds))
                            : i18n("Not connected")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.55
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        visible: root.myId !== ""
                        text: root.deviceName(root.myId)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.55
                    }
                }
            }
        }
    }
}
