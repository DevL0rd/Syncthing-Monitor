import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../lib/Highlight.js" as Highlight

ColumnLayout {
    id: list

    property var model: []
    property string query

    Layout.fillWidth: true
    spacing: 3

    Repeater {
        model: list.model.filter(entry => entry.value !== undefined && entry.value !== "")

        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Label {
                text: modelData.label
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                Layout.alignment: Qt.AlignTop
            }
            PlasmaComponents.Label {
                text: Highlight.mark(modelData.value, list.query, Kirigami.Theme.highlightColor)
                textFormat: Text.StyledText
                color: modelData.color !== undefined ? modelData.color : Kirigami.Theme.textColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.features: { "tnum": 1 }
                wrapMode: modelData.wrap ? Text.WrapAnywhere : Text.NoWrap
                elide: modelData.wrap ? Text.ElideNone : Text.ElideMiddle
                Layout.fillWidth: true
            }
        }
    }
}
