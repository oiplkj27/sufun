// SUFUN 하드웨어 점검: the guided input test, started by /usr/bin/sufun-hwcheck.
// Four rows (pointer, touch screen, pen, keyboard); a row turns green when an
// event of that kind arrives. This window changes nothing and stores nothing
// (no key names, no positions): at the end it prints one line
//     SUFUN-INPUT pointer=1 touch=0 pen=0 key=1
// and quits. It ends when you press "끝 / Done", close the window, or after 60 s.
// Argument "selfcheck=1" (CI test): ends by itself after 3 s.
import QtQuick
import QtQuick.Controls
import QtQuick.Window

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "SUFUN 하드웨어 점검"
    color: "#f3f3f3"
    font.pointSize: 14
    // Light look with dark text, whatever the system's dark/light setting is
    palette.window: "#f3f3f3"
    palette.windowText: "#1b1b1b"
    palette.button: "#fbfbfb"
    palette.buttonText: "#1b1b1b"

    property bool pointer: false
    property bool touch: false
    property bool pen: false
    property bool key: false
    property int secondsLeft: 60
    property bool finished: false
    // Where the pointer was first seen: a window that opens under a resting
    // pointer must not count as "the pointer moved".
    property bool haveStart: false
    property real startX: 0
    property real startY: 0
    // Qt turns a finger or pen that nothing "took" into a made-up mouse event.
    // So pointer events right after a touch/pen event do not count as the pointer.
    property double lastOther: 0
    function other() { lastOther = Date.now(); }
    function fromPointer() { return Date.now() - lastOther > 700; }

    // A finger tap on the Done button reaches us as a mouse click: not counted either.
    function overButton(x, y) {
        var p = doneButton.mapFromItem(area, x, y);
        return doneButton.contains(p);
    }

    function moved(x, y) {
        if (!fromPointer() || overButton(x, y)) {
            haveStart = false;
            return;
        }
        if (!haveStart) {
            haveStart = true; startX = x; startY = y;
            return;
        }
        if (Math.abs(x - startX) + Math.abs(y - startY) > 12)
            pointer = true;
    }
    function finish() {
        if (finished)
            return;
        finished = true;
        // One line on stderr (QT_MESSAGE_PATTERN=%{message}), read by sufun-hwcheck
        console.info("SUFUN-INPUT pointer=" + (pointer ? 1 : 0) + " touch=" + (touch ? 1 : 0)
                     + " pen=" + (pen ? 1 : 0) + " key=" + (key ? 1 : 0));
        Qt.quit();
    }
    onClosing: finish()

    Component.onCompleted: {
        Qt.styleHints.colorScheme = Qt.ColorScheme.Light;
        var args = Qt.application.arguments;
        for (var i = 0; i < args.length; i++)
            if (args[i] === "selfcheck=1")
                secondsLeft = 3;
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            win.secondsLeft--;
            if (win.secondsLeft <= 0)
                win.finish();
        }
    }

    // One row of the list: grey = nothing seen yet, green = seen
    component CheckRow: Rectangle {
        property string label: ""
        property bool on: false
        width: parent.width
        height: 76
        radius: 10
        color: on ? "#2f9e44" : "#ffffff"
        border.color: on ? "#2b8a3e" : "#c8c8c8"
        border.width: 1
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 24
            text: parent.label
            font.pointSize: 16
            color: parent.on ? "#ffffff" : "#1b1b1b"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right; anchors.rightMargin: 24
            text: parent.on ? "확인됨 / OK" : "기다리는 중 / waiting"
            font.pointSize: 14
            color: parent.on ? "#ffffff" : "#6b6b6b"
        }
    }

    Item {
        id: area
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => { win.key = true; event.accepted = true; }

        // Touchpad or mouse: moving the pointer, or a click
        HoverHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onPointChanged: win.moved(point.position.x, point.position.y)
        }
        PointHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            acceptedButtons: Qt.AllButtons
            target: null
            onActiveChanged: {
                if (active && win.fromPointer() && !win.overButton(point.position.x, point.position.y))
                    win.pointer = true;
            }
        }
        // Finger on the screen
        PointHandler {
            acceptedDevices: PointerDevice.TouchScreen
            target: null
            onActiveChanged: { win.other(); if (active) win.touch = true; }
            onPointChanged: win.other()
        }
        // Pen: touching the screen, or hovering just above it
        PointHandler {
            acceptedDevices: PointerDevice.Stylus
            target: null
            onActiveChanged: { win.other(); if (active) win.pen = true; }
            onPointChanged: win.other()
        }
        HoverHandler {
            acceptedDevices: PointerDevice.Stylus
            onHoveredChanged: { win.other(); if (hovered) win.pen = true; }
            onPointChanged: win.other()
        }
        // These two "take" the finger/pen press, so Qt does not make a mouse event of it
        TapHandler {
            acceptedDevices: PointerDevice.TouchScreen
            gesturePolicy: TapHandler.WithinBounds
            onPressedChanged: { win.other(); if (pressed) win.touch = true; }
        }
        TapHandler {
            acceptedDevices: PointerDevice.Stylus
            gesturePolicy: TapHandler.WithinBounds
            onPressedChanged: { win.other(); if (pressed) win.pen = true; }
        }

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 760)
            spacing: 14

            Text {
                width: parent.width
                text: "입력 장치 테스트 / Input test"
                font.pointSize: 22; font.bold: true
                color: "#1b1b1b"
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "터치패드를 움직이고, 화면을 손가락으로 누르고, 펜으로 화면을 누르고, 키보드의 아무 키나 누르세요.\n"
                      + "없는 장치는 그냥 두면 됩니다. 다 했으면 [끝]을 누르세요.\n"
                      + "Move the touchpad, touch the screen, tap with the pen, press any key. Then press Done."
                font.pointSize: 13
                color: "#3b3b3b"
            }
            CheckRow { label: "터치패드/마우스 포인터 / Pointer"; on: win.pointer }
            CheckRow { label: "터치 스크린 / Touch screen"; on: win.touch }
            CheckRow { label: "펜 / Pen"; on: win.pen }
            CheckRow { label: "키보드 / Keyboard"; on: win.key }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.secondsLeft + "초 뒤 자동으로 끝납니다 / ends in " + win.secondsLeft + " s"
                font.pointSize: 12
                color: "#6b6b6b"
            }
            Button {
                id: doneButton
                anchors.horizontalCenter: parent.horizontalCenter
                width: 320; height: 84
                text: "끝 / Done"
                font.pointSize: 20; font.bold: true
                focusPolicy: Qt.NoFocus      // keys keep going to the test, not to the button
                onClicked: win.finish()
            }
        }
    }
}
