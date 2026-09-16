import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "../lib"

PopScroll {
    id: tab

    property string filter: "all"
    readonly property var shown: root.folders.filter(folder => {
        const state = root.folderState(folder.id)
        if (tab.filter === "syncing") return state === "busy" || state === "local"
        if (tab.filter === "errors") return state === "error" || (root.folderErrors[folder.id] || []).length > 0
        if (tab.filter === "paused") return state === "paused"
        return true
    })

    Component.onCompleted: column.spacing = Kirigami.Units.smallSpacing * 1.5

    RowLayout {
        Layout.fillWidth: true
        FilterPills {
            current: tab.filter
            onPicked: key => tab.filter = key
            model: [
                { key: "all", label: i18n("All"), count: root.folders.length },
                { key: "syncing", label: i18n("Syncing"), count: root.busyFolders + root.countFolders("local"), color: Kirigami.Theme.neutralTextColor },
                { key: "errors", label: i18n("Errors"), count: root.errorFolders, color: Kirigami.Theme.negativeTextColor },
                { key: "paused", label: i18n("Paused"), count: root.pausedFolders }
            ]
        }
        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            text: i18n("Rescan all")
            enabled: root.reachable
            onClicked: root.middleClick()
        }
    }

    Repeater {
        model: tab.shown.length
        FolderRow {
            required property int index
            folder: tab.shown[index] || ({})
        }
    }

    PlasmaExtras.PlaceholderMessage {
        visible: tab.shown.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit * 2
        iconName: "folder-sync"
        text: root.folders.length === 0 ? i18n("No folders yet") : i18n("No folders match this filter")
        explanation: root.folders.length === 0 ? i18n("Add a folder in the Syncthing web interface.") : ""
    }
}
