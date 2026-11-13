import QtQuick
import Quickshell
import SekaiDesk

Item {
    id: widgetsRoot
    visible: false

    required property var themeHub
    required property bool fullscreenActive

    // Live wall-clock tick shared cleanly by Clock, Profile, Calendar
    property date nowDate: new Date()
    property bool beatPhase: false
    Timer {
        interval: 1000
        repeat: true
        running: themeHub.wClockVisible || themeHub.wProfileVisible || themeHub.wCalendarVisible
        onTriggered: {
            widgetsRoot.nowDate = new Date()
            widgetsRoot.beatPhase = !widgetsRoot.beatPhase
        }
    }

    // -------------------------------------------------------------------------
    // Core Window Shell & Drag Surface (desktopLayer: true)
    // -------------------------------------------------------------------------
    component WidgetShell: PanelWindow {
        id: wShell
        required property string widgetKey
        required property int cardWidth
        required property int cardHeight
        property bool allowFocus: false
        property int shadowOffset: 8
        default property alias content: innerContainer.data

        color: "transparent"
        clickThrough: false
        desktopLayer: true
        desktopAllowFocus: allowFocus
        width: cardWidth + shadowOffset
        height: cardHeight + shadowOffset

        Item {
            id: innerContainer
            x: 2
            y: 2
            width: wShell.cardWidth
            height: wShell.cardHeight
        }
    }

    component DragSurface: MouseArea {
        required property var shellWin
        required property string widgetKey
        required property var hubRef
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
            const maxW = hubRef ? hubRef.screenW - 80 : 1840
            const maxH = hubRef ? hubRef.screenH - 60 : 1020
            const nx = Math.max(8, Math.min(maxW, Math.round(startWinX + (cur.x - startMouse.x))))
            const ny = Math.max(52, Math.min(maxH, Math.round(startWinY + (cur.y - startMouse.y))))
            shellWin.x = nx
            shellWin.y = ny
        }
        onReleased: {
            if (dragging) {
                dragging = false
                if (hubRef)
                    hubRef.saveWidgetPos(widgetKey, shellWin.x, shellWin.y)
            }
        }
        onCanceled: dragging = false
    }

    // -------------------------------------------------------------------------
    // SekaiPop Visual Primitives (inline components — QRC-safe)
    // -------------------------------------------------------------------------
    component DiamondDot: Item {
        id: dd
        property int size: 8
        property color color: "#FFFFFF"
        property color borderColor: "#1A1B2E"
        property int borderWidth: 1
        width: size
        height: size
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(4, Math.round(dd.size * 0.72))
            height: width
            rotation: 45
            radius: 1
            color: dd.color
            border.color: dd.borderColor
            border.width: dd.borderWidth
            antialiasing: true
        }
    }

    component Slant: Canvas {
        id: slantCanvas
        property color color: "#28FFFFFF"
        property real skew: 0.28
        property int cornerRadius: 0
        onColorChanged: requestPaint()
        onSkewChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 2 || height <= 2)
                return
            const dx = Math.min(width * 0.45, Math.abs(skew) * height)
            ctx.fillStyle = color
            ctx.beginPath()
            if (skew >= 0) {
                ctx.moveTo(dx, 0)
                ctx.lineTo(width, 0)
                ctx.lineTo(width - dx, height)
                ctx.lineTo(0, height)
            } else {
                ctx.moveTo(0, 0)
                ctx.lineTo(width - dx, 0)
                ctx.lineTo(width, height)
                ctx.lineTo(dx, height)
            }
            ctx.closePath()
            ctx.fill()
        }
    }

    component DotField: Canvas {
        id: dotFieldCanvas
        property color color: "#1A1B2E"
        property real dotAlpha: 0.12
        property int step: 11
        property real dotRadius: 1.5
        onColorChanged: requestPaint()
        onDotAlphaChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width <= 4 || height <= 4)
                return
            ctx.save()
            ctx.globalAlpha = dotAlpha
            ctx.fillStyle = color
            let row = 0
            for (let y = 5; y < height - 2; y += step) {
                const offset = (row % 2 === 1) ? step * 0.5 : 0
                for (let x = 5 + offset; x < width - 2; x += step) {
                    ctx.beginPath()
                    ctx.arc(x, y, dotRadius, 0, Math.PI * 2)
                    ctx.fill()
                }
                row++
            }
            ctx.restore()
        }
    }

    component SekaiPill: Item {
        id: pillRoot
        property int radius: 18
        property color color: "#FFFFFF"
        property color gradientTop: "transparent"
        property color gradientBottom: "transparent"
        property bool useGradient: false
        property color inkColor: "#1A1B2E"
        property int borderWidth: 3
        property int shadowShift: 4
        property color shadowColor: "#1A1B2E"
        property bool showInnerRing: true
        property color ringColor: "#99FFFFFF"
        property bool pressedState: false
        property bool clipContent: true
        default property alias inner: pillContent.data

        readonly property int pressOffset: pressedState ? Math.max(2, shadowShift - 1) : 0

        Rectangle {
            id: pillShadow
            x: pillRoot.shadowShift
            y: pillRoot.shadowShift
            width: Math.max(0, pillRoot.width - pillRoot.shadowShift)
            height: Math.max(0, pillRoot.height - pillRoot.shadowShift)
            radius: pillRoot.radius
            color: pillRoot.shadowColor
            visible: pillRoot.shadowShift > 0
        }

        Rectangle {
            id: pillBody
            x: pillRoot.pressOffset
            y: pillRoot.pressOffset
            width: Math.max(0, pillRoot.width - pillRoot.shadowShift)
            height: Math.max(0, pillRoot.height - pillRoot.shadowShift)
            radius: pillRoot.radius
            color: pillRoot.useGradient ? "transparent" : pillRoot.color
            border.color: pillRoot.inkColor
            border.width: pillRoot.borderWidth
            clip: pillRoot.clipContent
            antialiasing: true

            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
            Behavior on y { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

            gradient: Gradient {
                GradientStop { position: 0.0; color: pillRoot.useGradient ? pillRoot.gradientTop : pillRoot.color }
                GradientStop { position: 1.0; color: pillRoot.useGradient ? pillRoot.gradientBottom : pillRoot.color }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: pillRoot.borderWidth
                radius: Math.max(2, pillRoot.radius - pillRoot.borderWidth)
                color: "transparent"
                border.color: pillRoot.ringColor
                border.width: 2
                visible: pillRoot.showInnerRing
                z: 50
            }

            Item {
                id: pillContent
                anchors.fill: parent
                anchors.margins: pillRoot.borderWidth
            }
        }
    }

    component SekaiPlate: Item {
        id: plateRoot
        property int radius: 16
        property color topColor: "#FF5E9E"
        property color bottomColor: "#8A63FF"
        property color inkColor: "#1A1B2E"
        property int borderWidth: 3
        property int shadowShift: 4
        property real dotAlpha: 0.14
        default property alias plateContent: plateBody.data

        SekaiPill {
            anchors.fill: parent
            radius: plateRoot.radius
            useGradient: true
            gradientTop: plateRoot.topColor
            gradientBottom: plateRoot.bottomColor
            inkColor: plateRoot.inkColor
            borderWidth: plateRoot.borderWidth
            shadowShift: plateRoot.shadowShift
            ringColor: "#B3FFFFFF"

            DotField {
                anchors.fill: parent
                color: plateRoot.inkColor
                dotAlpha: plateRoot.dotAlpha
                step: 10
                dotRadius: 1.4
            }

            Slant {
                x: Math.round(parent.width * 0.14)
                y: -4
                width: Math.round(parent.width * 0.24)
                height: parent.height + 8
                color: "#22FFFFFF"
                skew: 0.34
            }

            Slant {
                x: Math.round(parent.width * 0.62)
                y: -4
                width: Math.round(parent.width * 0.12)
                height: parent.height + 8
                color: "#1CFFFFFF"
                skew: 0.34
            }

            Item {
                id: plateBody
                anchors.fill: parent
            }
        }
    }

    component StickerText: Item {
        id: stRoot
        property string text: ""
        property int fontSize: 28
        property color fillColor: "#FFFFFF"
        property color inkColor: "#1A1B2E"
        property color haloColor: "#FFFFFF"
        property int shadowShift: 3
        property int inkThickness: 3
        property int haloThickness: 2
        property bool popOnChange: false
        property string fontFamily: "Segoe UI"
        property int fontWeight: Font.Black

        implicitWidth: Math.ceil(mainTxt.implicitWidth) + (inkThickness + haloThickness) * 2 + shadowShift + 4
        implicitHeight: Math.ceil(mainTxt.implicitHeight) + (inkThickness + haloThickness) * 2 + shadowShift + 2
        width: implicitWidth
        height: implicitHeight

        onTextChanged: {
            if (popOnChange)
                popAnim.restart()
        }

        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: stScale; property: "xScale"; to: 1.12; duration: 75; easing.type: Easing.OutQuad }
            NumberAnimation { target: stScale; property: "xScale"; to: 1.0; duration: 150; easing.type: Easing.OutBack }
        }

        Item {
            anchors.fill: parent
            transform: Scale {
                id: stScale
                origin.x: stRoot.width / 2
                origin.y: stRoot.height / 2
                xScale: 1.0
                yScale: xScale
            }

            // Hard comic drop shadow
            Text {
                x: stRoot.inkThickness + stRoot.haloThickness + stRoot.shadowShift
                y: stRoot.inkThickness + stRoot.haloThickness + stRoot.shadowShift
                text: stRoot.text
                font.family: stRoot.fontFamily
                font.pixelSize: Math.max(8, Math.round(stRoot.fontSize))
                font.weight: stRoot.fontWeight
                color: stRoot.inkColor
            }

            // Outer white halo ring (if > 0)
            Repeater {
                model: stRoot.haloThickness > 0 ? [
                    { dx: -1, dy: 0 }, { dx: 1, dy: 0 }, { dx: 0, dy: -1 }, { dx: 0, dy: 1 },
                    { dx: -1, dy: -1 }, { dx: 1, dy: -1 }, { dx: -1, dy: 1 }, { dx: 1, dy: 1 }
                ] : []
                Text {
                    required property var modelData
                    x: stRoot.inkThickness + stRoot.haloThickness + modelData.dx * (stRoot.inkThickness + stRoot.haloThickness)
                    y: stRoot.inkThickness + stRoot.haloThickness + modelData.dy * (stRoot.inkThickness + stRoot.haloThickness)
                    text: stRoot.text
                    font.family: stRoot.fontFamily
                    font.pixelSize: Math.max(8, Math.round(stRoot.fontSize))
                    font.weight: stRoot.fontWeight
                    color: stRoot.haloColor
                }
            }

            // Crisp dark ink outline
            Repeater {
                model: [
                    { dx: -1, dy: 0 }, { dx: 1, dy: 0 }, { dx: 0, dy: -1 }, { dx: 0, dy: 1 },
                    { dx: -1, dy: -1 }, { dx: 1, dy: -1 }, { dx: -1, dy: 1 }, { dx: 1, dy: 1 }
                ]
                Text {
                    required property var modelData
                    x: stRoot.inkThickness + stRoot.haloThickness + modelData.dx * stRoot.inkThickness
                    y: stRoot.inkThickness + stRoot.haloThickness + modelData.dy * stRoot.inkThickness
                    text: stRoot.text
                    font.family: stRoot.fontFamily
                    font.pixelSize: Math.max(8, Math.round(stRoot.fontSize))
                    font.weight: stRoot.fontWeight
                    color: stRoot.inkColor
                }
            }

            Text {
                id: mainTxt
                x: stRoot.inkThickness + stRoot.haloThickness
                y: stRoot.inkThickness + stRoot.haloThickness
                text: stRoot.text
                font.family: stRoot.fontFamily
                font.pixelSize: Math.max(8, Math.round(stRoot.fontSize))
                font.weight: stRoot.fontWeight
                color: stRoot.fillColor
            }
        }
    }

    component Burst: Item {
        id: burstRoot
        property color colorA: "#FF5E9E"
        property color colorB: "#4ECDC4"
        property color inkColor: "#1A1B2E"
        property real progress: 0.0
        property bool active: false
        width: 72
        height: 72
        visible: active

        function fire() {
            active = true
            burstAnim.restart()
        }

        SequentialAnimation {
            id: burstAnim
            NumberAnimation { target: burstRoot; property: "progress"; from: 0.0; to: 1.0; duration: 420; easing.type: Easing.OutCubic }
            ScriptAction { script: burstRoot.active = false }
        }

        Repeater {
            model: 8
            Item {
                required property int index
                readonly property real angle: index * Math.PI / 4
                readonly property real dist: 12 + burstRoot.progress * 24
                x: burstRoot.width / 2 + Math.cos(angle) * dist - 4
                y: burstRoot.height / 2 + Math.sin(angle) * dist - 4
                width: 8
                height: 8
                opacity: 1.0 - burstRoot.progress
                scale: 1.15 - burstRoot.progress * 0.55

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    rotation: 45
                    color: (index % 2 === 0) ? burstRoot.colorA : burstRoot.colorB
                    border.color: burstRoot.inkColor
                    border.width: 1
                }
            }
        }
    }

    component WeatherGlyph: Canvas {
        id: wgCanvas
        property int code: 0
        property bool isDay: true
        property color inkColor: "#FFFFFF"
        property color accentColor: "#FFD166"
        onCodeChanged: requestPaint()
        onIsDayChanged: requestPaint()
        onInkColorChanged: requestPaint()
        onAccentColorChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const w = width
            const h = height
            const cx = w * 0.5
            const cy = h * 0.5
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.strokeStyle = inkColor
            ctx.lineWidth = Math.max(2, Math.round(Math.min(w, h) * 0.09))

            function drawSun(sx, sy, sr) {
                ctx.fillStyle = accentColor
                ctx.beginPath()
                ctx.arc(sx, sy, sr, 0, Math.PI * 2)
                ctx.fill()
                ctx.stroke()
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4
                    ctx.beginPath()
                    ctx.moveTo(sx + Math.cos(a) * (sr + 3), sy + Math.sin(a) * (sr + 3))
                    ctx.lineTo(sx + Math.cos(a) * (sr + 6), sy + Math.sin(a) * (sr + 6))
                    ctx.stroke()
                }
            }
            function drawMoon(mx, my, mr) {
                ctx.fillStyle = accentColor
                ctx.beginPath()
                ctx.arc(mx, my, mr, 0.35, Math.PI * 1.65, false)
                ctx.arc(mx + mr * 0.45, my - mr * 0.15, mr * 0.78, Math.PI * 1.55, 0.45, true)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
            }
            function drawCloud(cx0, cy0, cw) {
                ctx.fillStyle = "#FFFFFF"
                ctx.beginPath()
                ctx.moveTo(cx0 - cw * 0.35, cy0 + cw * 0.22)
                ctx.arc(cx0 - cw * 0.24, cy0 + cw * 0.04, cw * 0.20, Math.PI * 0.65, Math.PI * 1.85)
                ctx.arc(cx0 + cw * 0.02, cy0 - cw * 0.08, cw * 0.25, Math.PI * 1.05, Math.PI * 1.98)
                ctx.arc(cx0 + cw * 0.28, cy0 + cw * 0.06, cw * 0.18, Math.PI * 1.35, Math.PI * 0.5)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
            }

            if (code === 0) {
                if (isDay) drawSun(cx, cy, Math.min(w, h) * 0.20)
                else drawMoon(cx, cy, Math.min(w, h) * 0.26)
            } else if (code <= 2) {
                if (isDay) drawSun(cx - w * 0.14, cy - h * 0.12, Math.min(w, h) * 0.15)
                else drawMoon(cx - w * 0.14, cy - h * 0.12, Math.min(w, h) * 0.18)
                drawCloud(cx + w * 0.06, cy + h * 0.08, Math.min(w, h) * 0.66)
            } else if (code === 3 || code === 45 || code === 48) {
                drawCloud(cx, cy - (code >= 45 ? h * 0.08 : 0), Math.min(w, h) * 0.72)
                if (code >= 45) {
                    ctx.beginPath()
                    ctx.moveTo(cx - w * 0.24, cy + h * 0.24)
                    ctx.lineTo(cx + w * 0.24, cy + h * 0.24)
                    ctx.moveTo(cx - w * 0.18, cy + h * 0.36)
                    ctx.lineTo(cx + w * 0.18, cy + h * 0.36)
                    ctx.stroke()
                }
            } else if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
                drawCloud(cx, cy - h * 0.08, Math.min(w, h) * 0.68)
                ctx.strokeStyle = "#4ECDC4"
                for (let k = -1; k <= 1; k++) {
                    const rx = cx + k * w * 0.16
                    ctx.beginPath()
                    ctx.moveTo(rx, cy + h * 0.18)
                    ctx.lineTo(rx - w * 0.05, cy + h * 0.36)
                    ctx.stroke()
                }
            } else if ((code >= 71 && code <= 77) || code === 85 || code === 86) {
                drawCloud(cx, cy - h * 0.08, Math.min(w, h) * 0.68)
                ctx.fillStyle = "#D8F3FF"
                for (let k = -1; k <= 1; k++) {
                    ctx.beginPath()
                    ctx.arc(cx + k * w * 0.17, cy + h * 0.28, Math.max(2, w * 0.055), 0, Math.PI * 2)
                    ctx.fill()
                }
            } else if (code >= 95) {
                drawCloud(cx, cy - h * 0.10, Math.min(w, h) * 0.68)
                ctx.strokeStyle = "#FFD166"
                ctx.beginPath()
                ctx.moveTo(cx + w * 0.04, cy + h * 0.12)
                ctx.lineTo(cx - w * 0.08, cy + h * 0.26)
                ctx.lineTo(cx + w * 0.04, cy + h * 0.26)
                ctx.lineTo(cx - w * 0.06, cy + h * 0.42)
                ctx.stroke()
            } else {
                drawCloud(cx, cy, Math.min(w, h) * 0.70)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Helper Functions (strict JS math for Calendar & Weather)
    // -------------------------------------------------------------------------
    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    function isoDateStr(d) {
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    }

    function isoWeekNumber(d) {
        const tmp = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        tmp.setHours(0, 0, 0, 0)
        tmp.setDate(tmp.getDate() + 3 - ((tmp.getDay() + 6) % 7))
        const week1 = new Date(tmp.getFullYear(), 0, 4)
        return 1 + Math.round(((tmp.getTime() - week1.getTime()) / 86400000 - 3 + ((week1.getDay() + 6) % 7)) / 7)
    }

    function attrColor(attr) {
        if (attr === "cute") return "#FF5E9E"
        if (attr === "cool") return "#4ECDC4"
        if (attr === "pure") return "#54D17A"
        if (attr === "happy") return "#FFA94D"
        if (attr === "mysterious") return "#9B72FF"
        return themeHub.accentA
    }

    function uvColor(uv) {
        if (uv < 3) return "#54D17A"
        if (uv < 6) return "#FFD166"
        if (uv < 8) return "#FFA94D"
        if (uv < 11) return "#FF5E7E"
        return "#9B72FF"
    }

    // =========================================================================
    // 1. CLOCK WIDGET (4 SekaiPop Modes: KEYS / TOWER / STICKER / STACK)
    // =========================================================================
    WidgetShell {
        id: clockWin
        widgetKey: "clock"
        allowFocus: false
        readonly property int mode: Math.max(0, Math.min(3, themeHub.clockStyle))
        cardWidth: mode === 0 ? 320 : (mode === 1 ? 238 : (mode === 2 ? 344 : 224))
        cardHeight: mode === 0 ? 276 : (mode === 1 ? 304 : (mode === 2 ? 176 : 254))
        x: themeHub.wClockX
        y: themeHub.wClockY
        visible: themeHub.wClockVisible && !widgetsRoot.fullscreenActive

        readonly property int rawH: widgetsRoot.nowDate.getHours()
        readonly property int dispH: themeHub.clockUse24h ? rawH : ((rawH % 12 === 0) ? 12 : rawH % 12)
        readonly property int mins: widgetsRoot.nowDate.getMinutes()
        readonly property int secs: widgetsRoot.nowDate.getSeconds()
        readonly property string h1: Math.floor(dispH / 10) + ""
        readonly property string h2: (dispH % 10) + ""
        readonly property string m1: Math.floor(mins / 10) + ""
        readonly property string m2: (mins % 10) + ""
        readonly property string ampm: themeHub.clockUse24h ? "24H" : (rawH >= 12 ? "PM" : "AM")
        readonly property int weekdayIdx: (widgetsRoot.nowDate.getDay() + 6) % 7
        readonly property string monthShort: ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"][widgetsRoot.nowDate.getMonth()]
        readonly property string dayShort: ["MON","TUE","WED","THU","FRI","SAT","SUN"][weekdayIdx]
        readonly property int dayNum: widgetsRoot.nowDate.getDate()
        property bool hovered: false

        DragSurface {
            shellWin: clockWin
            widgetKey: "clock"
            hubRef: widgetsRoot.themeHub
            onDoubleClicked: widgetsRoot.themeHub.setClockUse24h(!widgetsRoot.themeHub.clockUse24h)
        }

        HoverHandler {
            onHoveredChanged: clockWin.hovered = hovered
        }

        // Floating hover action strip (Mode / 12-24h / Close)
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 10
            spacing: 5
            z: 40
            opacity: clockWin.hovered ? 1.0 : 0.0
            visible: opacity > 0.02
            Behavior on opacity { NumberAnimation { duration: 130 } }

            Rectangle {
                height: 22
                width: modeLabel.implicitWidth + 14
                radius: 11
                color: themeHub.darkInk
                border.color: "#FFFFFF"
                border.width: 2
                Text {
                    id: modeLabel
                    anchors.centerIn: parent
                    text: themeHub.clockDesignNames[clockWin.mode] || "KEYS"
                    font.pixelSize: 10
                    font.weight: Font.Black
                    color: "#FFFFFF"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: themeHub.cycleClockStyle()
                }
            }

            Rectangle {
                height: 22
                width: 22
                radius: 11
                color: "#FFFFFF"
                border.color: themeHub.darkInk
                border.width: 2
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.pixelSize: 13
                    font.weight: Font.Black
                    color: themeHub.darkInk
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: themeHub.setWidgetVisible("clock", false)
                }
            }
        }

        // --- MODE 0: KEYS (SekaiPop 320x276 3D Keycap Board) ---
        SekaiPill {
            anchors.fill: parent
            visible: clockWin.mode === 0
            radius: 22
            color: "#FFFDF9"
            inkColor: themeHub.darkInk
            shadowShift: 5

            // Subtle vertical guide lanes
            Row {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 42
                opacity: 0.06
                Repeater {
                    model: 6
                    Rectangle { width: 2; height: parent.height; color: themeHub.darkInk }
                }
            }

            // Header: DateSticker + AmPmSwitch
            Item {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                height: 36

                SekaiPill {
                    id: dateSticker
                    width: 146
                    height: 32
                    radius: 11
                    color: themeHub.accentB
                    inkColor: themeHub.darkInk
                    borderWidth: 2
                    shadowShift: 3
                    rotation: -2.0
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: clockWin.dayShort + " " + widgetsRoot.pad2(clockWin.dayNum) + " " + clockWin.monthShort
                            font.pixelSize: 11
                            font.weight: Font.Black
                            color: "#FFFFFF"
                        }
                    }
                }

                SekaiPill {
                    id: ampmBtn
                    anchors.left: dateSticker.right
                    anchors.leftMargin: 8
                    y: 2
                    width: 48
                    height: 28
                    radius: 10
                    color: "#FFFFFF"
                    inkColor: themeHub.darkInk
                    borderWidth: 2
                    shadowShift: 2
                    pressedState: ampmMa.pressed
                    Text {
                        anchors.centerIn: parent
                        text: clockWin.ampm
                        font.pixelSize: 11
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: ampmMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themeHub.setClockUse24h(!themeHub.clockUse24h)
                    }
                }
            }

            // 4 Staggered 3D Keycap Tiles + 2 Beat Diamonds
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 66
                spacing: 6

                Repeater {
                    model: [
                        { val: clockWin.h1, rot: -2.6, tint: "#FFFFFF", txt: themeHub.darkInk, accent: themeHub.accentA },
                        { val: clockWin.h2, rot: 1.8,  tint: "#FFF5FA", txt: themeHub.darkInk, accent: themeHub.accentA },
                        { val: ":",         rot: 0,    isColon: true },
                        { val: clockWin.m1, rot: -1.6, tint: "#F3FBFF", txt: themeHub.darkInk, accent: themeHub.accentB },
                        { val: clockWin.m2, rot: 2.5,  tint: "#FFFFFF", txt: themeHub.darkInk, accent: themeHub.accentB }
                    ]

                    Item {
                        required property var modelData
                        readonly property bool isColon: !!modelData.isColon
                        width: isColon ? 20 : 62
                        height: 92

                        // 2 Beat diamonds for colon
                        Column {
                            visible: isColon
                            anchors.centerIn: parent
                            spacing: 16
                            DiamondDot {
                                size: 13
                                color: widgetsRoot.beatPhase ? themeHub.accentA : themeHub.accentB
                                borderColor: themeHub.darkInk
                                borderWidth: 2
                                scale: widgetsRoot.beatPhase ? 1.18 : 0.92
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                            }
                            DiamondDot {
                                size: 13
                                color: widgetsRoot.beatPhase ? themeHub.accentB : themeHub.accentA
                                borderColor: themeHub.darkInk
                                borderWidth: 2
                                scale: widgetsRoot.beatPhase ? 0.92 : 1.18
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                            }
                        }

                        // 3D Mechanical Keycap
                        Item {
                            visible: !isColon
                            anchors.fill: parent
                            rotation: modelData.rot

                            // Keycap base skirt
                            Rectangle {
                                x: 3
                                y: 7
                                width: 56
                                height: 82
                                radius: 14
                                color: themeHub.darkInk
                            }
                            // Bottom colored lip
                            Rectangle {
                                x: 0
                                y: 6
                                width: 56
                                height: 80
                                radius: 14
                                color: modelData.accent || themeHub.accentA
                                border.color: themeHub.darkInk
                                border.width: 3
                            }
                            // Top key face
                            Rectangle {
                                x: 0
                                y: 0
                                width: 56
                                height: 74
                                radius: 13
                                color: modelData.tint || "#FFFFFF"
                                border.color: themeHub.darkInk
                                border.width: 3
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.val
                                    font.pixelSize: 40
                                    font.weight: Font.Black
                                    color: modelData.txt || themeHub.darkInk
                                }
                            }
                        }
                    }
                }
            }

            // 60-Second Lane + Sliding SecChip
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                y: 174
                height: 32

                Rectangle {
                    id: secTrack
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 12
                    radius: 6
                    color: "#EEF1F8"
                    border.color: themeHub.darkInk
                    border.width: 2

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        width: Math.max(8, Math.round((parent.width - 4) * (clockWin.secs / 59.0)))
                        radius: 4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: themeHub.accentA }
                            GradientStop { position: 1.0; color: themeHub.accentB }
                        }
                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }

                    // 15s / 30s / 45s gates
                    Repeater {
                        model: [0.25, 0.5, 0.75]
                        Rectangle {
                            required property real modelData
                            x: Math.round(secTrack.width * modelData) - 1
                            y: 2
                            width: 2
                            height: 8
                            color: "#661A1B2E"
                        }
                    }
                }

                // Sliding SecChip
                SekaiPill {
                    width: 44
                    height: 26
                    radius: 9
                    color: themeHub.darkInk
                    inkColor: "#FFFFFF"
                    borderWidth: 2
                    shadowShift: 2
                    showInnerRing: false
                    rotation: (clockWin.secs % 2 === 0) ? -3 : 3
                    x: Math.max(0, Math.min(parent.width - width, Math.round((parent.width - width) * (clockWin.secs / 59.0))))
                    y: 3
                    Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.centerIn: parent
                        text: ":" + widgetsRoot.pad2(clockWin.secs)
                        font.pixelSize: 11
                        font.weight: Font.Black
                        color: "#FFFFFF"
                    }
                }
            }

            // 7-Day Badge Strip
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                spacing: 6
                Repeater {
                    model: ["M","T","W","T","F","S","S"]
                    SekaiPill {
                        required property int index
                        required property string modelData
                        readonly property bool isToday: index === clockWin.weekdayIdx
                        width: 34
                        height: 34
                        radius: 10
                        color: isToday ? themeHub.accentA : "#F4F6FB"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: isToday ? 3 : 1
                        showInnerRing: isToday
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 12
                            font.weight: Font.Black
                            color: isToday ? "#FFFFFF" : "#661A1B2E"
                        }
                    }
                }
            }
        }

        // --- MODE 1: TOWER (Vertical Keycap Stack 238x304) ---
        SekaiPill {
            anchors.fill: parent
            visible: clockWin.mode === 1
            radius: 22
            color: "#FFFDF9"
            inkColor: themeHub.darkInk
            shadowShift: 5

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Date + 12/24 pill
                Row {
                    spacing: 6
                    SekaiPill {
                        width: 118
                        height: 28
                        radius: 9
                        color: themeHub.accentA
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2
                        Text {
                            anchors.centerIn: parent
                            text: clockWin.dayShort + " " + clockWin.dayNum + " " + clockWin.monthShort
                            font.pixelSize: 10
                            font.weight: Font.Black
                            color: "#FFFFFF"
                        }
                    }
                    SekaiPill {
                        width: 44
                        height: 28
                        radius: 9
                        color: "#FFFFFF"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2
                        Text {
                            anchors.centerIn: parent
                            text: clockWin.ampm
                            font.pixelSize: 10
                            font.weight: Font.Black
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.setClockUse24h(!themeHub.clockUse24h)
                        }
                    }
                }

                // Hours Row + Minutes Row + Vertical Seconds Strip
                Row {
                    spacing: 10
                    Column {
                        spacing: 10
                        Row {
                            spacing: 8
                            Repeater {
                                model: [clockWin.h1, clockWin.h2]
                                Item {
                                    required property string modelData
                                    required property int index
                                    width: 70; height: 84
                                    rotation: index === 0 ? -2.2 : 1.8
                                    Rectangle { x: 2; y: 6; width: 66; height: 76; radius: 14; color: themeHub.darkInk }
                                    Rectangle { x: 0; y: 5; width: 66; height: 74; radius: 14; color: themeHub.accentA; border.color: themeHub.darkInk; border.width: 3 }
                                    Rectangle {
                                        x: 0; y: 0; width: 66; height: 68; radius: 13; color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 3
                                        Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 40; font.weight: Font.Black; color: themeHub.darkInk }
                                    }
                                }
                            }
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [clockWin.m1, clockWin.m2]
                                Item {
                                    required property string modelData
                                    required property int index
                                    width: 70; height: 84
                                    rotation: index === 0 ? 1.8 : -2.0
                                    Rectangle { x: 2; y: 6; width: 66; height: 76; radius: 14; color: themeHub.darkInk }
                                    Rectangle { x: 0; y: 5; width: 66; height: 74; radius: 14; color: themeHub.accentB; border.color: themeHub.darkInk; border.width: 3 }
                                    Rectangle {
                                        x: 0; y: 0; width: 66; height: 68; radius: 13; color: "#F7FBFF"; border.color: themeHub.darkInk; border.width: 3
                                        Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 40; font.weight: Font.Black; color: themeHub.darkInk }
                                    }
                                }
                            }
                        }
                    }

                    // Vertical seconds tower
                    Item {
                        width: 34
                        height: 178
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 14; height: parent.height; radius: 7
                            color: "#EEF1F8"; border.color: themeHub.darkInk; border.width: 2
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 2
                                height: Math.max(8, Math.round((parent.height - 4) * (clockWin.secs / 59.0)))
                                radius: 5; color: themeHub.accentB
                                Behavior on height { NumberAnimation { duration: 240 } }
                            }
                        }
                        SekaiPill {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - height - Math.round((parent.height - height) * (clockWin.secs / 59.0))
                            width: 34; height: 24; radius: 8
                            color: themeHub.darkInk; inkColor: "#FFFFFF"; borderWidth: 2; shadowShift: 1; showInnerRing: false
                            Text { anchors.centerIn: parent; text: widgetsRoot.pad2(clockWin.secs); font.pixelSize: 10; font.weight: Font.Black; color: "#FFFFFF" }
                        }
                    }
                }

                // Compact week dots
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: ["M","T","W","T","F","S","S"]
                        Rectangle {
                            required property int index
                            required property string modelData
                            readonly property bool isToday: index === clockWin.weekdayIdx
                            width: 22; height: 22; radius: 7
                            color: isToday ? themeHub.accentA : "#EEF1F8"
                            border.color: themeHub.darkInk; border.width: isToday ? 2 : 1
                            Text { anchors.centerIn: parent; text: modelData; font.pixelSize: 10; font.weight: Font.Black; color: isToday ? "#FFFFFF" : "#661A1B2E" }
                        }
                    }
                }
            }
        }

        // --- MODE 2: STICKER (Cardless Floating Desktop Stickers) ---
        Item {
            anchors.fill: parent
            visible: clockWin.mode === 2

            Row {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -12
                spacing: 4
                StickerText {
                    text: clockWin.h1 + clockWin.h2
                    fontSize: 64
                    fillColor: themeHub.accentA
                    inkColor: themeHub.darkInk
                    inkThickness: 4
                    haloThickness: 3
                    shadowShift: 4
                    popOnChange: true
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    DiamondDot { size: 14; color: themeHub.accentB; borderColor: themeHub.darkInk; borderWidth: 2; scale: widgetsRoot.beatPhase ? 1.2 : 0.9 }
                    DiamondDot { size: 14; color: themeHub.accentA; borderColor: themeHub.darkInk; borderWidth: 2; scale: widgetsRoot.beatPhase ? 0.9 : 1.2 }
                }
                StickerText {
                    text: clockWin.m1 + clockWin.m2
                    fontSize: 64
                    fillColor: "#FFFFFF"
                    inkColor: themeHub.darkInk
                    inkThickness: 4
                    haloThickness: 3
                    shadowShift: 4
                    popOnChange: true
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                spacing: 8
                SekaiPill {
                    width: 132; height: 30; radius: 10; color: themeHub.accentB; inkColor: themeHub.darkInk; borderWidth: 2; shadowShift: 3; rotation: -2
                    Text { anchors.centerIn: parent; text: clockWin.dayShort + " " + clockWin.dayNum + " " + clockWin.monthShort; font.pixelSize: 11; font.weight: Font.Black; color: "#FFFFFF" }
                }
                SekaiPill {
                    width: 56; height: 30; radius: 10; color: themeHub.darkInk; inkColor: "#FFFFFF"; borderWidth: 2; shadowShift: 3; showInnerRing: false; rotation: 2
                    Text { anchors.centerIn: parent; text: ":" + widgetsRoot.pad2(clockWin.secs) + " " + (themeHub.clockUse24h ? "" : clockWin.ampm); font.pixelSize: 11; font.weight: Font.Black; color: "#FFFFFF" }
                }
            }
        }

        // --- MODE 3: STACK (Cardless Vertical Sticker Stack) ---
        Item {
            anchors.fill: parent
            visible: clockWin.mode === 3

            Column {
                anchors.centerIn: parent
                spacing: 0
                StickerText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clockWin.h1 + clockWin.h2
                    fontSize: 62
                    fillColor: themeHub.accentA
                    inkColor: themeHub.darkInk
                    inkThickness: 4
                    haloThickness: 3
                    shadowShift: 4
                    rotation: -3
                    popOnChange: true
                }
                StickerText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clockWin.m1 + clockWin.m2
                    fontSize: 62
                    fillColor: themeHub.accentB
                    inkColor: themeHub.darkInk
                    inkThickness: 4
                    haloThickness: 3
                    shadowShift: 4
                    rotation: 2.5
                    popOnChange: true
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    SekaiPill {
                        width: 112; height: 28; radius: 9; color: "#FFFFFF"; inkColor: themeHub.darkInk; borderWidth: 2; shadowShift: 3; rotation: -1.5
                        Text { anchors.centerIn: parent; text: clockWin.dayShort + " " + clockWin.dayNum + " " + clockWin.monthShort; font.pixelSize: 10; font.weight: Font.Black; color: themeHub.darkInk }
                    }
                    SekaiPill {
                        width: 44; height: 28; radius: 9; color: themeHub.darkInk; inkColor: "#FFFFFF"; borderWidth: 2; shadowShift: 3; showInnerRing: false; rotation: 2
                        Text { anchors.centerIn: parent; text: ":" + widgetsRoot.pad2(clockWin.secs); font.pixelSize: 11; font.weight: Font.Black; color: "#FFFFFF" }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 2. WEATHER WIDGET (SekaiPop Classic & Minimal Modes)
    // =========================================================================
    WidgetShell {
        id: weatherWin
        widgetKey: "weather"
        allowFocus: false
        readonly property bool isMinimal: themeHub.weatherMinimal
        cardWidth: 320
        cardHeight: isMinimal ? 212 : 276
        x: themeHub.wWeatherX
        y: themeHub.wWeatherY
        visible: themeHub.wWeatherVisible && !widgetsRoot.fullscreenActive

        property int hoveredHour: -1
        property int hoveredDay: -1
        property bool hovered: false

        readonly property var hourList: WeatherService.hourlyForecast || []
        readonly property var dayList: WeatherService.dailyForecast || []
        readonly property int activeTemp: (hoveredHour >= 0 && hoveredHour < hourList.length)
                                          ? Math.round(hourList[hoveredHour].temp)
                                          : ((hoveredDay >= 0 && hoveredDay < dayList.length)
                                             ? Math.round(dayList[hoveredDay].high)
                                             : WeatherService.temperature)
        readonly property string activeCond: (hoveredHour >= 0 && hoveredHour < hourList.length)
                                             ? (hourList[hoveredHour].condition || WeatherService.conditionText)
                                             : ((hoveredDay >= 0 && hoveredDay < dayList.length)
                                                ? (dayList[hoveredDay].condition || WeatherService.conditionText)
                                                : WeatherService.conditionText)
        readonly property int activeCode: (hoveredHour >= 0 && hoveredHour < hourList.length)
                                          ? (hourList[hoveredHour].code || 0)
                                          : ((hoveredDay >= 0 && hoveredDay < dayList.length)
                                             ? (dayList[hoveredDay].code || 0)
                                             : WeatherService.weatherCode)
        readonly property bool activeIsDay: (hoveredHour >= 0 && hoveredHour < hourList.length)
                                            ? !!hourList[hoveredHour].isDay
                                            : WeatherService.isDay

        DragSurface {
            shellWin: weatherWin
            widgetKey: "weather"
            hubRef: widgetsRoot.themeHub
        }

        HoverHandler {
            onHoveredChanged: weatherWin.hovered = hovered
        }

        SekaiPill {
            anchors.fill: parent
            radius: 22
            color: "#FFFDF9"
            inkColor: themeHub.darkInk
            shadowShift: 5

            // Top SekaiPlate Hero
            SekaiPlate {
                id: wPlate
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 114
                radius: 17
                topColor: themeHub.accentA
                bottomColor: themeHub.accentB
                inkColor: themeHub.darkInk
                borderWidth: 3
                shadowShift: 3

                // Big temperature + condition + Hi/Lo
                Column {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 2

                    Row {
                        spacing: 6
                        StickerText {
                            text: weatherWin.activeTemp + "°"
                            fontSize: 38
                            fillColor: "#FFFFFF"
                            inkColor: themeHub.darkInk
                            inkThickness: 3
                            haloThickness: 2
                            shadowShift: 3
                            popOnChange: true
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: weatherWin.hoveredHour >= 0 && weatherWin.hoveredHour < weatherWin.hourList.length
                                      ? (weatherWin.hourList[weatherWin.hoveredHour].label + " · " + weatherWin.activeCond)
                                      : (weatherWin.hoveredDay >= 0 && weatherWin.hoveredDay < weatherWin.dayList.length
                                         ? (weatherWin.dayList[weatherWin.hoveredDay].label + " · " + weatherWin.activeCond)
                                         : (weatherWin.activeCond || (WeatherService.loading ? "Syncing..." : "Clear")))
                                font.pixelSize: 12
                                font.weight: Font.Black
                                color: "#FFFFFF"
                                elide: Text.ElideRight
                                width: 122
                            }
                            Text {
                                text: "H " + WeatherService.tempMax + "°  L " + WeatherService.tempMin + "°  •  Feels " + WeatherService.feelsLike + "°"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#E8FFFFFF"
                            }
                        }
                    }
                }

                // Hanging Slant location tab at bottom-left of plate
                Item {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.bottomMargin: 6
                    width: locTxt.implicitWidth + 22
                    height: 22
                    Slant {
                        anchors.fill: parent
                        color: themeHub.darkInk
                        skew: 0.28
                    }
                    Text {
                        id: locTxt
                        anchors.centerIn: parent
                        text: (WeatherService.city || "Local").toUpperCase()
                        font.pixelSize: 10
                        font.weight: Font.Black
                        color: "#FFFFFF"
                    }
                }

                // Bottom-right quick mode switches inside plate
                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 6
                    spacing: 4

                    Rectangle {
                        visible: !weatherWin.isMinimal
                        height: 20
                        width: viewTxt.implicitWidth + 12
                        radius: 10
                        color: "#331A1B2E"
                        border.color: "#99FFFFFF"
                        border.width: 1
                        Text {
                            id: viewTxt
                            anchors.centerIn: parent
                            text: themeHub.weatherView === "days" ? "3-DAY" : "HOURLY"
                            font.pixelSize: 9
                            font.weight: Font.Black
                            color: "#FFFFFF"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.setWeatherView(themeHub.weatherView === "days" ? "hourly" : "days")
                        }
                    }

                    Rectangle {
                        height: 20
                        width: 22
                        radius: 10
                        color: "#331A1B2E"
                        border.color: "#99FFFFFF"
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: weatherWin.isMinimal ? "M" : "C"
                            font.pixelSize: 9
                            font.weight: Font.Black
                            color: "#FFFFFF"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.setWeatherMinimal(!themeHub.weatherMinimal)
                        }
                    }

                    Rectangle {
                        height: 20
                        width: 20
                        radius: 10
                        color: "#331A1B2E"
                        border.color: "#99FFFFFF"
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "↻"
                            font.pixelSize: 11
                            font.weight: Font.Black
                            color: "#FFFFFF"
                            RotationAnimation on rotation {
                                running: WeatherService.loading
                                from: 0; to: 360; duration: 800; loops: Animation.Infinite
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WeatherService.refresh()
                        }
                    }
                }

                // Clickable tilted WeatherGlyph disc on top-right
                SekaiPill {
                    id: wDisc
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 12
                    anchors.topMargin: 10
                    width: 62
                    height: 62
                    radius: 31
                    color: themeHub.darkInk
                    inkColor: "#FFFFFF"
                    borderWidth: 2
                    shadowShift: 3
                    rotation: 6
                    pressedState: wDiscMa.pressed

                    WeatherGlyph {
                        anchors.centerIn: parent
                        width: 42
                        height: 42
                        code: weatherWin.activeCode
                        isDay: weatherWin.activeIsDay
                        inkColor: "#FFFFFF"
                        accentColor: "#FFD166"
                    }

                    Burst {
                        id: wBurst
                        anchors.centerIn: parent
                        colorA: themeHub.accentA
                        colorB: "#FFD166"
                        inkColor: themeHub.darkInk
                    }

                    MouseArea {
                        id: wDiscMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wBurst.fire()
                            WeatherService.refresh()
                        }
                    }
                }

                // Close badge (appears on hover)
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4
                    width: 20; height: 20; radius: 10
                    color: "#FFFFFF"
                    border.color: themeHub.darkInk
                    border.width: 2
                    opacity: weatherWin.hovered ? 1.0 : 0.0
                    visible: opacity > 0.02
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("weather", false) }
                }
            }

            // --- CLASSIC BODY (3 Tactile Gauges + Cubic Bezier Hourly / 3-Day Forecast) ---
            Item {
                visible: !weatherWin.isMinimal
                anchors.top: wPlate.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                anchors.topMargin: 6

                // 3 Tactile Gauges Row
                Row {
                    id: gaugesRow
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 54
                    spacing: 6

                    // 1. Humidity Water Tank
                    SekaiPill {
                        width: Math.floor((gaugesRow.width - 12) / 3)
                        height: 54
                        radius: 12
                        color: "#F3FAFF"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: Math.max(6, Math.round(parent.height * Math.min(1.0, Math.max(0.08, WeatherService.humidity / 100.0))))
                            color: "#554ECDC4"
                            Behavior on height { NumberAnimation { duration: 300 } }
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "HUM"; font.pixelSize: 8; font.weight: Font.Black; color: "#881A1B2E" }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: WeatherService.humidity + "%"; font.pixelSize: 14; font.weight: Font.Black; color: themeHub.darkInk }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "RAIN " + (WeatherService.precipProb || 0) + "%"; font.pixelSize: 8; font.weight: Font.Bold; color: "#2D8A94" }
                        }
                    }

                    // 2. Rotating Wind Compass
                    SekaiPill {
                        width: Math.floor((gaugesRow.width - 12) / 3)
                        height: 54
                        radius: 12
                        color: "#F8F6FF"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2

                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                width: 30; height: 30; radius: 15
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 2
                                Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.topMargin: 1; text: "N"; font.pixelSize: 7; font.weight: Font.Black; color: themeHub.accentA }
                                Item {
                                    anchors.centerIn: parent
                                    width: 14; height: 14
                                    rotation: ((WeatherService.windDeg || 0) + 180) % 360
                                    Behavior on rotation { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                    Canvas {
                                        anchors.fill: parent
                                        onPaint: {
                                            const ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.fillStyle = "#1A1B2E"
                                            ctx.beginPath()
                                            ctx.moveTo(7, 1)
                                            ctx.lineTo(12, 12)
                                            ctx.lineTo(7, 9)
                                            ctx.lineTo(2, 12)
                                            ctx.closePath()
                                            ctx.fill()
                                        }
                                    }
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: WeatherService.windSpeed + " km/h"; font.pixelSize: 10; font.weight: Font.Black; color: themeHub.darkInk }
                                Text { text: WeatherService.windDirection || "CALM"; font.pixelSize: 9; font.weight: Font.Bold; color: "#881A1B2E" }
                            }
                        }
                    }

                    // 3. 5-Diamond UV Gauge
                    SekaiPill {
                        width: gaugesRow.width - 2 * Math.floor((gaugesRow.width - 12) / 3) - 12
                        height: 54
                        radius: 12
                        color: "#FFF9F2"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 4
                                Text { text: "UV " + WeatherService.uvIndex; font.pixelSize: 11; font.weight: Font.Black; color: themeHub.darkInk }
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3
                                Repeater {
                                    model: 5
                                    DiamondDot {
                                        required property int index
                                        readonly property int litCount: Math.min(5, Math.max(0, Math.ceil(WeatherService.uvIndex / 2.2)))
                                        size: 9
                                        color: index < litCount ? widgetsRoot.uvColor(WeatherService.uvIndex) : "#E4E7F0"
                                        borderColor: themeHub.darkInk
                                        borderWidth: 1
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Hourly Cubic Bezier Curve OR 3-Day Rows
                SekaiPill {
                    anchors.top: gaugesRow.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    radius: 12
                    color: "#FFFFFF"
                    inkColor: themeHub.darkInk
                    borderWidth: 2
                    shadowShift: 2

                    // Hourly View
                    Item {
                        anchors.fill: parent
                        visible: themeHub.weatherView !== "days"

                        Text {
                            anchors.centerIn: parent
                            visible: weatherWin.hourList.length === 0
                            text: WeatherService.loading ? "Loading forecast..." : "Tap icon to refresh"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#881A1B2E"
                        }

                        Canvas {
                            id: hourlyCanvas
                            anchors.fill: parent
                            visible: weatherWin.hourList.length > 0
                            property var pointsData: weatherWin.hourList
                            property int hoverIdx: weatherWin.hoveredHour
                            property color lineColor: themeHub.accentA
                            property color dotColor: themeHub.accentB
                            onPointsDataChanged: requestPaint()
                            onHoverIdxChanged: requestPaint()
                            onLineColorChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                const list = pointsData || []
                                const n = Math.min(8, list.length)
                                if (n < 2)
                                    return
                                let minT = 999, maxT = -999
                                for (let i = 0; i < n; i++) {
                                    const t = Number(list[i].temp)
                                    if (t < minT) minT = t
                                    if (t > maxT) maxT = t
                                }
                                const span = Math.max(2, maxT - minT)
                                const padX = 18
                                const topY = 22
                                const botY = height - 22
                                const pts = []
                                for (let i = 0; i < n; i++) {
                                    const x = padX + (width - padX * 2) * (i / (n - 1))
                                    const norm = (Number(list[i].temp) - minT) / span
                                    const y = botY - norm * (botY - topY)
                                    pts.push({ x: x, y: y, item: list[i] })
                                }

                                // Soft gradient fill under curve
                                const grad = ctx.createLinearGradient(0, topY, 0, botY)
                                grad.addColorStop(0, "#44FF5E9E")
                                grad.addColorStop(1, "#054ECDC4")
                                ctx.beginPath()
                                ctx.moveTo(pts[0].x, pts[0].y)
                                for (let i = 0; i < n - 1; i++) {
                                    const xc = (pts[i].x + pts[i + 1].x) * 0.5
                                    ctx.bezierCurveTo(xc, pts[i].y, xc, pts[i + 1].y, pts[i + 1].x, pts[i + 1].y)
                                }
                                ctx.lineTo(pts[n - 1].x, botY + 4)
                                ctx.lineTo(pts[0].x, botY + 4)
                                ctx.closePath()
                                ctx.fillStyle = grad
                                ctx.fill()

                                // Ink curve stroke
                                ctx.beginPath()
                                ctx.moveTo(pts[0].x, pts[0].y)
                                for (let i = 0; i < n - 1; i++) {
                                    const xc = (pts[i].x + pts[i + 1].x) * 0.5
                                    ctx.bezierCurveTo(xc, pts[i].y, xc, pts[i + 1].y, pts[i + 1].x, pts[i + 1].y)
                                }
                                ctx.strokeStyle = "#1A1B2E"
                                ctx.lineWidth = 3
                                ctx.stroke()

                                // Dots + temp & time labels
                                ctx.textAlign = "center"
                                ctx.font = 'bold 9px "Segoe UI"'
                                for (let i = 0; i < n; i++) {
                                    const isHov = (i === hoverIdx)
                                    ctx.beginPath()
                                    ctx.arc(pts[i].x, pts[i].y, isHov ? 5 : 3.5, 0, Math.PI * 2)
                                    ctx.fillStyle = isHov ? lineColor : "#FFFFFF"
                                    ctx.fill()
                                    ctx.lineWidth = 2
                                    ctx.strokeStyle = "#1A1B2E"
                                    ctx.stroke()

                                    ctx.fillStyle = "#1A1B2E"
                                    ctx.fillText(Math.round(pts[i].item.temp) + "°", pts[i].x, pts[i].y - 8)
                                    ctx.fillStyle = "#881A1B2E"
                                    ctx.fillText(pts[i].item.label || "", pts[i].x, height - 5)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: mouse => {
                                const n = Math.min(8, weatherWin.hourList.length)
                                if (n <= 0) { weatherWin.hoveredHour = -1; return }
                                const idx = Math.max(0, Math.min(n - 1, Math.round((mouse.x - 16) / Math.max(1, width - 32) * (n - 1))))
                                weatherWin.hoveredHour = idx
                            }
                            onExited: weatherWin.hoveredHour = -1
                        }
                    }

                    // 3-Day View
                    Column {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 3
                        visible: themeHub.weatherView === "days"

                        Repeater {
                            model: Math.min(3, weatherWin.dayList.length)
                            Rectangle {
                                required property int index
                                readonly property var dayObj: weatherWin.dayList[index]
                                width: parent.width
                                height: 22
                                radius: 7
                                color: weatherWin.hoveredDay === index ? "#EEF6FF" : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 48
                                        text: dayObj.label || ""
                                        font.pixelSize: 10
                                        font.weight: Font.Black
                                        color: themeHub.darkInk
                                    }
                                    WeatherGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18; height: 18
                                        code: dayObj.code || 0
                                        isDay: true
                                        inkColor: themeHub.darkInk
                                        accentColor: "#FFB703"
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 34
                                        text: (dayObj.rain || 0) + "%"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: "#2D8A94"
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(36, parent.width - 172)
                                        height: 6; radius: 3
                                        color: "#EAEFF7"
                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: Math.max(8, Math.round(parent.width * 0.72))
                                            radius: 3
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: themeHub.accentB }
                                                GradientStop { position: 1.0; color: themeHub.accentA }
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 54
                                        horizontalAlignment: Text.AlignRight
                                        text: Math.round(dayObj.high) + "°/" + Math.round(dayObj.low) + "°"
                                        font.pixelSize: 10
                                        font.weight: Font.Black
                                        color: themeHub.darkInk
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: weatherWin.hoveredDay = index
                                    onExited: if (weatherWin.hoveredDay === index) weatherWin.hoveredDay = -1
                                }
                            }
                        }
                    }
                }
            }

            // --- MINIMAL BODY (4 Quick Slots) ---
            Row {
                visible: weatherWin.isMinimal
                anchors.top: wPlate.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                spacing: 6

                Repeater {
                    model: Math.min(4, weatherWin.hourList.length)
                    SekaiPill {
                        required property int index
                        readonly property var hObj: weatherWin.hourList[index]
                        width: Math.floor((parent.width - 18) / 4)
                        height: parent.height
                        radius: 12
                        color: "#F6F8FC"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: hObj.label || ""; font.pixelSize: 9; font.weight: Font.Black; color: "#881A1B2E" }
                            WeatherGlyph { anchors.horizontalCenter: parent.horizontalCenter; width: 24; height: 24; code: hObj.code || 0; isDay: !!hObj.isDay; inkColor: themeHub.darkInk; accentColor: "#FFB703" }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(hObj.temp) + "°"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. PROFILE CARD WIDGET (Custom Avatar/Banner, StatKeys, TODAY Lane)
    // =========================================================================
    WidgetShell {
        id: profileWin
        widgetKey: "profile"
        property bool editing: false
        allowFocus: editing
        cardWidth: 320
        cardHeight: 276
        x: themeHub.wProfileX
        y: themeHub.wProfileY
        visible: themeHub.wProfileVisible && !widgetsRoot.fullscreenActive

        property bool hovered: false
        readonly property int nowHour: widgetsRoot.nowDate.getHours()
        readonly property int nowMin: widgetsRoot.nowDate.getMinutes()
        readonly property int dayPct: Math.round(((nowHour * 60 + nowMin) / 1440.0) * 100)
        readonly property string greetingText: nowHour < 5 ? "LATE NIGHT"
                                             : (nowHour < 12 ? "GOOD MORNING"
                                             : (nowHour < 18 ? "GOOD AFTERNOON" : "GOOD EVENING"))

        DragSurface {
            shellWin: profileWin
            widgetKey: "profile"
            hubRef: widgetsRoot.themeHub
        }

        HoverHandler {
            onHoveredChanged: profileWin.hovered = hovered
        }

        SekaiPill {
            anchors.fill: parent
            radius: 22
            color: "#FFFDF9"
            inkColor: themeHub.darkInk
            shadowShift: 5

            // Banner Area (Image or Gradient + SparkDiamonds)
            Item {
                id: pBannerBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 88

                SekaiPill {
                    anchors.fill: parent
                    radius: 16
                    useGradient: true
                    gradientTop: themeHub.accentA
                    gradientBottom: themeHub.accentB
                    inkColor: themeHub.darkInk
                    borderWidth: 3
                    shadowShift: 3

                    Image {
                        anchors.fill: parent
                        source: themeHub.profileBannerUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: themeHub.profileBannerUrl.length > 0 && status === Image.Ready
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#331A1B2E"
                        visible: themeHub.profileBannerUrl.length > 0
                    }

                    DotField {
                        anchors.fill: parent
                        color: "#FFFFFF"
                        dotAlpha: 0.16
                        step: 10
                    }

                    // SparkDiamonds
                    Repeater {
                        model: [
                            { x: 0.18, y: 0.25, s: 7 }, { x: 0.34, y: 0.65, s: 6 },
                            { x: 0.50, y: 0.22, s: 8 }, { x: 0.68, y: 0.56, s: 7 },
                            { x: 0.82, y: 0.28, s: 9 }, { x: 0.90, y: 0.72, s: 6 }
                        ]
                        DiamondDot {
                            required property var modelData
                            x: Math.round(parent.width * modelData.x)
                            y: Math.round(parent.height * modelData.y)
                            size: modelData.s
                            color: "#FFFFFF"
                            borderColor: themeHub.darkInk
                            borderWidth: 1
                        }
                    }

                    // Tilted GreetChip
                    SekaiPill {
                        x: 10
                        y: 10
                        width: greetLbl.implicitWidth + 18
                        height: 24
                        radius: 8
                        color: themeHub.darkInk
                        inkColor: "#FFFFFF"
                        borderWidth: 2
                        shadowShift: 2
                        showInnerRing: false
                        rotation: -2.5
                        Text {
                            id: greetLbl
                            anchors.centerIn: parent
                            text: profileWin.greetingText
                            font.pixelSize: 9
                            font.weight: Font.Black
                            color: "#FFFFFF"
                        }
                    }

                    // Top-right edit & close controls
                    Row {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4
                        opacity: (profileWin.hovered || profileWin.editing) ? 1.0 : 0.0
                        visible: opacity > 0.02
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: profileWin.editing ? themeHub.accentA : "#FFFFFF"
                            border.color: themeHub.darkInk; border.width: 2
                            Text { anchors.centerIn: parent; text: profileWin.editing ? "✓" : "✎"; font.pixelSize: 11; font.weight: Font.Black; color: profileWin.editing ? "#FFFFFF" : themeHub.darkInk }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (profileWin.editing)
                                        themeHub.saveProfile(nameEdit.text.trim() || themeHub.profileName, statusEdit.text.trim())
                                    profileWin.editing = !profileWin.editing
                                }
                            }
                        }
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 2
                            Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("profile", false) }
                        }
                    }
                }
            }

            // Overlapping Tilted Circular Avatar
            SekaiPill {
                id: avatarBadge
                x: 18
                y: 60
                width: 64
                height: 64
                radius: 32
                color: themeHub.accentB
                inkColor: themeHub.darkInk
                borderWidth: 3
                shadowShift: 3
                rotation: avMa.containsMouse ? 4 : -4
                pressedState: avMa.pressed
                Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                Image {
                    id: avImg
                    anchors.fill: parent
                    source: themeHub.profileAvatarUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: themeHub.profileAvatarUrl.length > 0 && status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !avImg.visible
                    text: (themeHub.profileName || "Y").charAt(0).toUpperCase()
                    font.pixelSize: 26
                    font.weight: Font.Black
                    color: "#FFFFFF"
                }

                Burst {
                    id: avBurst
                    anchors.centerIn: parent
                    colorA: themeHub.accentA
                    colorB: themeHub.accentB
                    inkColor: themeHub.darkInk
                }

                MouseArea {
                    id: avMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: avBurst.fire()
                    onDoubleClicked: {
                        const url = SystemControl.pickImageFile("Choose Profile Avatar")
                        if (url && url.length > 0)
                            themeHub.setProfileAvatar(url)
                    }
                }
            }

            // Name & Machine / Inline Editor
            Item {
                anchors.left: avatarBadge.right
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                y: 94
                height: 44

                Column {
                    anchors.fill: parent
                    visible: !profileWin.editing
                    spacing: 1
                    Row {
                        spacing: 5
                        Text {
                            text: themeHub.profileName
                            font.pixelSize: 15
                            font.weight: Font.Black
                            color: themeHub.darkInk
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "@" + (WindowTracker.machineName || "sekaidesk").toLowerCase()
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#881A1B2E"
                        }
                    }
                    Text {
                        text: themeHub.profileStatus
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#AA1A1B2E"
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                Column {
                    anchors.fill: parent
                    visible: profileWin.editing
                    spacing: 3
                    Row {
                        width: parent.width; height: 20; spacing: 4
                        Rectangle {
                            width: Math.max(70, parent.width - 102); height: 20; radius: 6
                            color: "#F3F5FA"; border.color: themeHub.darkInk; border.width: 1
                            TextInput {
                                id: nameEdit
                                anchors.fill: parent; anchors.margins: 3
                                verticalAlignment: TextInput.AlignVCenter
                                text: themeHub.profileName
                                font.pixelSize: 10; font.weight: Font.Bold; color: themeHub.darkInk
                                onAccepted: { themeHub.saveProfile(text.trim() || themeHub.profileName, statusEdit.text.trim()); profileWin.editing = false }
                            }
                        }
                        Rectangle {
                            width: 48; height: 20; radius: 6; color: themeHub.accentA; border.color: themeHub.darkInk; border.width: 1
                            Text { anchors.centerIn: parent; text: "Avatar"; font.pixelSize: 9; font.weight: Font.Black; color: "#FFFFFF" }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { const u = SystemControl.pickImageFile("Choose Profile Avatar"); if (u) themeHub.setProfileAvatar(u) } }
                        }
                        Rectangle {
                            width: 46; height: 20; radius: 6; color: themeHub.accentB; border.color: themeHub.darkInk; border.width: 1
                            Text { anchors.centerIn: parent; text: "Banner"; font.pixelSize: 9; font.weight: Font.Black; color: "#FFFFFF" }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { const u = SystemControl.pickImageFile("Choose Profile Banner"); if (u) themeHub.setProfileBanner(u) } }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 20; radius: 6
                        color: "#F3F5FA"; border.color: themeHub.darkInk; border.width: 1
                        TextInput {
                            id: statusEdit
                            anchors.fill: parent; anchors.margins: 3
                            verticalAlignment: TextInput.AlignVCenter
                            text: themeHub.profileStatus
                            font.pixelSize: 10; color: themeHub.darkInk
                            onAccepted: { themeHub.saveProfile(nameEdit.text.trim() || themeHub.profileName, text.trim()); profileWin.editing = false }
                        }
                    }
                }
            }

            // 3 Shallow-V StatKey Keycaps (UPTIME / CPU / RAM)
            Row {
                id: statRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                y: 142
                height: 50
                spacing: 8

                Repeater {
                    model: [
                        { lbl: "UPTIME", val: WindowTracker.uptimeText || "0m", rot: -1.5, c: "#FFF5FA" },
                        { lbl: "CPU",    val: WindowTracker.cpuUsage + "%",     rot: 0.0,  c: "#F3FBFF" },
                        { lbl: "RAM",    val: WindowTracker.ramUsage + "%",     rot: 1.5,  c: "#F6F3FF" }
                    ]
                    SekaiPill {
                        required property var modelData
                        width: Math.floor((statRow.width - 16) / 3)
                        height: 46
                        radius: 12
                        color: modelData.c
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 3
                        rotation: modelData.rot
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.lbl; font.pixelSize: 8; font.weight: Font.Black; color: "#881A1B2E" }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.val; font.pixelSize: 13; font.weight: Font.Black; color: themeHub.darkInk }
                        }
                    }
                }
            }

            // TODAY 24h Segmented Progress Lane
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                y: 198
                height: 28

                Row {
                    anchors.fill: parent
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TODAY"
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 96
                        height: 14
                        Rectangle {
                            anchors.fill: parent
                            radius: 7
                            color: "#EEF1F8"
                            border.color: themeHub.darkInk
                            border.width: 2
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: 2
                                width: Math.max(6, Math.round((parent.width - 4) * (profileWin.dayPct / 100.0)))
                                radius: 5
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: themeHub.accentB }
                                    GradientStop { position: 1.0; color: themeHub.accentA }
                                }
                            }
                            Repeater {
                                model: [0.25, 0.5, 0.75]
                                Rectangle {
                                    required property real modelData
                                    x: Math.round(parent.width * modelData) - 1
                                    y: 2; width: 2; height: 10; color: "#551A1B2E"
                                }
                            }
                        }
                        DiamondDot {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, Math.round(parent.width * (profileWin.dayPct / 100.0) - width / 2)))
                            size: 14
                            color: "#FFFFFF"
                            borderColor: themeHub.darkInk
                            borderWidth: 2
                        }
                    }
                    SekaiPill {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 22; radius: 8
                        color: themeHub.darkInk; inkColor: "#FFFFFF"; borderWidth: 1; shadowShift: 2; showInnerRing: false; rotation: 3
                        Text { anchors.centerIn: parent; text: profileWin.dayPct + "%"; font.pixelSize: 9; font.weight: Font.Black; color: "#FFFFFF" }
                    }
                }
            }

            // Bottom Quick Utility Pills (Home / Shot / Themes / Lock)
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                anchors.bottomMargin: 10
                spacing: 6
                Repeater {
                    model: [
                        { id: "home",   lbl: "Home" },
                        { id: "shot",   lbl: "Shot" },
                        { id: "themes", lbl: "Themes" },
                        { id: "lock",   lbl: "Lock" }
                    ]
                    SekaiPill {
                        required property var modelData
                        width: Math.floor((parent.width - 18) / 4)
                        height: 26
                        radius: 9
                        color: pBtnMa.containsMouse ? themeHub.hoverTint : "#F4F6FB"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2
                        showInnerRing: false
                        pressedState: pBtnMa.pressed
                        Text {
                            anchors.centerIn: parent
                            text: modelData.lbl
                            font.pixelSize: 10
                            font.weight: Font.Black
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            id: pBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.id === "home") WindowTracker.openSpecialFolder("home")
                                else if (modelData.id === "shot") WindowTracker.takeScreenshot()
                                else if (modelData.id === "themes") themeHub.settingsOpen = true
                                else if (modelData.id === "lock") WindowTracker.lockWorkstation()
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 4. CALENDAR WIDGET (SekaiPop Month Grid + Colored Attribute Diamonds + Events)
    // =========================================================================
    WidgetShell {
        id: calendarWin
        widgetKey: "calendar"
        allowFocus: true
        cardWidth: 346
        cardHeight: 520
        x: themeHub.wCalendarX
        y: themeHub.wCalendarY
        visible: themeHub.wCalendarVisible && !widgetsRoot.fullscreenActive

        property int viewYear: widgetsRoot.nowDate.getFullYear()
        property int viewMonth: widgetsRoot.nowDate.getMonth()
        property string selectedDay: ""
        property bool showEditor: false
        property string editingId: ""
        property string draftAttr: "cute"
        property bool draftDeadline: false
        property bool hovered: false

        readonly property string todayStr: widgetsRoot.isoDateStr(widgetsRoot.nowDate)
        readonly property string monthLabel: ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"][viewMonth] + " " + viewYear
        readonly property int isoWeek: widgetsRoot.isoWeekNumber(widgetsRoot.nowDate)

        readonly property var dayCells: {
            const first = new Date(viewYear, viewMonth, 1)
            const lead = (first.getDay() + 6) % 7
            const start = new Date(viewYear, viewMonth, 1 - lead)
            const out = []
            for (let i = 0; i < 42; i++) {
                const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
                out.push({
                    dateStr: widgetsRoot.isoDateStr(d),
                    dayNum: d.getDate(),
                    inMonth: d.getMonth() === viewMonth
                })
            }
            return out
        }

        function eventsForDay(dateStr) {
            const list = themeHub.calendarEvents || []
            const out = []
            for (let i = 0; i < list.length; i++) {
                if (list[i].date === dateStr)
                    out.push(list[i])
            }
            return out
        }

        readonly property var visibleEvents: {
            const list = themeHub.calendarEvents || []
            const out = []
            for (let i = 0; i < list.length; i++) {
                const ev = list[i]
                if (selectedDay.length > 0) {
                    if (ev.date === selectedDay) out.push(ev)
                } else {
                    if (!ev.done || ev.date >= todayStr) out.push(ev)
                }
            }
            out.sort(function(a, b) {
                if (!!a.done !== !!b.done) return a.done ? 1 : -1
                const ka = (a.date || "") + " " + (a.time || "99:99")
                const kb = (b.date || "") + " " + (b.time || "99:99")
                return ka < kb ? -1 : (ka > kb ? 1 : 0)
            })
            return out
        }

        readonly property int upcomingCount: {
            const list = themeHub.calendarEvents || []
            let c = 0
            for (let i = 0; i < list.length; i++) if (!list[i].done) c++
            return c
        }

        function stepMonth(delta) {
            let m = viewMonth + delta
            let y = viewYear
            while (m < 0) { m += 12; y-- }
            while (m > 11) { m -= 12; y++ }
            viewMonth = m
            viewYear = y
        }

        function openNewEvent(dateOverride) {
            editingId = ""
            evTitleIn.text = ""
            evDateIn.text = (dateOverride && dateOverride.length > 0) ? dateOverride : (selectedDay.length > 0 ? selectedDay : todayStr)
            evTimeIn.text = "18:00"
            draftAttr = "cute"
            draftDeadline = false
            showEditor = true
        }

        function openEditEvent(ev) {
            editingId = ev.id || ""
            evTitleIn.text = ev.title || ""
            evDateIn.text = ev.date || todayStr
            evTimeIn.text = ev.time || ""
            draftAttr = ev.attr || "cute"
            draftDeadline = !!ev.isDeadline
            showEditor = true
        }

        DragSurface {
            shellWin: calendarWin
            widgetKey: "calendar"
            hubRef: widgetsRoot.themeHub
        }

        HoverHandler {
            onHoveredChanged: calendarWin.hovered = hovered
        }

        SekaiPill {
            anchors.fill: parent
            radius: 22
            color: "#FFFDF9"
            inkColor: themeHub.darkInk
            shadowShift: 5

            // SekaiPlate Header
            SekaiPlate {
                id: calPlate
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 86
                radius: 16
                topColor: themeHub.accentB
                bottomColor: themeHub.accentA
                inkColor: themeHub.darkInk
                borderWidth: 3
                shadowShift: 3

                WheelHandler {
                    onWheel: event => calendarWin.stepMonth(event.angleDelta.y > 0 ? -1 : 1)
                }

                Column {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 2
                    StickerText {
                        text: calendarWin.monthLabel
                        fontSize: 22
                        fillColor: "#FFFFFF"
                        inkColor: themeHub.darkInk
                        inkThickness: 2
                        haloThickness: 1
                        shadowShift: 2
                    }
                    Row {
                        spacing: 6
                        Text {
                            text: "WEEK " + calendarWin.isoWeek + (calendarWin.selectedDay ? "  •  " + calendarWin.selectedDay : "")
                            font.pixelSize: 10
                            font.weight: Font.Black
                            color: "#EEFFFFFF"
                        }
                    }
                }

                // Hanging Slant Tally Tab
                Item {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.bottomMargin: 5
                    width: calTallyTxt.implicitWidth + 20
                    height: 18
                    Slant { anchors.fill: parent; color: themeHub.darkInk; skew: 0.25 }
                    Text {
                        id: calTallyTxt
                        anchors.centerIn: parent
                        text: calendarWin.upcomingCount + " OPEN"
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: "#FFFFFF"
                    }
                }

                // Nav & Action buttons + Today tilted disc
                Row {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 4

                    Repeater {
                        model: [
                            { act: "prev", lbl: "‹" },
                            { act: "next", lbl: "›" },
                            { act: "add",  lbl: "+" },
                            { act: "close", lbl: "×" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: 22; height: 22; radius: 11
                            color: modelData.act === "add" ? themeHub.accentA : "#FFFFFF"
                            border.color: themeHub.darkInk; border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: modelData.lbl
                                font.pixelSize: 12; font.weight: Font.Black
                                color: modelData.act === "add" ? "#FFFFFF" : themeHub.darkInk
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.act === "prev") calendarWin.stepMonth(-1)
                                    else if (modelData.act === "next") calendarWin.stepMonth(1)
                                    else if (modelData.act === "add") {
                                        if (calendarWin.showEditor) calendarWin.showEditor = false
                                        else calendarWin.openNewEvent("")
                                    }
                                    else if (modelData.act === "close") themeHub.setWidgetVisible("calendar", false)
                                }
                            }
                        }
                    }
                }

                // Clickable tilted Today Disc (jumps back to current month/day)
                SekaiPill {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 6
                    width: 42; height: 42; radius: 21
                    color: themeHub.darkInk; inkColor: "#FFFFFF"; borderWidth: 2; shadowShift: 2; rotation: 6
                    pressedState: calTodayMa.pressed
                    Column {
                        anchors.centerIn: parent
                        spacing: -2
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "TODAY"; font.pixelSize: 7; font.weight: Font.Black; color: "#BBFFFFFF" }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "" + widgetsRoot.nowDate.getDate(); font.pixelSize: 14; font.weight: Font.Black; color: "#FFFFFF" }
                    }
                    Burst { id: calBurst; anchors.centerIn: parent; colorA: themeHub.accentA; colorB: themeHub.accentB; inkColor: themeHub.darkInk }
                    MouseArea {
                        id: calTodayMa
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            calBurst.fire()
                            calendarWin.viewYear = widgetsRoot.nowDate.getFullYear()
                            calendarWin.viewMonth = widgetsRoot.nowDate.getMonth()
                            calendarWin.selectedDay = ""
                        }
                    }
                }
            }

            // Weekday Header Row
            Row {
                id: calWeekdayRow
                anchors.top: calPlate.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                anchors.topMargin: 6
                spacing: 4
                Repeater {
                    model: ["MON","TUE","WED","THU","FRI","SAT","SUN"]
                    Text {
                        required property string modelData
                        width: Math.floor((calWeekdayRow.width - 24) / 7)
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: "#881A1B2E"
                    }
                }
            }

            // 6x7 Month Keycap Grid
            Grid {
                id: calGrid
                anchors.top: calWeekdayRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                anchors.topMargin: 4
                columns: 7
                spacing: 4

                WheelHandler {
                    onWheel: event => calendarWin.stepMonth(event.angleDelta.y > 0 ? -1 : 1)
                }

                Repeater {
                    model: calendarWin.dayCells
                    Item {
                        required property var modelData
                        readonly property var dayEvents: calendarWin.eventsForDay(modelData.dateStr)
                        readonly property bool isToday: modelData.dateStr === calendarWin.todayStr
                        readonly property bool isSel: modelData.dateStr === calendarWin.selectedDay
                        readonly property bool hasDeadline: {
                            for (let k = 0; k < dayEvents.length; k++)
                                if (dayEvents[k].isDeadline && !dayEvents[k].done) return true
                            return false
                        }
                        width: Math.floor((calGrid.width - 24) / 7)
                        height: 30

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: isToday ? themeHub.accentA : (dayEvents.length > 0 ? "#FFF4FA" : (modelData.inMonth ? "#F4F6FB" : "#FAFBFD"))
                            border.color: isSel ? themeHub.darkInk : (isToday ? themeHub.darkInk : (modelData.inMonth ? "#331A1B2E" : "#151A1B2E"))
                            border.width: isSel ? 2 : (isToday ? 2 : 1)
                            opacity: modelData.inMonth ? 1.0 : 0.45

                            // Deadline corner flag
                            Rectangle {
                                visible: hasDeadline
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 2
                                width: 6; height: 6; radius: 2
                                color: "#FF3B6B"
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 3
                                text: "" + modelData.dayNum
                                font.pixelSize: 10
                                font.weight: (isToday || isSel || dayEvents.length > 0) ? Font.Black : Font.Bold
                                color: isToday ? "#FFFFFF" : themeHub.darkInk
                            }

                            // Up to 3 Attribute Diamonds
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                spacing: 2
                                Repeater {
                                    model: Math.min(3, dayEvents.length)
                                    DiamondDot {
                                        required property int index
                                        size: 6
                                        color: widgetsRoot.attrColor(dayEvents[index].attr || "cute")
                                        borderColor: themeHub.darkInk
                                        borderWidth: 1
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendarWin.selectedDay = (calendarWin.selectedDay === modelData.dateStr ? "" : modelData.dateStr)
                            onDoubleClicked: calendarWin.openNewEvent(modelData.dateStr)
                        }
                    }
                }
            }

            // Inline Event / Deadline Form (slides open when editing/adding)
            SekaiPill {
                id: evFormBox
                visible: calendarWin.showEditor
                anchors.top: calGrid.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                anchors.topMargin: 6
                height: visible ? 116 : 0
                radius: 14
                color: "#FFF8FC"
                inkColor: themeHub.darkInk
                borderWidth: 2
                shadowShift: 3

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Rectangle {
                        width: parent.width; height: 26; radius: 8
                        color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 1
                        TextInput {
                            id: evTitleIn
                            anchors.fill: parent; anchors.margins: 5
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: 11; font.weight: Font.Bold; color: themeHub.darkInk
                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Event or deadline title..."; font.pixelSize: 11; color: "#771A1B2E"; visible: !parent.text }
                        }
                    }

                    Row {
                        width: parent.width; spacing: 6
                        Rectangle {
                            width: 104; height: 24; radius: 7; color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 1
                            TextInput { id: evDateIn; anchors.fill: parent; anchors.margins: 4; verticalAlignment: TextInput.AlignVCenter; font.pixelSize: 10; font.weight: Font.Bold; color: themeHub.darkInk }
                        }
                        Rectangle {
                            width: 58; height: 24; radius: 7; color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 1
                            TextInput { id: evTimeIn; anchors.fill: parent; anchors.margins: 4; verticalAlignment: TextInput.AlignVCenter; font.pixelSize: 10; font.weight: Font.Bold; color: themeHub.darkInk }
                        }
                        Rectangle {
                            width: 72; height: 24; radius: 7
                            color: calendarWin.draftDeadline ? "#FF5E7E" : "#EEF1F8"
                            border.color: themeHub.darkInk; border.width: 1
                            Text { anchors.centerIn: parent; text: calendarWin.draftDeadline ? "DEADLINE" : "EVENT"; font.pixelSize: 9; font.weight: Font.Black; color: calendarWin.draftDeadline ? "#FFFFFF" : themeHub.darkInk }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calendarWin.draftDeadline = !calendarWin.draftDeadline }
                        }
                    }

                    Row {
                        width: parent.width; spacing: 6
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Repeater {
                                model: ["cute", "cool", "pure", "happy", "mysterious"]
                                Rectangle {
                                    required property string modelData
                                    width: 18; height: 18; radius: 9
                                    color: widgetsRoot.attrColor(modelData)
                                    border.color: themeHub.darkInk
                                    border.width: calendarWin.draftAttr === modelData ? 3 : 1
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calendarWin.draftAttr = modelData }
                                }
                            }
                        }
                        Item { width: Math.max(4, parent.width - 216); height: 1 }
                        Rectangle {
                            width: 48; height: 24; radius: 7; color: "#EEF1F8"; border.color: themeHub.darkInk; border.width: 1
                            Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 9; font.weight: Font.Black; color: themeHub.darkInk }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calendarWin.showEditor = false }
                        }
                        Rectangle {
                            width: 48; height: 24; radius: 7; color: themeHub.accentA; border.color: themeHub.darkInk; border.width: 2
                            Text { anchors.centerIn: parent; text: "Save"; font.pixelSize: 9; font.weight: Font.Black; color: "#FFFFFF" }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const t = evTitleIn.text.trim()
                                    if (!t) return
                                    themeHub.upsertCalendarEvent({
                                        id: calendarWin.editingId,
                                        title: t,
                                        date: evDateIn.text.trim() || calendarWin.todayStr,
                                        time: evTimeIn.text.trim(),
                                        attr: calendarWin.draftAttr,
                                        isDeadline: calendarWin.draftDeadline,
                                        done: false
                                    })
                                    calendarWin.showEditor = false
                                }
                            }
                        }
                    }
                }
            }

            // Coming Up / Selected-Day Event List
            Item {
                anchors.top: calendarWin.showEditor ? evFormBox.bottom : calGrid.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                anchors.topMargin: 8

                Row {
                    id: listHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 18
                    Text {
                        text: calendarWin.selectedDay ? ("DAY " + calendarWin.selectedDay) : "COMING UP"
                        font.pixelSize: 10
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    Item { width: parent.width - 130; height: 1 }
                    Text {
                        visible: calendarWin.selectedDay.length > 0
                        text: "Show all"
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: themeHub.accentA
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calendarWin.selectedDay = "" }
                    }
                }

                ListView {
                    anchors.top: listHeader.bottom
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    clip: true
                    spacing: 6
                    model: calendarWin.visibleEvents

                    delegate: SekaiPill {
                        required property var modelData
                        width: ListView.view.width
                        height: 44
                        radius: 11
                        color: modelData.done ? "#F4F6FA" : "#FFFFFF"
                        inkColor: themeHub.darkInk
                        borderWidth: 2
                        shadowShift: 2
                        opacity: modelData.done ? 0.65 : 1.0

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            // Colored attribute stripe + check diamond
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.done ? widgetsRoot.attrColor(modelData.attr) : "#FFFFFF"
                                border.color: themeHub.darkInk; border.width: 2
                                Text { anchors.centerIn: parent; visible: !!modelData.done; text: "✓"; font.pixelSize: 10; font.weight: Font.Black; color: "#FFFFFF" }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.toggleCalendarDone(modelData.id) }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(80, parent.width - 110)
                                spacing: 0
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.title || ""
                                    font.pixelSize: 11
                                    font.weight: Font.Black
                                    font.strikeout: !!modelData.done
                                    color: themeHub.darkInk
                                }
                                Text {
                                    text: (modelData.date || "") + (modelData.time ? (" · " + modelData.time) : "") + (modelData.isDeadline ? " · DEADLINE" : "")
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: (modelData.isDeadline && !modelData.done && modelData.date < calendarWin.todayStr) ? "#FF3B6B" : "#881A1B2E"
                                }
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Rectangle {
                                    width: 20; height: 20; radius: 6; color: "#EEF1F8"; border.color: themeHub.darkInk; border.width: 1
                                    Text { anchors.centerIn: parent; text: "✎"; font.pixelSize: 10; font.weight: Font.Black; color: themeHub.darkInk }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: calendarWin.openEditEvent(modelData) }
                                }
                                Rectangle {
                                    width: 20; height: 20; radius: 6; color: "#FFE8EE"; border.color: themeHub.darkInk; border.width: 1
                                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 11; font.weight: Font.Black; color: "#D92652" }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.deleteCalendarEvent(modelData.id) }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: calendarWin.visibleEvents.length === 0
                        text: "No events — click + to add"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: "#771A1B2E"
                    }
                }
            }
        }
    }

    // =========================================================================
    // 5. LYRICS WIDGET (Cardless Floating Desktop Outlined Stickers + Hover Controls)
    // =========================================================================
    WidgetShell {
        id: lyricsWin
        widgetKey: "lyrics"
        property bool searchOpen: false
        allowFocus: searchOpen
        cardWidth: 460
        cardHeight: 164
        x: themeHub.wLyricsX
        y: themeHub.wLyricsY
        visible: themeHub.wLyricsVisible && !widgetsRoot.fullscreenActive

        property bool hovered: false
        readonly property var linesList: LyricsService.lines || []
        readonly property int actIdx: LyricsService.activeIndex
        readonly property bool validSync: LyricsService.hasLyrics && linesList.length > 0
        readonly property var prevLine: (validSync && actIdx > 0 && actIdx - 1 < linesList.length) ? linesList[actIdx - 1] : null
        readonly property var curLine: (validSync && actIdx >= 0 && actIdx < linesList.length) ? linesList[actIdx] : (validSync ? linesList[0] : null)
        readonly property var nextLine: (validSync && actIdx >= 0 && actIdx + 1 < linesList.length) ? linesList[actIdx + 1] : (validSync && actIdx < 0 && linesList.length > 1 ? linesList[1] : null)

        DragSurface {
            shellWin: lyricsWin
            widgetKey: "lyrics"
            hubRef: widgetsRoot.themeHub
        }

        HoverHandler {
            onHoveredChanged: lyricsWin.hovered = hovered
        }

        // Hover-only Pill Toolbar (transparent when idle so widget stays 100% cardless!)
        Item {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 20
            height: 30
            z: 30
            opacity: (lyricsWin.hovered || lyricsWin.searchOpen) ? 1.0 : 0.0
            visible: opacity > 0.02
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Row {
                anchors.centerIn: parent
                spacing: 6

                SekaiPill {
                    visible: !lyricsWin.searchOpen
                    width: Math.min(240, trackChipLbl.implicitWidth + 20)
                    height: 26
                    radius: 13
                    color: themeHub.darkInk
                    inkColor: "#FFFFFF"
                    borderWidth: 2
                    shadowShift: 2
                    showInnerRing: false
                    Text {
                        id: trackChipLbl
                        anchors.centerIn: parent
                        width: parent.width - 14
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        text: MediaService.hasSession ? ((MediaService.title || "Playing") + (MediaService.artist ? " — " + MediaService.artist : "")) : "Lyrics Ready"
                        font.pixelSize: 10
                        font.weight: Font.Black
                        color: "#FFFFFF"
                    }
                }

                // Inline manual search box
                SekaiPill {
                    visible: lyricsWin.searchOpen
                    width: 240
                    height: 26
                    radius: 13
                    color: "#FFFFFF"
                    inkColor: themeHub.darkInk
                    borderWidth: 2
                    shadowShift: 2
                    showInnerRing: false
                    TextInput {
                        id: lyricSearchIn
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Artist - Song..."; font.pixelSize: 10; color: "#771A1B2E"; visible: !parent.text }
                        onAccepted: {
                            const q = text.trim()
                            if (q.length > 0) LyricsService.searchManual(q)
                            lyricsWin.searchOpen = false
                        }
                    }
                }

                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: lyricsWin.searchOpen ? themeHub.accentA : "#FFFFFF"
                    border.color: themeHub.darkInk; border.width: 2
                    Text { anchors.centerIn: parent; text: "⌕"; font.pixelSize: 12; font.weight: Font.Black; color: lyricsWin.searchOpen ? "#FFFFFF" : themeHub.darkInk }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            lyricsWin.searchOpen = !lyricsWin.searchOpen
                            if (lyricsWin.searchOpen) lyricSearchIn.forceActiveFocus()
                        }
                    }
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 2
                    Text { anchors.centerIn: parent; text: "↻"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: LyricsService.refresh() }
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 2
                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("lyrics", false) }
                }
            }
        }

        // Cardless Outlined Desktop Lyrics Stickers
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 10
            width: parent.width - 16
            spacing: 4

            // Previous Line (faded sticker)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, prevSticker.implicitWidth)
                height: visible ? prevSticker.implicitHeight : 0
                visible: lyricsWin.validSync && lyricsWin.prevLine !== null
                opacity: 0.62
                StickerText {
                    id: prevSticker
                    anchors.centerIn: parent
                    text: lyricsWin.prevLine ? (lyricsWin.prevLine.text || "") : ""
                    fontSize: 13
                    fillColor: "#EAF4FF"
                    inkColor: themeHub.darkInk
                    inkThickness: 2
                    haloThickness: 1
                    shadowShift: 2
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: if (lyricsWin.prevLine && lyricsWin.prevLine.time >= 0) MediaService.seek(lyricsWin.prevLine.time)
                }
            }

            // Current Active Line (large vibrant sticker + bouncing diamond)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                visible: lyricsWin.validSync && lyricsWin.curLine !== null

                DiamondDot {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 11
                    color: themeHub.accentA
                    borderColor: themeHub.darkInk
                    borderWidth: 2
                }
                StickerText {
                    id: curSticker
                    text: lyricsWin.curLine ? (lyricsWin.curLine.text || "♪") : "♪"
                    fontSize: 20
                    fillColor: "#FFFFFF"
                    inkColor: themeHub.darkInk
                    inkThickness: 3
                    haloThickness: 2
                    shadowShift: 3
                    popOnChange: true
                }
            }

            // Next Line (tilted anticipation sticker)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, nextSticker.implicitWidth)
                height: visible ? nextSticker.implicitHeight : 0
                visible: lyricsWin.validSync && lyricsWin.nextLine !== null
                opacity: 0.78
                rotation: 1.0
                StickerText {
                    id: nextSticker
                    anchors.centerIn: parent
                    text: lyricsWin.nextLine ? (lyricsWin.nextLine.text || "") : ""
                    fontSize: 14
                    fillColor: themeHub.accentB
                    inkColor: themeHub.darkInk
                    inkThickness: 2
                    haloThickness: 1
                    shadowShift: 2
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: if (lyricsWin.nextLine && lyricsWin.nextLine.time >= 0) MediaService.seek(lyricsWin.nextLine.time)
                }
            }

            // Fallback / Status Sticker when unsynced or idle
            StickerText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !lyricsWin.validSync
                text: LyricsService.loading ? "Searching lyrics..."
                      : (LyricsService.plainText && LyricsService.plainText.length > 0
                         ? LyricsService.plainText.split("\n")[0]
                         : (MediaService.hasSession ? (LyricsService.statusText || "No synced lyrics") : "Play music for lyrics"))
                fontSize: 17
                fillColor: "#FFFFFF"
                inkColor: themeHub.darkInk
                inkThickness: 3
                haloThickness: 2
                shadowShift: 3
            }
        }
    }

    // =========================================================================
    // 6. TO-DO CARD WIDGET (SekaiPill Checklist + Inline Rename + Clear Done)
    // =========================================================================
    WidgetShell {
        id: todoWin
        widgetKey: "todo"
        allowFocus: true
        cardWidth: 320
        cardHeight: themeHub.todoSmall ? 268 : 340
        x: themeHub.wTodoX
        y: themeHub.wTodoY
        visible: themeHub.wTodoVisible && !widgetsRoot.fullscreenActive

        property int editingIndex: -1

        readonly property int openTodoCount: {
            const list = themeHub.todoItems || []
            let c = 0
            for (let i = 0; i < list.length; i++) if (!list[i].done) c++
            return c
        }

        DragSurface {
            shellWin: todoWin
            widgetKey: "todo"
            hubRef: widgetsRoot.themeHub
        }

        SekaiPill {
            anchors.fill: parent
            radius: 22
            color: "#FFFDF9"
            inkColor: themeHub.darkInk
            shadowShift: 5

            // Header
            Row {
                id: todoHdr
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                height: 32
                spacing: 8

                SekaiPill {
                    width: 28; height: 28; radius: 9
                    useGradient: true; gradientTop: themeHub.accentA; gradientBottom: themeHub.accentB
                    inkColor: themeHub.darkInk; borderWidth: 2; shadowShift: 2
                    Text { anchors.centerIn: parent; text: "✓"; font.pixelSize: 14; font.weight: Font.Black; color: "#FFFFFF" }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TO-DO"
                    font.pixelSize: 14
                    font.weight: Font.Black
                    color: themeHub.darkInk
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20; width: todoCntTxt.implicitWidth + 12; radius: 10
                    color: "#EEF1F8"; border.color: themeHub.darkInk; border.width: 1
                    Text { id: todoCntTxt; anchors.centerIn: parent; text: todoWin.openTodoCount + " left"; font.pixelSize: 10; font.weight: Font.Black; color: themeHub.darkInk }
                }

                Item { width: Math.max(2, parent.width - 216); height: 1 }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 22; radius: 8
                    color: "#F4F6FB"; border.color: themeHub.darkInk; border.width: 1
                    Text { anchors.centerIn: parent; text: "Clear"; font.pixelSize: 9; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.clearDoneTodos() }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 8
                    color: "#F4F6FB"; border.color: themeHub.darkInk; border.width: 1
                    Text { anchors.centerIn: parent; text: themeHub.todoSmall ? "↕" : "▾"; font.pixelSize: 11; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setTodoSmall(!themeHub.todoSmall) }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 2
                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("todo", false) }
                }
            }

            // Add-Task Row
            Row {
                id: todoAddRow
                anchors.top: todoHdr.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                anchors.topMargin: 8
                height: 34
                spacing: 6

                SekaiPill {
                    width: parent.width - 42
                    height: 34
                    radius: 12
                    color: "#F5F7FC"
                    inkColor: themeHub.darkInk
                    borderWidth: 2
                    shadowShift: 2
                    showInnerRing: false
                    TextInput {
                        id: todoInput
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 12; font.weight: Font.DemiBold; color: themeHub.darkInk
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Add a task..."; font.pixelSize: 12; color: "#771A1B2E"; visible: !parent.text }
                        onAccepted: {
                            if (text.trim().length > 0) {
                                themeHub.addTodo(text)
                                text = ""
                            }
                        }
                    }
                }

                SekaiPill {
                    width: 34; height: 34; radius: 12
                    color: themeHub.accentA; inkColor: themeHub.darkInk; borderWidth: 2; shadowShift: 2
                    pressedState: todoAddBtnMa.pressed
                    Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 18; font.weight: Font.Black; color: "#FFFFFF" }
                    MouseArea {
                        id: todoAddBtnMa
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (todoInput.text.trim().length > 0) {
                                themeHub.addTodo(todoInput.text)
                                todoInput.text = ""
                            }
                        }
                    }
                }
            }

            // Checklist
            ListView {
                anchors.top: todoAddRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                anchors.topMargin: 8
                clip: true
                spacing: 6
                model: themeHub.todoItems

                delegate: SekaiPill {
                    required property int index
                    required property var modelData
                    readonly property bool isEditing: todoWin.editingIndex === index
                    width: ListView.view.width
                    height: 38
                    radius: 11
                    color: modelData.done ? "#F4F6FA" : "#FFFFFF"
                    inkColor: themeHub.darkInk
                    borderWidth: 2
                    shadowShift: 2
                    opacity: modelData.done ? 0.65 : 1.0

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 9
                            color: modelData.done ? themeHub.accentA : "#FFFFFF"
                            border.color: themeHub.darkInk; border.width: 2
                            Text { anchors.centerIn: parent; visible: !!modelData.done; text: "✓"; font.pixelSize: 11; font.weight: Font.Black; color: "#FFFFFF" }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.toggleTodo(index) }
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(80, parent.width - 78)
                            height: 26

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !isEditing
                                elide: Text.ElideRight
                                text: modelData.text || ""
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.strikeout: !!modelData.done
                                color: themeHub.darkInk
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: themeHub.toggleTodo(index)
                                    onDoubleClicked: {
                                        todoWin.editingIndex = index
                                        rowEdit.text = modelData.text || ""
                                        rowEdit.forceActiveFocus()
                                    }
                                }
                            }

                            TextInput {
                                id: rowEdit
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                visible: isEditing
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                                onAccepted: {
                                    themeHub.renameTodo(index, text)
                                    todoWin.editingIndex = -1
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus && isEditing) {
                                        themeHub.renameTodo(index, text)
                                        todoWin.editingIndex = -1
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 6
                            color: "#FFE8EE"; border.color: themeHub.darkInk; border.width: 1
                            Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 11; font.weight: Font.Black; color: "#D92652" }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.removeTodo(index) }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 7. STICKY NOTES WIDGET (5 SekaiPop Paper Tints + 2-Click Clear Confirm)
    // =========================================================================
    WidgetShell {
        id: notesWin
        widgetKey: "notes"
        allowFocus: true
        cardWidth: 288
        cardHeight: 248
        x: themeHub.wNotesX
        y: themeHub.wNotesY
        visible: themeHub.wNotesVisible && !widgetsRoot.fullscreenActive

        property bool hovered: false
        property bool confirmClear: false
        readonly property color paperColor: {
            if (themeHub.noteTint === "mint") return "#E2FAEE"
            if (themeHub.noteTint === "pink") return "#FFE6F1"
            if (themeHub.noteTint === "sky") return "#E3F4FF"
            if (themeHub.noteTint === "lavender") return "#EFE8FF"
            return "#FFF6CC"
        }

        Timer {
            id: clearResetTimer
            interval: 2200
            onTriggered: notesWin.confirmClear = false
        }

        DragSurface {
            shellWin: notesWin
            widgetKey: "notes"
            hubRef: widgetsRoot.themeHub
        }

        HoverHandler {
            onHoveredChanged: notesWin.hovered = hovered
        }

        SekaiPill {
            anchors.fill: parent
            radius: 20
            color: notesWin.paperColor
            inkColor: themeHub.darkInk
            shadowShift: 5

            // Subtle ruled lines across paper
            Column {
                anchors.fill: parent
                anchors.topMargin: 48
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 22
                opacity: 0.08
                Repeater {
                    model: 8
                    Rectangle { width: parent.width; height: 1; color: themeHub.darkInk }
                }
            }

            // Header bar with tint swatches + Clear confirm + Close
            Row {
                id: noteHdr
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                height: 28
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NOTE"
                    font.pixelSize: 12
                    font.weight: Font.Black
                    color: themeHub.darkInk
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    opacity: notesWin.hovered ? 1.0 : 0.65
                    Repeater {
                        model: [
                            { k: "butter",   c: "#FFE66D" },
                            { k: "mint",     c: "#7CE8B5" },
                            { k: "pink",     c: "#FF92C2" },
                            { k: "sky",      c: "#7DD3FC" },
                            { k: "lavender", c: "#C4B5FD" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: 14; height: 14; radius: 7
                            color: modelData.c
                            border.color: themeHub.darkInk
                            border.width: themeHub.noteTint === modelData.k ? 2 : 1
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setNoteTint(modelData.k) }
                        }
                    }
                }

                Item { width: Math.max(4, parent.width - 216); height: 1 }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: notesWin.confirmClear ? 46 : 36
                    height: 22; radius: 8
                    color: notesWin.confirmClear ? "#FF5E7E" : "#88FFFFFF"
                    border.color: themeHub.darkInk; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: notesWin.confirmClear ? "Sure?" : "Clear"
                        font.pixelSize: 9; font.weight: Font.Black
                        color: notesWin.confirmClear ? "#FFFFFF" : themeHub.darkInk
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!notesWin.confirmClear) {
                                notesWin.confirmClear = true
                                clearResetTimer.restart()
                            } else {
                                noteEdit.text = ""
                                themeHub.saveNoteText("")
                                notesWin.confirmClear = false
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: "#FFFFFF"; border.color: themeHub.darkInk; border.width: 2
                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 12; font.weight: Font.Black; color: themeHub.darkInk }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible("notes", false) }
                }
            }

            Flickable {
                anchors.top: noteHdr.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                anchors.topMargin: 6
                contentWidth: width
                contentHeight: Math.max(height, noteEdit.contentHeight + 12)
                clip: true

                TextEdit {
                    id: noteEdit
                    width: parent.width
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: themeHub.darkInk
                    text: themeHub.noteText
                    onTextChanged: {
                        if (text !== themeHub.noteText)
                            themeHub.saveNoteText(text)
                    }
                    Text {
                        anchors.fill: parent
                        text: "Jot something down..."
                        font.pixelSize: 13
                        color: "#661A1B2E"
                        visible: noteEdit.text.length === 0
                    }
                }
            }
        }
    }
}
