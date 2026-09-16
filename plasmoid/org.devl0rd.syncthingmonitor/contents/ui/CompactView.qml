import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import "lib"

MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real thickness: vertical ? width : height
    readonly property real valueSize: Math.max(Kirigami.Theme.smallFont.pixelSize, Math.min(Kirigami.Theme.defaultFont.pixelSize * 1.05, thickness * 0.4))
    readonly property string show: Plasmoid.configuration.compactShow
    readonly property bool connected: root.overallState !== "offline" && root.overallState !== "setup"
    readonly property bool showStatus: show === "status" && !vertical
    readonly property bool showRates: show === "rates" && !vertical
    property bool wasExpanded: false

    TextMetrics {
        id: percentMetrics
        font.pixelSize: compact.valueSize
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        text: "100%"
    }
    TextMetrics {
        id: rateMetrics
        font.pixelSize: compact.valueSize * 0.9
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        text: "88.88"
    }
    TextMetrics {
        id: rateUnitMetrics
        font.pixelSize: compact.valueSize * 0.68
        text: "kB/s"
    }

    component RateGroup: RowLayout {
        property string arrow
        property color arrowColor
        property real rate
        readonly property var parts: visible ? compact.rateParts(rate) : ({ number: "", unit: "" })
        Layout.alignment: Qt.AlignCenter
        spacing: 2
        PlasmaComponents.Label {
            text: parent.arrow
            color: parent.arrowColor
            font.pixelSize: compact.valueSize
            font.weight: Font.Bold
            Layout.alignment: Qt.AlignBaseline
        }
        PlasmaComponents.Label {
            text: compact.connected ? parent.parts.number : "—"
            horizontalAlignment: Text.AlignRight
            Layout.minimumWidth: Math.ceil(rateMetrics.advanceWidth)
            font.pixelSize: compact.valueSize * 0.9
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            Layout.alignment: Qt.AlignBaseline
        }
        PlasmaComponents.Label {
            text: compact.connected ? parent.parts.unit : ""
            Layout.minimumWidth: Math.ceil(rateUnitMetrics.advanceWidth)
            font.pixelSize: compact.valueSize * 0.68
            opacity: 0.6
            Layout.alignment: Qt.AlignBaseline
        }
    }

    function rateParts(value) {
        var text = root.formatBytes(value)
        var space = text.lastIndexOf(" ")
        return { number: text.slice(0, space), unit: text.slice(space + 1) + "/s" }
    }

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    onPressed: function(mouse) { wasExpanded = root.expanded }
    onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton)
            root.middleClick()
        else
            root.expanded = !wasExpanded
    }

    Layout.minimumWidth: vertical ? 0 : content.implicitWidth + Kirigami.Units.smallSpacing * 3
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: vertical ? content.implicitHeight + Kirigami.Units.smallSpacing * 3 : 0
    Layout.preferredHeight: Layout.minimumHeight

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(Kirigami.Theme.textColor, compact.containsMouse || root.expanded ? 0.08 : 0)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Sparkline {
        visible: compact.showRates && compact.connected
        anchors.fill: parent
        anchors.margins: 3
        opacity: 0.35
        values: visible ? root.series("in").slice(-40) : []
        values2: visible ? root.series("out").slice(-40) : []
        lineColor: root.downColor
        lineColor2: root.upColor
        gradient: false
        peakMarker: false
        hoverable: false
        rangeFloor: 1024
    }

    GridLayout {
        id: content
        anchors.centerIn: parent
        flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing * 1.5
        rowSpacing: Kirigami.Units.smallSpacing

        Item {
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: Math.round(compact.show === "icon" || compact.vertical
                ? Math.min(compact.thickness * 0.72, Kirigami.Units.iconSizes.medium)
                : compact.valueSize * 1.35)
            Layout.preferredHeight: Layout.preferredWidth

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

        ColumnLayout {
            visible: compact.showStatus
            Layout.alignment: Qt.AlignCenter
            spacing: 2

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                Layout.minimumWidth: Math.ceil(percentMetrics.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: !compact.connected ? "—"
                    : root.attentionCount > 0 ? i18n("%1 !", root.attentionCount)
                    : Math.floor(root.overallPercent) + "%"
                color: root.attentionCount > 0 && compact.connected ? Kirigami.Theme.negativeTextColor
                    : root.workActive ? Kirigami.Theme.neutralTextColor
                    : Kirigami.Theme.textColor
                font.pixelSize: compact.valueSize
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 2
                Rectangle {
                    anchors.fill: parent
                    radius: 1
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
                }
                Rectangle {
                    height: parent.height
                    radius: 1
                    width: parent.width * (compact.connected ? root.overallPercent / 100 : 0)
                    color: root.stateColor
                }
            }
        }

        RateGroup {
            visible: compact.showRates
            arrow: "↓"
            arrowColor: root.downColor
            rate: root.inRate
        }
        RateGroup {
            visible: compact.showRates
            arrow: "↑"
            arrowColor: root.upColor
            rate: root.outRate
        }
    }
}
