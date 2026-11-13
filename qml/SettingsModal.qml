import QtQuick
import Quickshell
import SekaiDesk

PanelWindow {
    id: settingsWin
    required property var themeHub
    required property bool fullscreenActive

    visible: themeHub.settingsOpen && !fullscreenActive
    clickThrough: false
    color: "transparent"

    readonly property int cardW: 480
    readonly property int shadow: 5
    width: cardW + shadow
    height: cardRect.height + shadow

    x: Math.max(12, Math.round((themeHub.screenW - width) * 0.5))
    y: Math.max(40, Math.round((themeHub.screenH - height) * 0.36))

    property double openedAt: 0
    onVisibleChanged: {
        if (visible) {
            openedAt = Date.now()
            cityInput.text = WeatherService.city
            focusActivate()
        }
    }

    onWindowDeactivated: {
        if (themeHub.settingsOpen && !cityInput.activeFocus) {
            themeHub.settingsClosedAt = Date.now()
            themeHub.settingsOpen = false
        }
    }

    Timer {
        interval: 70
        repeat: true
        running: settingsWin.visible
        onTriggered: {
            if ((Date.now() - settingsWin.openedAt) > 250 && settingsWin.isPointerOutsideAndPressed()) {
                themeHub.settingsClosedAt = Date.now()
                themeHub.settingsOpen = false
            }
        }
    }

    // Hard offset shadow
    Rectangle {
        x: settingsWin.shadow
        y: settingsWin.shadow
        width: settingsWin.cardW
        height: cardRect.height
        radius: 16
        color: themeHub.darkInk
    }

    Rectangle {
        id: cardRect
        x: 0
        y: 0
        width: settingsWin.cardW
        height: mainCol.implicitHeight + 28
        radius: 16
        color: "#F8FAFC"
        border.width: 2.5
        border.color: themeHub.darkInk

        Column {
            id: mainCol
            x: 14
            y: 14
            width: settingsWin.cardW - 28
            spacing: 12

            // Header
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: themeHub.accentA
                    border.width: 2
                    border.color: themeHub.darkInk
                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        sourceSize.width: 32
                        sourceSize.height: 32
                        smooth: true
                        source: "qrc:/qml/icons/settings-dark.svg"
                    }
                }

                Column {
                    width: parent.width - 72
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: "SekaiDesk Control Hub"
                        font.family: "Segoe UI"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    Text {
                        text: "Active Unit: " + themeHub.bandName
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: "#475569"
                    }
                }

                Rectangle {
                    width: 26
                    height: 26
                    radius: 8
                    color: closeSettingsMa.containsMouse ? "#FEE2E2" : "#E2E8F0"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Image {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        source: "qrc:/qml/icons/close-circle-dark.svg"
                    }
                    MouseArea {
                        id: closeSettingsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            themeHub.settingsClosedAt = Date.now()
                            themeHub.settingsOpen = false
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1.5; color: "#E2E8F0" }

            // Unit Theme Picker
            Text {
                text: "PROJECT SEKAI UNIT THEME"
                font.family: "Segoe UI"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#64748B"
            }

            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: themeHub.bands
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: themeHub.bandId === modelData.id
                        height: 30
                        width: bandRow.implicitWidth + 16
                        radius: 9
                        color: active ? modelData.A : (bandMa.containsMouse ? modelData.hoverTint : "#FFFFFF")
                        border.width: active ? 2 : 1.5
                        border.color: themeHub.darkInk

                        Row {
                            id: bandRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 11
                                height: 11
                                radius: 6
                                color: modelData.B
                                border.width: 1.5
                                border.color: themeHub.darkInk
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.weight: active ? Font.Bold : Font.Medium
                                color: modelData.id === "mono" && !active ? "#1E293B" : themeHub.darkInk
                            }
                        }

                        MouseArea {
                            id: bandMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.setBand(modelData.id)
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1.5; color: "#E2E8F0" }

            // Shell Behavior Toggles
            Text {
                text: "SHELL & DISPLAY"
                font.family: "Segoe UI"
                font.pixelSize: 10
                font.weight: Font.Bold
                color: "#64748B"
            }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) * 0.5
                    height: 32
                    radius: 9
                    color: themeHub.screenRoundEnabled ? themeHub.accentB : "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: "Screen Corners: " + (themeHub.screenRoundEnabled ? "ON" : "OFF")
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeHub.setScreenRound(!themeHub.screenRoundEnabled)
                    }
                }

                Rectangle {
                    width: (parent.width - 8) * 0.5
                    height: 32
                    radius: 9
                    color: themeHub.dockAutoHide ? themeHub.accentB : "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: "Dock Dodge: " + (themeHub.dockAutoHide ? "ON" : "OFF")
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeHub.setDockAutoHide(!themeHub.dockAutoHide)
                    }
                }
            }

            // Weather city row
            Row {
                width: parent.width
                spacing: 6
                Rectangle {
                    width: parent.width - 96
                    height: 30
                    radius: 8
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: cityInput.activeFocus ? themeHub.darkInk : "#CBD5E1"
                    TextInput {
                        id: cityInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        color: themeHub.darkInk
                        onAccepted: WeatherService.setCity(text)
                    }
                }
                Rectangle {
                    width: 90
                    height: 30
                    radius: 8
                    color: setCityMa.containsMouse ? themeHub.accentA : themeHub.accentB
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: "Set City"
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: setCityMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WeatherService.setCity(cityInput.text)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1.5; color: "#E2E8F0" }

            // Desktop Widgets Toggles
            Row {
                width: parent.width
                Text {
                    width: parent.width - 105
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DESKTOP WIDGETS (ABOVE WALLPAPER)"
                    font.family: "Segoe UI"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "#64748B"
                }
                Rectangle {
                    width: 105
                    height: 22
                    radius: 7
                    color: resetWMa.containsMouse ? "#E2E8F0" : "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: "Reset Positions"
                        font.family: "Segoe UI"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: resetWMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeHub.resetWidgetPositions()
                    }
                }
            }

            Grid {
                width: parent.width
                columns: 3
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: [
                        { key: "clock", label: "Clock", active: themeHub.wClockVisible },
                        { key: "weather", label: "Weather", active: themeHub.wWeatherVisible },
                        { key: "todo", label: "Todo List", active: themeHub.wTodoVisible },
                        { key: "notes", label: "Sticky Note", active: themeHub.wNotesVisible },
                        { key: "lyrics", label: "Live Lyrics", active: themeHub.wLyricsVisible },
                        { key: "profile", label: "Profile Card", active: themeHub.wProfileVisible }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (mainCol.width - 12) / 3
                        height: 30
                        radius: 8
                        color: modelData.active ? themeHub.accentA : (wMa.containsMouse ? themeHub.hoverTint : "#FFFFFF")
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        Text {
                            anchors.centerIn: parent
                            text: (modelData.active ? "● " : "○ ") + modelData.label
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: modelData.active ? Font.Bold : Font.Medium
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            id: wMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.setWidgetVisible(modelData.key, !modelData.active)
                        }
                    }
                }
            }

            // Quick hotkeys footer
            Rectangle {
                width: parent.width
                height: 30
                radius: 8
                color: themeHub.bandDeep
                border.width: 1.5
                border.color: themeHub.darkInk
                Text {
                    anchors.centerIn: parent
                    text: "Alt+Space: Spotlight   •   Ctrl+Alt+V: Clipboard   •   Alt+Q: QuickPanel"
                    font.family: "Consolas"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: themeHub.accentA
                }
            }
        }
    }
}
