import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../lib/Highlight.js" as Highlight

ColumnLayout {
    id: list

    property var model: []
    property string query
    readonly property var entries: visible ? model.filter(entry => entry.value !== undefined && entry.value !== "") : []

    Layout.fillWidth: true
    spacing: 3

    Repeater {
        model: list.entries.length

        RowLayout {
            required property int index
            readonly property var modelData: list.entries[index] || ({})
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
                text: list.query !== "" ? Highlight.mark(modelData.value, list.query, Kirigami.Theme.highlightColor) : modelData.value
                textFormat: list.query !== "" ? Text.StyledText : Text.PlainText
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
