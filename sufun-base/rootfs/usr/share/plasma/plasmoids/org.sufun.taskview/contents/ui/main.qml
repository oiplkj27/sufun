// SUFUN Task View button (like the Windows 11 taskbar button next to search).
// Opens KWin's Overview: all open windows and desktops (also Win+Tab / Win+W).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property bool korean: Qt.locale().name.startsWith("ko")

    // The button is the "full representation" shown directly in the panel (like
    // Plasma's Show Desktop button). A compact-only widget would show nothing:
    // Plasma 6 treats a widget without a full representation as "always expanded".
    preferredRepresentation: fullRepresentation
    toolTipMainText: korean ? "작업 보기" : "Task View"
    toolTipSubText: korean ? "열린 창과 데스크톱 보기 (Win+Tab)" : "See open windows and desktops (Win+Tab)"

    function openOverview() {
        // D-Bus: ask the shortcut service to run KWin's "Overview" action
        DBus.SessionBus.asyncCall({
            "service": "org.kde.kglobalaccel",
            "path": "/component/kwin",
            "iface": "org.kde.kglobalaccel.Component",
            "member": "invokeShortcut",
            "arguments": [new DBus.string("Overview")],
            "signature": "s"
        });
    }

    fullRepresentation: MouseArea {
        id: button

        Layout.minimumWidth: height
        Layout.preferredWidth: height
        Layout.maximumWidth: height
        Layout.fillHeight: true

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.toolTipMainText
        onClicked: root.openOverview()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.openOverview();
            }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(Math.min(parent.width, parent.height) * 0.6)
            height: width
            // Two windows on top of each other = "show all windows" (Fluent's glyph,
            // installed by sufun-base as a hicolor icon so it works with any icon theme).
            // Fluent's "multitasking-view" looked like a network icon.
            source: "sufun-taskview"
            fallback: "window-duplicate"
            active: button.containsMouse
        }
    }
}
