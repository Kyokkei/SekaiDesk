import QtQuick
import Quickshell
import SekaiDesk

PanelWindow {
    id: settingsWin
    required property var themeHub
    required property bool fullscreenActive

    // Disabled in Round 5: Landscape Phone Settings inside quickPanelWindow replaces SettingsModal
    visible: false
    clickThrough: true
    color: "transparent"

    readonly property int cardW: 500
    readonly property int shadow: 5
    width: cardW + shadow
    height: cardRect.height + shadow

    x: Math.max(12, Math.round((themeHub.screenW - width) * 0.5))
    y: Math.max(40, Math.round((themeHub.screenH - height) * 0.28))

    property double openedAt: 0
    property bool pickingFile: false

    onVisibleChanged: {
        if (visible) {
            openedAt = Date.now()
            cityInput.text = WeatherService.city
            focusActivate()
        }
    }

    onWindowDeactivated: {
        if (themeHub.settingsOpen && !cityInput.activeFocus && !pickingFile) {
            themeHub.settingsClosedAt = Date.now()
            themeHub.settingsOpen = false
        }
    }

    Timer {
        interval: 70
        repeat: true
        running: settingsWin.visible && !settingsWin.pickingFile
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
            spacing: 11

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

            Rectangle { width: parent.width; height: 2; color: "#E2E8F0" }

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

            Rectangle { width: parent.width; height: 2; color: "#E2E8F0" }

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

            Rectangle { width: parent.width; height: 2; color: "#E2E8F0" }

            // Desktop Widgets Toggles
            Row {
                width: parent.width
                spacing: 6
                Text {
                    width: parent.width - 204
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DESKTOP WIDGETS (DESKTOP LAYER)"
                    font.family: "Segoe UI"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "#64748B"
                }
                Rectangle {
                    width: 90
                    height: 22
                    radius: 7
                    color: themeHub.editMode ? themeHub.accentA : (editDskMa.containsMouse ? themeHub.hoverTint : themeHub.accentB)
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: themeHub.editMode ? "Editing ✓" : "Edit Desktop"
                        font.family: "Segoe UI"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: editDskMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            themeHub.settingsClosedAt = Date.now()
                            themeHub.settingsOpen = false
                            themeHub.setEditMode(true)
                        }
                    }
                }
                Rectangle {
                    width: 102
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

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { key: "clock", label: "Clock", active: themeHub.wClockVisible },
                        { key: "weather", label: "Weather", active: themeHub.wWeatherVisible },
                        { key: "profile", label: "Profile Card", active: themeHub.wProfileVisible },
                        { key: "calendar", label: "Calendar", active: themeHub.wCalendarVisible },
                        { key: "todo", label: "Todo List", active: themeHub.wTodoVisible },
                        { key: "notes", label: "Sticky Note", active: themeHub.wNotesVisible },
                        { key: "lyrics", label: "Live Lyrics", active: themeHub.wLyricsVisible }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: Math.floor((mainCol.width - 18) / 4)
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

            // Clock & Weather Styles Row
            Row {
                width: parent.width
                spacing: 6

                // Clock style cycle + 12h/24h
                Rectangle {
                    width: (parent.width - 6) * 0.5
                    height: 30
                    radius: 8
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Row {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clock:"
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#64748B"
                        }
                        Rectangle {
                            width: 82
                            height: 22
                            radius: 6
                            color: themeHub.accentB
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: themeHub.clockDesignNames[themeHub.clockStyle] + " ↻"
                                font.family: "Consolas"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.cycleClockStyle()
                            }
                        }
                        Rectangle {
                            width: 44
                            height: 22
                            radius: 6
                            color: themeHub.clockUse24h ? themeHub.accentA : "#F1F5F9"
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: themeHub.clockUse24h ? "24H" : "12H"
                                font.family: "Consolas"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.setClockUse24h(!themeHub.clockUse24h)
                            }
                        }
                    }
                }

                // Weather style + forecast view
                Rectangle {
                    width: (parent.width - 6) * 0.5
                    height: 30
                    radius: 8
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Row {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Weather:"
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#64748B"
                        }
                        Rectangle {
                            width: 74
                            height: 22
                            radius: 6
                            color: themeHub.weatherMinimal ? themeHub.accentA : themeHub.accentB
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: themeHub.weatherMinimal ? "MINIMAL" : "CLASSIC"
                                font.family: "Consolas"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.setWeatherMinimal(!themeHub.weatherMinimal)
                            }
                        }
                        Rectangle {
                            width: 64
                            height: 22
                            radius: 6
                            color: "#F1F5F9"
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: themeHub.weatherView === "days" ? "3-DAY" : "HOURLY"
                                font.family: "Consolas"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.setWeatherView(themeHub.weatherView === "days" ? "hourly" : "days")
                            }
                        }
                    }
                }
            }

            // Profile Card Avatar & Banner Pickers
            Row {
                width: parent.width
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) * 0.5
                    height: 30
                    radius: 8
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Row {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Rectangle {
                            width: parent.width - (themeHub.profileAvatarUrl !== "" ? 50 : 0)
                            height: 22
                            radius: 6
                            color: pickAvMa.containsMouse ? themeHub.accentA : themeHub.hoverTint
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: themeHub.profileAvatarUrl !== "" ? "Avatar Set ✓" : "Pick Avatar Image"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                id: pickAvMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    settingsWin.pickingFile = true
                                    const url = SystemControl.pickImageFile("Select Profile Avatar")
                                    settingsWin.pickingFile = false
                                    if (url !== "")
                                        themeHub.setProfileAvatar(url)
                                    settingsWin.focusActivate()
                                }
                            }
                        }
                        Rectangle {
                            visible: themeHub.profileAvatarUrl !== ""
                            width: 46
                            height: 22
                            radius: 6
                            color: "#FEE2E2"
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: "Reset"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#DC2626"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.setProfileAvatar("")
                            }
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 6) * 0.5
                    height: 30
                    radius: 8
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Row {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Rectangle {
                            width: parent.width - (themeHub.profileBannerUrl !== "" ? 50 : 0)
                            height: 22
                            radius: 6
                            color: pickBnMa.containsMouse ? themeHub.accentA : themeHub.hoverTint
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: themeHub.profileBannerUrl !== "" ? "Banner Set ✓" : "Pick Banner Image"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                id: pickBnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    settingsWin.pickingFile = true
                                    const url = SystemControl.pickImageFile("Select Profile Banner")
                                    settingsWin.pickingFile = false
                                    if (url !== "")
                                        themeHub.setProfileBanner(url)
                                    settingsWin.focusActivate()
                                }
                            }
                        }
                        Rectangle {
                            visible: themeHub.profileBannerUrl !== ""
                            width: 46
                            height: 22
                            radius: 6
                            color: "#FEE2E2"
                            border.width: 1
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: "Reset"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#DC2626"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.setProfileBanner("")
                            }
                        }
                    }
                }
            }

            // Quick hotkeys + Quit/Reset footer
            Row {
                width: parent.width
                spacing: 6

                Rectangle {
                    width: parent.width - 96
                    height: 30
                    radius: 8
                    color: themeHub.bandDeep
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: "Alt+Space: Spotlight  •  Ctrl+Alt+V: Clipboard  •  Ctrl+Alt+A: QuickPanel"
                        font.family: "Consolas"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: themeHub.accentA
                        elide: Text.ElideRight
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Rectangle {
                    width: 90
                    height: 30
                    radius: 8
                    color: quitHubMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
                    border.width: 1.5
                    border.color: "#DC2626"
                    Text {
                        anchors.centerIn: parent
                        text: "Quit Shell"
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: "#DC2626"
                    }
                    MouseArea {
                        id: quitHubMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ConfigStore.flush()
                            Qt.quit()
                        }
                    }
                }
            }
        }
    }
}
