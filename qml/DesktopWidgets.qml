import QtQuick
import Quickshell
import SekaiDesk

// Phase 3 Desktop Widgets — desktopLayer PanelWindows hovering cleanly above Wallpaper
Item {
    id: widgetsRoot
    visible: false

    required property var themeHub
    required property bool fullscreenActive

    // Keep desktopLayer widgets visible above desktop wallpaper after Win+D
    Connections {
        target: WindowTracker
        function onActiveWindowChanged() {
            if (WindowTracker.activeAppName === "Desktop") {
                if (clockWidgetWin.visible) clockWidgetWin.raiseOnDesktop()
                if (weatherWidgetWin.visible) weatherWidgetWin.raiseOnDesktop()
                if (todoWidgetWin.visible) todoWidgetWin.raiseOnDesktop()
                if (notesWidgetWin.visible) notesWidgetWin.raiseOnDesktop()
                if (lyricsWidgetWin.visible) lyricsWidgetWin.raiseOnDesktop()
                if (profileWidgetWin.visible) profileWidgetWin.raiseOnDesktop()
            }
        }
    }

    function weatherIconFor(code, isDay) {
        if (code >= 95) return "qrc:/qml/icons/cloud-storm-dark.svg"
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "qrc:/qml/icons/cloud-snowfall-dark.svg"
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "qrc:/qml/icons/cloud-rain-dark.svg"
        if (code === 0 || code === 1) return isDay ? "qrc:/qml/icons/cloud-sun-dark.svg" : "qrc:/qml/icons/cloudy-moon-dark.svg"
        return "qrc:/qml/icons/cloud-dark.svg"
    }

    // Reusable drag handle helper (placed inside widget header bar)
    component WidgetHeader: Rectangle {
        id: hdr
        required property string widgetKey
        required property string title
        required property string iconSource
        required property var hostWin
        required property var themeHub

        width: parent.width
        height: 28
        radius: 9
        color: themeHub.accentA
        border.width: 1.5
        border.color: themeHub.darkInk

        property real pressScreenX: 0
        property real pressScreenY: 0
        property int startWinX: 0
        property int startWinY: 0

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: closeBtn.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 13
                height: 13
                sourceSize.width: 26
                sourceSize.height: 26
                smooth: true
                source: hdr.iconSource
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: hdr.title
                font.family: "Segoe UI"
                font.pixelSize: 11
                font.weight: Font.Bold
                color: hdr.themeHub.darkInk
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.left: parent.left
            anchors.right: closeBtn.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            cursorShape: Qt.SizeAllCursor
            onPressed: mouse => {
                const gp = mapToGlobal(mouse.x, mouse.y)
                hdr.pressScreenX = gp.x
                hdr.pressScreenY = gp.y
                hdr.startWinX = hdr.hostWin.x
                hdr.startWinY = hdr.hostWin.y
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    const gp = mapToGlobal(mouse.x, mouse.y)
                    const nx = Math.max(0, Math.min(hdr.themeHub.screenW - hdr.hostWin.width, hdr.startWinX + Math.round(gp.x - hdr.pressScreenX)))
                    const ny = Math.max(28, Math.min(hdr.themeHub.screenH - hdr.hostWin.height, hdr.startWinY + Math.round(gp.y - hdr.pressScreenY)))
                    hdr.hostWin.x = nx
                    hdr.hostWin.y = ny
                }
            }
            onReleased: {
                hdr.themeHub.saveWidgetPos(hdr.widgetKey, hdr.hostWin.x, hdr.hostWin.y)
            }
        }

        Rectangle {
            id: closeBtn
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 6
            color: hdrCloseMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
            border.width: 1
            border.color: hdr.themeHub.darkInk
            Image {
                anchors.centerIn: parent
                width: 11
                height: 11
                source: "qrc:/qml/icons/close-circle-dark.svg"
            }
            MouseArea {
                id: hdrCloseMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: hdr.themeHub.setWidgetVisible(hdr.widgetKey, false)
            }
        }
    }

    // =========================================================================
    // 1. CLOCK WIDGET
    // =========================================================================
    PanelWindow {
        id: clockWidgetWin
        desktopLayer: true
        visible: themeHub.wClockVisible && !fullscreenActive
        color: "transparent"
        width: 254
        height: 126
        x: themeHub.wClockX
        y: themeHub.wClockY

        property string bigTime: "00:00"
        property string secPart: "00"
        property string dateLine: ""

        Timer {
            interval: 1000
            repeat: true
            running: clockWidgetWin.visible
            triggeredOnStart: true
            onTriggered: {
                const d = new Date()
                clockWidgetWin.bigTime = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
                clockWidgetWin.secPart = String(d.getSeconds()).padStart(2, "0")
                const days = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]
                clockWidgetWin.dateLine = days[d.getDay()] + ", " + String(d.getDate()).padStart(2, "0") + "/" + String(d.getMonth() + 1).padStart(2, "0") + "/" + d.getFullYear()
            }
        }

        Rectangle { x: 4; y: 4; width: 248; height: 120; radius: 14; color: themeHub.darkInk }
        Rectangle {
            width: 248
            height: 120
            radius: 14
            color: "#FFFFFF"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                WidgetHeader {
                    widgetKey: "clock"
                    title: "CLOCK"
                    iconSource: "qrc:/qml/icons/clock-circle-dark.svg"
                    hostWin: clockWidgetWin
                    themeHub: widgetsRoot.themeHub
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: clockWidgetWin.bigTime
                        font.family: "Consolas"
                        font.pixelSize: 34
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 22
                        radius: 6
                        color: themeHub.accentB
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        Text {
                            anchors.centerIn: parent
                            text: clockWidgetWin.secPart
                            font.family: "Consolas"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clockWidgetWin.dateLine
                    font.family: "Segoe UI"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: "#475569"
                }
            }
        }
    }

    // =========================================================================
    // 2. WEATHER WIDGET
    // =========================================================================
    PanelWindow {
        id: weatherWidgetWin
        desktopLayer: true
        visible: themeHub.wWeatherVisible && !fullscreenActive
        color: "transparent"
        width: 274
        height: 158
        x: themeHub.wWeatherX
        y: themeHub.wWeatherY

        Rectangle { x: 4; y: 4; width: 268; height: 152; radius: 14; color: themeHub.darkInk }
        Rectangle {
            width: 268
            height: 152
            radius: 14
            color: "#FFFFFF"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                WidgetHeader {
                    widgetKey: "weather"
                    title: WeatherService.city
                    iconSource: widgetsRoot.weatherIconFor(WeatherService.weatherCode, WeatherService.isDay)
                    hostWin: weatherWidgetWin
                    themeHub: widgetsRoot.themeHub
                }

                Row {
                    width: parent.width
                    spacing: 10
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 44
                        sourceSize.width: 88
                        sourceSize.height: 88
                        smooth: true
                        source: widgetsRoot.weatherIconFor(WeatherService.weatherCode, WeatherService.isDay)
                    }
                    Column {
                        width: parent.width - 60
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: WeatherService.temperature + "°C"
                            font.family: "Consolas"
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Text {
                            text: WeatherService.conditionText
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#475569"
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 28
                    radius: 8
                    color: themeHub.hoverTint
                    border.width: 1
                    border.color: themeHub.darkInk
                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            text: "Feels " + WeatherService.feelsLike + "°"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Text {
                            text: "Hum " + WeatherService.humidity + "%"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Text {
                            text: WeatherService.tempMin + "°/" + WeatherService.tempMax + "°"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WeatherService.refresh()
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. TODO CHECKLIST WIDGET
    // =========================================================================
    PanelWindow {
        id: todoWidgetWin
        desktopLayer: true
        visible: themeHub.wTodoVisible && !fullscreenActive
        color: "transparent"
        width: 274
        height: 276
        x: themeHub.wTodoX
        y: themeHub.wTodoY

        Rectangle { x: 4; y: 4; width: 268; height: 270; radius: 14; color: themeHub.darkInk }
        Rectangle {
            width: 268
            height: 270
            radius: 14
            color: "#FFFFFF"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                WidgetHeader {
                    widgetKey: "todo"
                    title: "TODO (" + themeHub.todoItems.length + ")"
                    iconSource: "qrc:/qml/icons/checklist-dark.svg"
                    hostWin: todoWidgetWin
                    themeHub: widgetsRoot.themeHub
                }

                Row {
                    width: parent.width
                    spacing: 4
                    Rectangle {
                        width: parent.width - 42
                        height: 28
                        radius: 7
                        color: "#F8FAFC"
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        TextInput {
                            id: todoAddInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            color: themeHub.darkInk
                            onAccepted: {
                                themeHub.addTodo(text)
                                text = ""
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: parent.text === ""
                                text: "Add new task..."
                                font: parent.font
                                color: "#94A3B8"
                            }
                        }
                    }
                    Rectangle {
                        width: 38
                        height: 28
                        radius: 7
                        color: themeHub.accentB
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.family: "Consolas"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                themeHub.addTodo(todoAddInput.text)
                                todoAddInput.text = ""
                            }
                        }
                    }
                }

                ListView {
                    width: parent.width
                    height: parent.height - 74
                    clip: true
                    spacing: 4
                    model: themeHub.todoItems
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 30
                        radius: 7
                        color: modelData.done ? "#F1F5F9" : themeHub.hoverTint
                        border.width: 1
                        border.color: "#CBD5E1"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 6
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 15
                                height: 15
                                opacity: modelData.done ? 1.0 : 0.3
                                source: "qrc:/qml/icons/check-circle-dark.svg"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 42
                                text: modelData.text || ""
                                elide: Text.ElideRight
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.strikeout: !!modelData.done
                                color: modelData.done ? "#64748B" : themeHub.darkInk
                            }
                        }
                        MouseArea {
                            anchors.left: parent.left
                            anchors.right: delTodoBtn.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.toggleTodo(index)
                        }
                        Rectangle {
                            id: delTodoBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            radius: 5
                            color: "#FEE2E2"
                            Image {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                source: "qrc:/qml/icons/close-circle-dark.svg"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: themeHub.removeTodo(index)
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 4. STICKY NOTES WIDGET
    // =========================================================================
    PanelWindow {
        id: notesWidgetWin
        desktopLayer: true
        visible: themeHub.wNotesVisible && !fullscreenActive
        color: "transparent"
        width: 266
        height: 226
        x: themeHub.wNotesX
        y: themeHub.wNotesY

        Timer {
            id: noteSaveTimer
            interval: 400
            onTriggered: themeHub.saveNoteText(noteEdit.text)
        }

        Rectangle { x: 4; y: 4; width: 260; height: 220; radius: 14; color: themeHub.darkInk }
        Rectangle {
            width: 260
            height: 220
            radius: 14
            color: "#FEFCE8"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                WidgetHeader {
                    widgetKey: "notes"
                    title: "STICKY NOTE"
                    iconSource: "qrc:/qml/icons/notes-dark.svg"
                    hostWin: notesWidgetWin
                    themeHub: widgetsRoot.themeHub
                }

                Flickable {
                    width: parent.width
                    height: parent.height - 36
                    contentWidth: width
                    contentHeight: Math.max(height, noteEdit.paintedHeight + 8)
                    clip: true

                    TextEdit {
                        id: noteEdit
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: themeHub.darkInk
                        text: themeHub.noteText
                        onTextChanged: {
                            if (activeFocus)
                                noteSaveTimer.restart()
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 5. LIVE SYNCED LYRICS WIDGET
    // =========================================================================
    PanelWindow {
        id: lyricsWidgetWin
        desktopLayer: true
        visible: themeHub.wLyricsVisible && !fullscreenActive
        color: "transparent"
        width: 316
        height: 266
        x: themeHub.wLyricsX
        y: themeHub.wLyricsY

        Connections {
            target: LyricsService
            function onActiveIndexChanged() {
                if (lyricsList.visible && LyricsService.activeIndex >= 0) {
                    lyricsList.positionViewAtIndex(LyricsService.activeIndex, ListView.Center)
                }
            }
        }

        Rectangle { x: 4; y: 4; width: 310; height: 260; radius: 14; color: themeHub.darkInk }
        Rectangle {
            width: 310
            height: 260
            radius: 14
            color: themeHub.bandDeep
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                WidgetHeader {
                    widgetKey: "lyrics"
                    title: MediaService.hasSession ? (MediaService.title || "LYRICS") : "LIVE LYRICS"
                    iconSource: "qrc:/qml/icons/music-note-dark.svg"
                    hostWin: lyricsWidgetWin
                    themeHub: widgetsRoot.themeHub
                }

                Text {
                    visible: !MediaService.hasSession || LyricsService.loading || !LyricsService.hasLyrics
                    width: parent.width
                    height: parent.height - 40
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !MediaService.hasSession
                        ? "Play music (Spotify / Browser) to fetch synced lyrics"
                        : (LyricsService.loading ? "Searching LRCLIB..." : "No lyrics found for this track")
                    font.family: "Segoe UI"
                    font.pixelSize: 12
                    color: "#CBD5E1"
                }

                ListView {
                    id: lyricsList
                    visible: MediaService.hasSession && LyricsService.hasLyrics && LyricsService.lines.length > 0
                    width: parent.width
                    height: parent.height - 40
                    clip: true
                    spacing: 4
                    model: LyricsService.lines
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool cur: index === LyricsService.activeIndex
                        width: ListView.view.width
                        height: lyricTxt.implicitHeight + 10
                        radius: 7
                        color: cur ? themeHub.accentA : "transparent"

                        Text {
                            id: lyricTxt
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: modelData.text || ""
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                            font.family: "Segoe UI"
                            font.pixelSize: cur ? 13 : 11
                            font.weight: cur ? Font.Bold : Font.Normal
                            color: cur ? themeHub.darkInk : "#CBD5E1"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (LyricsService.synced && modelData.timeMs >= 0)
                                    MediaService.seekToSec(modelData.timeMs / 1000.0)
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 6. USER PROFILE / UNIT CARD WIDGET
    // =========================================================================
    PanelWindow {
        id: profileWidgetWin
        desktopLayer: true
        visible: themeHub.wProfileVisible && !fullscreenActive
        color: "transparent"
        width: 260
        height: 146
        x: themeHub.wProfileX
        y: themeHub.wProfileY

        Rectangle { x: 4; y: 4; width: 254; height: 140; radius: 14; color: themeHub.darkInk }
        Rectangle {
            width: 254
            height: 140
            radius: 14
            color: "#FFFFFF"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                WidgetHeader {
                    widgetKey: "profile"
                    title: "PROFILE CARD"
                    iconSource: "qrc:/qml/icons/user-rounded-dark.svg"
                    hostWin: profileWidgetWin
                    themeHub: widgetsRoot.themeHub
                }

                Row {
                    width: parent.width
                    spacing: 10
                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: themeHub.accentB
                        border.width: 2
                        border.color: themeHub.darkInk
                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            source: "qrc:/qml/icons/user-rounded-dark.svg"
                        }
                    }
                    Column {
                        width: parent.width - 56
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: themeHub.profileName
                            font.family: "Segoe UI"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Text {
                            text: themeHub.profileStatus
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            color: "#475569"
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 28
                    radius: 8
                    color: themeHub.bandDeep
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    Text {
                        anchors.centerIn: parent
                        text: themeHub.bandName + "  •  Switch Theme"
                        font.family: "Segoe UI"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: themeHub.accentA
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            themeHub.closeAllTools()
                            themeHub.settingsOpen = true
                        }
                    }
                }
            }
        }
    }
}
