import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_serverUrl: serverUrlField.text
    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_offlineGraceHours: offlineGraceHours.value
    property alias cfg_notifySyncComplete: syncCompleteCheck.checked
    property alias cfg_notifyErrors: errorsCheck.checked
    property alias cfg_notifyInvitations: invitationsCheck.checked
    property alias cfg_notifyOfflineDevices: offlineCheck.checked

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Connection override")
        font.weight: Font.DemiBold
    }

    QQC2.TextField {
        id: serverUrlField
        Kirigami.FormData.label: i18n("Server address:")
        placeholderText: "http://127.0.0.1:8384"
        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
        selectByMouse: true
        Layout.fillWidth: true
    }

    QQC2.TextField {
        id: apiKeyField
        Kirigami.FormData.label: i18n("API key:")
        echoMode: QQC2.TextInput.Password
        selectByMouse: true
        Layout.fillWidth: true
    }

    QQC2.Label {
        text: i18n("Leave both fields empty to use the address and API key from the local Syncthing configuration automatically.")
        opacity: 0.7
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Device status")
        font.weight: Font.DemiBold
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Offline warning:")
        QQC2.SpinBox {
            id: offlineGraceHours
            from: 0
            to: 720
            editable: true
        }
        QQC2.Label { text: i18n("hours") }
    }

    QQC2.Label {
        text: i18n("After this long offline, a device is highlighted in the device list. Set 0 to disable the warning.")
        opacity: 0.7
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 24
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: i18n("Notifications")
        font.weight: Font.DemiBold
    }

    QQC2.CheckBox {
        id: syncCompleteCheck
        Kirigami.FormData.label: i18n("Notify when:")
        text: i18n("Synchronization completes")
    }
    QQC2.CheckBox {
        id: errorsCheck
        text: i18n("An error occurs")
    }
    QQC2.CheckBox {
        id: invitationsCheck
        text: i18n("A device or folder is offered")
    }
    QQC2.CheckBox {
        id: offlineCheck
        text: i18n("A device exceeds the offline warning time")
    }
}
