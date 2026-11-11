// SUFUN search box: looks like the "검색" field on the Windows 11 taskbar.
// Clicking it opens KRunner, Plasma's search for apps, recent files, folders,
// settings and a calculator (the same window as Alt+Space and Win+R).
// No typing happens in the panel itself: KRunner takes the keyboard focus.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property bool korean: Qt.locale().name.startsWith("ko")
    readonly property string label: korean ? "검색" : "Search"

    preferredRepresentation: compactRepresentation
    toolTipMainText: label
    toolTipSubText: korean ? "앱, 파일, 설정을 찾습니다" : "Find apps, files and settings"

    function openSearch() {
        // D-Bus: org.kde.krunner /App org.kde.krunner.App.display()
        DBus.SessionBus.asyncCall({
            "service": "org.kde.krunner",
            "path": "/App",
            "iface": "org.kde.krunner.App",
            "member": "display",
            "arguments": [],
            "signature": ""
        });
    }

    compactRepresentation: MouseArea {
        id: box

        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.label
        onClicked: root.openSearch()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.openSearch();
            }
        }

        // The "text field": a plain light pill with a thin border (no blur, no shadow)
        Rectangle {
            id: field
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            anchors.verticalCenter: parent.verticalCenter
            height: Math.min(parent.height - 2 * Kirigami.Units.smallSpacing, Math.round(Kirigami.Units.gridUnit * 1.8))
            radius: height / 2

            Kirigami.Theme.colorSet: Kirigami.Theme.View
            Kirigami.Theme.inherit: false
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: box.containsMouse || box.activeFocus
                ? Kirigami.Theme.highlightColor
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "search"
                    fallback: "edit-find"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    opacity: 0.7
                }
            }
        }
    }
}
