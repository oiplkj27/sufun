// SUFUN installer window (live system). Full screen, touch-friendly, like the
// Windows setup screens. It only SHOWS questions and sends answers: every check
// and every safety rule is in /usr/local/bin/sufun-install (root), which this
// window talks to:
//   reads   /run/sufun-install/q.json   the current question (written by the installer)
//           /run/sufun-install/status   what it is doing now
//           /run/sufun-install/tail     the last lines of its log ("자세히")
//   writes  "SUFUN-ANSWER <id> <value>" / "SUFUN-CANCEL" lines on stderr, which
//           /usr/local/bin/sufun-install-gui pipes into the installer.
// Typed confirmations (ERASE / YES) must be typed exactly; the installer checks
// the answer again itself.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "SUFUN 설치"
    color: "#f3f3f3"
    font.pointSize: 13
    // Light look with dark text, whatever the system's dark/light setting is
    palette.window: "#f3f3f3"
    palette.windowText: "#1b1b1b"
    palette.base: "#ffffff"
    palette.text: "#1b1b1b"
    palette.button: "#fbfbfb"
    palette.buttonText: "#1b1b1b"
    palette.placeholderText: "#6b6b6b"

    readonly property string ipc: "/run/sufun-install"
    property var q: null              // current question
    property int answered: 0          // id of the last answered question
    property string statusText: ""
    property string tailText: ""
    property bool showDetails: false
    property bool ko: q ? q.ko : true
    property string testMode: ""      // CI only: "cancel" (argument "test=cancel")
    readonly property real rowHeight: Math.max(52, fm.height * 2.6)
    readonly property bool waiting: !q || q.id === answered

    function t(k, e) { return ko ? k : e }
    FontMetrics { id: fm; font: win.font }

    function read(name, done) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE)
                done(x.responseText || "");
        };
        x.open("GET", "file://" + ipc + "/" + name);
        x.send();
    }
    function answer(value) {
        if (!q)
            return;
        var v = String(value).replace(/[\r\n]/g, " ");
        console.info("SUFUN-ANSWER " + q.id + " " + v);
        answered = q.id;
        if (q.type === "done" || q.type === "error" || q.type === "info")
            quitTimer.start();
    }
    function cancel() {
        console.info("SUFUN-CANCEL");
        quitTimer.start();
    }
    Timer { id: quitTimer; interval: 800; onTriggered: Qt.quit() }

    Component.onCompleted: {
        // Always the light look (our background is light), whatever the system says
        Qt.styleHints.colorScheme = Qt.ColorScheme.Light;
        var a = Qt.application.arguments;
        for (var i = 0; i < a.length; i++)
            if (a[i].indexOf("test=") === 0)
                testMode = a[i].substring(5);
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            win.read("q.json", function (text) {
                if (text.trim() === "")
                    return;
                try {
                    var n = JSON.parse(text);
                    if (!win.q || n.id !== win.q.id) {
                        win.q = n;
                        page.reset();
                        if (win.testMode === "cancel")
                            testTimer.start();
                    }
                } catch (e) { }
            });
            win.read("status", function (text) { win.statusText = text.trim(); });
            if (win.showDetails || win.waiting)
                win.read("tail", function (text) { win.tailText = text; });
        }
    }
    // CI test: show the first question for a screenshot, then cancel (nothing changes)
    Timer { id: testTimer; interval: 10000; onTriggered: { console.info("SUFUN-UI-SHOWN " + (win.q ? win.q.name : "")); win.cancel(); } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.round(win.rowHeight * 0.6)
        spacing: Math.round(win.rowHeight * 0.3)

        // --- title
        RowLayout {
            spacing: Math.round(win.rowHeight * 0.3)
            Image {
                source: "file:///usr/share/icons/hicolor/256x256/apps/sufun-logo.png"
                sourceSize.width: Math.round(win.rowHeight * 1.2)
                sourceSize.height: Math.round(win.rowHeight * 1.2)
                Layout.preferredWidth: Math.round(win.rowHeight * 1.2)
                Layout.preferredHeight: Math.round(win.rowHeight * 1.2)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: win.waiting ? (win.statusText !== "" ? win.statusText : win.t("SUFUN 설치", "Install SUFUN"))
                                      : win.q.title
                    font.pointSize: win.font.pointSize * 1.7
                    font.weight: Font.DemiBold
                }
                Label { text: win.t("SUFUN 설치 · Microsoft Surface Go 3", "Install SUFUN · Microsoft Surface Go 3"); opacity: 0.65 }
            }
        }

        // --- the question
        Flickable {
            id: page
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.implicitHeight
            visible: !win.waiting
            property string choice: ""
            property string text1: ""
            property string text2: ""
            function reset() {
                choice = win.q && win.q["default"] !== undefined ? String(win.q["default"]) : "";
                text1 = (win.q && win.q.type === "text") ? choice : "";
                text2 = "";
                contentY = 0;
            }
            readonly property bool valid: {
                if (!win.q) return false;
                switch (win.q.type) {
                case "choice": return choice !== "";
                case "text": return text1.trim() !== "";
                case "password": return text1 !== "" && text1 === text2;
                case "confirm": return text1 === win.q.word;
                default: return true;
                }
            }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                width: page.width
                spacing: Math.round(win.rowHeight * 0.25)

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    text: win.q ? win.q.text : ""
                    color: win.q && (win.q.type === "confirm" || win.q.type === "error") ? "#b00020" : palette.windowText
                    font.weight: win.q && win.q.type === "confirm" ? Font.DemiBold : Font.Normal
                }
                // disk list / partition table / log lines
                Rectangle {
                    Layout.fillWidth: true
                    visible: win.q && win.q.detail !== ""
                    implicitHeight: detailLabel.implicitHeight + 24
                    color: "#ffffff"; border.color: "#d0d0d0"; radius: 6
                    Label {
                        id: detailLabel
                        anchors.fill: parent; anchors.margins: 12
                        text: win.q ? win.q.detail : ""
                        font.family: "DejaVu Sans Mono"
                        font.pointSize: win.font.pointSize * 0.8
                        wrapMode: Text.WrapAnywhere
                    }
                }
                // choice
                Repeater {
                    model: win.q && win.q.type === "choice" ? win.q.options : []
                    delegate: ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: win.rowHeight
                        text: modelData.label
                        highlighted: page.choice === modelData.value
                        onClicked: page.choice = modelData.value
                    }
                }
                // text / password / typed confirmation
                TextField {
                    id: field1
                    Layout.fillWidth: true
                    Layout.preferredHeight: win.rowHeight
                    visible: win.q && (win.q.type === "text" || win.q.type === "password" || win.q.type === "confirm")
                    echoMode: win.q && win.q.type === "password" ? TextInput.Password : TextInput.Normal
                    placeholderText: !win.q ? "" : win.q.type === "password" ? win.t("암호", "Password")
                                     : win.q.type === "confirm" ? win.t(win.q.word + " 를 입력하세요", "Type " + win.q.word) : ""
                    text: page.text1
                    onTextEdited: page.text1 = text
                    inputMethodHints: win.q && win.q.type === "confirm" ? Qt.ImhNoPredictiveText | Qt.ImhUppercaseOnly : Qt.ImhNoPredictiveText
                    onVisibleChanged: if (visible) forceActiveFocus()
                    onAccepted: if (page.valid) nextButton.clicked()
                }
                TextField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: win.rowHeight
                    visible: win.q && win.q.type === "password"
                    echoMode: TextInput.Password
                    placeholderText: win.t("암호 다시", "Password again")
                    text: page.text2
                    onTextEdited: page.text2 = text
                    onAccepted: if (page.valid) nextButton.clicked()
                }
                Label {
                    visible: win.q && win.q.type === "password" && page.text2 !== "" && page.text1 !== page.text2
                    text: win.t("두 암호가 서로 다릅니다.", "The two passwords are different.")
                    color: "#b00020"
                }
            }
        }

        // --- working: progress + details
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: win.waiting
            visible: win.waiting
            spacing: Math.round(win.rowHeight * 0.25)
            ProgressBar { Layout.fillWidth: true; indeterminate: true }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: win.t("기다려 주세요. 전원을 연결해 두는 것이 좋습니다.", "Please wait. Keeping the charger connected is a good idea.")
            }
            Button {
                text: win.showDetails ? win.t("자세히 숨기기", "Hide details") : win.t("자세히", "Details")
                Layout.preferredHeight: win.rowHeight
                onClicked: win.showDetails = !win.showDetails
            }
            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.showDetails
                text: win.tailText
                font.family: "DejaVu Sans Mono"
                font.pointSize: win.font.pointSize * 0.75
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideNone
                clip: true
            }
        }

        // --- buttons
        RowLayout {
            Layout.fillWidth: true
            visible: !win.waiting
            Button {
                text: win.t("취소", "Cancel")
                visible: win.q && win.q.type !== "done" && win.q.type !== "error" && win.q.type !== "info"
                Layout.preferredHeight: win.rowHeight
                Layout.preferredWidth: win.rowHeight * 3
                onClicked: win.cancel()
            }
            Item { Layout.fillWidth: true }
            Button {
                text: win.t("아니요", "No")
                visible: win.q && win.q.type === "yesno"
                Layout.preferredHeight: win.rowHeight
                Layout.preferredWidth: win.rowHeight * 3
                onClicked: win.answer("n")
            }
            Repeater {
                model: win.q && win.q.type === "done" ? win.q.options : []
                delegate: Button {
                    required property var modelData
                    text: modelData.label
                    highlighted: modelData.value === "restart"
                    Layout.preferredHeight: win.rowHeight
                    Layout.preferredWidth: win.rowHeight * 4
                    onClicked: win.answer(modelData.value)
                }
            }
            Button {
                id: nextButton
                visible: win.q && win.q.type !== "done"
                highlighted: true
                enabled: page.valid
                Layout.preferredHeight: win.rowHeight
                Layout.preferredWidth: win.rowHeight * 3
                text: !win.q ? "" : win.q.type === "yesno" ? win.t("예", "Yes")
                      : (win.q.type === "error" || win.q.type === "info") ? win.t("닫기", "Close")
                      : win.q.type === "confirm" ? win.t("설치", "Install") : win.t("다음", "Next")
                onClicked: {
                    switch (win.q.type) {
                    case "choice": win.answer(page.choice); break;
                    case "text": win.answer(page.text1.trim()); break;
                    case "password": win.answer(page.text1); break;
                    case "confirm": win.answer(page.text1); break;
                    case "yesno": win.answer("y"); break;
                    default: win.answer("ok");
                    }
                }
            }
        }
    }
}
