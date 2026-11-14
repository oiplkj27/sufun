// SUFUN tray toggle: screen rotation lock (like Windows' quick setting).
// Tap the icon = lock / unlock. The rule is in /usr/lib/sufun/input-switch:
// cover open = always landscape; tablet mode = turns with the device unless locked.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    property bool locked: false
    readonly property bool korean: Qt.locale().name.startsWith("ko")
    readonly property string title: korean ? "화면 회전 잠금" : "Rotation lock"
    readonly property string stateText: locked ? (korean ? "켜짐: 화면이 돌아가지 않습니다" : "On: the screen does not rotate")
                                               : (korean ? "꺼짐: 태블릿 모드에서 화면이 돌아갑니다" : "Off: the screen rotates in tablet mode")

    Plasmoid.icon: locked ? "rotation-locked" : "rotation-allowed"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: title
    toolTipSubText: stateText
    preferredRepresentation: compactRepresentation

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            root.locked = (data["stdout"] || "").trim() === "locked";
            disconnectSource(source);
        }
    }
    function run(arg) { exec.connectSource("/usr/lib/sufun/rotation-lock " + arg); }
    Component.onCompleted: run("status")

    compactRepresentation: MouseArea {
        onClicked: root.run("toggle")
        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: parent.containsMouse
        }
        hoverEnabled: true
    }
    fullRepresentation: ColumnLayout {
        PlasmaComponents.Switch {
            text: root.title
            checked: root.locked
            onToggled: root.run("toggle")
        }
        PlasmaComponents.Label { text: root.stateText; opacity: 0.7 }
    }
}
