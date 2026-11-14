// SUFUN first start: language, time zone and keyboard, before the desktop.
// Runs full screen in its own small KWin (see /usr/lib/sufun/welcome-session),
// as the unprivileged user "sufun-oobe". This window changes NOTHING itself: at
// the end it prints one line
//     SUFUN-CHOICE LANG=<locale> TZ=<zone> KB=<keyboard id>
// and quits; /usr/lib/sufun/welcome-apply (root) checks those values against the
// lists below and applies them. Touch-friendly: big rows, no typing needed.
// Data files (read-only): /usr/share/sufun/languages.tsv, keyboards.tsv,
// /usr/share/zoneinfo/zone1970.tab.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "SUFUN"
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

    property var languages: []     // [{locale, name, tz, kb}]
    property var keyboards: []     // [{id, name}]
    property var zones: []         // ["Asia/Seoul", ...] sorted
    property var regions: []       // ["Africa", "America", ...]
    property int step: 0           // 0 language, 1 time zone, 2 keyboard, 3 summary
    property string lang: "ko_KR.UTF-8"
    property string tz: "Asia/Seoul"
    property string kb: "kr"
    property string region: "Asia"
    property bool ko: lang.indexOf("ko_") === 0
    property string autoLang: ""   // CI test only: "auto=<locale>" argument
    property string netMessage: ""
    property int loaded: 0
    readonly property color accent: "#e8590c"
    readonly property real rowHeight: Math.max(52, fontMetrics.height * 2.6)

    function t(korean, english) { return ko ? korean : english }

    FontMetrics { id: fontMetrics; font: win.font }

    function readText(path, done) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE)
                done(x.responseText || "");
        };
        x.open("GET", "file://" + path);
        x.send();
    }
    function tsv(text) {
        var rows = [];
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            if (l.length === 0 || l.charAt(0) === "#")
                continue;
            rows.push(l.split("\t"));
        }
        return rows;
    }
    function langInfo(locale) {
        for (var i = 0; i < languages.length; i++)
            if (languages[i].locale === locale)
                return languages[i];
        return null;
    }
    function kbName(id) {
        for (var i = 0; i < keyboards.length; i++)
            if (keyboards[i].id === id)
                return keyboards[i].name;
        return id;
    }
    function hasZone(z) { return zones.indexOf(z) >= 0; }
    function pickLanguage(locale) {
        lang = locale;
        var info = langInfo(locale);
        if (info) {
            if (hasZone(info.tz) || zones.length === 0)
                setZone(info.tz);
            kb = info.kb;
        }
    }
    function setZone(z) {
        tz = z;
        var slash = z.indexOf("/");
        region = slash > 0 ? z.substring(0, slash) : z;
    }
    function citiesOf(r) {
        var out = [];
        for (var i = 0; i < zones.length; i++) {
            var z = zones[i];
            if (z === r || z.indexOf(r + "/") === 0)
                out.push(z);
        }
        return out;
    }
    function finish() {
        // One line on stderr, read by welcome-session (QT_MESSAGE_PATTERN=%{message})
        console.info("SUFUN-CHOICE LANG=" + lang + " TZ=" + tz + " KB=" + kb);
        Qt.quit();
    }
    // Optional, only when the user taps the button: ask ipapi.co for the time
    // zone of this internet connection (sends the IP address there, nothing else).
    function guessZone() {
        netMessage = t("찾는 중...", "Looking up...");
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE)
                return;
            var z = (x.responseText || "").trim();
            if (x.status === 200 && hasZone(z)) {
                setZone(z);
                netMessage = t("찾음: ", "Found: ") + z;
            } else {
                netMessage = t("찾지 못했습니다 (인터넷 연결이 없거나 서비스가 응답하지 않음). 목록에서 고르세요.",
                               "Not found (no internet connection or no answer). Please pick from the list.");
            }
        };
        x.open("GET", "https://ipapi.co/timezone/");
        x.send();
    }

    Component.onCompleted: {
        // Always the light look (our background is light), whatever the system says
        Qt.styleHints.colorScheme = Qt.ColorScheme.Light;
        var args = Qt.application.arguments;
        for (var i = 0; i < args.length; i++)
            if (args[i].indexOf("auto=") === 0)
                autoLang = args[i].substring(5);
        readText("/usr/share/sufun/languages.tsv", function (text) {
            var rows = tsv(text), list = [];
            for (var i = 0; i < rows.length; i++)
                if (rows[i].length >= 4)
                    list.push({ locale: rows[i][0], name: rows[i][1], tz: rows[i][2], kb: rows[i][3] });
            languages = list;
            loaded++;
        });
        readText("/usr/share/sufun/keyboards.tsv", function (text) {
            var rows = tsv(text), list = [];
            for (var i = 0; i < rows.length; i++)
                if (rows[i].length >= 2)
                    list.push({ id: rows[i][0], name: rows[i][1] });
            keyboards = list;
            loaded++;
        });
        readText("/usr/share/zoneinfo/zone1970.tab", function (text) {
            var rows = tsv(text), list = ["UTC"], seen = {};
            for (var i = 0; i < rows.length; i++)
                if (rows[i].length >= 3)
                    list.push(rows[i][2]);
            list.sort();
            var regs = [];
            for (var j = 0; j < list.length; j++) {
                var s = list[j].indexOf("/");
                var r = s > 0 ? list[j].substring(0, s) : list[j];
                if (!seen[r]) { seen[r] = true; regs.push(r); }
            }
            zones = list;
            regions = regs;
            loaded++;
        });
    }
    onLoadedChanged: {
        if (loaded < 3)
            return;
        pickLanguage(autoLang !== "" && langInfo(autoLang) ? autoLang : "ko_KR.UTF-8");
        if (autoLang !== "")
            autoTimer.start();
    }
    // CI test: show the first page for a screenshot, then accept the defaults
    Timer { id: autoTimer; interval: 15000; onTriggered: win.finish() }

    // ------------------------------------------------------------------ layout
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.round(win.rowHeight * 0.6)
        spacing: Math.round(win.rowHeight * 0.3)

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
                spacing: 2
                Label {
                    text: [win.t("언어를 고르세요", "Choose your language"),
                           win.t("시간대를 고르세요", "Choose your time zone"),
                           win.t("키보드를 고르세요", "Choose your keyboard"),
                           win.t("준비되었습니다", "All set")][win.step]
                    font.pointSize: win.font.pointSize * 1.9
                    font.weight: Font.DemiBold
                }
                Label {
                    text: win.t("SUFUN 시작 설정 · ", "SUFUN setup · ") + (win.step + 1) + " / 4"
                    opacity: 0.65
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: win.step

            // --- 0: language
            ListView {
                id: langList
                clip: true
                focus: win.step === 0
                model: win.languages
                keyNavigationEnabled: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    height: win.rowHeight
                    text: modelData.name
                    highlighted: modelData.locale === win.lang
                    onClicked: win.pickLanguage(modelData.locale)
                }
            }

            // --- 1: time zone (region | city)
            ColumnLayout {
                spacing: Math.round(win.rowHeight * 0.2)
                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: win.t("인터넷으로 내 시간대 찾기", "Find my time zone online")
                        Layout.preferredHeight: win.rowHeight
                        onClicked: win.guessZone()
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                        text: win.netMessage !== "" ? win.netMessage
                              : win.t("(선택 사항: 누르면 ipapi.co에 이 연결의 IP 주소가 전송됩니다)",
                                      "(optional: sends this connection's IP address to ipapi.co)")
                    }
                }
                Label { text: win.t("선택됨: ", "Selected: ") + win.tz; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Math.round(win.rowHeight * 0.3)
                    ListView {
                        Layout.preferredWidth: Math.round(win.width * 0.3)
                        Layout.fillHeight: true
                        clip: true
                        model: win.regions
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: ItemDelegate {
                            required property var modelData
                            width: ListView.view.width
                            height: win.rowHeight
                            text: modelData
                            highlighted: modelData === win.region
                            onClicked: {
                                win.region = modelData;
                                var c = win.citiesOf(modelData);
                                if (c.length === 1)
                                    win.setZone(c[0]);
                            }
                        }
                    }
                    ListView {
                        id: cityList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: win.citiesOf(win.region)
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: ItemDelegate {
                            required property var modelData
                            width: ListView.view.width
                            height: win.rowHeight
                            text: modelData.indexOf("/") > 0
                                  ? modelData.substring(modelData.indexOf("/") + 1).replace(/_/g, " ").replace(/\//g, " / ")
                                  : modelData
                            highlighted: modelData === win.tz
                            onClicked: win.setZone(modelData)
                        }
                        onModelChanged: {
                            var i = win.citiesOf(win.region).indexOf(win.tz);
                            if (i >= 0)
                                positionViewAtIndex(i, ListView.Center);
                        }
                    }
                }
            }

            // --- 2: keyboard
            ListView {
                clip: true
                model: win.keyboards
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    height: win.rowHeight
                    text: modelData.name
                    highlighted: modelData.id === win.kb
                    onClicked: win.kb = modelData.id
                }
            }

            // --- 3: summary
            ColumnLayout {
                spacing: Math.round(win.rowHeight * 0.3)
                Label {
                    text: win.t("언어: ", "Language: ") + (win.langInfo(win.lang) ? win.langInfo(win.lang).name : win.lang)
                }
                Label { text: win.t("시간대: ", "Time zone: ") + win.tz }
                Label { text: win.t("키보드: ", "Keyboard: ") + win.kbName(win.kb) }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: win.t("나중에 시스템 설정에서 바꿀 수 있습니다. SUFUN을 설치하면 이 설정이 그대로 쓰입니다.",
                                "You can change this later in System Settings. Installing SUFUN uses these settings.")
                }
                Item { Layout.fillHeight: true }
            }
        }

        // --- bottom buttons
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Button {
                text: win.t("뒤로", "Back")
                visible: win.step > 0
                Layout.preferredHeight: win.rowHeight
                Layout.preferredWidth: win.rowHeight * 3
                onClicked: win.step--
            }
            Button {
                id: nextButton
                text: win.step < 3 ? win.t("다음", "Next") : win.t("시작", "Start")
                highlighted: true
                enabled: win.loaded >= 3
                Layout.preferredHeight: win.rowHeight
                Layout.preferredWidth: win.rowHeight * 3
                onClicked: win.step < 3 ? win.step++ : win.finish()
            }
        }
    }
    // Enter = next (Type Cover)
    Shortcut { sequences: ["Return", "Enter"]; onActivated: nextButton.clicked() }
}
