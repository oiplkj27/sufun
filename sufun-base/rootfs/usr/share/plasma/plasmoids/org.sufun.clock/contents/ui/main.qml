// SUFUN clock: two lines like Windows 11, right-aligned, same font size.
//   Korean:  오전 2:33      English:  2:33 AM
//            2026-11-12              2026-11-12
// Plasma's own Digital Clock can't do this: it always puts AM/PM after the
// time, draws the date smaller, and centers both lines.
// Click: opens Plasma's calendar (the same month view the Digital Clock uses).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.clock
import org.kde.plasma.workspace.calendar as PlasmaCalendar

PlasmoidItem {
    id: root

    // System time and time zone (follows changes, like Plasma's clock)
    Clock {
        id: clock
    }

    readonly property bool korean: Qt.locale().name.startsWith("ko")
    // 12-hour, no seconds. "AP" = the language's AM/PM word (오전/오후, AM/PM).
    readonly property string timeText: Qt.locale().toString(clock.dateTime, korean ? "AP h:mm" : "h:mm AP")
    readonly property string dateText: Qt.formatDate(clock.dateTime, "yyyy-MM-dd")

    preferredRepresentation: compactRepresentation
    toolTipMainText: Qt.locale().toString(clock.dateTime, Qt.locale().dateFormat(Locale.LongFormat))
    toolTipSubText: ""

    compactRepresentation: MouseArea {
        id: compact

        readonly property int sidePadding: Kirigami.Units.smallSpacing * 2

        Layout.minimumWidth: Math.ceil(Math.max(timeLabel.implicitWidth, dateLabel.implicitWidth)) + 2 * sidePadding
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true

        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.timeText + " " + root.dateText

        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.expanded = !root.expanded;
            }
        }

        ColumnLayout {
            anchors.right: parent.right
            anchors.rightMargin: compact.sidePadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            // Both labels use the default font (Selawik), so both lines are the same size.
            PlasmaComponents.Label {
                id: timeLabel
                Layout.alignment: Qt.AlignRight
                horizontalAlignment: Text.AlignRight
                text: root.timeText
                textFormat: Text.PlainText
            }
            PlasmaComponents.Label {
                id: dateLabel
                Layout.alignment: Qt.AlignRight
                horizontalAlignment: Text.AlignRight
                text: root.dateText
                textFormat: Text.PlainText
            }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        PlasmaCalendar.EventPluginsManager {
            id: eventPluginsManager
        }

        PlasmaCalendar.MonthView {
            id: monthView
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            borderOpacity: 0.25
            eventPluginsManager: eventPluginsManager
            today: clock.dateTime
            firstDayOfWeek: Qt.locale().firstDayOfWeek
            showWeekNumbers: false
        }

        // Always open on the current month
        Connections {
            target: root
            function onExpandedChanged() {
                if (root.expanded) {
                    monthView.resetToToday();
                }
            }
        }
    }
}
