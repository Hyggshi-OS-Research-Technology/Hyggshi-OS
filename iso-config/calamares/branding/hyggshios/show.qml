/* === This file is part of Calamares - <http://github.com/calamares> ===
 *
 *   Hyggshi OS slideshow — 6 slides
 */

import QtQuick 2.5
import calamares.slideshow 1.0

Presentation
{
    id: presentation

    function onActivate() {
        if (advanceTimer) {
            advanceTimer.restart()
        }
    }

    function onLeave() {
        if (advanceTimer) {
            advanceTimer.stop()
        }
    }

    Timer {
        id: advanceTimer
        interval: 15000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: background1
                source: "slide1.png"
                width: Math.min(parent.width * 0.9, 500)
                height: Math.min(parent.height * 0.65, 280)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: background1.bottom
                anchors.topMargin: 14
                width: Math.min(parent.width * 0.92, 620)
                text: qsTr("Welcome to Hyggshi OS.<br/>The installation is automated and should complete in just a few minutes.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: "#2c3e50"
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: background2
                source: "slide2.png"
                width: Math.min(parent.width * 0.9, 500)
                height: Math.min(parent.height * 0.65, 280)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: background2.bottom
                anchors.topMargin: 14
                width: Math.min(parent.width * 0.92, 620)
                text: qsTr("Some applications are already available.<br/>fcitx5 + Lotus (Vietnamese input), Nexfetch, and Firefox come pre-installed.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: "#2c3e50"
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: background3
                source: "slide3.png"
                width: Math.min(parent.width * 0.9, 500)
                height: Math.min(parent.height * 0.65, 280)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: background3.bottom
                anchors.topMargin: 14
                width: Math.min(parent.width * 0.92, 620)
                text: qsTr("After installation, the Welcome assistant helps you<br/>set up your machine quickly in just a few simple steps.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: "#2c3e50"
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: background4
                source: "slide4.png"
                width: Math.min(parent.width * 0.9, 500)
                height: Math.min(parent.height * 0.65, 280)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: background4.bottom
                anchors.topMargin: 14
                width: Math.min(parent.width * 0.92, 620)
                text: qsTr("NexCode IDE comes bundled with Hyggshi OS.<br/>A lightweight, fast code editor built on Electron + Monaco Editor.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: "#2c3e50"
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: background5
                source: "slide5.png"
                width: Math.min(parent.width * 0.9, 500)
                height: Math.min(parent.height * 0.65, 280)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: background5.bottom
                anchors.topMargin: 14
                width: Math.min(parent.width * 0.92, 620)
                text: qsTr("Nexfetch — a system info fetch tool,<br/>up to 3x faster than fastfetch, built specifically for the HORT ecosystem.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: "#2c3e50"
            }
        }
    }

    Slide {
        Item {
            anchors.fill: parent

            Image {
                id: background6
                source: "slide6.png"
                width: Math.min(parent.width * 0.9, 500)
                height: Math.min(parent.height * 0.65, 280)
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: background6.bottom
                anchors.topMargin: 14
                width: Math.min(parent.width * 0.92, 620)
                text: qsTr("From Hyggshi OS 1.3 on Roblox to 1.4.1 Verdant Valley.<br/>The next-generation Linux experience, built from scratch.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: "#2c3e50"
            }
        }
    }
}
