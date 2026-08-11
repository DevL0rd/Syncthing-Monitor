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
    property bool completionTrackingReady: false
    property bool completionPulseActive: false
    property bool completionPulsePending: false
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

    readonly property int failureNotificationCooldownMs: 5 * 60 * 1000

    readonly property var remoteDevices: root.devices.filter(function(device) { return device.deviceID !== root.myId })
    readonly property int connectedDevices: root.countConnectedDevices()
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

    onOverallStateChanged: {
        if (!root.completionTrackingReady) return
        if (root.overallState === "error" || root.overallState === "offline"
                || root.overallState === "setup" || root.overallState === "paused") {
            root.cancelCompletionPulse()
            return
        }
        root.maybeStartCompletionPulse()
    }
    onWorkActiveChanged: {
        if (!root.completionTrackingReady) return
        if (root.workActive && root.completionPulseActive) {
            root.completionPulseActive = false
            completionPulseTimer.stop()
        } else if (!root.workActive) {
            root.maybeStartCompletionPulse()
        }
    }

    Plasmoid.icon: "folder-sync"
    Plasmoid.title: i18n("Syncthing Monitor")
    toolTipMainText: root.overallTitle()
    toolTipSubText: root.overallSubtitle()
    preferredRepresentation: compactRepresentation

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

    function applyRemoteDownloadProgress(data, notifyCompletion) {
        var device = String(data.device || "")
        var folder = String(data.folder || "")
        if (device === "" || folder === "") return
        var hadActivity = false
        for (var existingKey in root.remoteDownloadActivity) {
            hadActivity = true
            break
        }
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
        if (notifyCompletion && hadActivity) {
            var hasActivity = false
            for (var remainingKey in next) {
                hasActivity = true
                break
            }
            if (!hasActivity) root.markWorkCompleted()
        }
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
                root.applyRemoteDownloadProgress(data, false)
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

    function markWorkCompleted() {
        if (!root.completionTrackingReady) return
        if (root.overallState === "error" || root.overallState === "offline"
                || root.overallState === "setup" || root.overallState === "paused") return
        root.completionPulsePending = true
        root.maybeStartCompletionPulse()
    }

    function maybeStartCompletionPulse() {
        if (!root.completionPulsePending || root.workActive || root.overallState !== "ok") return
        root.completionPulsePending = false
        root.completionPulseActive = true
        completionPulseTimer.restart()
    }

    function cancelCompletionPulse() {
        root.completionPulsePending = false
        root.completionPulseActive = false
        completionPulseTimer.stop()
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
            if (root.expanded && root.openFolder === id && root.folderState(id) === "busy")
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
            ? "?since=0&limit=" + (diskEvents ? 1 : 256) + "&timeout=0"
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
                if (data.from && data.from !== "idle" && data.to === "idle") root.markWorkCompleted()
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
                root.applyRemoteDownloadProgress(data, true)
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
        root.completionTrackingReady = true
        root.connect()
    }
    Component.onDestruction: root.stopEventStreams()
    onExpandedChanged: {
        if (!root.expanded) return
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
        id: completionPulseTimer
        interval: 10000
        onTriggered: root.completionPulseActive = false
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
        running: root.expanded && root.reachable
        onTriggered: root.refreshConnections()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.reachable
        onTriggered: {
            ++root.clockTick
            root.checkOfflineDevices()
            if (root.expanded) {
                root.refreshSystem()
                root.refreshStats()
                root.refreshDeviceStats()
                root.refreshAttention()
            }
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        implicitWidth: Kirigami.Units.gridUnit * 1.5
        implicitHeight: Kirigami.Units.gridUnit * 1.5
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) root.rescanAll()
            else root.expanded = !root.expanded
        }

        Kirigami.Icon {
            id: trayIcon
            anchors.fill: parent
            anchors.margins: Math.round(Math.min(parent.width, parent.height) * 0.1)
            source: "folder-sync"
            opacity: root.overallState === "offline" || root.overallState === "setup" ? 0.55 : 1
        }

        Rectangle {
            id: statusDot
            readonly property int diameter: Math.max(6, Math.round(Math.min(compact.width, compact.height) * 0.36))
            width: diameter
            height: diameter
            radius: diameter / 2
            anchors.right: trayIcon.right
            anchors.bottom: trayIcon.bottom
            color: root.stateColor
            border.width: Math.max(1, Math.round(diameter * 0.16))
            border.color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.9)

            SequentialAnimation on opacity {
                running: root.overallState === "syncing" || root.completionPulseActive
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.3; duration: 750; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
            }
        }
    }

    component StatusDot: Rectangle {
        required property string state
        property int diameter: Kirigami.Units.gridUnit * 0.5
        width: diameter
        height: diameter
        radius: diameter / 2
        color: root.colorForState(state)

        SequentialAnimation on opacity {
            running: parent.state === "busy"
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.3; duration: 750; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
        }
    }

    component StatTile: Item {
        id: tile
        property string label: ""
        property string value: ""
        property string iconName: ""
        property color valueColor: Kirigami.Theme.textColor
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 1
        implicitHeight: tileContent.implicitHeight

        ColumnLayout {
            id: tileContent
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    visible: tile.iconName !== ""
                    source: tile.iconName
                    color: tile.valueColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents.Label {
                    text: tile.value
                    color: tile.valueColor
                    font.weight: Font.DemiBold
                }
            }
            PlasmaComponents.Label {
                text: tile.label
                font: Kirigami.Theme.smallFont
                opacity: 0.65
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }
    }

    component SectionHeader: RowLayout {
        id: header
        property string title: ""
        default property alias trailing: trailingRow.data
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Label {
            text: header.title
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.capitalization: Font.AllUppercase
            font.weight: Font.Bold
            opacity: 0.6
        }
        Kirigami.Separator { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
        RowLayout { id: trailingRow; spacing: 0 }
    }

    component DetailRow: RowLayout {
        id: detail
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        PlasmaComponents.Label {
            text: detail.label
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        PlasmaComponents.Label {
            text: detail.value
            font: Kirigami.Theme.smallFont
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }
    }

    component RowCard: Rectangle {
        id: card
        property bool current: false
        default property alias content: body.data
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: Kirigami.Units.smallSpacing
        color: hoverHandler.hovered || card.current
            ? Qt.alpha(Kirigami.Theme.textColor, 0.07)
            : "transparent"
        HoverHandler { id: hoverHandler }
        Behavior on implicitHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 32

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Item {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                    Kirigami.Icon {
                        id: headerIcon
                        anchors.fill: parent
                        source: "folder-sync"
                    }
                    Rectangle {
                        readonly property int diameter: Math.round(headerIcon.height * 0.36)
                        width: diameter
                        height: diameter
                        radius: diameter / 2
                        anchors.right: headerIcon.right
                        anchors.bottom: headerIcon.bottom
                        color: root.stateColor
                        border.width: 2
                        border.color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.9)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents.Label {
                        text: root.overallTitle()
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                        font.weight: Font.Bold
                        color: root.overallState === "error" || root.overallState === "offline" || root.overallState === "setup"
                            ? Kirigami.Theme.negativeTextColor
                            : Kirigami.Theme.textColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: root.overallSubtitle()
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                QQC2.ToolButton {
                    icon.name: root.allDevicesPaused ? "media-playback-start" : "media-playback-pause"
                    enabled: root.reachable && root.remoteDevices.length > 0 && !root.globalActionPending
                    onClicked: root.requestGlobalPause(!root.allDevicesPaused)
                    Layout.alignment: Qt.AlignTop
                    Accessible.name: root.allDevicesPaused ? i18n("Resume all devices") : i18n("Pause all devices")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 400
                    QQC2.ToolTip.text: Accessible.name
                }

                QQC2.ToolButton {
                    icon.name: "internet-web-browser"
                    enabled: root.baseUrl !== ""
                    onClicked: root.openWebInterface()
                    Layout.alignment: Qt.AlignTop
                    Accessible.name: i18n("Open the Syncthing web interface")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 400
                    QQC2.ToolTip.text: i18n("Open the Syncthing web interface")
                }
            }

            QQC2.ProgressBar {
                visible: root.overallState === "syncing" && root.totalNeedBytes > 0
                from: 0
                to: 100
                value: root.overallPercent
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                spacing: 0
                StatTile {
                    iconName: "go-down"
                    value: root.formatRate(root.inRate)
                    label: i18n("Download")
                }
                StatTile {
                    iconName: "go-up"
                    value: root.formatRate(root.outRate)
                    label: i18n("Upload")
                }
                StatTile {
                    iconName: "drive-harddisk"
                    value: root.formatBytes(root.totalLocalBytes)
                    label: i18n("Local data")
                }
                StatTile {
                    iconName: root.attentionCount > 0 ? "dialog-warning" : "checkmark"
                    value: root.attentionCount > 0
                        ? root.formatNumber(root.attentionCount)
                        : root.totalNeedItems > 0 ? root.formatNumber(root.totalNeedItems) : "0"
                    valueColor: root.attentionCount > 0
                        ? Kirigami.Theme.negativeTextColor
                        : root.totalNeedItems > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    label: root.attentionCount > 0 ? i18n("Attention") : i18n("Pending")
                }
            }

            PlasmaComponents.Label {
                visible: root.setupError !== "" || (!root.reachable && root.lastError !== "")
                text: root.setupError !== "" ? root.setupError : root.lastError
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    SectionHeader {
                        visible: root.attentionCount > 0
                        title: i18n("Needs attention")
                    }

                    Repeater {
                        model: root.attentionItems.slice(0, 6)
                        delegate: RowCard {
                            required property var modelData

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: modelData.icon
                                    color: Kirigami.Theme.negativeTextColor
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    Layout.alignment: Qt.AlignTop
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PlasmaComponents.Label {
                                        text: modelData.title
                                        font.weight: Font.DemiBold
                                        color: Kirigami.Theme.negativeTextColor
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: modelData.detail
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.75
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        readonly property int extraAttention: root.attentionCount - 6
                        visible: extraAttention > 0
                        text: i18np("%1 more item needs attention", "%1 more items need attention", extraAttention)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.65
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                    }

                    SectionHeader {
                        title: i18n("Folders")
                        QQC2.ToolButton {
                            icon.name: "view-refresh"
                            enabled: root.reachable
                            onClicked: root.rescanAll()
                            display: QQC2.AbstractButton.IconOnly
                            text: i18n("Rescan every folder")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 400
                            QQC2.ToolTip.text: text
                        }
                    }

                    PlasmaComponents.Label {
                        visible: root.folders.length === 0
                        text: root.reachable
                            ? i18n("Add a folder in the Syncthing web interface.")
                            : i18n("Folders appear once Syncthing responds.")
                        opacity: 0.6
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                    }

                    Repeater {
                        model: root.folders
                        delegate: RowCard {
                            id: folderCard
                            required property var modelData
                            readonly property string folderId: folderCard.modelData.id
                            readonly property var status: root.folderStatus[folderCard.folderId] || ({})
                            readonly property var stats: root.folderStats[folderCard.folderId] || ({})
                            readonly property string state: root.folderState(folderCard.folderId)
                            readonly property bool showDetail: root.openFolder === folderCard.folderId
                            current: folderCard.showDetail

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                StatusDot {
                                    state: folderCard.state
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PlasmaComponents.Label {
                                        text: folderCard.modelData.label || folderCard.folderId
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: root.folderStateText(folderCard.folderId)
                                        font: Kirigami.Theme.smallFont
                                        color: folderCard.state === "error"
                                            ? Kirigami.Theme.negativeTextColor
                                            : Kirigami.Theme.textColor
                                        opacity: folderCard.state === "error" ? 1 : 0.65
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                PlasmaComponents.Label {
                                    visible: folderCard.state === "busy" && Number(folderCard.status.needBytes || 0) > 0
                                    text: i18n("%1%", Math.floor(root.folderPercent(folderCard.folderId)))
                                    font.weight: Font.DemiBold
                                    color: Kirigami.Theme.neutralTextColor
                                }

                                RowLayout {
                                    id: folderActions
                                    visible: folderCard.showDetail
                                    spacing: 0

                                    QQC2.ToolButton {
                                        text: i18n("Open")
                                        icon.name: "folder-open"
                                        display: QQC2.AbstractButton.IconOnly
                                        Accessible.name: text
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.delay: 400
                                        QQC2.ToolTip.text: text
                                        onClicked: root.openFolderPath(folderCard.modelData.path)
                                    }
                                    QQC2.ToolButton {
                                        text: i18n("Rescan")
                                        icon.name: "view-refresh"
                                        display: QQC2.AbstractButton.IconOnly
                                        enabled: !folderCard.modelData.paused
                                        Accessible.name: text
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.delay: 400
                                        QQC2.ToolTip.text: text
                                        onClicked: root.rescanFolder(folderCard.folderId)
                                    }
                                    QQC2.ToolButton {
                                        text: folderCard.modelData.paused ? i18n("Resume") : i18n("Pause")
                                        icon.name: folderCard.modelData.paused ? "media-playback-start" : "media-playback-pause"
                                        display: QQC2.AbstractButton.IconOnly
                                        Accessible.name: text
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.delay: 400
                                        QQC2.ToolTip.text: text
                                        onClicked: root.setFolderPaused(folderCard.folderId, !folderCard.modelData.paused)
                                    }
                                }

                                Kirigami.Separator {
                                    visible: folderCard.showDetail
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Kirigami.Icon {
                                    source: folderCard.showDetail ? "go-down" : "go-next"
                                    opacity: 0.6
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                TapHandler {
                                    id: folderTapHandler
                                    onTapped: {
                                        var position = folderTapHandler.point.position
                                        if (folderActions.visible
                                                && position.x >= folderActions.x
                                                && position.x <= folderActions.x + folderActions.width)
                                            return
                                        root.openFolder = folderCard.showDetail ? "" : folderCard.folderId
                                        if (root.openFolder === folderCard.folderId && folderCard.state === "busy")
                                            root.refreshFolderNeed(folderCard.folderId)
                                    }
                                }
                            }

                            QQC2.ProgressBar {
                                visible: folderCard.state === "busy" && Number(folderCard.status.needBytes || 0) > 0
                                from: 0
                                to: 100
                                value: root.folderPercent(folderCard.folderId)
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                visible: folderCard.showDetail
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: 2

                                Kirigami.Separator { Layout.fillWidth: true }
                                DetailRow {
                                    label: i18n("Path")
                                    value: folderCard.modelData.path || ""
                                }
                                DetailRow {
                                    label: i18n("Mode")
                                    value: root.folderTypeText(folderCard.modelData.type)
                                }
                                DetailRow {
                                    label: i18n("Content")
                                    value: i18n("%1 in %2 files",
                                        root.formatBytes(folderCard.status.localBytes),
                                        root.formatNumber(folderCard.status.localFiles))
                                }
                                DetailRow {
                                    visible: Number(folderCard.status.needTotalItems || 0) > 0
                                    label: i18n("Remaining")
                                    value: i18n("%1 in %2 items",
                                        root.formatBytes(folderCard.status.needBytes),
                                        root.formatNumber(folderCard.status.needTotalItems))
                                }
                                ColumnLayout {
                                    readonly property var queueItems: root.folderNeedItems[folderCard.folderId] || []
                                    visible: folderCard.state === "busy"
                                        && (root.folderNeedLoading[folderCard.folderId] || queueItems.length > 0)
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    spacing: 2

                                    PlasmaComponents.Label {
                                        text: i18n("Sync queue")
                                        font.weight: Font.DemiBold
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.75
                                    }
                                    QQC2.ProgressBar {
                                        visible: root.folderNeedLoading[folderCard.folderId] === true
                                        indeterminate: true
                                        Layout.fillWidth: true
                                    }
                                    Repeater {
                                        model: parent.queueItems
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing
                                            PlasmaComponents.Label {
                                                text: modelData.stage
                                                font: Kirigami.Theme.smallFont
                                                opacity: 0.55
                                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                                            }
                                            PlasmaComponents.Label {
                                                text: modelData.name
                                                font: Kirigami.Theme.smallFont
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                            }
                                            PlasmaComponents.Label {
                                                text: root.formatBytes(modelData.size)
                                                font: Kirigami.Theme.smallFont
                                                opacity: 0.65
                                            }
                                        }
                                    }
                                }
                                DetailRow {
                                    label: i18n("Shared with")
                                    value: folderCard.sharedWith()
                                }
                                DetailRow {
                                    label: i18n("Last scan")
                                    value: root.formatWhen(folderCard.stats.lastScan)
                                }
                                DetailRow {
                                    visible: !!(folderCard.stats.lastFile && folderCard.stats.lastFile.filename)
                                    label: i18n("Last change")
                                    value: folderCard.stats.lastFile
                                        ? i18n("%1 · %2",
                                            String(folderCard.stats.lastFile.filename).split("/").pop(),
                                            root.formatWhen(folderCard.stats.lastFile.at))
                                        : ""
                                }

                                Repeater {
                                    model: (root.folderErrors[folderCard.folderId] || []).slice(0, 4)
                                    delegate: PlasmaComponents.Label {
                                        required property var modelData
                                        text: i18n("%1 — %2", modelData.path, modelData.error)
                                        color: Kirigami.Theme.negativeTextColor
                                        font: Kirigami.Theme.smallFont
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }
                                }
                                PlasmaComponents.Label {
                                    readonly property int extra: (root.folderErrors[folderCard.folderId] || []).length - 4
                                    visible: extra > 0
                                    text: i18np("%1 more failed item", "%1 more failed items", extra)
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                    Layout.fillWidth: true
                                }

                            }

                            function sharedWith() {
                                var names = []
                                var shared = folderCard.modelData.devices || []
                                for (var i = 0; i < shared.length; ++i) {
                                    if (shared[i].deviceID === root.myId) continue
                                    names.push(root.deviceName(shared[i].deviceID))
                                }
                                return names.length > 0 ? names.join(", ") : i18n("nobody")
                            }
                        }
                    }

                    SectionHeader { title: i18n("Devices") }

                    PlasmaComponents.Label {
                        visible: root.remoteDevices.length === 0
                        text: i18n("No remote devices are configured.")
                        opacity: 0.6
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                    }

                    Repeater {
                        model: root.remoteDevices
                        delegate: RowCard {
                            id: deviceCard
                            required property var modelData
                            readonly property string deviceId: deviceCard.modelData.deviceID
                            readonly property var connection: root.deviceConnections[deviceCard.deviceId] || ({})
                            readonly property var completion: root.deviceCompletion[deviceCard.deviceId] || ({})
                            readonly property var stats: root.deviceStats[deviceCard.deviceId] || ({})
                            readonly property bool showDetail: root.openDevice === deviceCard.deviceId
                            readonly property string state: root.deviceState(deviceCard.modelData)
                            current: deviceCard.showDetail

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                StatusDot {
                                    state: deviceCard.state === "offline" ? "unknown" : deviceCard.state
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    PlasmaComponents.Label {
                                        text: deviceCard.modelData.name || deviceCard.deviceId.slice(0, 7)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents.Label {
                                        text: root.deviceStatusText(deviceCard.modelData)
                                        font: Kirigami.Theme.smallFont
                                        color: deviceCard.state === "stale"
                                            ? Kirigami.Theme.neutralTextColor
                                            : Kirigami.Theme.textColor
                                        opacity: deviceCard.state === "stale" ? 1 : 0.65
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                QQC2.ToolButton {
                                    id: devicePauseButton
                                    visible: deviceCard.showDetail
                                    text: deviceCard.modelData.paused ? i18n("Resume") : i18n("Pause")
                                    icon.name: deviceCard.modelData.paused ? "media-playback-start" : "media-playback-pause"
                                    display: QQC2.AbstractButton.IconOnly
                                    Accessible.name: text
                                    QQC2.ToolTip.visible: hovered
                                    QQC2.ToolTip.delay: 400
                                    QQC2.ToolTip.text: text
                                    onClicked: root.setDevicePaused(deviceCard.deviceId, !deviceCard.modelData.paused)
                                }

                                Kirigami.Separator {
                                    visible: deviceCard.showDetail
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Kirigami.Icon {
                                    source: deviceCard.showDetail ? "go-down" : "go-next"
                                    opacity: 0.6
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                TapHandler {
                                    id: deviceTapHandler
                                    onTapped: {
                                        var position = deviceTapHandler.point.position
                                        if (devicePauseButton.visible
                                                && position.x >= devicePauseButton.x
                                                && position.x <= devicePauseButton.x + devicePauseButton.width)
                                            return
                                        root.openDevice = deviceCard.showDetail ? "" : deviceCard.deviceId
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: deviceCard.showDetail
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: 2

                                Kirigami.Separator { Layout.fillWidth: true }
                                DetailRow {
                                    visible: !!deviceCard.connection.address
                                    label: i18n("Address")
                                    value: i18n("%1 · %2",
                                        deviceCard.connection.address || "",
                                        deviceCard.connection.type || "")
                                }
                                DetailRow {
                                    visible: !!deviceCard.connection.clientVersion
                                    label: i18n("Version")
                                    value: deviceCard.connection.clientVersion || ""
                                }
                                DetailRow {
                                    label: i18n("Transferred")
                                    value: i18n("%1 in · %2 out",
                                        root.formatBytes(deviceCard.connection.inBytesTotal),
                                        root.formatBytes(deviceCard.connection.outBytesTotal))
                                }
                                DetailRow {
                                    visible: deviceCard.completion.completion !== undefined
                                    label: i18n("In sync")
                                    value: i18n("%1%", Math.floor(Number(deviceCard.completion.completion || 0)))
                                }
                                DetailRow {
                                    label: i18n("Last seen")
                                    value: root.validTimestamp(deviceCard.stats.lastSeen)
                                        ? root.formatWhen(deviceCard.stats.lastSeen)
                                        : i18n("never")
                                }
                                DetailRow {
                                    visible: Number(deviceCard.stats.lastConnectionDurationS || 0) > 0
                                    label: i18n("Last connection")
                                    value: root.formatDuration(deviceCard.stats.lastConnectionDurationS)
                                }
                                DetailRow {
                                    label: i18n("Device ID")
                                    value: deviceCard.deviceId.slice(0, 7)
                                }

                            }
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: root.versionText !== ""
                        ? i18n("Syncthing %1 · up %2", root.versionText, root.formatUptime(root.uptimeSeconds))
                        : i18n("Not connected")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    visible: root.myId !== ""
                    text: root.deviceName(root.myId)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }
        }
    }
}
