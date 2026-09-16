import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "../lib"

PopScroll {
    id: tab

    property string filter: "all"
    readonly property var shown: root.activity.filter(entry => tab.filter === "all" || entry.kind === tab.filter).slice(0, 120)

    Component.onCompleted: column.spacing = Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        FilterPills {
            current: tab.filter
            onPicked: key => tab.filter = key
            model: [
                { key: "all", label: i18n("All"), count: root.activity.length },
                { key: "remote", label: i18n("From devices"), count: root.activity.filter(entry => entry.kind === "remote").length },
                { key: "local", label: i18n("Local"), count: root.activity.filter(entry => entry.kind === "local").length },
                { key: "device", label: i18n("Connections"), count: root.activity.filter(entry => entry.kind === "device").length }
            ]
        }
    }

    Repeater {
        model: tab.shown.length
        ActivityRow {
            required property int index
            entry: tab.shown[index] || ({})
        }
    }

    PlasmaExtras.PlaceholderMessage {
        visible: tab.shown.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit * 2
        iconName: "document-edit"
        text: i18n("No activity yet")
        explanation: i18n("File changes and device connections appear here as they happen.")
    }
}
