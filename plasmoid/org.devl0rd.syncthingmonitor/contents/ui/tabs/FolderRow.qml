import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../lib"
import "../lib/Highlight.js" as Highlight

Rectangle {
    id: row

    property var folder: ({})
    property string query
    readonly property string folderId: folder.id || ""
    readonly property var status: root.folderStatus[folderId] || ({})
    readonly property var stats: root.folderStats[folderId] || ({})
    readonly property var errors: root.folderErrors[folderId] || []
    readonly property string folderState: root.folderState(folderId)
    readonly property bool expanded: root.openFolder === folderId
    readonly property bool syncing: folderState === "busy" && Number(status.needBytes || 0) > 0
    readonly property var queueItems: root.folderNeedItems[folderId] || []
    readonly property var sharedWith: root.devicesSharingFolder(folder)

    function toggle() {
        root.openFolder = expanded ? "" : folderId
        if (root.openFolder === folderId && folderState === "busy")
            root.refreshFolderNeed(folderId)
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 4
    radius: Kirigami.Units.cornerRadius * 2
    color: folderState === "error" ? Qt.alpha(Kirigami.Theme.negativeTextColor, 0.1)
         : Qt.alpha(Kirigami.Theme.textColor, expanded ? 0.075 : mouse.containsMouse ? 0.06 : 0.04)
    border.width: 1
    border.color: expanded ? Qt.alpha(Kirigami.Theme.highlightColor, 0.45) : Qt.alpha(Kirigami.Theme.textColor, 0.07)
    Behavior on color { ColorAnimation { duration: 150 } }
    clip: true

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggle()
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
                    source: row.folder.paused ? "folder-grey" : "folder"
                    opacity: row.folder.paused ? 0.6 : 0.9
                }
                StateDot {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    diameter: Math.round(parent.width * 0.45)
                    kind: row.folderState === "local" ? "busy" : row.folderState
                    border.width: 1.5
                    border.color: Kirigami.Theme.backgroundColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    text: Highlight.mark(row.folder.label || row.folderId, row.query, Kirigami.Theme.highlightColor)
                    textFormat: Text.StyledText
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: root.folderStateText(row.folderId)
                    font: Kirigami.Theme.smallFont
                    color: row.folderState === "error" ? Kirigami.Theme.negativeTextColor
                         : row.folderState === "busy" || row.folderState === "local" ? Kirigami.Theme.neutralTextColor
                         : Kirigami.Theme.textColor
                    opacity: row.folderState === "ok" || row.folderState === "paused" ? 0.65 : 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            ColumnLayout {
                spacing: 0
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignRight
                    text: row.syncing ? Math.floor(root.folderPercent(row.folderId)) + "%" : root.formatBytes(row.status.localBytes)
                    color: row.syncing ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignRight
                    text: i18np("%1 file", "%1 files", Number(row.status.localFiles || 0))
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                    opacity: 0.55
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
            visible: row.syncing
            Layout.fillWidth: true
            label: i18n("%1 of %2", root.formatBytes(Number(row.status.globalBytes || 0) - Number(row.status.needBytes || 0)), root.formatBytes(row.status.globalBytes))
            valueText: i18np("%1 item left", "%1 items left", Number(row.status.needTotalItems || 0))
            value: root.folderPercent(row.folderId)
            color: Kirigami.Theme.neutralTextColor
            thickness: 4
        }

        DetailList {
            visible: row.expanded
            Layout.topMargin: Kirigami.Units.smallSpacing
            query: row.query
            model: [
                { label: i18n("Path"), value: row.folder.path || "" },
                { label: i18n("Folder ID"), value: row.folderId },
                { label: i18n("Mode"), value: root.folderTypeText(row.folder.type) },
                { label: i18n("Content"), value: i18n("%1 in %2 files", root.formatBytes(row.status.localBytes), root.formatNumber(row.status.localFiles)) },
                { label: i18n("Global"), value: i18n("%1 in %2 files", root.formatBytes(row.status.globalBytes), root.formatNumber(row.status.globalFiles)) },
                { label: i18n("Remaining"), value: Number(row.status.needTotalItems || 0) > 0 ? i18n("%1 in %2 items", root.formatBytes(row.status.needBytes), root.formatNumber(row.status.needTotalItems)) : "" },
                { label: i18n("Local changes"), value: Number(row.status.receiveOnlyChangedFiles || 0) > 0 ? root.formatNumber(row.status.receiveOnlyChangedFiles) : "" },
                { label: i18n("Shared with"), value: row.sharedWith.length > 0 ? row.sharedWith.join(", ") : i18n("nobody") },
                { label: i18n("Rescan interval"), value: Number(row.folder.rescanIntervalS || 0) > 0 ? root.formatDuration(row.folder.rescanIntervalS) : "" },
                { label: i18n("Watching"), value: row.folder.fsWatcherEnabled === undefined ? "" : row.folder.fsWatcherEnabled ? i18n("Yes") : i18n("No") },
                { label: i18n("Last scan"), value: root.formatWhen(row.stats.lastScan) },
                { label: i18n("Last change"), value: row.stats.lastFile && row.stats.lastFile.filename
                    ? i18n("%1 · %2", String(row.stats.lastFile.filename).split("/").pop(), root.formatWhen(row.stats.lastFile.at)) : "" }
            ]
        }

        ColumnLayout {
            visible: row.expanded && row.folderState === "busy" && (root.folderNeedLoading[row.folderId] === true || row.queueItems.length > 0)
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: 3

            PlasmaComponents.Label {
                text: i18n("Sync queue")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
                opacity: 0.6
            }
            PlasmaComponents.Label {
                visible: root.folderNeedLoading[row.folderId] === true && row.queueItems.length === 0
                text: i18n("Loading the queue…")
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
            Repeater {
                model: row.queueItems
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        Layout.preferredWidth: stageLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                        Layout.preferredHeight: stageLabel.implicitHeight + 2
                        radius: height / 2
                        color: Qt.alpha(Kirigami.Theme.neutralTextColor, 0.18)
                        PlasmaComponents.Label {
                            id: stageLabel
                            anchors.centerIn: parent
                            text: modelData.stage
                            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.9
                        }
                    }
                    PlasmaComponents.Label {
                        text: modelData.name
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: root.formatBytes(modelData.size)
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.features: { "tnum": 1 }
                        opacity: 0.65
                    }
                }
            }
        }

        ColumnLayout {
            visible: row.errors.length > 0 && (row.expanded || row.query !== "")
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: 3

            PlasmaComponents.Label {
                text: i18np("%1 failed item", "%1 failed items", row.errors.length)
                color: Kirigami.Theme.negativeTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
            }
            Repeater {
                model: row.errors.slice(0, 6)
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents.Label {
                        text: Highlight.mark(modelData.path, row.query, Kirigami.Theme.highlightColor)
                        textFormat: Text.StyledText
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: modelData.error
                        color: Kirigami.Theme.negativeTextColor
                        font: Kirigami.Theme.smallFont
                        wrapMode: Text.Wrap
                        opacity: 0.85
                        Layout.fillWidth: true
                    }
                }
            }
            PlasmaComponents.Label {
                visible: row.errors.length > 6
                text: i18np("%1 more failed item", "%1 more failed items", row.errors.length - 6)
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
        }

        PopActions {
            visible: row.expanded
            Layout.topMargin: Kirigami.Units.smallSpacing
            model: [
                { icon: "folder-open", text: i18n("Open"), run: () => root.openFolderPath(row.folder.path) },
                { icon: "view-refresh", text: i18n("Rescan"), visible: !row.folder.paused, run: () => {
                    root.rescanFolder(row.folderId)
                    root.flashMessage(i18n("Rescanning %1", row.folder.label || row.folderId), false)
                } },
                { icon: row.folder.paused ? "media-playback-start" : "media-playback-pause", text: row.folder.paused ? i18n("Resume") : i18n("Pause"),
                  run: () => root.setFolderPaused(row.folderId, !row.folder.paused) },
                { icon: "edit-copy", text: i18n("Copy path"), run: () => root.copy(root.expandPath(row.folder.path)) },
                { icon: "tag", text: i18n("Copy ID"), run: () => root.copy(row.folderId) }
            ]
        }
    }
}
