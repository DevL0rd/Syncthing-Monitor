import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../lib"
import "../lib/Highlight.js" as Highlight

Rectangle {
    id: row

    property var device: ({})
    property string query
    readonly property string deviceId: device.deviceID || ""
    readonly property var connection: root.deviceConnections[deviceId] || ({})
    readonly property var completion: root.deviceCompletion[deviceId] || ({})
    readonly property var stats: root.deviceStats[deviceId] || ({})
    readonly property var rates: root.deviceRates[deviceId] || ({ inRate: 0, outRate: 0 })
    readonly property string deviceState: root.deviceState(device)
    readonly property bool expanded: root.openDevice === deviceId
    readonly property bool connected: connection.connected === true
    readonly property var sharedFolders: root.foldersSharedWith(deviceId)
    readonly property real percent: completion.completion === undefined ? -1 : Number(completion.completion)

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 4
    radius: Kirigami.Units.cornerRadius * 2
    color: deviceState === "stale" ? Qt.alpha(Kirigami.Theme.neutralTextColor, 0.1)
         : Qt.alpha(Kirigami.Theme.textColor, expanded ? 0.075 : mouse.containsMouse ? 0.06 : 0.04)
    border.width: 1
    border.color: expanded ? Qt.alpha(Kirigami.Theme.highlightColor, 0.45) : Qt.alpha(Kirigami.Theme.textColor, 0.07)
    clip: true

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openDevice = row.expanded ? "" : row.deviceId
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 1.5

            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Kirigami.Icon {
                    anchors.fill: parent
                    source: "video-display"
                    opacity: row.connected ? 0.95 : 0.7
                }
                StateDot {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    diameter: Math.round(parent.width * 0.45)
                    kind: row.deviceState === "offline" ? "unknown" : row.deviceState
                    border.width: 1.5
                    border.color: Kirigami.Theme.backgroundColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    text: row.query !== "" ? Highlight.mark(row.device.name || row.deviceId.slice(0, 7), row.query, Kirigami.Theme.highlightColor) : row.device.name || row.deviceId.slice(0, 7)
                    textFormat: row.query !== "" ? Text.StyledText : Text.PlainText
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: root.deviceStatusText(row.device)
                    font: Kirigami.Theme.smallFont
                    color: row.deviceState === "stale" || row.deviceState === "busy" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    opacity: row.deviceState === "stale" || row.deviceState === "busy" ? 1 : 0.65
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                visible: row.connected
                spacing: 0
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignRight
                    text: "↓ " + root.formatRate(row.rates.inRate)
                    color: row.rates.inRate > 0 ? root.downColor : Kirigami.Theme.textColor
                    opacity: row.rates.inRate > 0 ? 1 : 0.5
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignRight
                    text: "↑ " + root.formatRate(row.rates.outRate)
                    color: row.rates.outRate > 0 ? root.upColor : Kirigami.Theme.textColor
                    opacity: row.rates.outRate > 0 ? 1 : 0.5
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                }
            }

            Kirigami.Icon {
                source: row.expanded ? "arrow-up" : "arrow-down"
                opacity: 0.45
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
        }

        PopBar {
            visible: row.connected && row.percent >= 0 && (row.percent < 100 || row.expanded)
            Layout.fillWidth: true
            label: Number(row.completion.needBytes || 0) > 0 ? i18n("%1 left", root.formatBytes(row.completion.needBytes)) : i18n("In sync")
            valueText: Math.floor(Math.max(0, row.percent)) + "%"
            value: Math.max(0, row.percent)
            color: row.percent >= 100 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
            thickness: 4
        }

        Loader {
            Layout.fillWidth: true
            active: row.expanded
            visible: active
            sourceComponent: Component {
                ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    DetailList {
                        query: row.query
                        model: [
                            { label: i18n("Address"), value: row.connection.address ? i18n("%1 · %2", row.connection.address, row.connection.type || "") : "" },
                            { label: i18n("Version"), value: row.connection.clientVersion || "" },
                            { label: i18n("Encryption"), value: row.connection.crypto || "" },
                            { label: i18n("Transferred"), value: i18n("%1 in · %2 out", root.formatBytes(row.connection.inBytesTotal), root.formatBytes(row.connection.outBytesTotal)) },
                            { label: i18n("Connected since"), value: row.connected && root.validTimestamp(row.connection.startedAt) ? root.formatWhen(row.connection.startedAt) : "" },
                            { label: i18n("In sync"), value: row.percent >= 0 ? i18n("%1%", Math.floor(row.percent)) : "" },
                            { label: i18n("Remaining"), value: Number(row.completion.needItems || 0) + Number(row.completion.needDeletes || 0) > 0
                                ? i18n("%1 · %2 items", root.formatBytes(row.completion.needBytes), root.formatNumber(Number(row.completion.needItems || 0) + Number(row.completion.needDeletes || 0))) : "" },
                            { label: i18n("Last seen"), value: root.validTimestamp(row.stats.lastSeen) ? root.formatWhen(row.stats.lastSeen) : i18n("never") },
                            { label: i18n("Last connection"), value: Number(row.stats.lastConnectionDurationS || 0) > 0 ? root.formatDuration(row.stats.lastConnectionDurationS) : "" },
                            { label: i18n("Shared folders"), value: row.sharedFolders.length > 0 ? row.sharedFolders.join(", ") : i18n("none"), wrap: true },
                            { label: i18n("Addresses"), value: (row.device.addresses || []).join(", "), wrap: true },
                            { label: i18n("Device ID"), value: row.deviceId, wrap: true }
                        ]
                    }
                    PopActions {
                        model: [
                            { icon: row.device.paused ? "media-playback-start" : "media-playback-pause", text: row.device.paused ? i18n("Resume") : i18n("Pause"),
                              run: () => root.setDevicePaused(row.deviceId, !row.device.paused) },
                            { icon: "edit-copy", text: i18n("Copy device ID"), run: () => root.copy(row.deviceId) },
                            { icon: "internet-web-browser", text: i18n("Edit in web UI"), run: () => root.openWebInterface() }
                        ]
                    }
                }
            }
        }
    }
}
