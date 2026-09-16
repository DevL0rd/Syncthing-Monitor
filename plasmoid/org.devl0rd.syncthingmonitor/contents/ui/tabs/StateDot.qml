import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: dot

    property string kind
    property real diameter: Kirigami.Units.smallSpacing * 2

    width: diameter
    height: diameter
    radius: diameter / 2
    color: root.colorForState(kind)
    Behavior on color { ColorAnimation { duration: 280 } }
}
