import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import "../lib"

PopScroll {
    id: overview

    PopCard {
        title: i18n("Sync status")
        icon: "folder-sync"
        trailing: root.overallState === "ok" ? i18n("Up to date")
                : root.overallState === "syncing" ? i18n("Syncing")
                : root.overallState === "busy" ? i18n("Pending")
                : root.overallState === "error" ? i18np("%1 issue", "%1 issues", root.attentionCount)
                : root.overallState === "paused" ? i18n("Paused")
                : ""
        trailingColor: root.stateColor

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing * 2

            PopRing {
                value: root.overallPercent
                text: Math.floor(root.overallPercent) + ""
                label: i18n("Synced")
                color: root.stateColor
                diameter: Kirigami.Units.gridUnit * 5
                onClicked: root.tabKey = "folders"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing * 2
                    PopStat {
                        label: i18n("↓ Download")
                        value: root.formatRate(root.inRate).split(" ")[0]
                        unit: root.formatRate(root.inRate).split(" ").slice(1).join(" ")
                        color: root.downColor
                        scale: 1.6
                    }
                    PopStat {
                        label: i18n("↑ Upload")
                        value: root.formatRate(root.outRate).split(" ")[0]
                        unit: root.formatRate(root.outRate).split(" ").slice(1).join(" ")
                        color: root.upColor
                        scale: 1.6
                    }
                    Item { Layout.fillWidth: true }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.totalNeedBytes > 0
                        ? i18n("%1 left in %2", root.formatBytes(root.totalNeedBytes), i18np("%1 item", "%1 items", root.totalNeedItems))
                        : root.totalNeedItems > 0 ? i18np("%1 item left", "%1 items left", root.totalNeedItems)
                        : root.validTimestamp(Plasmoid.configuration.lastSuccessfulSync)
                            ? i18n("Last completed sync %1", root.formatWhen(Plasmoid.configuration.lastSuccessfulSync))
                            : i18n("Nothing waiting to sync")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    wrapMode: Text.Wrap
                }
            }
        }

        Sparkline {
            visible: Plasmoid.configuration.showRateGraph
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
            values: root.series("in")
            values2: root.series("out")
            lineColor: root.downColor
            lineColor2: root.upColor
            gradient: false
            rangeFloor: 1024 * 64
            peakMarker: values.some(v => v > 0) || values2.some(v => v > 0)
            tipText: v => root.formatRate(v)
        }
    }

    PopCard {
        visible: root.attentionCount > 0
        title: i18n("Needs attention")
        icon: "dialog-warning"
        trailing: root.attentionCount + ""
        trailingColor: Kirigami.Theme.negativeTextColor
        border.color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.35)

        Repeater {
            model: Math.min(8, root.attentionCount)

            RowLayout {
                required property int index
                readonly property var modelData: root.attentionItems[index] || ({})
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5

                Kirigami.Icon {
                    source: modelData.icon
                    color: modelData.kind === "device" || modelData.kind === "folderOffer" ? Kirigami.Theme.highlightColor : Kirigami.Theme.negativeTextColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    Layout.alignment: Qt.AlignTop
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents.Label {
                        text: modelData.title
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: modelData.detail
                        font: Kirigami.Theme.smallFont
                        opacity: 0.75
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                PlasmaComponents.ToolButton {
                    Layout.alignment: Qt.AlignVCenter
                    icon.name: modelData.kind === "folder" ? "go-next" : "internet-web-browser"
                    text: modelData.kind === "folder" ? i18n("Show") : i18n("Review")
                    display: PlasmaComponents.AbstractButton.TextBesideIcon
                    onClicked: {
                        if (modelData.kind === "folder") {
                            root.openFolder = modelData.id
                            root.tabKey = "folders"
                        } else {
                            root.openWebInterface()
                        }
                    }
                }
            }
        }
        PlasmaComponents.Label {
            visible: root.attentionCount > 8
            text: i18np("%1 more item needs attention", "%1 more items need attention", root.attentionCount - 8)
            font: Kirigami.Theme.smallFont
            opacity: 0.65
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.largeSpacing

        Tile {
            label: i18n("Folders")
            value: root.upToDateFolders + ""
            unit: "/ " + root.folders.length
            valueColor: root.errorFolders > 0 ? Kirigami.Theme.negativeTextColor : root.upToDateFolders === root.folders.length ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
            caption: root.busyFolders > 0 ? i18np("%1 syncing", "%1 syncing", root.busyFolders)
                   : root.pausedFolders > 0 ? i18np("%1 paused", "%1 paused", root.pausedFolders)
                   : i18n("up to date")
            icon: "folder"
            onClicked: root.tabKey = "folders"
        }
        Tile {
            label: i18n("Devices")
            value: root.connectedDevices + ""
            unit: "/ " + root.remoteDevices.length
            valueColor: root.overdueDevices > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            caption: root.overdueDevices > 0 ? i18np("%1 overdue", "%1 overdue", root.overdueDevices)
                   : root.activeRemoteSyncDevices > 0 ? i18np("%1 receiving", "%1 receiving", root.activeRemoteSyncDevices)
                   : i18n("online")
            icon: "video-display"
            onClicked: root.tabKey = "devices"
        }
        Tile {
            label: i18n("Local data")
            value: root.formatBytes(root.totalLocalBytes).split(" ")[0]
            unit: root.formatBytes(root.totalLocalBytes).split(" ").slice(1).join(" ")
            caption: i18n("of %1 global", root.formatBytes(root.totalGlobalBytes))
            icon: "drive-harddisk"
            onClicked: root.tabKey = "folders"
        }
        Tile {
            label: i18n("Pending")
            value: root.formatNumber(root.totalNeedItems)
            unit: ""
            valueColor: root.totalNeedItems > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            caption: root.totalNeedBytes > 0 ? root.formatBytes(root.totalNeedBytes) : i18n("items to sync")
            icon: "view-refresh"
            onClicked: root.tabKey = "folders"
        }
        Tile {
            label: i18n("Failed")
            value: root.formatNumber(root.totalFailedItems)
            unit: ""
            valueColor: root.totalFailedItems > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            caption: i18n("items")
            icon: "dialog-error"
            onClicked: root.tabKey = "folders"
        }
        Tile {
            label: i18n("Changes")
            value: root.activity.filter(entry => entry.kind !== "device").length + ""
            unit: ""
            caption: root.activity.length > 0 ? root.formatWhen(root.activity[0].time) : i18n("none yet")
            icon: "document-edit"
            onClicked: root.tabKey = "activity"
        }
    }

    PopCard {
        visible: root.activity.length > 0
        title: i18n("Recent changes")
        icon: "document-edit"

        Repeater {
            model: Math.min(4, root.activity.length)
            ActivityRow {
                required property int index
                entry: root.activity[index] || ({})
            }
        }
        PlasmaComponents.Button {
            Layout.alignment: Qt.AlignRight
            text: i18n("All activity")
            icon.name: "go-next"
            flat: true
            onClicked: root.tabKey = "activity"
        }
    }

    PopCard {
        visible: root.myId !== ""
        title: i18n("This device")
        icon: "computer-laptop"
        trailing: root.deviceName(root.myId)

        DetailList {
            model: [
                { label: i18n("Device ID"), value: root.myId, wrap: true },
                { label: i18n("Version"), value: root.versionText },
                { label: i18n("Uptime"), value: root.formatUptime(root.uptimeSeconds) },
                { label: i18n("API"), value: root.baseUrl }
            ]
        }
        PopActions {
            model: [
                { icon: "edit-copy", text: i18n("Copy device ID"), run: () => root.copy(root.myId) },
                { icon: "internet-web-browser", text: i18n("Web interface"), run: () => root.openWebInterface() },
                { icon: "view-refresh", text: i18n("Rescan all"), run: () => root.middleClick() }
            ]
        }
    }
}
