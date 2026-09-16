import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Flow {
    id: pills

    property var model: []
    property string current
    signal picked(string key)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: pills.model.length

        MouseArea {
            id: pill
            required property int index
            readonly property var modelData: pills.model[index] || ({})
            readonly property bool active: modelData.key === pills.current
            visible: modelData.visible === undefined || modelData.visible
            width: pillRow.implicitWidth + Kirigami.Units.smallSpacing * 4
            height: pillRow.implicitHeight + Kirigami.Units.smallSpacing * 1.5
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pills.picked(modelData.key)

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: pill.active ? Qt.alpha(Kirigami.Theme.highlightColor, 0.24) : Qt.alpha(Kirigami.Theme.textColor, pill.containsMouse ? 0.09 : 0.05)
                border.width: 1
                border.color: pill.active ? Qt.alpha(Kirigami.Theme.highlightColor, 0.5) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: pill.modelData.label
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.weight: pill.active ? Font.DemiBold : Font.Normal
                }
                PlasmaComponents.Label {
                    visible: pill.modelData.count !== undefined
                    text: pill.modelData.count === undefined ? "" : pill.modelData.count + ""
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                    color: pill.modelData.color !== undefined && pill.modelData.count > 0 ? pill.modelData.color : Kirigami.Theme.textColor
                    opacity: pill.modelData.count > 0 ? 0.9 : 0.45
                }
            }
        }
    }
}
