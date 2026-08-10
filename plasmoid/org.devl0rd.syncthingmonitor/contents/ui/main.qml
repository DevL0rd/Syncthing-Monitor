pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
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
    property var deviceCompletion: ({})
    property var deviceConnections: ({})
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
    property var eventRequest: null
    property string openFolder: ""
    property string openDevice: ""
    property var pendingFolders: ({})
    property bool pendingConfig: false
    property bool pendingConnections: false
    property bool pendingCompletion: false

    readonly property var remoteDevices: root.devices.filter(function(device) { return device.deviceID !== root.myId })
    readonly property int connectedDevices: root.countConnectedDevices()
    readonly property int errorFolders: root.countFolders("error")
    readonly property int busyFolders: root.countFolders("busy")
    readonly property int pausedFolders: root.countFolders("paused")
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
        : root.errorFolders > 0 ? "error"
        : root.busyFolders > 0 ? "syncing"
        : root.folders.length === 0 ? "empty"
        : root.pausedFolders === root.folders.length ? "paused"
        : "ok"

    readonly property color stateColor: root.colorForState(root.overallState)

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
        }
    ]

    function urlToPath(value) {
        return String(value).replace(/^file:\/\//, "")
    }

    function colorForState(state) {
        switch (state) {
        case "ok": return Kirigami.Theme.positiveTextColor
        case "busy":
        case "syncing": return Kirigami.Theme.neutralTextColor
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
        case "error": return i18np("%1 folder needs attention", "%1 folders need attention", root.errorFolders)
        case "syncing": return i18n("Syncing · %1%", Math.floor(root.overallPercent))
        case "paused": return i18n("Every folder is paused")
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
        if (root.totalNeedBytes > 0)
            parts.push(i18n("%1 left", root.formatBytes(root.totalNeedBytes)))
        else if (root.totalNeedItems > 0)
            parts.push(i18np("%1 item left", "%1 items left", root.totalNeedItems))
        if (root.pausedFolders > 0 && root.overallState !== "paused")
            parts.push(i18np("%1 paused", "%1 paused", root.pausedFolders))
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

    function api(method, path, done, payload) {
        if (root.baseUrl === "") return
        var request = new XMLHttpRequest()
        request.open(method, root.baseUrl + path)
        request.setRequestHeader("X-API-Key", root.apiKey)
        if (payload !== undefined) request.setRequestHeader("Content-Type", "application/json")
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            if (request.status >= 200 && request.status < 300) {
                root.reachable = true
                root.lastError = ""
                var data = null
                try { data = JSON.parse(request.responseText || "null") } catch (error) { data = null }
                if (done) done(data)
            } else if (request.status === 0) {
                root.reachable = false
                root.lastError = i18n("Cannot reach %1", root.baseUrl)
            } else {
                root.lastError = request.status === 403
                    ? i18n("The API key was rejected")
                    : i18n("Syncthing returned HTTP %1", request.status)
            }
        }
        request.send(payload === undefined ? null : JSON.stringify(payload))
    }

    function refreshConfig() {
        root.api("GET", "/rest/config/folders", function(data) {
            root.folders = data || []
            for (var i = 0; i < root.folders.length; ++i) root.refreshFolder(root.folders[i].id)
        })
        root.api("GET", "/rest/config/devices", function(data) { root.devices = data || [] })
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

    function pollEvents() {
        if (root.baseUrl === "") return
        if (root.lastEventId === 0) {
            root.api("GET", "/rest/events?limit=1", function(data) {
                if (data && data.length > 0) root.lastEventId = Number(data[data.length - 1].id || 0)
                root.waitForEvents()
            })
            return
        }
        root.waitForEvents()
    }

    function waitForEvents() {
        var request = new XMLHttpRequest()
        root.eventRequest = request
        request.open("GET", root.baseUrl + "/rest/events?since=" + root.lastEventId + "&timeout=55")
        request.setRequestHeader("X-API-Key", root.apiKey)
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            root.eventRequest = null
            if (request.status >= 200 && request.status < 300) {
                root.reachable = true
                root.lastError = ""
                var events = null
                try { events = JSON.parse(request.responseText || "[]") } catch (error) { events = [] }
                root.handleEvents(events || [])
                root.waitForEvents()
            } else {
                root.reachable = false
                root.lastEventId = 0
                root.lastError = request.status === 0
                    ? i18n("Cannot reach %1", root.baseUrl)
                    : i18n("Syncthing returned HTTP %1", request.status)
                reconnectTimer.restart()
            }
        }
        request.send()
    }

    function handleEvents(events) {
        for (var i = 0; i < events.length; ++i) {
            var event = events[i]
            var id = Number(event.id || 0)
            if (id > root.lastEventId) root.lastEventId = id
            var data = event.data || ({})
            switch (event.type) {
            case "FolderSummary":
                if (data.folder && data.summary)
                    root.folderStatus = root.withEntry(root.folderStatus, data.folder, data.summary)
                break
            case "FolderErrors":
                if (data.folder)
                    root.folderErrors = root.withEntry(root.folderErrors, data.folder, data.errors || [])
                break
            case "StateChanged":
            case "FolderScanProgress":
            case "DownloadProgress":
            case "LocalIndexUpdated":
            case "RemoteIndexUpdated":
            case "LocalChangeDetected":
            case "RemoteChangeDetected":
            case "FolderWatchStateChanged":
                if (data.folder) root.pendingFolders = root.withEntry(root.pendingFolders, data.folder, true)
                root.pendingStats = true
                break
            case "FolderCompletion":
                root.pendingCompletion = true
                break
            case "DeviceConnected":
            case "DeviceDisconnected":
            case "DevicePaused":
            case "DeviceResumed":
                root.pendingConnections = true
                root.pendingCompletion = true
                break
            case "ConfigSaved":
            case "FolderPaused":
            case "FolderResumed":
                root.pendingConfig = true
                break
            case "Starting":
            case "StartupComplete":
                root.pendingConfig = true
                root.pendingConnections = true
                break
            }
        }
        if (events.length > 0) refreshTimer.restart()
    }

    property bool pendingStats: false

    function applyPending() {
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

    Component.onCompleted: root.connect()
    Component.onDestruction: if (root.eventRequest) root.eventRequest.abort()

    Connections {
        target: plasmoid.configuration
        function onServerUrlChanged() { root.reconnect() }
        function onApiKeyChanged() { root.reconnect() }
    }

    function reconnect() {
        if (root.eventRequest) root.eventRequest.abort()
        root.eventRequest = null
        root.lastEventId = 0
        root.reachable = false
        root.connect()
    }

    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.applyPending()
    }

    Timer {
        id: reconnectTimer
        interval: 5000
        onTriggered: root.connect()
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
        running: root.expanded && root.reachable
        onTriggered: {
            root.refreshSystem()
            root.refreshStats()
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
                running: root.overallState === "syncing"
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

    component StatTile: ColumnLayout {
        id: tile
        property string label: ""
        property string value: ""
        property string iconName: ""
        property color valueColor: Kirigami.Theme.textColor
        Layout.fillWidth: true
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
            Layout.alignment: Qt.AlignHCenter
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
                spacing: Kirigami.Units.smallSpacing
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
                    iconName: root.totalFailedItems > 0 ? "dialog-warning" : "checkmark"
                    value: root.totalFailedItems > 0
                        ? root.formatNumber(root.totalFailedItems)
                        : root.totalNeedItems > 0 ? root.formatNumber(root.totalNeedItems) : "0"
                    valueColor: root.totalFailedItems > 0
                        ? Kirigami.Theme.negativeTextColor
                        : root.totalNeedItems > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    label: root.totalFailedItems > 0 ? i18n("Failed") : i18n("Pending")
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

                                Kirigami.Icon {
                                    source: folderCard.showDetail ? "go-down" : "go-next"
                                    opacity: 0.6
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                TapHandler {
                                    onTapped: root.openFolder = folderCard.showDetail ? "" : folderCard.folderId
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

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    QQC2.Button {
                                        text: i18n("Open")
                                        icon.name: "folder-open"
                                        onClicked: root.openFolderPath(folderCard.modelData.path)
                                    }
                                    QQC2.Button {
                                        text: i18n("Rescan")
                                        icon.name: "view-refresh"
                                        enabled: !folderCard.modelData.paused
                                        onClicked: root.rescanFolder(folderCard.folderId)
                                    }
                                    Item { Layout.fillWidth: true }
                                    QQC2.Button {
                                        text: folderCard.modelData.paused ? i18n("Resume") : i18n("Pause")
                                        icon.name: folderCard.modelData.paused ? "media-playback-start" : "media-playback-pause"
                                        onClicked: root.setFolderPaused(folderCard.folderId, !folderCard.modelData.paused)
                                    }
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
                            readonly property bool showDetail: root.openDevice === deviceCard.deviceId
                            readonly property string state: deviceCard.modelData.paused
                                ? "paused"
                                : !deviceCard.connection.connected ? "offline"
                                : Number(deviceCard.completion.needBytes || 0) > 0 ? "busy"
                                : "ok"
                            current: deviceCard.showDetail

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                StatusDot {
                                    state: deviceCard.state === "offline" ? "unknown" : deviceCard.state
                                    Layout.alignment: Qt.AlignVCenter
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
                                        text: deviceCard.modelData.paused
                                            ? i18n("Paused")
                                            : deviceCard.connection.connected
                                                ? (Number(deviceCard.completion.needBytes || 0) > 0
                                                    ? i18n("Syncing · %1 left", root.formatBytes(deviceCard.completion.needBytes))
                                                    : i18n("Connected · up to date"))
                                                : i18n("Disconnected")
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.65
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Kirigami.Icon {
                                    source: deviceCard.showDetail ? "go-down" : "go-next"
                                    opacity: 0.6
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                }

                                TapHandler {
                                    onTapped: root.openDevice = deviceCard.showDetail ? "" : deviceCard.deviceId
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
                                    label: i18n("Device ID")
                                    value: deviceCard.deviceId.slice(0, 7)
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    Item { Layout.fillWidth: true }
                                    QQC2.Button {
                                        text: deviceCard.modelData.paused ? i18n("Resume") : i18n("Pause")
                                        icon.name: deviceCard.modelData.paused ? "media-playback-start" : "media-playback-pause"
                                        onClicked: root.setDevicePaused(deviceCard.deviceId, !deviceCard.modelData.paused)
                                    }
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
