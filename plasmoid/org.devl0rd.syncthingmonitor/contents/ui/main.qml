pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.notification as KNotifications
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "lib"
import "lib/History.js" as History
import "lib/PopStyle.js" as Style

PlasmoidItem {
    id: root

    readonly property string homePath: root.urlToPath(StandardPaths.writableLocation(StandardPaths.HomeLocation))
    readonly property var configCandidates: [
        root.urlToPath(StandardPaths.writableLocation(StandardPaths.GenericStateLocation)) + "/syncthing/config.xml",
        root.urlToPath(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)) + "/syncthing/config.xml",
        root.urlToPath(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)) + "/syncthing/config.xml"
    ]

    property string baseUrl: ""
    property string apiKey: ""
    property string setupError: ""
    property string lastError: ""
    property bool reachable: false
    property var folders: []
    property var devices: []
    property var folderStatus: ({})
    property var folderErrors: ({})
    property var folderStats: ({})
    property var folderNeedItems: ({})
    property var folderNeedLoading: ({})
    property var deviceCompletion: ({})
    property var deviceConnections: ({})
    property var deviceStats: ({})
    property var systemErrors: []
    property var pendingDevices: ({})
    property var pendingFolderOffers: ({})
    property string myId: ""
    property string myName: ""
    property string versionText: ""
    property real uptimeSeconds: 0
    property real inRate: 0
    property real outRate: 0
    property real sampledIn: -1
    property real sampledOut: -1
    property real sampledAt: 0
    property int lastEventId: 0
    property int lastDiskEventId: 0
    property var eventRequest: null
    property var diskEventRequest: null
    property real eventRequestStartedAt: 0
    property real diskEventRequestStartedAt: 0
    property int eventGeneration: 0
    property var remoteDownloadActivity: ({})
    property string openFolder: ""
    property string openDevice: ""
    property var pendingFolders: ({})
    property bool pendingConfig: false
    property bool pendingConnections: false
    property bool pendingCompletion: false
    property bool pendingAttention: false
    property bool pendingDeviceStats: false
    property bool pendingFullRefresh: false
    property var pendingNeedFolders: ({})
    property bool globalActionPending: false
    property bool syncTrackingReady: false
    property bool syncWasActive: false
    property bool devicesLoaded: false
    property bool connectionsLoaded: false
    property bool deviceStatsLoaded: false
    property bool offlineBaselineReady: false
    property var offlineStates: ({})
    property var recentFailureNotifications: ({})
    property int clockTick: 0
    property var deviceRates: ({})
    property var lastDeviceTotals: ({})
    property var history: History.make(90)
    property int tick: 0
    property var activity: []
    readonly property int activityLimit: 200

    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    property bool popupAlive: !inPanel
    readonly property bool viewVisible: root.expanded || !root.inPanel
    readonly property bool wantsRates: root.viewVisible || (root.inPanel && Plasmoid.configuration.compactShow === "rates")
    property string tabKey: Plasmoid.configuration.rememberTab ? Plasmoid.configuration.currentTab : Plasmoid.configuration.defaultTab
    onTabKeyChanged: Plasmoid.configuration.currentTab = tabKey

    property string message
    property bool messageError: false

    readonly property int failureNotificationCooldownMs: 5 * 60 * 1000

    readonly property var remoteDevices: root.devices.filter(function(device) { return device.deviceID !== root.myId })
    readonly property int connectedDevices: root.countConnectedDevices()
    readonly property int upToDateFolders: root.countFolders("ok")
    readonly property int errorFolders: root.countFolders("error")
    readonly property int busyFolders: root.countFolders("busy")
    readonly property int activelySyncingFolders: root.countFoldersActivelySyncing()
    readonly property int activeRemoteSyncDevices: root.countActiveRemoteSyncDevices()
    readonly property bool workActive: root.activelySyncingFolders > 0
        || root.activeRemoteSyncDevices > 0
        || root.busyFolders > 0
    readonly property int pausedFolders: root.countFolders("paused")
    readonly property bool allDevicesPaused: root.remoteDevices.length > 0
        && root.countPausedDevices() === root.remoteDevices.length
    readonly property int overdueDevices: root.countOverdueDevices()
    readonly property var attentionItems: root.buildAttentionItems()
    readonly property int attentionCount: root.attentionItems.length
    readonly property real totalGlobalBytes: root.sumStatus("globalBytes")
    readonly property real totalLocalBytes: root.sumStatus("localBytes")
    readonly property real totalNeedBytes: root.sumStatus("needBytes")
    readonly property real totalNeedItems: root.sumStatus("needTotalItems")
    readonly property real totalFailedItems: root.sumStatus("errors")
    readonly property real overallPercent: root.totalGlobalBytes <= 0
        ? 100
        : Math.max(0, Math.min(100, 100 * (root.totalGlobalBytes - root.totalNeedBytes) / root.totalGlobalBytes))

    readonly property string overallState:
          root.setupError !== "" ? "setup"
        : !root.reachable ? "offline"
        : root.attentionCount > 0 ? "error"
        : root.activelySyncingFolders > 0 || root.activeRemoteSyncDevices > 0 ? "syncing"
        : root.busyFolders > 0 ? "busy"
        : root.folders.length === 0 ? "empty"
        : root.pausedFolders === root.folders.length || root.allDevicesPaused ? "paused"
        : "ok"

    readonly property color stateColor: root.colorForState(root.overallState)
    readonly property color downColor: Style.hue("down", Kirigami.Theme)
    readonly property color upColor: Style.hue("up", Kirigami.Theme)

    Plasmoid.icon: "folder-sync"
    Plasmoid.title: i18n("Syncthing Monitor")
    toolTipMainText: root.overallTitle()
    toolTipSubText: root.overallSubtitle()
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Open Syncthing Web Interface")
            icon.name: "internet-web-browser"
            enabled: root.baseUrl !== ""
            onTriggered: root.openWebInterface()
        },
        PlasmaCore.Action {
            text: i18n("Rescan All Folders")
            icon.name: "view-refresh"
            enabled: root.reachable
            onTriggered: root.rescanAll()
        },
        PlasmaCore.Action {
            text: root.allDevicesPaused ? i18n("Resume All Devices") : i18n("Pause All Devices")
            icon.name: root.allDevicesPaused ? "media-playback-start" : "media-playback-pause"
            enabled: root.reachable && root.remoteDevices.length > 0 && !root.globalActionPending
            onTriggered: root.requestGlobalPause(!root.allDevicesPaused)
        }
    ]

    Timer {
        id: releasePopup
        interval: 1500
        onTriggered: root.popupAlive = root.expanded || !root.inPanel
    }

    Timer {
        id: messageTimer
        interval: 4000
        onTriggered: root.message = ""
    }

    function flashMessage(text, isError) {
        root.message = text
        root.messageError = isError === true
        messageTimer.restart()
    }

    TextEdit { id: clipboard; visible: false }

    function copy(text) {
        clipboard.text = text
        clipboard.selectAll()
        clipboard.copy()
        root.flashMessage(i18n("Copied %1", text.length > 48 ? text.slice(0, 45) + "…" : text), false)
    }

    function series(key) {
        var tick = root.tick
        return History.values(root.history, key)
    }

    function foldersSharedWith(deviceId) {
        var names = []
        for (var i = 0; i < root.folders.length; ++i) {
            var shared = root.folders[i].devices || []
            for (var j = 0; j < shared.length; ++j) {
                if (shared[j].deviceID === deviceId) {
                    names.push(root.folders[i].label || root.folders[i].id)
                    break
                }
            }
        }
        return names
    }

    function devicesSharingFolder(folder) {
        var names = []
        var shared = (folder && folder.devices) || []
        for (var i = 0; i < shared.length; ++i) {
            if (shared[i].deviceID === root.myId) continue
            names.push(root.deviceName(shared[i].deviceID))
        }
        return names
    }

    function activityEntry(event) {
        var data = event.data || ({})
        switch (event.type) {
        case "LocalChangeDetected":
        case "RemoteChangeDetected":
            return {
                id: "d" + event.id,
                time: event.time,
                kind: event.type === "LocalChangeDetected" ? "local" : "remote",
                action: data.action || "modified",
                itemType: data.type || "file",
                folder: data.folder || data.folderID || "",
                label: data.label || data.folder || "",
                path: data.path || "",
                device: data.modifiedBy || ""
            }
        case "DeviceConnected":
        case "DeviceDisconnected":
            return {
                id: "e" + event.id,
                time: event.time,
                kind: "device",
                action: event.type === "DeviceConnected" ? "connected" : "disconnected",
                itemType: "device",
                folder: "",
                label: "",
                path: data.addr || data.address || "",
                device: data.id || data.device || ""
            }
        }
        return null
    }

    function recordActivity(events) {
        var added = []
        for (var i = events.length - 1; i >= 0; --i) {
            var entry = root.activityEntry(events[i])
            if (entry) added.push(entry)
        }
        if (added.length === 0) return
        root.activity = added.concat(root.activity).slice(0, root.activityLimit)
    }

    function activityActionText(entry) {
        switch (entry.action) {
        case "added": return i18n("Added")
        case "deleted": return i18n("Deleted")
        case "connected": return i18n("Connected")
        case "disconnected": return i18n("Disconnected")
        default: return i18n("Modified")
        }
    }

    function activityDeviceText(entry) {
        if (!entry.device) return ""
        if (root.myId !== "" && root.myId.indexOf(entry.device) === 0) return i18n("this device")
        for (var i = 0; i < root.devices.length; ++i)
            if (root.devices[i].deviceID.indexOf(entry.device) === 0)
                return root.devices[i].name || entry.device
        return entry.device
    }

    function openActivityLocation(entry) {
        var folder = root.folderById(entry.folder)
        if (!folder) return
        var relative = String(entry.path || "")
        var directory = entry.action === "deleted" || entry.itemType !== "dir"
            ? relative.substring(0, relative.lastIndexOf("/"))
            : relative
        var base = root.expandPath(folder.path).replace(/\/+$/, "")
        Qt.openUrlExternally("file://" + (directory !== "" ? base + "/" + directory : base))
    }

    function middleClick() {
        root.rescanAll()
        root.flashMessage(i18n("Rescanning every folder"), false)
    }

    function urlToPath(value) {
        return String(value).replace(/^file:\/\//, "")
    }

    function colorForState(state) {
        switch (state) {
        case "ok": return Kirigami.Theme.positiveTextColor
        case "busy":
        case "syncing":
        case "stale": return Kirigami.Theme.neutralTextColor
        case "error":
        case "offline":
        case "setup": return Kirigami.Theme.negativeTextColor
        default: return Kirigami.Theme.disabledTextColor
        }
    }

    function folderById(id) {
        for (var i = 0; i < root.folders.length; ++i)
            if (root.folders[i].id === id) return root.folders[i]
        return null
    }

    function folderName(id) {
        var folder = root.folderById(id)
        return folder ? (folder.label || folder.id) : id
    }

    function folderState(id) {
        var folder = root.folderById(id)
        if (folder && folder.paused) return "paused"
        var status = root.folderStatus[id]
        if (!status) return "unknown"
        if (status.error || status.invalid) return "error"
        if (Number(status.errors || 0) > 0) return "error"
        if (status.state === "error") return "error"
        if (status.state && status.state !== "idle") return "busy"
        if (Number(status.needTotalItems || 0) > 0) return "busy"
        if (Number(status.receiveOnlyChangedFiles || 0) > 0) return "local"
        return "ok"
    }

    function folderStateText(id) {
        var status = root.folderStatus[id] || ({})
        switch (root.folderState(id)) {
        case "paused": return i18n("Paused")
        case "unknown": return i18n("Waiting for status…")
        case "error": return status.error
            ? status.error
            : i18np("%1 failed item", "%1 failed items", Number(status.errors || 0))
        case "local": return i18np("%1 local change not sent", "%1 local changes not sent",
            Number(status.receiveOnlyChangedFiles || 0))
        case "busy":
            if (status.state === "scanning") return i18n("Scanning")
            if (status.state === "scan-waiting") return i18n("Waiting to scan")
            if (status.state === "sync-waiting") return i18n("Waiting to sync")
            if (status.state === "sync-preparing") return i18n("Preparing to sync")
            if (status.state === "cleaning" || status.state === "cleaning-waiting") return i18n("Cleaning versions")
            if (Number(status.needBytes || 0) > 0)
                return i18n("Syncing · %1 left", root.formatBytes(status.needBytes))
            if (Number(status.needTotalItems || 0) > 0)
                return i18np("Out of sync · %1 item", "Out of sync · %1 items", Number(status.needTotalItems))
            return i18n("Syncing")
        default: return i18n("Up to date")
        }
    }

    function folderPercent(id) {
        var status = root.folderStatus[id] || ({})
        var global = Number(status.globalBytes || 0)
        if (global <= 0) return 100
        return Math.max(0, Math.min(100, 100 * (global - Number(status.needBytes || 0)) / global))
    }

    function folderTypeText(type) {
        switch (type) {
        case "sendonly": return i18n("Send only")
        case "receiveonly": return i18n("Receive only")
        case "receiveencrypted": return i18n("Receive encrypted")
        default: return i18n("Send and receive")
        }
    }

    function countFolders(state) {
        var total = 0
        for (var i = 0; i < root.folders.length; ++i)
            if (root.folderState(root.folders[i].id) === state) ++total
        return total
    }

    function countFoldersActivelySyncing() {
        var total = 0
        for (var i = 0; i < root.folders.length; ++i) {
            var status = root.folderStatus[root.folders[i].id] || ({})
            if (status.state === "syncing") ++total
        }
        return total
    }

    function countActiveRemoteSyncDevices() {
        var devices = ({})
        for (var key in root.remoteDownloadActivity) {
            var activity = root.remoteDownloadActivity[key]
            if (activity && activity.device) devices[activity.device] = true
        }
        var total = 0
        for (var deviceId in devices) ++total
        return total
    }

    function deviceIsReceiving(id) {
        for (var key in root.remoteDownloadActivity) {
            var activity = root.remoteDownloadActivity[key]
            if (activity && activity.device === id) return true
        }
        return false
    }

    function applyRemoteDownloadProgress(data) {
        var device = String(data.device || "")
        var folder = String(data.folder || "")
        if (device === "" || folder === "") return
        var activityKey = device + "\u001f" + folder
        var next = ({})
        for (var key in root.remoteDownloadActivity) {
            if (key !== activityKey) next[key] = root.remoteDownloadActivity[key]
        }
        var state = data.state || ({})
        for (var path in state) {
            next[activityKey] = { device: device, folder: folder }
            break
        }
        root.remoteDownloadActivity = next
    }

    function clearRemoteDownloadActivity(device, folder) {
        if (!device && !folder) return
        var next = ({})
        for (var key in root.remoteDownloadActivity) {
            var activity = root.remoteDownloadActivity[key]
            if ((device && activity.device === device) || (folder && activity.folder === folder)) continue
            next[key] = activity
        }
        root.remoteDownloadActivity = next
    }

    function restoreRemoteDownloadActivity(events) {
        root.remoteDownloadActivity = ({})
        for (var index = 0; index < events.length; ++index) {
            var event = events[index]
            var data = event.data || ({})
            switch (event.type) {
            case "RemoteDownloadProgress":
                root.applyRemoteDownloadProgress(data)
                break
            case "DeviceDisconnected":
            case "DevicePaused":
                root.clearRemoteDownloadActivity(data.id || data.device, "")
                break
            case "FolderPaused":
                root.clearRemoteDownloadActivity("", data.folder)
                break
            case "Starting":
                root.remoteDownloadActivity = ({})
                break
            }
        }
    }

    function sumStatus(key) {
        var total = 0
        for (var i = 0; i < root.folders.length; ++i) {
            var status = root.folderStatus[root.folders[i].id]
            if (status) total += Number(status[key] || 0)
        }
        return total
    }

    function countConnectedDevices() {
        var total = 0
        for (var i = 0; i < root.remoteDevices.length; ++i) {
            var connection = root.deviceConnections[root.remoteDevices[i].deviceID]
            if (connection && connection.connected) ++total
        }
        return total
    }

    function countPausedDevices() {
        var total = 0
        for (var i = 0; i < root.remoteDevices.length; ++i)
            if (root.remoteDevices[i].paused) ++total
        return total
    }

    function validTimestamp(stamp) {
        if (!stamp) return false
        var moment = new Date(stamp)
        return !isNaN(moment.getTime()) && moment.getFullYear() >= 1971
    }

    function deviceIsOverdue(device) {
        var tick = root.clockTick
        var graceHours = Number(plasmoid.configuration.offlineGraceHours || 0)
        if (!device || device.paused || graceHours <= 0) return false
        var connection = root.deviceConnections[device.deviceID] || ({})
        if (connection.connected) return false
        var stats = root.deviceStats[device.deviceID] || ({})
        if (!root.validTimestamp(stats.lastSeen)) return false
        return Date.now() - new Date(stats.lastSeen).getTime() >= graceHours * 3600000
    }

    function countOverdueDevices() {
        var total = 0
        for (var i = 0; i < root.remoteDevices.length; ++i)
            if (root.deviceIsOverdue(root.remoteDevices[i])) ++total
        return total
    }

    function deviceState(device) {
        if (!device) return "unknown"
        if (device.paused) return "paused"
        var connection = root.deviceConnections[device.deviceID] || ({})
        if (connection.connected)
            return root.deviceIsReceiving(device.deviceID) || root.deviceNeedsSync(device.deviceID) ? "busy" : "ok"
        return root.deviceIsOverdue(device) ? "stale" : "offline"
    }

    function deviceNeedsSync(id) {
        var completion = root.deviceCompletion[id] || ({})
        if (Number(completion.needBytes || 0) > 0) return true
        if (Number(completion.needItems || 0) > 0) return true
        if (Number(completion.needDeletes || 0) > 0) return true
        return completion.completion !== undefined && Number(completion.completion) < 100
    }

    function deviceStatusText(device) {
        if (!device) return i18n("Unknown")
        if (device.paused) return i18n("Paused")
        var connection = root.deviceConnections[device.deviceID] || ({})
        if (connection.connected) {
            if (root.deviceIsReceiving(device.deviceID)) return i18n("Receiving files")
            var completion = root.deviceCompletion[device.deviceID] || ({})
            return root.deviceNeedsSync(device.deviceID)
                ? (Number(completion.needBytes || 0) > 0
                    ? i18n("Syncing · %1 left", root.formatBytes(completion.needBytes))
                    : i18n("Syncing · %1% complete", Math.floor(Number(completion.completion || 0))))
                : i18n("Connected · up to date")
        }
        var stats = root.deviceStats[device.deviceID] || ({})
        return root.validTimestamp(stats.lastSeen)
            ? i18n("Disconnected · last seen %1", root.formatWhen(stats.lastSeen))
            : i18n("Disconnected · never seen")
    }

    function buildAttentionItems() {
        var items = []
        for (var i = 0; i < root.folders.length; ++i) {
            var folder = root.folders[i]
            var errors = root.folderErrors[folder.id] || []
            if (root.folderState(folder.id) === "error" || errors.length > 0) {
                items.push({
                    id: folder.id,
                    kind: "folder",
                    icon: "folder-sync",
                    title: folder.label || folder.id,
                    detail: errors.length > 0
                        ? (errors[0].error || root.folderStateText(folder.id))
                        : root.folderStateText(folder.id)
                })
            }
        }
        for (var errorIndex = root.systemErrors.length - 1; errorIndex >= 0; --errorIndex) {
            var systemError = root.systemErrors[errorIndex] || ({})
            items.push({
                kind: "system",
                icon: "dialog-error",
                title: i18n("Syncthing error"),
                detail: (systemError.message || systemError.error || i18n("Unknown system error"))
                    + (root.validTimestamp(systemError.when || systemError.time)
                        ? i18n(" · %1", root.formatWhen(systemError.when || systemError.time))
                        : "")
            })
        }
        for (var deviceId in root.pendingDevices) {
            var pendingDevice = root.pendingDevices[deviceId] || ({})
            items.push({
                kind: "device",
                icon: "network-connect",
                title: pendingDevice.name || deviceId.slice(0, 7),
                detail: pendingDevice.address
                    ? i18n("New device invitation · %1", pendingDevice.address)
                    : i18n("New device invitation")
            })
        }
        for (var folderId in root.pendingFolderOffers) {
            var offer = root.pendingFolderOffers[folderId] || ({})
            var offeredBy = offer.offeredBy || ({})
            var label = folderId
            var names = []
            for (var offeringDevice in offeredBy) {
                var details = offeredBy[offeringDevice] || ({})
                if (details.label) label = details.label
                names.push(root.deviceName(offeringDevice))
            }
            items.push({
                kind: "folderOffer",
                icon: "folder-add",
                title: label,
                detail: names.length > 0
                    ? i18n("Folder offered by %1", names.join(", "))
                    : i18n("New folder invitation")
            })
        }
        return items
    }

    function deviceName(id) {
        for (var i = 0; i < root.devices.length; ++i)
            if (root.devices[i].deviceID === id)
                return root.devices[i].name || id.slice(0, 7)
        return id.slice(0, 7)
    }

    function overallTitle() {
        switch (root.overallState) {
        case "setup": return i18n("Syncthing was not found")
        case "offline": return i18n("Syncthing is not responding")
        case "error": return i18np("%1 item needs attention", "%1 items need attention", root.attentionCount)
        case "syncing":
            if (root.activeRemoteSyncDevices > 0 && root.activelySyncingFolders === 0)
                return i18np("Syncing with %1 device", "Syncing with %1 devices", root.activeRemoteSyncDevices)
            if (root.activeRemoteSyncDevices > 0) return i18n("Syncing with devices")
            if (root.totalNeedBytes > 0) return i18n("Syncing · %1%", Math.floor(root.overallPercent))
            return i18n("Syncing")
        case "busy": return i18n("Synchronization pending")
        case "paused": return root.allDevicesPaused ? i18n("All devices are paused") : i18n("Every folder is paused")
        case "empty": return i18n("No folders are configured")
        default: return i18n("Everything is up to date")
        }
    }

    function overallSubtitle() {
        if (root.setupError !== "") return root.setupError
        if (!root.reachable) return root.lastError !== "" ? root.lastError : i18n("Waiting for the Syncthing API")
        var parts = [i18np("%1 folder", "%1 folders", root.folders.length)]
        if (root.remoteDevices.length > 0)
            parts.push(i18n("%1 of %2 devices online", root.connectedDevices, root.remoteDevices.length))
        if (root.activeRemoteSyncDevices > 0)
            parts.push(i18np("%1 remote device syncing", "%1 remote devices syncing", root.activeRemoteSyncDevices))
        if (root.totalNeedBytes > 0)
            parts.push(i18n("%1 left", root.formatBytes(root.totalNeedBytes)))
        else if (root.totalNeedItems > 0)
            parts.push(i18np("%1 item left", "%1 items left", root.totalNeedItems))
        if (root.pausedFolders > 0 && root.overallState !== "paused")
            parts.push(i18np("%1 paused", "%1 paused", root.pausedFolders))
        if (root.overdueDevices > 0)
            parts.push(i18np("%1 device overdue", "%1 devices overdue", root.overdueDevices))
        if (root.validTimestamp(plasmoid.configuration.lastSuccessfulSync))
            parts.push(i18n("synced %1", root.formatWhen(plasmoid.configuration.lastSuccessfulSync)))
        return parts.join(" · ")
    }

    function formatBytes(value) {
        var bytes = Number(value || 0)
        if (bytes < 1000) return i18n("%1 B", Math.round(bytes))
        var units = ["kB", "MB", "GB", "TB", "PB"]
        var index = -1
        do {
            bytes /= 1000
            ++index
        } while (bytes >= 1000 && index < units.length - 1)
        var digits = bytes >= 100 ? 0 : bytes >= 10 ? 1 : 2
        return bytes.toFixed(digits) + " " + units[index]
    }

    function formatRate(value) {
        return i18n("%1/s", root.formatBytes(value))
    }

    function formatNumber(value) {
        return Number(value || 0).toLocaleString(Qt.locale(), "f", 0)
    }

    function formatUptime(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds || 0)))
        var days = Math.floor(total / 86400)
        var hours = Math.floor((total % 86400) / 3600)
        var minutes = Math.floor((total % 3600) / 60)
        if (days > 0) return i18n("%1d %2h", days, hours)
        if (hours > 0) return i18n("%1h %2m", hours, minutes)
        return i18n("%1m", minutes)
    }

    function formatWhen(stamp) {
        var tick = root.clockTick
        if (!stamp) return i18n("never")
        var moment = new Date(stamp)
        if (isNaN(moment.getTime()) || moment.getFullYear() < 1971) return i18n("never")
        var seconds = (Date.now() - moment.getTime()) / 1000
        if (seconds < 0) return i18n("just now")
        if (seconds < 60) return i18n("just now")
        if (seconds < 3600) return i18np("%1 minute ago", "%1 minutes ago", Math.floor(seconds / 60))
        if (seconds < 86400) return i18np("%1 hour ago", "%1 hours ago", Math.floor(seconds / 3600))
        if (seconds < 604800) return i18np("%1 day ago", "%1 days ago", Math.floor(seconds / 86400))
        return moment.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }

    function formatDuration(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds || 0)))
        if (total < 60) return i18np("%1 second", "%1 seconds", total)
        if (total < 3600) return i18np("%1 minute", "%1 minutes", Math.floor(total / 60))
        if (total < 86400) return i18np("%1 hour", "%1 hours", Math.floor(total / 3600))
        return i18np("%1 day", "%1 days", Math.floor(total / 86400))
    }

    function withEntry(map, key, value) {
        var next = ({})
        for (var existing in map) next[existing] = map[existing]
        next[key] = value
        return next
    }

    function locate(index) {
        if (index >= root.configCandidates.length) {
            root.setupError = i18n("No Syncthing configuration was found. Set the address and API key in the widget settings.")
            return
        }
        var path = root.configCandidates[index]
        var request = new XMLHttpRequest()
        request.open("GET", "file://" + path)
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            var body = request.responseText || ""
            var gui = /<gui\b([^>]*)>([\s\S]*?)<\/gui>/.exec(body)
            if (!gui) {
                root.locate(index + 1)
                return
            }
            var address = /<address>([^<]*)<\/address>/.exec(gui[2])
            var key = /<apikey>([^<]*)<\/apikey>/.exec(gui[2])
            if (!address || !key) {
                root.locate(index + 1)
                return
            }
            var host = address[1].trim().replace(/^0\.0\.0\.0:/, "127.0.0.1:").replace(/^:/, "127.0.0.1:")
            root.applyEndpoint((/tls\s*=\s*"true"/.test(gui[1]) ? "https://" : "http://") + host, key[1].trim())
        }
        request.send()
    }

    function applyEndpoint(url, key) {
        var overrideUrl = String(plasmoid.configuration.serverUrl || "").trim().replace(/\/+$/, "")
        var overrideKey = String(plasmoid.configuration.apiKey || "").trim()
        root.baseUrl = overrideUrl !== "" ? overrideUrl : url
        root.apiKey = overrideKey !== "" ? overrideKey : key
        if (root.baseUrl === "" || root.apiKey === "") {
            root.setupError = i18n("The Syncthing address or API key is missing. Set both in the widget settings.")
            return
        }
        root.setupError = ""
        root.refreshConfig()
        root.refreshSystem()
        root.refreshConnections()
        root.refreshDeviceStats()
        root.refreshAttention()
        root.pollEvents()
    }

    function connect() {
        root.setupError = ""
        var overrideUrl = String(plasmoid.configuration.serverUrl || "").trim().replace(/\/+$/, "")
        var overrideKey = String(plasmoid.configuration.apiKey || "").trim()
        if (overrideUrl !== "" && overrideKey !== "") {
            root.applyEndpoint(overrideUrl, overrideKey)
            return
        }
        root.locate(0)
    }

    function api(method, path, done, payload, failed) {
        if (root.baseUrl === "") return
        var generation = root.eventGeneration
        var request = new XMLHttpRequest()
        request.open(method, root.baseUrl + path)
        request.setRequestHeader("X-API-Key", root.apiKey)
        if (payload !== undefined) request.setRequestHeader("Content-Type", "application/json")
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            if (generation !== root.eventGeneration) return
            if (request.status >= 200 && request.status < 300) {
                root.reachable = true
                root.lastError = ""
                var data = null
                try { data = JSON.parse(request.responseText || "null") } catch (error) { data = null }
                if (done) done(data)
            } else if (request.status === 0) {
                root.reachable = false
                root.lastError = i18n("Cannot reach %1", root.baseUrl)
                if (failed) failed(request.status)
            } else {
                root.lastError = request.status === 403
                    ? i18n("The API key was rejected")
                    : i18n("Syncthing returned HTTP %1", request.status)
                if (failed) failed(request.status)
            }
        }
        request.send(payload === undefined ? null : JSON.stringify(payload))
    }

    function refreshConfig() {
        root.api("GET", "/rest/config/folders", function(data) {
            root.folders = data || []
            for (var i = 0; i < root.folders.length; ++i) root.refreshFolder(root.folders[i].id)
        })
        root.api("GET", "/rest/config/devices", function(data) {
            root.devices = data || []
            root.devicesLoaded = true
            root.refreshCompletion()
            root.checkOfflineDevices()
        })
        root.api("GET", "/rest/stats/folder", function(data) { root.folderStats = data || ({}) })
    }

    function refreshSystem() {
        root.api("GET", "/rest/system/status", function(data) {
            if (!data) return
            root.myId = data.myID || ""
            root.uptimeSeconds = Number(data.uptime || 0)
        })
        root.api("GET", "/rest/system/version", function(data) {
            if (data) root.versionText = data.version || ""
        })
    }

    function refreshFolder(id) {
        root.api("GET", "/rest/db/status?folder=" + encodeURIComponent(id), function(data) {
            if (!data) return
            root.folderStatus = root.withEntry(root.folderStatus, id, data)
            if (Number(data.errors || 0) > 0) root.refreshFolderErrors(id)
            else if (root.folderErrors[id]) root.folderErrors = root.withEntry(root.folderErrors, id, [])
            if (root.folderState(id) !== "busy") {
                root.folderNeedItems = root.withEntry(root.folderNeedItems, id, [])
                root.folderNeedLoading = root.withEntry(root.folderNeedLoading, id, false)
            }
            if (root.viewVisible && root.openFolder === id && root.folderState(id) === "busy")
                root.refreshFolderNeed(id)
            root.evaluateSyncState()
        })
    }

    function refreshFolderErrors(id) {
        root.api("GET", "/rest/folder/errors?folder=" + encodeURIComponent(id), function(data) {
            root.folderErrors = root.withEntry(root.folderErrors, id, (data && data.errors) || [])
        })
    }

    function refreshConnections() {
        root.api("GET", "/rest/system/connections", function(data) {
            if (!data) return
            root.deviceConnections = data.connections || ({})
            root.connectionsLoaded = true
            var total = data.total || ({})
            var now = Date.now()
            if (root.sampledAt > 0 && now > root.sampledAt) {
                var span = (now - root.sampledAt) / 1000
                root.inRate = Math.max(0, (Number(total.inBytesTotal || 0) - root.sampledIn) / span)
                root.outRate = Math.max(0, (Number(total.outBytesTotal || 0) - root.sampledOut) / span)
            }
            if (root.sampledAt > 0 && now > root.sampledAt) {
                var elapsed = (now - root.sampledAt) / 1000
                var rates = ({})
                for (var deviceId in root.deviceConnections) {
                    var connection = root.deviceConnections[deviceId] || ({})
                    var previous = root.lastDeviceTotals[deviceId]
                    rates[deviceId] = previous && connection.connected
                        ? {
                            inRate: Math.max(0, (Number(connection.inBytesTotal || 0) - previous.inBytes) / elapsed),
                            outRate: Math.max(0, (Number(connection.outBytesTotal || 0) - previous.outBytes) / elapsed)
                        }
                        : { inRate: 0, outRate: 0 }
                }
                root.deviceRates = rates
                History.push(root.history, "in", root.inRate)
                History.push(root.history, "out", root.outRate)
                ++root.tick
            }
            var totals = ({})
            for (var id in root.deviceConnections) {
                var current = root.deviceConnections[id] || ({})
                totals[id] = { inBytes: Number(current.inBytesTotal || 0), outBytes: Number(current.outBytesTotal || 0) }
            }
            root.lastDeviceTotals = totals
            root.sampledIn = Number(total.inBytesTotal || 0)
            root.sampledOut = Number(total.outBytesTotal || 0)
            root.sampledAt = now
            root.checkOfflineDevices()
        })
    }

    function refreshDeviceStats() {
        root.api("GET", "/rest/stats/device", function(data) {
            root.deviceStats = data || ({})
            root.deviceStatsLoaded = true
            root.checkOfflineDevices()
        })
    }

    function refreshAttention() {
        root.api("GET", "/rest/system/error", function(data) {
            root.systemErrors = data && data.errors ? data.errors : []
        })
        root.api("GET", "/rest/cluster/pending/devices", function(data) {
            root.pendingDevices = data || ({})
        })
        root.api("GET", "/rest/cluster/pending/folders", function(data) {
            root.pendingFolderOffers = data || ({})
        })
    }

    function currentOfflineStates() {
        var states = ({})
        for (var i = 0; i < root.remoteDevices.length; ++i) {
            var device = root.remoteDevices[i]
            states[device.deviceID] = root.deviceIsOverdue(device)
        }
        return states
    }

    function checkOfflineDevices() {
        if (!root.devicesLoaded || !root.connectionsLoaded || !root.deviceStatsLoaded) return
        var next = root.currentOfflineStates()
        if (!root.offlineBaselineReady) {
            root.offlineStates = next
            root.offlineBaselineReady = true
            return
        }
        if (plasmoid.configuration.notifyOfflineDevices) {
            for (var deviceId in next) {
                if (next[deviceId] && !root.offlineStates[deviceId]) {
                    root.sendNotification(
                        i18n("Syncthing device overdue"),
                        i18n("%1 has been offline longer than %2 hours.",
                            root.deviceName(deviceId), Number(plasmoid.configuration.offlineGraceHours || 0)),
                        true)
                }
            }
        }
        root.offlineStates = next
    }

    function allFolderStatusesLoaded() {
        if (root.folders.length === 0) return false
        for (var i = 0; i < root.folders.length; ++i)
            if (!root.folderStatus[root.folders[i].id]) return false
        return true
    }

    function folderShowsTransfer(id) {
        var status = root.folderStatus[id] || ({})
        var state = String(status.state || "")
        return Number(status.needTotalItems || 0) > 0 || state.indexOf("sync") === 0
    }

    function evaluateSyncState() {
        if (!root.allFolderStatusesLoaded()) return
        var active = false
        for (var i = 0; i < root.folders.length; ++i) {
            if (root.folderShowsTransfer(root.folders[i].id)) {
                active = true
                break
            }
        }
        if (!root.syncTrackingReady) {
            root.syncTrackingReady = true
            root.syncWasActive = active
            return
        }
        if (active) {
            root.syncWasActive = true
            return
        }
        if (!root.syncWasActive) return
        root.syncWasActive = false
        plasmoid.configuration.lastSuccessfulSync = new Date().toISOString()
        if (plasmoid.configuration.notifySyncComplete)
            root.sendNotification(i18n("Syncthing is up to date"), i18n("All folders finished syncing."), false)
    }

    function flattenNeedItems(data) {
        var items = []
        var groups = [
            { key: "progress", stage: i18n("Now") },
            { key: "queued", stage: i18n("Next") },
            { key: "rest", stage: i18n("Later") }
        ]
        for (var groupIndex = 0; groupIndex < groups.length && items.length < 3; ++groupIndex) {
            var group = groups[groupIndex]
            var entries = data && data[group.key] ? data[group.key] : []
            for (var itemIndex = 0; itemIndex < entries.length && items.length < 3; ++itemIndex) {
                var entry = entries[itemIndex] || ({})
                items.push({ name: entry.name || "", size: Number(entry.size || 0), stage: group.stage })
            }
        }
        return items
    }

    function refreshFolderNeed(id) {
        if (!id || root.folderState(id) !== "busy") return
        if (root.folderNeedLoading[id] === true) return
        root.folderNeedLoading = root.withEntry(root.folderNeedLoading, id, true)
        root.api("GET", "/rest/db/need?folder=" + encodeURIComponent(id) + "&page=1&perpage=3", function(data) {
            root.folderNeedItems = root.withEntry(root.folderNeedItems, id, root.flattenNeedItems(data))
            root.folderNeedLoading = root.withEntry(root.folderNeedLoading, id, false)
        }, undefined, function() {
            root.folderNeedLoading = root.withEntry(root.folderNeedLoading, id, false)
        })
    }

    function refreshCompletion() {
        for (var i = 0; i < root.remoteDevices.length; ++i) {
            var id = root.remoteDevices[i].deviceID
            root.api("GET", "/rest/db/completion?device=" + encodeURIComponent(id), (function(device) {
                return function(data) {
                    if (data) root.deviceCompletion = root.withEntry(root.deviceCompletion, device, data)
                }
            })(id))
        }
    }

    function refreshStats() {
        root.api("GET", "/rest/stats/folder", function(data) { root.folderStats = data || ({}) })
    }

    function refreshAllData() {
        root.refreshConfig()
        root.refreshSystem()
        root.refreshConnections()
        root.refreshDeviceStats()
        root.refreshAttention()
    }

    function eventCursor(diskEvents) {
        return diskEvents ? root.lastDiskEventId : root.lastEventId
    }

    function setEventCursor(diskEvents, value) {
        if (diskEvents) root.lastDiskEventId = value
        else root.lastEventId = value
    }

    function eventStreamRequest(diskEvents) {
        return diskEvents ? root.diskEventRequest : root.eventRequest
    }

    function setEventStreamRequest(diskEvents, request) {
        if (diskEvents) root.diskEventRequest = request
        else root.eventRequest = request
    }

    function setEventRequestStartedAt(diskEvents, value) {
        if (diskEvents) root.diskEventRequestStartedAt = value
        else root.eventRequestStartedAt = value
    }

    function stopEventStreams() {
        ++root.eventGeneration
        var normalRequest = root.eventRequest
        var diskRequest = root.diskEventRequest
        root.eventRequest = null
        root.diskEventRequest = null
        root.eventRequestStartedAt = 0
        root.diskEventRequestStartedAt = 0
        if (normalRequest) normalRequest.abort()
        if (diskRequest) diskRequest.abort()
    }

    function pollEvents() {
        if (root.baseUrl === "" || root.apiKey === "") return
        if (root.eventRequest || root.diskEventRequest) return
        var generation = root.eventGeneration
        root.requestEvents(false, root.lastEventId === 0, generation)
        root.requestEvents(true, root.lastDiskEventId === 0, generation)
    }

    function requestEvents(diskEvents, bootstrap, generation) {
        if (generation !== root.eventGeneration || root.eventStreamRequest(diskEvents)) return
        var cursor = root.eventCursor(diskEvents)
        var endpoint = diskEvents ? "/rest/events/disk" : "/rest/events"
        var query = bootstrap
            ? "?since=0&limit=" + (diskEvents ? 100 : 256) + "&timeout=0"
            : "?since=" + cursor + "&timeout=55"
        var request = new XMLHttpRequest()
        root.setEventStreamRequest(diskEvents, request)
        root.setEventRequestStartedAt(diskEvents, Date.now())
        request.open("GET", root.baseUrl + endpoint + query)
        request.setRequestHeader("X-API-Key", root.apiKey)
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            if (generation !== root.eventGeneration) return
            if (root.eventStreamRequest(diskEvents) !== request) return
            root.setEventStreamRequest(diskEvents, null)
            root.setEventRequestStartedAt(diskEvents, 0)
            if (request.status >= 200 && request.status < 300) {
                root.reachable = true
                root.lastError = ""
                reconnectTimer.stop()
                var events
                try {
                    events = JSON.parse(request.responseText || "[]")
                    if (!Array.isArray(events)) throw new Error("Invalid event response")
                } catch (error) {
                    root.failEventStreams(0, generation)
                    return
                }
                if (bootstrap) {
                    if (events.length > 0) {
                        root.setEventCursor(diskEvents, Number(events[events.length - 1].id || 0))
                        if (!diskEvents) root.restoreRemoteDownloadActivity(events)
                        root.recordActivity(events)
                    }
                } else {
                    if (events.length > 0) {
                        var newestId = cursor
                        for (var index = 0; index < events.length; ++index) {
                            var currentId = Number(events[index].id || 0)
                            if (newestId > 0 && currentId > newestId + 1) {
                                root.pendingFullRefresh = true
                                if (!diskEvents) root.remoteDownloadActivity = ({})
                            }
                            newestId = Math.max(newestId, currentId)
                        }
                        root.setEventCursor(diskEvents, newestId)
                        root.recordActivity(events)
                        root.handleEvents(events)
                    }
                }
                root.requestEvents(diskEvents, false, generation)
            } else {
                root.failEventStreams(request.status, generation)
            }
        }
        request.send()
    }

    function failEventStreams(status, generation) {
        if (generation !== root.eventGeneration) return
        root.stopEventStreams()
        root.lastEventId = 0
        root.lastDiskEventId = 0
        root.remoteDownloadActivity = ({})
        root.reachable = false
        root.lastError = status === 403
            ? i18n("The API key was rejected")
            : status === 0
                ? i18n("Cannot reach %1", root.baseUrl)
                : i18n("Syncthing returned HTTP %1", status)
        reconnectTimer.restart()
    }

    function handleEvents(events) {
        for (var i = 0; i < events.length; ++i) {
            var event = events[i]
            var data = event.data || ({})
            switch (event.type) {
            case "FolderSummary":
                if (data.folder && data.summary) {
                    root.folderStatus = root.withEntry(root.folderStatus, data.folder, data.summary)
                    root.evaluateSyncState()
                    if (root.openFolder === data.folder && root.folderState(data.folder) === "busy")
                        root.pendingNeedFolders = root.withEntry(root.pendingNeedFolders, data.folder, true)
                }
                break
            case "FolderErrors":
                if (data.folder) {
                    root.folderErrors = root.withEntry(root.folderErrors, data.folder, data.errors || [])
                    if (plasmoid.configuration.notifyErrors && data.errors && data.errors.length > 0) {
                        root.sendNotification(
                            i18n("Syncthing folder error"),
                            i18np("%1 failed item in %2", "%1 failed items in %2",
                                data.errors.length, root.folderName(data.folder)),
                            true)
                    }
            }
            break
            case "StateChanged":
                if (data.folder && data.to) root.applyFolderState(data.folder, data.to)
                root.queueFolderEventRefresh(event.type, data)
                break
            case "FolderScanProgress":
            case "DownloadProgress":
            case "LocalIndexUpdated":
            case "RemoteIndexUpdated":
            case "LocalChangeDetected":
            case "RemoteChangeDetected":
            case "FolderWatchStateChanged":
                root.queueFolderEventRefresh(event.type, data)
                break
            case "ItemStarted":
                if (root.syncTrackingReady) root.syncWasActive = true
                if (data.folder && root.openFolder === data.folder)
                    root.pendingNeedFolders = root.withEntry(root.pendingNeedFolders, data.folder, true)
                break
            case "ItemFinished":
                if (data.folder) root.pendingFolders = root.withEntry(root.pendingFolders, data.folder, true)
                if (data.folder && root.openFolder === data.folder)
                    root.pendingNeedFolders = root.withEntry(root.pendingNeedFolders, data.folder, true)
                root.pendingStats = true
                break
            case "FolderCompletion":
                root.pendingCompletion = true
                break
            case "DeviceConnected":
                root.applyDeviceConnected(data.id || data.device, true)
                root.pendingConnections = true
                root.pendingCompletion = true
                root.pendingDeviceStats = true
                break
            case "DeviceDisconnected":
                root.applyDeviceConnected(data.id || data.device, false)
                root.clearRemoteDownloadActivity(data.id || data.device, "")
                root.pendingConnections = true
                root.pendingCompletion = true
                root.pendingDeviceStats = true
                break
            case "DevicePaused":
                root.applyDevicePaused(data.id || data.device, true)
                root.clearRemoteDownloadActivity(data.id || data.device, "")
                root.pendingConnections = true
                root.pendingCompletion = true
                root.pendingDeviceStats = true
                break
            case "DeviceResumed":
                root.applyDevicePaused(data.id || data.device, false)
                root.pendingConnections = true
                root.pendingCompletion = true
                root.pendingDeviceStats = true
                break
            case "ConfigSaved":
                root.pendingConfig = true
                break
            case "FolderPaused":
                root.applyFolderPaused(data.folder, true)
                root.clearRemoteDownloadActivity("", data.folder)
                root.pendingConfig = true
                break
            case "FolderResumed":
                root.applyFolderPaused(data.folder, false)
                root.pendingConfig = true
                break
            case "RemoteDownloadProgress":
                root.applyRemoteDownloadProgress(data)
                root.pendingCompletion = true
                break
            case "ClusterConfigReceived":
                root.pendingCompletion = true
                break
            case "DeviceRejected":
            case "FolderRejected":
                root.pendingAttention = true
                break
            case "Starting":
                root.remoteDownloadActivity = ({})
                root.pendingConfig = true
                root.pendingConnections = true
                root.pendingAttention = true
                root.pendingDeviceStats = true
                break
            case "StartupComplete":
                root.pendingConfig = true
                root.pendingConnections = true
                root.pendingAttention = true
                root.pendingDeviceStats = true
                break
            case "PendingDevicesChanged":
                root.pendingAttention = true
                if (plasmoid.configuration.notifyInvitations && data.added && data.added.length > 0) {
                    var addedDevice = data.added[0] || ({})
                    root.sendNotification(
                        i18n("New Syncthing device"),
                        data.added.length === 1
                            ? (addedDevice.name || addedDevice.deviceID || i18n("An unknown device wants to connect."))
                            : i18np("%1 new device invitation", "%1 new device invitations", data.added.length),
                        true)
                }
                break
            case "PendingFoldersChanged":
                root.pendingAttention = true
                if (plasmoid.configuration.notifyInvitations && data.added && data.added.length > 0) {
                    var addedFolder = data.added[0] || ({})
                    root.sendNotification(
                        i18n("New Syncthing folder"),
                        data.added.length === 1
                            ? (addedFolder.folderLabel || addedFolder.folderID || i18n("A device offered a folder."))
                            : i18np("%1 new folder invitation", "%1 new folder invitations", data.added.length),
                        false)
                }
                break
            case "Failure":
                root.pendingAttention = true
                var failureMessage = root.failureMessage(data)
                if (plasmoid.configuration.notifyErrors && root.shouldNotifyFailure(failureMessage))
                    root.sendNotification(i18n("Syncthing error"), failureMessage, true)
                break
            case "DeviceDiscovered":
            case "ListenAddressesChanged":
            case "LoginAttempt":
            case "UpgradeRestartScheduled":
                break
            default:
                root.pendingFullRefresh = true
                break
            }
        }
        if (events.length > 0 && !refreshTimer.running) refreshTimer.start()
    }

    property bool pendingStats: false

    function queueFolderEventRefresh(eventType, data) {
        if (eventType === "DownloadProgress") {
            var hasFolder = false
            for (var folderId in data) {
                root.pendingFolders = root.withEntry(root.pendingFolders, folderId, true)
                hasFolder = true
            }
            if (!hasFolder) {
                for (var index = 0; index < root.folders.length; ++index)
                    root.pendingFolders = root.withEntry(root.pendingFolders, root.folders[index].id, true)
            }
        } else if (data.folder) {
            root.pendingFolders = root.withEntry(root.pendingFolders, data.folder, true)
        }
        root.pendingStats = true
        if (eventType === "StateChanged" && data.folder && root.openFolder === data.folder)
            root.pendingNeedFolders = root.withEntry(root.pendingNeedFolders, data.folder, true)
    }

    function applyFolderState(id, state) {
        var current = root.folderStatus[id]
        if (!current) return
        var next = ({})
        for (var key in current) next[key] = current[key]
        next.state = state
        root.folderStatus = root.withEntry(root.folderStatus, id, next)
    }

    function applyDeviceConnected(id, connected) {
        if (!id) return
        var current = root.deviceConnections[id] || ({})
        var next = ({})
        for (var key in current) next[key] = current[key]
        next.connected = connected
        root.deviceConnections = root.withEntry(root.deviceConnections, id, next)
    }

    function applyDevicePaused(id, paused) {
        if (!id) return
        var next = []
        for (var index = 0; index < root.devices.length; ++index) {
            var current = root.devices[index]
            if (current.deviceID !== id) {
                next.push(current)
                continue
            }
            var updated = ({})
            for (var key in current) updated[key] = current[key]
            updated.paused = paused
            next.push(updated)
        }
        root.devices = next
    }

    function applyFolderPaused(id, paused) {
        if (!id) return
        var next = []
        for (var index = 0; index < root.folders.length; ++index) {
            var current = root.folders[index]
            if (current.id !== id) {
                next.push(current)
                continue
            }
            var updated = ({})
            for (var key in current) updated[key] = current[key]
            updated.paused = paused
            next.push(updated)
        }
        root.folders = next
    }

    function applyPending() {
        if (root.pendingFullRefresh) {
            root.pendingFullRefresh = false
            root.pendingFolders = ({})
            root.pendingConfig = false
            root.pendingConnections = false
            root.pendingCompletion = false
            root.pendingStats = false
            root.pendingAttention = false
            root.pendingDeviceStats = false
            root.pendingNeedFolders = ({})
            root.refreshAllData()
            return
        }
        for (var id in root.pendingFolders) root.refreshFolder(id)
        root.pendingFolders = ({})
        if (root.pendingConfig) {
            root.pendingConfig = false
            root.refreshConfig()
            root.refreshSystem()
        }
        if (root.pendingConnections) {
            root.pendingConnections = false
            root.refreshConnections()
        }
        if (root.pendingCompletion) {
            root.pendingCompletion = false
            root.refreshCompletion()
        }
        if (root.pendingStats) {
            root.pendingStats = false
            root.refreshStats()
        }
        if (root.pendingAttention) {
            root.pendingAttention = false
            root.refreshAttention()
        }
        if (root.pendingDeviceStats) {
            root.pendingDeviceStats = false
            root.refreshDeviceStats()
        }
        for (var folderId in root.pendingNeedFolders) root.refreshFolderNeed(folderId)
        root.pendingNeedFolders = ({})
    }

    function rescanFolder(id) {
        root.api("POST", "/rest/db/scan?folder=" + encodeURIComponent(id), null, {})
    }

    function rescanAll() {
        root.api("POST", "/rest/db/scan", null, {})
    }

    function setFolderPaused(id, paused) {
        root.api("PATCH", "/rest/config/folders/" + encodeURIComponent(id), function() {
            root.refreshConfig()
        }, { paused: paused })
    }

    function setDevicePaused(id, paused) {
        root.api("PATCH", "/rest/config/devices/" + encodeURIComponent(id), function() {
            root.refreshConfig()
            root.refreshConnections()
        }, { paused: paused })
    }

    function requestGlobalPause(paused) {
        if (paused) pauseAllDialog.open()
        else root.setGlobalPaused(false)
    }

    function setGlobalPaused(paused) {
        if (root.globalActionPending) return
        root.globalActionPending = true
        root.api("POST", paused ? "/rest/system/pause" : "/rest/system/resume", function() {
            root.globalActionPending = false
            root.refreshConfig()
            root.refreshConnections()
            root.refreshDeviceStats()
        }, undefined, function() {
            root.globalActionPending = false
        })
    }

    function sendNotification(title, text, urgent) {
        var notification = notificationComponent.createObject(root)
        if (!notification) return
        notification.title = title
        notification.text = text
        notification.urgency = urgent
            ? KNotifications.Notification.HighUrgency
            : KNotifications.Notification.NormalUrgency
        notification.sendEvent()
    }

    function failureMessage(data) {
        if (typeof data === "string") {
            var directMessage = data.trim()
            if (directMessage !== "") return directMessage
        }
        if (data && typeof data === "object") {
            var objectMessage = String(data.error || data.message || "").trim()
            if (objectMessage !== "") return objectMessage
        }
        return i18n("Syncthing reported a failure.")
    }

    function shouldNotifyFailure(message) {
        var now = Date.now()
        var recent = ({})
        var messageKey = "$" + message
        for (var key in root.recentFailureNotifications) {
            var notifiedAt = Number(root.recentFailureNotifications[key] || 0)
            if (now - notifiedAt < root.failureNotificationCooldownMs)
                recent[key] = notifiedAt
        }
        if (recent[messageKey] !== undefined) {
            root.recentFailureNotifications = recent
            return false
        }
        recent[messageKey] = now
        root.recentFailureNotifications = recent
        return true
    }

    function expandPath(path) {
        var value = String(path || "")
        if (value.indexOf("~") === 0) return root.homePath + value.slice(1)
        return value
    }

    function openFolderPath(path) {
        Qt.openUrlExternally("file://" + root.expandPath(path))
    }

    function openWebInterface() {
        if (root.baseUrl !== "") Qt.openUrlExternally(root.baseUrl)
    }

    Component.onCompleted: {
        root.connect()
    }
    Component.onDestruction: root.stopEventStreams()
    onExpandedChanged: {
        if (!root.expanded) {
            if (root.inPanel) releasePopup.restart()
            return
        }
        releasePopup.stop()
        root.popupAlive = true
        if (!Plasmoid.configuration.rememberTab) root.tabKey = Plasmoid.configuration.defaultTab
        if (root.baseUrl === "" || root.apiKey === "") {
            root.connect()
            return
        }
        root.refreshAllData()
    }

    Connections {
        target: plasmoid.configuration
        function onServerUrlChanged() { root.reconnect() }
        function onApiKeyChanged() { root.reconnect() }
        function onOfflineGraceHoursChanged() {
            ++root.clockTick
            root.checkOfflineDevices()
        }
    }

    function reconnect() {
        reconnectTimer.stop()
        root.activity = []
        root.deviceRates = ({})
        root.lastDeviceTotals = ({})
        root.stopEventStreams()
        root.lastEventId = 0
        root.lastDiskEventId = 0
        root.remoteDownloadActivity = ({})
        root.reachable = false
        root.devicesLoaded = false
        root.connectionsLoaded = false
        root.deviceStatsLoaded = false
        root.offlineBaselineReady = false
        root.offlineStates = ({})
        root.syncTrackingReady = false
        root.syncWasActive = false
        root.connect()
    }

    Component {
        id: notificationComponent
        KNotifications.Notification {
            componentName: "plasma_workspace"
            eventId: "notification"
            iconName: "folder-sync"
            flags: KNotifications.Notification.CloseOnTimeout
            autoDelete: true
        }
    }

    Kirigami.PromptDialog {
        id: pauseAllDialog
        title: i18n("Pause all Syncthing devices?")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        PlasmaComponents.Label {
            text: i18n("This stops every remote-device connection until you resume them.")
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        }
        onAccepted: root.setGlobalPaused(true)
    }

    Timer {
        id: refreshTimer
        interval: 100
        onTriggered: root.applyPending()
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        onTriggered: root.connect()
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.eventRequest !== null || root.diskEventRequest !== null
        onTriggered: {
            var now = Date.now()
            if ((root.eventRequestStartedAt > 0 && now - root.eventRequestStartedAt > 65000)
                    || (root.diskEventRequestStartedAt > 0 && now - root.diskEventRequestStartedAt > 65000))
                root.failEventStreams(0, root.eventGeneration)
        }
    }

    Timer {
        id: rateTimer
        interval: 2000
        repeat: true
        running: root.wantsRates && root.reachable
        triggeredOnStart: true
        onTriggered: root.refreshConnections()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.reachable
        onTriggered: {
            ++root.clockTick
            root.checkOfflineDevices()
            if (root.viewVisible) {
                root.refreshSystem()
                root.refreshStats()
                root.refreshDeviceStats()
                root.refreshAttention()
            }
        }
    }

    compactRepresentation: CompactView {}
    fullRepresentation: FullView {}
}
