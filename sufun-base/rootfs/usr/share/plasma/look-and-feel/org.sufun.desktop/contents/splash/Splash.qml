// SUFUN login splash (shown by ksplashqml while Plasma starts after you log in).
// Same look as the boot screen (Plymouth): black, the SUFUN logo, the word SUFUN
// in white below it, a small spinner below that. No KDE logo or text.
// The pictures in images/ are rendered from sufun-base/art when sufun-base is
// built (twice the size shown, so they stay sharp on the Surface's scaled screen).
import QtQuick

Rectangle {
    id: root
    color: "black"

    // ksplashqml counts the start-up steps here (1 ... 6); at the end it closes us.
    property int stage

    readonly property int gap: 24

    Item {
        id: content
        anchors.centerIn: parent
        width: Math.max(logo.width, word.width)
        // logo + text are centered together, like on the boot screen
        height: logo.height + root.gap + word.height
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 300 } }

        Image {
            id: logo
            anchors.horizontalCenter: parent.horizontalCenter
            source: "images/logo.png"
            width: 120; height: 120
            sourceSize.width: 240; sourceSize.height: 240
            smooth: true
        }
        Image {
            id: word
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logo.bottom
            anchors.topMargin: root.gap
            source: "images/sufun.png"
            height: 56
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    Image {
        id: spinner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: content.bottom
        anchors.topMargin: 2 * root.gap
        source: "images/spinner.png"
        width: 40; height: 40
        sourceSize.width: 80; sourceSize.height: 80
        smooth: true
        RotationAnimator on rotation {
            from: 0; to: 360
            duration: 1200
            loops: Animation.Infinite
            running: true
        }
    }
}
