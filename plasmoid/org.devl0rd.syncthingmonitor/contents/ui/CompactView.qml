import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real thickness: vertical ? width : height
    readonly property real iconSize: Math.round(Math.min(
        Kirigami.Units.iconSizes.medium,
        Math.max(Kirigami.Units.iconSizes.small, thickness * 0.72)))
    readonly property bool connected: root.overallState !== "offline" && root.overallState !== "setup"
    property bool wasExpanded: false

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    onPressed: function(mouse) { wasExpanded = root.expanded }
    onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton)
            root.middleClick()
        else
            root.expanded = !wasExpanded
    }

    Layout.minimumWidth: vertical ? 0 : iconSize + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: vertical ? iconSize + Kirigami.Units.smallSpacing * 2 : 0
    Layout.preferredHeight: Layout.minimumHeight

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, compact.containsMouse || root.expanded ? 0.08 : 0)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Item {
        width: compact.iconSize
        height: width
        anchors.centerIn: parent

        Kirigami.Icon {
            anchors.fill: parent
            source: "folder-sync"
            opacity: compact.connected ? 1 : 0.55
        }

        Rectangle {
            width: Math.max(6, Math.round(parent.width * 0.44))
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: -2
            color: root.stateColor
            border.width: 1.5
            border.color: Kirigami.Theme.backgroundColor
        }
    }
}
