import QtQuick
import QtQuick.Controls

Item {
    id: root
    width: 1920
    height: 1080

    property int stage: 0

    onStageChanged: {
        if (stage === 1) {
            introAnim.start()
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: "#1a1b26"

        RadialGradient {
            anchors.fill: parent
            // Soft subtle glow in center
            opacity: 0.15
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 24
        opacity: 0
        id: centerGroup

        Image {
            id: logo
            anchors.horizontalCenter: parent.horizontalCenter
            width: 128
            height: 128
            source: "/usr/share/icons/hicolor/scalable/apps/hyggshi-logo.svg"
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Hyggshi OS"
            font.pixelSize: 28
            font.weight: Font.DemiBold
            font.family: "Noto Sans, sans-serif"
            color: "#c0caf5"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Arch Edition"
            font.pixelSize: 14
            font.weight: Font.Normal
            font.family: "Noto Sans, sans-serif"
            color: "#7aa2f7"
        }

        Item {
            width: 160
            height: 4
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                anchors.fill: parent
                color: "#24283b"
                radius: 2
            }

            Rectangle {
                id: progressBar
                height: parent.height
                radius: 2
                color: "#7aa2f7"
                width: 0

                NumberAnimation on width {
                    from: 0
                    to: 160
                    duration: 3000
                    loops: Animation.Infinite
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    ParallelAnimation {
        id: introAnim
        NumberAnimation {
            target: centerGroup
            property: "opacity"
            from: 0
            to: 1
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    Component.onCompleted: {
        introAnim.start()
    }
}
