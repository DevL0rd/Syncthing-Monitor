import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../lib/Highlight.js" as Highlight

MouseArea {
    id: row

    property var entry: ({})
    property string query
    readonly property bool isDevice: entry.kind === "device"
    readonly property string fileName: String(entry.path || "").split("/").pop()
    readonly property string directory: {
        const path = String(entry.path || "")
        const cut = path.lastIndexOf("/")
        return cut > 0 ? path.slice(0, cut) : ""
    }
    readonly property color actionColor: entry.action === "deleted" || entry.action === "disconnected" ? Kirigami.Theme.negativeTextColor
                                       : entry.action === "added" || entry.action === "connected" ? Kirigami.Theme.positiveTextColor
                                       : Kirigami.Theme.neutralTextColor

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Kirigami.Units.smallSpacing * 2.5
    hoverEnabled: true
    cursorShape: isDevice ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: if (!isDevice) root.openActivityLocation(entry)

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius * 1.5
        color: Qt.alpha(Kirigami.Theme.textColor, row.containsMouse ? 0.07 : 0.035)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing * 1.5

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium + 4
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: Qt.alpha(row.actionColor, 0.16)
            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.small
                height: width
                source: row.isDevice ? (row.entry.action === "connected" ? "network-connect" : "network-disconnect")
                      : row.entry.itemType === "dir" ? "folder"
                      : row.entry.action === "deleted" ? "edit-delete"
                      : row.entry.action === "added" ? "list-add"
                      : "document-edit"
                color: row.actionColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            PlasmaComponents.Label {
                text: row.isDevice
                    ? i18n("%1 %2", root.activityDeviceText(row.entry), row.entry.action === "connected" ? i18n("connected") : i18n("disconnected"))
                    : Highlight.mark(row.fileName, row.query, Kirigami.Theme.highlightColor)
                textFormat: Text.StyledText
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                text: {
                    const parts = []
                    if (row.isDevice) {
                        if (row.entry.path) parts.push(row.entry.path)
                    } else {
                        parts.push(root.activityActionText(row.entry))
                        parts.push(row.directory !== "" ? row.entry.label + "/" + row.directory : row.entry.label)
                        const by = root.activityDeviceText(row.entry)
                        if (by !== "" && row.entry.kind === "remote") parts.push(i18n("by %1", by))
                    }
                    return Highlight.mark(parts.join("  ·  "), row.query, Kirigami.Theme.highlightColor)
                }
                textFormat: Text.StyledText
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
        }

        ColumnLayout {
            spacing: 0
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                text: root.formatWhen(row.entry.time)
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
            Rectangle {
                visible: !row.isDevice
                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: kindLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                Layout.preferredHeight: kindLabel.implicitHeight + 2
                radius: height / 2
                color: Qt.alpha(row.entry.kind === "remote" ? root.downColor : root.upColor, 0.18)
                PlasmaComponents.Label {
                    id: kindLabel
                    anchors.centerIn: parent
                    text: row.entry.kind === "remote" ? i18n("Remote") : i18n("Local")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                }
            }
        }
    }

    QQC2.ToolTip.visible: containsMouse && !isDevice
    QQC2.ToolTip.delay: 600
    QQC2.ToolTip.text: (entry.label || "") + "/" + (entry.path || "")
}
