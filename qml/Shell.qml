import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import SekaiDesk

// ===========================================================================
// PHASE 0 SMOKE TEST — SekaiDesk shell skeleton
//
// Validates the survival-critical Win32 window behavior before any real UI:
//   1. Frameless, translucent, always-on-top panel hugging its content
//      (NO full-screen overlay).
//   2. setMask cuts the rounded corners: right-clicking a transparent corner
//      must open the native Explorer desktop context menu.
//   3. clickThrough toggle switches WS_EX_TRANSPARENT live.
//   4. Process (cmd.exe echo) and FileView (JSON roundtrip) prove the
//      Quickshell.Io compat layer on Windows.
//
// Acceptance (blueprint Phase 0 "Done When" — window subset):
//   - runs >= 60s with zero binding loops / TypeErrors in the log
//   - right-click on empty desktop beside the pill opens Explorer menu
//   - right-click in the pill's transparent corner opens Explorer menu
// ===========================================================================

PanelWindow {
    id: win

    visible: true
    color: "transparent"

    // Bottom-center pill — dock placeholder geometry (hugs content).
    anchors {
        left: true
        right: true
        bottom: true
        margins {
            left: 12
            right: 12
            bottom: 12
        }
    }
    height: 84

    clickThrough: false
    mask: Region {
        item: pillBody
    }

    Rectangle {
        id: pillBody
        anchors.fill: parent
        radius: 42
        color: "#F0121A2A"          // navy sticker style, near-opaque
        border.color: "#3E5A96"     // navy 2px sticker border
        border.width: 2

        Row {
            anchors.centerIn: parent
            spacing: 24

            Column {
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SEKAIDESK · PHASE 0"
                    color: "#EDEFF7"
                    font.pixelSize: 15
                    font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(SystemClock.date, "ddd dd MMM yyyy")
                    color: "#9FB2D8"
                    font.pixelSize: 12
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: SystemClock.hours + ":"
                      + String(SystemClock.minutes).padStart(2, "0") + ":"
                      + String(SystemClock.seconds).padStart(2, "0")
                color: "#FFD1DC"
                font.pixelSize: 26
                font.bold: true
            }

            Column {
                spacing: 4
                Text {
                    text: "process: " + (bootTest.textOk ? "PASS" : "…")
                    color: bootTest.textOk ? "#8CE99A" : "#9FB2D8"
                    font.pixelSize: 12
                }
                Text {
                    text: "fileview: " + (bootTest.fileOk ? "PASS" : "…")
                    color: bootTest.fileOk ? "#8CE99A" : "#9FB2D8"
                    font.pixelSize: 12
                }
                Text {
                    text: "mask: pill corners are click-through — right-click them"
                    color: "#9FB2D8"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 120
                height: 34
                radius: 17
                color: clickThroughToggle.containsMouse
                       ? "#2B3A67" : "#1B2440"
                border.color: "#3E5A96"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: win.clickThrough ? "click-through: ON"
                                           : "click-through: OFF"
                    color: "#EDEFF7"
                    font.pixelSize: 11
                }

                MouseArea {
                    id: clickThroughToggle
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: win.clickThrough = !win.clickThrough
                }
            }
        }
    }

    // --- Quickshell.Io compat verification ---------------------------------
    QtObject {
        id: bootTest
        property bool textOk: false
        property bool fileOk: false
    }

    Process {
        id: echoProc
        command: ["cmd", "/c", "echo", "SekaiDesk-boot-ok"]
        stdout: StdioCollector {
            onStreamFinished: {
                bootTest.textOk = text.indexOf("SekaiDesk-boot-ok") >= 0
                console.log("[smoke] process output:", text.trim())
            }
        }
    }

    FileView {
        id: smokeFile
        path: StandardPaths.writableLocation(StandardPaths.TempLocation)
              + "/sekaidesk-smoke.txt"
        Component.onCompleted: {
            text = "sekaidesk smoke " + Date.now()
            save()
        }
        onSaved: {
            reload()
        }
        onLoaded: {
            bootTest.fileOk = text.indexOf("sekaidesk smoke") === 0
            console.log("[smoke] fileview roundtrip:", text)
        }
    }

    Component.onCompleted: {
        console.log("[smoke] shellDir =", shellDir || "(not found)")
        console.log("[smoke] screens =", Quickshell.screens.length)
        echoProc.start()
    }
}
