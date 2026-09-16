import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "../lib"

PopScroll {
    id: tab

    property string filter: "all"
    readonly property var shown: root.remoteDevices.filter(device => {
        const state = root.deviceState(device)
        if (tab.filter === "online") return state === "ok" || state === "busy"
        if (tab.filter === "offline") return state === "offline" || state === "stale"
        if (tab.filter === "paused") return state === "paused"
        return true
    }).sort((a, b) => {
        const rank = device => {
            const state = root.deviceState(device)
            return state === "busy" ? 0 : state === "ok" ? 1 : state === "stale" ? 2 : state === "offline" ? 3 : 4
        }
        return rank(a) - rank(b) || (a.name || "").localeCompare(b.name || "")
    })

    Component.onCompleted: column.spacing = Kirigami.Units.smallSpacing * 1.5

    RowLayout {
        Layout.fillWidth: true
        FilterPills {
            current: tab.filter
            onPicked: key => tab.filter = key
            model: [
                { key: "all", label: i18n("All"), count: root.remoteDevices.length },
                { key: "online", label: i18n("Online"), count: root.connectedDevices, color: Kirigami.Theme.positiveTextColor },
                { key: "offline", label: i18n("Offline"), count: root.remoteDevices.filter(device => { const s = root.deviceState(device); return s === "offline" || s === "stale" }).length },
                { key: "paused", label: i18n("Paused"), count: root.countPausedDevices() }
            ]
        }
        PlasmaComponents.ToolButton {
            visible: root.remoteDevices.length > 0 && root.allDevicesPaused
            icon.name: "media-playback-start"
            text: i18n("Resume all")
            enabled: root.reachable && !root.globalActionPending
            onClicked: root.setGlobalPaused(false)
        }
        PopConfirm {
            visible: root.remoteDevices.length > 0 && !root.allDevicesPaused
            flat: true
            label: i18n("Pause all")
            iconName: "media-playback-pause"
            confirmText: i18n("Pause every device?")
            enabled: root.reachable && !root.globalActionPending
            onConfirmed: root.setGlobalPaused(true)
        }
    }

    Repeater {
        model: tab.shown.length
        DeviceRow {
            required property int index
            device: tab.shown[index] || ({})
        }
    }

    PlasmaExtras.PlaceholderMessage {
        visible: tab.shown.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit * 2
        iconName: "video-display"
        text: root.remoteDevices.length === 0 ? i18n("No remote devices") : i18n("No devices match this filter")
        explanation: root.remoteDevices.length === 0 ? i18n("Add a device in the Syncthing web interface.") : ""
    }
}
