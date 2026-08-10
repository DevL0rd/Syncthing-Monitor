import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_serverUrl: serverUrlField.text
    property alias cfg_apiKey: apiKeyField.text

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
}
