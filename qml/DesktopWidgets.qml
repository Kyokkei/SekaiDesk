import QtQuick
import Quickshell
import SekaiDesk

Item {
    id: widgetsRoot
    visible: false

    required property var themeHub
    required property bool fullscreenActive

    // Live wall-clock tick shared cleanly by Clock & Profile card
    property date nowDate: new Date()
    property bool beatPhase: false
    Timer {
        interval: 1000
        repeat: true
        running: themeHub.wClockVisible || themeHub.wProfileVisible
        onTriggered: {
            widgetsRoot.nowDate = new Date()
            widgetsRoot.beatPhase = !widgetsRoot.beatPhase
        }
    }

    // Reusable full-card drag + safe coordinate persistence container
    component WidgetShell: PanelWindow {
        id: wShell
        required property string widgetKey
        required property int cardWidth
        required property int cardHeight
        property int shadowOffset: 5
        default property alias content: innerContainer.data

        color: "transparent"
        clickThrough: false
        width: cardWidth + shadowOffset
        height: cardHeight + shadowOffset

        // Drag handler sits BEHIND interactive controls on MouseArea z: -1,
        // and users can also drag from anywhere inside empty card space.
        Item {
            id: innerContainer
            x: 0
            y: 0
            width: wShell.cardWidth
            height: wShell.cardHeight
        }
    }

    component DragSurface: MouseArea {
        required property var shellWin
        required property string widgetKey
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property point startMouse: Qt.point(0, 0)
        property int startWinX: 0
        property int startWinY: 0
        property bool dragging: false

        onPressed: mouse => {
            startMouse = mapToGlobal(mouse.x, mouse.y)
            startWinX = shellWin.x
            startWinY = shellWin.y
            dragging = true
        }
        onPositionChanged: mouse => {
            if (!dragging)
                return
            const cur = mapToGlobal(mouse.x, mouse.y)
            const nx = Math.max(8, Math.min(widgetsRoot.themeHub.screenW - 80, startWinX + (cur.x - startMouse.x)))
            const ny = Math.max(52, Math.min(widgetsRoot.themeHub.screenH - 60, startWinY + (cur.y - startMouse.y)))
            shellWin.x = nx
            shellWin.y = ny
        }
        onReleased: {
            if (dragging) {
                dragging = false
                widgetsRoot.themeHub.saveWidgetPos(widgetKey, shellWin.x, shellWin.y)
            }
        }
        onCanceled: dragging = false
    }

    // Double-stroke SekaiPop Sticker Numeral (White halo + Ink outline + Drop shadow + Vibrant fill)
    component StickerNumeralPair: Item {
        id: snp
        required property string textValue
        required property color fillColor
        required property color outlineColor
        property int fontPx: 70
        property real tiltDeg: 0

        width: numLbl.implicitWidth + 18
        height: numLbl.implicitHeight + 12
        transform: Rotation {
            origin.x: snp.width * 0.5
            origin.y: snp.height * 0.5
            angle: snp.tiltDeg
        }

        // Layer 1: Hard offset shadow
        Text {
            x: 7
            y: 7
            text: snp.textValue
            font.family: "Arial Black"
            font.pixelSize: snp.fontPx
            font.weight: Font.Black
            font.letterSpacing: -3
            color: snp.outlineColor
        }

        // Layer 2: Outer white sticker ring
        Repeater {
            model: [
                [-4, -4], [0, -4], [4, -4],
                [-4, 0],           [4, 0],
                [-4, 4],  [0, 4],  [4, 4]
            ]
            delegate: Text {
                required property var modelData
                x: 3 + modelData[0]
                y: 2 + modelData[1]
                text: snp.textValue
                font.family: "Arial Black"
                font.pixelSize: snp.fontPx
                font.weight: Font.Black
                font.letterSpacing: -3
                color: "#FFFFFF"
            }
        }

        // Layer 3: Crisp ink border around glyph
        Repeater {
            model: [[-2, 0], [2, 0], [0, -2], [0, 2]]
            delegate: Text {
                required property var modelData
                x: 3 + modelData[0]
                y: 2 + modelData[1]
                text: snp.textValue
                font.family: "Arial Black"
                font.pixelSize: snp.fontPx
                font.weight: Font.Black
                font.letterSpacing: -3
                color: snp.outlineColor
            }
        }

        // Layer 4: Foreground vibrant fill
        Text {
            id: numLbl
            x: 3
            y: 2
            text: snp.textValue
            font.family: "Arial Black"
            font.pixelSize: snp.fontPx
            font.weight: Font.Black
            font.letterSpacing: -3
            color: snp.fillColor
        }
    }

    // =========================================================================
    // 1. AUTHENTIC SEKAIPOP STICKER CLOCK WIDGET (STACK & KEYS MODES)
    // =========================================================================
    WidgetShell {
        id: clockWin
        widgetKey: "clock"
        visible: themeHub.wClockVisible && !fullscreenActive
        x: themeHub.wClockX
        y: themeHub.wClockY
        cardWidth: themeHub.clockStyle === "keys" ? 248 : 178
        cardHeight: themeHub.clockStyle === "keys" ? 210 : 210
        shadowOffset: themeHub.clockStyle === "keys" ? 5 : 0

        readonly property bool isKeys: themeHub.clockStyle === "keys"
        readonly property int h24: widgetsRoot.nowDate.getHours()
        readonly property int hDisp: themeHub.clockUse24h ? h24 : ((h24 % 12 === 0) ? 12 : (h24 % 12))
        readonly property string hhStr: (hDisp < 10 ? "0" : "") + hDisp
        readonly property string mmStr: {
            const m = widgetsRoot.nowDate.getMinutes()
            return (m < 10 ? "0" : "") + m
        }
        readonly property string ssStr: {
            const s = widgetsRoot.nowDate.getSeconds()
            return (s < 10 ? "0" : "") + s
        }
        readonly property string ampmStr: themeHub.clockUse24h ? "24H" : (h24 >= 12 ? "PM" : "AM")
        readonly property string dateChipStr: Qt.formatDate(widgetsRoot.nowDate, "ddd • MMM d").toUpperCase()
        readonly property int weekdayIdx: widgetsRoot.nowDate.getDay() // 0=Sun..6=Sat

        // Whole widget draggable + double-click 12h/24h toggle
        DragSurface {
            id: clockDrag
            shellWin: clockWin
            widgetKey: "clock"
            onDoubleClicked: themeHub.setClockUse24h(!themeHub.clockUse24h)
        }

        // --- STACK MODE (Cardless SekaiPop Sticker Numerals) ---
        Item {
            anchors.fill: parent
            visible: !clockWin.isKeys

            StickerNumeralPair {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                textValue: clockWin.hhStr
                fillColor: "#F1F5F9"
                outlineColor: themeHub.darkInk
                fontPx: 66
                tiltDeg: -3
            }

            // Center Beat Diamonds
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 92
                spacing: 12
                Rectangle {
                    width: 11
                    height: 11
                    radius: 2
                    rotation: 45
                    color: widgetsRoot.beatPhase ? themeHub.accentA : themeHub.accentB
                    border.width: 2
                    border.color: themeHub.darkInk
                    scale: widgetsRoot.beatPhase ? 1.15 : 0.92
                    Behavior on scale { NumberAnimation { duration: 180 } }
                }
                Rectangle {
                    width: 11
                    height: 11
                    radius: 2
                    rotation: 45
                    color: widgetsRoot.beatPhase ? themeHub.accentB : "#FFFFFF"
                    border.width: 2
                    border.color: themeHub.darkInk
                    scale: widgetsRoot.beatPhase ? 0.92 : 1.15
                    Behavior on scale { NumberAnimation { duration: 180 } }
                }
            }

            StickerNumeralPair {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 108
                textValue: clockWin.mmStr
                fillColor: themeHub.accentA
                outlineColor: themeHub.darkInk
                fontPx: 66
                tiltDeg: 2.5
            }

            // Tilted AM/PM badge
            Rectangle {
                x: parent.width - width - 10
                y: 168
                width: 44
                height: 24
                radius: 7
                rotation: -6
                color: themeHub.accentB
                border.width: 2
                border.color: themeHub.darkInk
                Text {
                    anchors.centerIn: parent
                    text: clockWin.ampmStr
                    font.family: "Arial Black"
                    font.pixelSize: 11
                    color: themeHub.darkInk
                }
            }

            // Bottom subtle date chip
            Rectangle {
                x: 10
                y: 172
                width: dateStackTxt.implicitWidth + 14
                height: 20
                radius: 6
                color: "#FFFFFF"
                border.width: 1.5
                border.color: themeHub.darkInk
                Text {
                    id: dateStackTxt
                    anchors.centerIn: parent
                    text: clockWin.dateChipStr
                    font.family: "Consolas"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: themeHub.darkInk
                }
            }
        }

        // --- KEYS MODE (SekaiPop Keycap Card) ---
        Item {
            anchors.fill: parent
            visible: clockWin.isKeys

            Rectangle {
                x: 5; y: 5
                width: 248; height: 196
                radius: 18
                color: themeHub.darkInk
            }

            Rectangle {
                x: 0; y: 14
                width: 248; height: 186
                radius: 18
                color: "#FFFFFF"
                border.width: 2.5
                border.color: themeHub.darkInk

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.topMargin: 20
                    spacing: 10

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        // Hour Keycap
                        Rectangle {
                            width: 96; height: 96
                            radius: 16
                            color: "#2D3342"
                            border.width: 2.5
                            border.color: themeHub.darkInk
                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: 6
                                radius: 14
                                color: "#3A4154"
                                border.width: 1
                                border.color: "#4F5870"
                                Text {
                                    anchors.centerIn: parent
                                    text: clockWin.hhStr
                                    font.family: "Arial Black"
                                    font.pixelSize: 48
                                    color: "#FFFFFF"
                                }
                            }
                        }

                        // Center sec column
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Rectangle {
                                width: 14; height: 14
                                radius: 7
                                color: widgetsRoot.beatPhase ? themeHub.accentA : themeHub.accentB
                                border.width: 2
                                border.color: themeHub.darkInk
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Rectangle {
                                width: 28; height: 22
                                radius: 6
                                color: themeHub.accentB
                                border.width: 1.5
                                border.color: themeHub.darkInk
                                Text {
                                    anchors.centerIn: parent
                                    text: clockWin.ssStr
                                    font.family: "Consolas"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: themeHub.darkInk
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: clockWin.ampmStr
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#475569"
                            }
                        }

                        // Minute Keycap
                        Rectangle {
                            width: 96; height: 96
                            radius: 16
                            color: themeHub.bandDeep
                            border.width: 2.5
                            border.color: themeHub.darkInk
                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: 6
                                radius: 14
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: themeHub.accentA }
                                    GradientStop { position: 1.0; color: themeHub.accentB }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: clockWin.mmStr
                                    font.family: "Arial Black"
                                    font.pixelSize: 48
                                    color: themeHub.darkInk
                                }
                            }
                        }
                    }

                    // 7-Day Weekday Strip
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                readonly property bool isToday: index === clockWin.weekdayIdx
                                width: 25; height: 22
                                radius: 6
                                color: isToday ? themeHub.accentA : "#F1F5F9"
                                border.width: isToday ? 1.8 : 1
                                border.color: isToday ? themeHub.darkInk : "#CBD5E1"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.weight: isToday ? Font.Bold : Font.Medium
                                    color: isToday ? themeHub.darkInk : "#64748B"
                                }
                            }
                        }
                    }
                }
            }

            // Tilted top date sticker
            Rectangle {
                x: 16; y: 2
                width: dateKeyTxt.implicitWidth + 16
                height: 22
                radius: 7
                rotation: -2
                color: themeHub.accentA
                border.width: 2
                border.color: themeHub.darkInk
                Text {
                    id: dateKeyTxt
                    anchors.centerIn: parent
                    text: clockWin.dateChipStr
                    font.family: "Segoe UI"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: themeHub.darkInk
                }
            }
        }

        // Hover quick controls (Style switch STACK/KEYS + Close)
        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 4
            anchors.topMargin: 4
            spacing: 4
            visible: clockDrag.containsMouse || clockStyleMa.containsMouse || closeClockMa.containsMouse

            Rectangle {
                width: 46; height: 20; radius: 6
                color: "#FFFFFF"
                border.width: 1.5; border.color: themeHub.darkInk
                Text {
                    anchors.centerIn: parent
                    text: clockWin.isKeys ? "STACK" : "KEYS"
                    font.family: "Consolas"; font.pixelSize: 9; font.weight: Font.Bold
                    color: themeHub.darkInk
                }
                MouseArea {
                    id: clockStyleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: themeHub.setClockStyle(clockWin.isKeys ? "stack" : "keys")
                }
            }

            Rectangle {
                width: 20; height: 20; radius: 6
                color: closeClockMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
                border.width: 1.5; border.color: themeHub.darkInk
                Image { anchors.centerIn: parent; width: 11; height: 11; source: "qrc:/qml/icons/close-circle-dark.svg" }
                MouseArea {
                    id: closeClockMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: themeHub.setWidgetVisible("clock", false)
                }
            }
        }
    }

    // =========================================================================
    // 2. SEKAIPOP WEATHER & HOURLY FORECAST WIDGET
    // =========================================================================
    WidgetShell {
        id: weatherWin
        widgetKey: "weather"
        visible: themeHub.wWeatherVisible && !fullscreenActive
        x: themeHub.wWeatherX
        y: themeHub.wWeatherY
        cardWidth: 306
        cardHeight: 222

        DragSurface { id: weatherDrag; shellWin: weatherWin; widgetKey: "weather" }

        Rectangle { x: 5; y: 5; width: 306; height: 222; radius: 18; color: themeHub.darkInk }

        Rectangle {
            width: 306; height: 222; radius: 18
            color: "#FFFFFF"
            border.width: 2.5; border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // City + Actions Row
                Item {
                    width: parent.width
                    height: 24

                    Rectangle {
                        id: wCityPill
                        anchors.left: parent.left
                        height: 24
                        width: Math.min(parent.width - 54, wCityTxt.implicitWidth + 24)
                        radius: 8
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: themeHub.accentA }
                            GradientStop { position: 1.0; color: themeHub.accentB }
                        }
                        border.width: 1.5; border.color: themeHub.darkInk

                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12
                                source: WeatherService.isDay ? "qrc:/qml/icons/sun-dark.svg" : "qrc:/qml/icons/moon-dark.svg"
                            }
                            Text {
                                id: wCityTxt
                                anchors.verticalCenter: parent.verticalCenter
                                text: WeatherService.city
                                font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 4
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: refWMa.containsMouse ? themeHub.hoverTint : "#F1F5F9"
                            border.width: 1.5; border.color: themeHub.darkInk
                            Text { anchors.centerIn: parent; text: "↻"; font.pixelSize: 12; font.weight: Font.Bold; color: themeHub.darkInk }
                            MouseArea { id: refWMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WeatherService.refresh() }
                        }
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: closeWMa.containsMouse ? "#FEE2E2" : "#F1F5F9"
                            border.width: 1.5; border.color: themeHub.darkInk
                            Image { anchors.centerIn: parent; width: 12; height: 12; source: "qrc:/qml/icons/close-circle-dark.svg" }
                            MouseArea { id: closeWMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("weather", false) }
                        }
                    }
                }

                // Temp + Condition row
                Row {
                    width: parent.width
                    spacing: 12
                    Text {
                        text: WeatherService.temperature + "°"
                        font.family: "Arial Black"; font.pixelSize: 40; font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: WeatherService.conditionText
                            font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Text {
                            text: "Feels " + WeatherService.feelsLike + "°  •  H " + WeatherService.tempMax + "° / L " + WeatherService.tempMin + "°"
                            font.family: "Segoe UI"; font.pixelSize: 11
                            color: "#475569"
                        }
                    }
                }

                // 3 Stat Tiles (Humidity / Wind / UV)
                Row {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [
                            { k: "HUMIDITY", v: WeatherService.humidity + "%" },
                            { k: "WIND", v: WeatherService.windSpeed + " km/h" },
                            { k: "UV INDEX", v: String(WeatherService.uvIndex) }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (weatherWin.cardWidth - 36) / 3
                            height: 36; radius: 8
                            color: "#F1F5F9"
                            border.width: 1.5; border.color: themeHub.darkInk
                            Column {
                                anchors.centerIn: parent
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.k
                                    font.family: "Segoe UI"; font.pixelSize: 8; font.weight: Font.Bold; color: "#64748B"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.v
                                    font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Bold; color: themeHub.darkInk
                                }
                            }
                        }
                    }
                }

                // 6-Hour Forecast Strip
                Rectangle {
                    width: parent.width
                    height: 54
                    radius: 10
                    color: themeHub.bandDeep
                    border.width: 1.5; border.color: themeHub.darkInk

                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4
                        Repeater {
                            model: WeatherService.hourlyForecast.length > 0
                                   ? WeatherService.hourlyForecast
                                   : [
                                         { time: "Now", temp: WeatherService.temperature },
                                         { time: "+1h", temp: WeatherService.temperature },
                                         { time: "+2h", temp: WeatherService.temperature },
                                         { time: "+3h", temp: WeatherService.temperature },
                                         { time: "+4h", temp: WeatherService.temperature },
                                         { time: "+5h", temp: WeatherService.temperature }
                                     ]
                            delegate: Column {
                                required property var modelData
                                width: (weatherWin.cardWidth - 56) / 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.time || ""
                                    font.family: "Consolas"; font.pixelSize: 9; font.weight: Font.Bold
                                    color: themeHub.accentA
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: (modelData.temp !== undefined ? modelData.temp : "--") + "°"
                                    font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Bold
                                    color: "#FFFFFF"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. SEKAIPOP USEFUL PROFILE & SYSTEM CARD
    // =========================================================================
    WidgetShell {
        id: profileWin
        widgetKey: "profile"
        visible: themeHub.wProfileVisible && !fullscreenActive
        x: themeHub.wProfileX
        y: themeHub.wProfileY
        cardWidth: 312
        cardHeight: editing ? 286 : 254

        property bool editing: false
        property bool burstOn: false
        Timer { id: burstReset; interval: 320; onTriggered: profileWin.burstOn = false }

        readonly property string greetingStr: {
            const h = widgetsRoot.nowDate.getHours()
            if (h < 12) return "GOOD MORNING"
            if (h < 18) return "GOOD AFTERNOON"
            return "GOOD EVENING"
        }
        readonly property int dayPct: {
            const d = widgetsRoot.nowDate
            const mins = d.getHours() * 60 + d.getMinutes()
            return Math.max(1, Math.min(100, Math.round((mins / 1440.0) * 100)))
        }

        DragSurface { id: profileDrag; shellWin: profileWin; widgetKey: "profile" }

        Rectangle { x: 5; y: 5; width: 312; height: profileWin.cardHeight; radius: 18; color: themeHub.darkInk }

        Rectangle {
            width: 312; height: profileWin.cardHeight; radius: 18
            color: "#FFFFFF"
            border.width: 2.5; border.color: themeHub.darkInk
            clip: true

            // Top SekaiPop Gradient Banner + Diamond Watermark
            Rectangle {
                id: profBanner
                width: parent.width; height: 52
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: themeHub.accentA }
                    GradientStop { position: 1.0; color: themeHub.accentB }
                }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width; height: 2.5; color: themeHub.darkInk
                }
                // Decorative diamond
                Rectangle {
                    x: 210; y: -12; width: 42; height: 42; radius: 6; rotation: 45
                    color: "#FFFFFF"; opacity: 0.25
                }

                // Greeting Chip
                Rectangle {
                    x: 12; y: 12; height: 24; width: greetTxt.implicitWidth + 16; radius: 7
                    color: "#FFFFFF"; border.width: 1.5; border.color: themeHub.darkInk
                    Text {
                        id: greetTxt
                        anchors.centerIn: parent
                        text: profileWin.greetingStr + ", " + WindowTracker.userName.toUpperCase()
                        font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                }

                Row {
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Rectangle {
                        width: 22; height: 22; radius: 6
                        color: editProfMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                        border.width: 1.5; border.color: themeHub.darkInk
                        Text { anchors.centerIn: parent; text: "✎"; font.pixelSize: 11; font.weight: Font.Bold; color: themeHub.darkInk }
                        MouseArea {
                            id: editProfMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                profNameEdit.text = themeHub.profileName
                                profStatusEdit.text = themeHub.profileStatus
                                profileWin.editing = !profileWin.editing
                            }
                        }
                    }
                    Rectangle {
                        width: 22; height: 22; radius: 6
                        color: closeProfMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
                        border.width: 1.5; border.color: themeHub.darkInk
                        Image { anchors.centerIn: parent; width: 12; height: 12; source: "qrc:/qml/icons/close-circle-dark.svg" }
                        MouseArea { id: closeProfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("profile", false) }
                    }
                }
            }

            // Main Body
            Column {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: profBanner.bottom
                anchors.margins: 12
                anchors.topMargin: 10
                spacing: 9

                // Avatar + Identity
                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: 48; height: 48; radius: 13
                        rotation: profileWin.burstOn ? -8 : -2
                        color: themeHub.bandDeep
                        border.width: 2; border.color: themeHub.darkInk
                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        Text {
                            anchors.centerIn: parent
                            text: profileWin.burstOn ? "✦‿✦" : ">^.^<"
                            font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Bold
                            color: themeHub.accentA
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                profileWin.burstOn = true
                                burstReset.restart()
                            }
                        }
                    }

                    Column {
                        width: parent.width - 60
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: themeHub.profileName + "  •  @" + WindowTracker.machineName
                            font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: themeHub.profileStatus
                            font.family: "Segoe UI"; font.pixelSize: 11
                            color: "#475569"
                        }
                    }
                }

                // Optional inline edit bar
                Row {
                    visible: profileWin.editing
                    width: parent.width
                    spacing: 5
                    Rectangle {
                        width: 96; height: 26; radius: 7; color: "#F1F5F9"; border.width: 1.5; border.color: themeHub.darkInk
                        TextInput {
                            id: profNameEdit
                            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI"; font.pixelSize: 11; color: themeHub.darkInk
                        }
                    }
                    Rectangle {
                        width: parent.width - 148; height: 26; radius: 7; color: "#F1F5F9"; border.width: 1.5; border.color: themeHub.darkInk
                        TextInput {
                            id: profStatusEdit
                            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI"; font.pixelSize: 11; color: themeHub.darkInk
                        }
                    }
                    Rectangle {
                        width: 42; height: 26; radius: 7; color: themeHub.accentA; border.width: 1.5; border.color: themeHub.darkInk
                        Text { anchors.centerIn: parent; text: "Save"; font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Bold; color: themeHub.darkInk }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                themeHub.saveProfile(profNameEdit.text, profStatusEdit.text)
                                profileWin.editing = false
                            }
                        }
                    }
                }

                // 3 SekaiPop StatKey Tiles (UPTIME / CPU / RAM)
                Row {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [
                            { k: "UPTIME", v: WindowTracker.uptimeText },
                            { k: "CPU", v: WindowTracker.cpuUsage + "%" },
                            { k: "RAM", v: WindowTracker.ramUsage + "%" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 12) / 3
                            height: 40; radius: 9
                            color: "#F8FAFC"
                            border.width: 1.5; border.color: themeHub.darkInk
                            Column {
                                anchors.centerIn: parent
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.k; font.family: "Segoe UI"; font.pixelSize: 9; font.weight: Font.Bold; color: "#64748B" }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Bold; color: themeHub.darkInk }
                            }
                        }
                    }
                }

                // TODAY Progress Lane
                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TODAY " + profileWin.dayPct + "%"
                        font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Bold; color: "#475569"
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 78; height: 9; radius: 5
                        color: "#E2E8F0"; border.width: 1.2; border.color: themeHub.darkInk
                        Rectangle {
                            width: Math.max(8, parent.width * (profileWin.dayPct / 100.0))
                            height: parent.height; radius: 5
                            color: themeHub.accentA
                        }
                    }
                }

                // 4 Real Quick Utility Action Pills
                Row {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [
                            { label: "Home", act: "home" },
                            { label: "Shot", act: "shot" },
                            { label: "Themes", act: "hub" },
                            { label: "Lock", act: "lock" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 18) / 4
                            height: 28; radius: 8
                            color: actMa.containsMouse ? themeHub.accentA : themeHub.bandDeep
                            border.width: 1.5; border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Bold
                                color: actMa.containsMouse ? themeHub.darkInk : themeHub.accentA
                            }
                            MouseArea {
                                id: actMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.act === "home") WindowTracker.openSpecialFolder("home")
                                    else if (modelData.act === "shot") WindowTracker.takeScreenshot()
                                    else if (modelData.act === "hub") themeHub.settingsOpen = true
                                    else if (modelData.act === "lock") WindowTracker.lockWorkstation()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 4. SEKAIPOP TODO CHECKLIST WIDGET
    // =========================================================================
    WidgetShell {
        id: todoWin
        widgetKey: "todo"
        visible: themeHub.wTodoVisible && !fullscreenActive
        x: themeHub.wTodoX
        y: themeHub.wTodoY
        cardWidth: 274
        cardHeight: 266

        DragSurface { shellWin: todoWin; widgetKey: "todo" }

        Rectangle { x: 5; y: 5; width: 274; height: 266; radius: 18; color: themeHub.darkInk }

        Rectangle {
            width: 274; height: 266; radius: 18
            color: "#FFFFFF"
            border.width: 2.5; border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 8

                Item {
                    width: parent.width; height: 26
                    Rectangle {
                        height: 24; width: todoTitleTxt.implicitWidth + 24; radius: 8
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: themeHub.accentA }
                            GradientStop { position: 1.0; color: themeHub.accentB }
                        }
                        border.width: 1.5; border.color: themeHub.darkInk
                        Row {
                            anchors.centerIn: parent; spacing: 5
                            Image { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; source: "qrc:/qml/icons/checklist-dark.svg" }
                            Text { id: todoTitleTxt; anchors.verticalCenter: parent.verticalCenter; text: "TASKS (" + themeHub.todoItems.length + ")"; font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: themeHub.darkInk }
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right; width: 22; height: 22; radius: 6
                        color: closeTodoMa.containsMouse ? "#FEE2E2" : "#F1F5F9"
                        border.width: 1.5; border.color: themeHub.darkInk
                        Image { anchors.centerIn: parent; width: 12; height: 12; source: "qrc:/qml/icons/close-circle-dark.svg" }
                        MouseArea { id: closeTodoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("todo", false) }
                    }
                }

                // Add task bar
                Row {
                    width: parent.width; spacing: 6
                    Rectangle {
                        width: parent.width - 36; height: 28; radius: 8
                        color: "#F8FAFC"; border.width: 1.5; border.color: themeHub.darkInk
                        TextInput {
                            id: todoInput
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI"; font.pixelSize: 11; color: themeHub.darkInk
                            Keys.onReturnPressed: { themeHub.addTodo(text); text = "" }
                            Text {
                                anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter
                                visible: parent.text === ""; text: "Add task..."
                                font: parent.font; color: "#94A3B8"
                            }
                        }
                    }
                    Rectangle {
                        width: 30; height: 28; radius: 8
                        color: themeHub.accentA; border.width: 1.5; border.color: themeHub.darkInk
                        Text { anchors.centerIn: parent; text: "+"; font.family: "Segoe UI"; font.pixelSize: 16; font.weight: Font.Bold; color: themeHub.darkInk }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { themeHub.addTodo(todoInput.text); todoInput.text = "" } }
                    }
                }

                ListView {
                    width: parent.width; height: parent.height - 76
                    clip: true; spacing: 5
                    model: themeHub.todoItems
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 240
                        height: 30; radius: 8
                        color: modelData.done ? "#F1F5F9" : themeHub.hoverTint
                        border.width: 1.2; border.color: modelData.done ? "#CBD5E1" : themeHub.darkInk

                        Row {
                            anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 6; spacing: 7
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 15; height: 15; radius: 4
                                color: modelData.done ? themeHub.accentB : "#FFFFFF"
                                border.width: 1.5; border.color: themeHub.darkInk
                                Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"; font.pixelSize: 10; font.weight: Font.Bold; color: themeHub.darkInk }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.toggleTodo(index) }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 42; elide: Text.ElideRight
                                text: modelData.text || ""
                                font.family: "Segoe UI"; font.pixelSize: 11; font.strikeout: !!modelData.done
                                color: modelData.done ? "#94A3B8" : themeHub.darkInk
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.toggleTodo(index) }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 4; color: "#FEE2E2"
                                Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 10; font.weight: Font.Bold; color: "#DC2626" }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.removeTodo(index) }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 5. SEKAIPOP STICKY NOTE WIDGET
    // =========================================================================
    WidgetShell {
        id: notesWin
        widgetKey: "notes"
        visible: themeHub.wNotesVisible && !fullscreenActive
        x: themeHub.wNotesX
        y: themeHub.wNotesY
        cardWidth: 274
        cardHeight: 204

        DragSurface { shellWin: notesWin; widgetKey: "notes" }

        Rectangle { x: 5; y: 5; width: 274; height: 204; radius: 18; color: themeHub.darkInk }

        Rectangle {
            width: 274; height: 204; radius: 18
            color: "#FEFCE8"
            border.width: 2.5; border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 7

                Item {
                    width: parent.width; height: 24
                    Rectangle {
                        height: 24; width: 102; radius: 8
                        color: themeHub.accentB
                        border.width: 1.5; border.color: themeHub.darkInk
                        Row {
                            anchors.centerIn: parent; spacing: 5
                            Image { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; source: "qrc:/qml/icons/notes-dark.svg" }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "NOTES"; font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: themeHub.darkInk }
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right; width: 22; height: 22; radius: 6
                        color: closeNoteMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
                        border.width: 1.5; border.color: themeHub.darkInk
                        Image { anchors.centerIn: parent; width: 12; height: 12; source: "qrc:/qml/icons/close-circle-dark.svg" }
                        MouseArea { id: closeNoteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("notes", false) }
                    }
                }

                Rectangle {
                    width: parent.width; height: parent.height - 32
                    radius: 10; color: "#FFFFFF"; border.width: 1.5; border.color: themeHub.darkInk
                    Flickable {
                        anchors.fill: parent; anchors.margins: 8
                        contentWidth: width; contentHeight: Math.max(height, noteEdit.paintedHeight)
                        clip: true
                        TextEdit {
                            id: noteEdit
                            width: parent.width
                            wrapMode: TextEdit.Wrap
                            font.family: "Segoe UI"; font.pixelSize: 12; color: themeHub.darkInk
                            text: themeHub.noteText
                            onTextChanged: {
                                if (text !== themeHub.noteText)
                                    noteSaveDebounce.restart()
                            }
                            Timer {
                                id: noteSaveDebounce
                                interval: 280
                                onTriggered: themeHub.saveNoteText(noteEdit.text)
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 6. SAFE WINHTTP LIVE KARAOKE LYRICS WIDGET (#10 Fixed + Manual Search)
    // =========================================================================
    WidgetShell {
        id: lyricsWin
        widgetKey: "lyrics"
        visible: themeHub.wLyricsVisible && !fullscreenActive
        x: themeHub.wLyricsX
        y: themeHub.wLyricsY
        cardWidth: 356
        cardHeight: 238

        DragSurface { shellWin: lyricsWin; widgetKey: "lyrics" }

        Rectangle { x: 5; y: 5; width: 356; height: 238; radius: 18; color: themeHub.darkInk }

        Rectangle {
            width: 356; height: 238; radius: 18
            color: themeHub.bandDeep
            border.width: 2.5; border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                // Header
                Item {
                    width: parent.width; height: 24

                    Rectangle {
                        id: lyrBadge
                        anchors.left: parent.left
                        height: 24; width: 92; radius: 8
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: themeHub.accentA }
                            GradientStop { position: 1.0; color: themeHub.accentB }
                        }
                        border.width: 1.5; border.color: themeHub.darkInk
                        Row {
                            anchors.centerIn: parent; spacing: 5
                            Image { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; source: "qrc:/qml/icons/music-note-dark.svg" }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: LyricsService.synced ? "SYNCED" : "LYRICS"; font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Bold; color: themeHub.darkInk }
                        }
                    }

                    Text {
                        anchors.left: lyrBadge.right; anchors.right: lyrBtns.left
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: MediaService.hasSession ? (MediaService.title + " — " + MediaService.artist) : (LyricsService.trackKey || "No Track Playing")
                        font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold
                        color: "#E2E8F0"
                    }

                    Row {
                        id: lyrBtns
                        anchors.right: parent.right
                        spacing: 4
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: lyrRefMa.containsMouse ? themeHub.accentA : "#334155"
                            border.width: 1.2; border.color: themeHub.accentA
                            Text { anchors.centerIn: parent; text: "↻"; font.pixelSize: 12; font.weight: Font.Bold; color: lyrRefMa.containsMouse ? themeHub.darkInk : themeHub.accentA }
                            MouseArea { id: lyrRefMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: LyricsService.refresh() }
                        }
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: closeLyrMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
                            border.width: 1.2; border.color: themeHub.darkInk
                            Image { anchors.centerIn: parent; width: 12; height: 12; source: "qrc:/qml/icons/close-circle-dark.svg" }
                            MouseArea { id: closeLyrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("lyrics", false) }
                        }
                    }
                }

                // Inline Manual Search Bar (Bug #10 fix: safe WinHTTP LRCLIB lookup)
                Row {
                    width: parent.width; spacing: 6
                    Rectangle {
                        width: parent.width - 66; height: 28; radius: 8
                        color: "#0F172A"; border.width: 1.5; border.color: themeHub.accentA
                        TextInput {
                            id: lyrSearchInput
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Segoe UI"; font.pixelSize: 11; color: "#F8FAFC"
                            Keys.onReturnPressed: LyricsService.searchManual(text)
                            Text {
                                anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter
                                visible: parent.text === ""; text: "Search song lyrics manually..."
                                font: parent.font; color: "#64748B"
                            }
                        }
                    }
                    Rectangle {
                        width: 60; height: 28; radius: 8
                        color: themeHub.accentA; border.width: 1.5; border.color: themeHub.darkInk
                        Text { anchors.centerIn: parent; text: "Search"; font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: themeHub.darkInk }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: LyricsService.searchManual(lyrSearchInput.text)
                        }
                    }
                }

                // Empty / Loading State
                Item {
                    width: parent.width; height: parent.height - 68
                    visible: !LyricsService.hasLyrics
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: LyricsService.loading ? "Searching LRCLIB..." : (LyricsService.statusText || "Play music or search song title above")
                        font.family: "Segoe UI"; font.pixelSize: 12; color: "#94A3B8"
                    }
                }

                // Synced / Plain Karaoke Scroll List (no ListView.view null crash, valid MediaService.seek())
                ListView {
                    id: lyricsList
                    width: parent.width; height: parent.height - 68
                    visible: LyricsService.hasLyrics
                    clip: true; spacing: 5
                    model: LyricsService.lines
                    currentIndex: LyricsService.activeIndex

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < count)
                            positionViewAtIndex(currentIndex, ListView.Center)
                    }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: index === LyricsService.activeIndex
                        width: lyricsList.width
                        height: Math.max(28, lineTxt.implicitHeight + 10)
                        radius: 8
                        color: isCurrent ? themeHub.accentA : "transparent"

                        Text {
                            id: lineTxt
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.text || ""
                            font.family: "Segoe UI"
                            font.pixelSize: isCurrent ? 13.5 : 11.5
                            font.weight: isCurrent ? Font.Bold : Font.Normal
                            color: isCurrent ? themeHub.darkInk : "#CBD5E1"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData && modelData.time !== undefined && modelData.time >= 0)
                                    MediaService.seek(modelData.time)
                            }
                        }
                    }
                }
            }
        }
    }
}
