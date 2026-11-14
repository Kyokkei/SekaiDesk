import QtQuick
import Quickshell
import SekaiDesk

PanelWindow {
    id: osdWin

    required property var themeHub
    required property bool fullscreenActive

    readonly property int cardW: 316
    readonly property int cardH: 108

    width: cardW + 16
    height: cardH + 20
    x: Math.round((themeHub.screenW - width) * 0.5)
    y: 40

    property string kind: "volume"       // "volume" | "mic" | "brightness" | "darkmode"
    property int value: 50               // 0..150
    property bool muted: false
    property bool darkModeState: true

    property bool wantsShow: false
    property real revealed: 0.0
    property bool pulse: false
    property bool bump: false
    property real numberScale: 1.0
    property real stampScale: 1.0
    property real frontLift: 0.0

    property real smoothShown: Math.max(0, Math.min(100, value))
    Behavior on smoothShown {
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }

    readonly property bool showsMuted: muted && kind !== "brightness" && kind !== "darkmode"
    readonly property bool isOver100: !showsMuted && kind !== "darkmode" && value > 100
    readonly property string labelText: {
        if (kind === "mic") return "MICROPHONE"
        if (kind === "brightness") return "BRIGHTNESS"
        if (kind === "darkmode") return "APPEARANCE"
        return "VOLUME"
    }

    readonly property color plateTop: {
        if (kind === "darkmode")
            return darkModeState ? "#3E4270" : "#FFF3B0"
        if (showsMuted)
            return "#C6B6E8"
        if (isOver100)
            return "#FFB8DA"
        return themeHub.accentB
    }
    readonly property color plateBottom: {
        if (kind === "darkmode")
            return darkModeState ? "#232542" : "#FFD54A"
        if (showsMuted)
            return "#B39DDB"
        if (isOver100)
            return "#FF9ECB"
        return themeHub.accentA
    }
    readonly property color labelInk: (kind === "darkmode" && darkModeState) ? "#FFFFFF" : themeHub.darkInk

    function showOsd(newKind, newVal, isMuted) {
        if (themeHub.osdEnabled === false || fullscreenActive)
            return

        const kindChanged = (kind !== newKind)
        const muteChanged = (muted !== isMuted)
        const valChanged = (value !== newVal)

        kind = newKind
        value = newVal
        muted = !!isMuted

        if (kindChanged || muteChanged) {
            pulse = true
            pulseTimer.restart()
            if (showsMuted || kind === "darkmode")
                stampAnim.restart()
        }
        if (valChanged || kindChanged) {
            bump = true
            bumpTimer.restart()
            numberAnim.restart()
            frontLiftAnim.restart()
        }

        wantsShow = true
        showAnim.stop()
        hideAnim.stop()
        showAnim.restart()
        autoHideTimer.restart()
        gaugeCanvas.requestPaint()
        if (kind === "mic")
            micCanvas.requestPaint()
    }

    function hide() {
        wantsShow = false
        autoHideTimer.stop()
        showAnim.stop()
        hideAnim.stop()
        hideAnim.restart()
    }

    onFullscreenActiveChanged: {
        if (fullscreenActive && wantsShow)
            hide()
    }

    onSmoothShownChanged: gaugeCanvas.requestPaint()
    onFrontLiftChanged: gaugeCanvas.requestPaint()
    onShowsMutedChanged: gaugeCanvas.requestPaint()

    NumberAnimation {
        id: showAnim
        target: osdWin
        property: "revealed"
        to: 1.0
        duration: 170
        easing.type: Easing.OutBack
        easing.overshoot: 1.5
    }

    NumberAnimation {
        id: hideAnim
        target: osdWin
        property: "revealed"
        to: 0.0
        duration: 210
        easing.type: Easing.InCubic
    }

    NumberAnimation {
        id: numberAnim
        target: osdWin
        property: "numberScale"
        from: 1.15
        to: 1.0
        duration: 200
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: stampAnim
        target: osdWin
        property: "stampScale"
        from: 1.28
        to: 1.0
        duration: 320
        easing.type: Easing.OutBack
        easing.overshoot: 2.2
    }

    SequentialAnimation {
        id: frontLiftAnim
        NumberAnimation {
            target: osdWin
            property: "frontLift"
            to: 1.0
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: osdWin
            property: "frontLift"
            to: 0.0
            duration: 140
            easing.type: Easing.OutBack
        }
    }

    Timer {
        id: autoHideTimer
        interval: 1600
        onTriggered: osdWin.hide()
    }

    Timer {
        id: pulseTimer
        interval: 95
        onTriggered: osdWin.pulse = false
    }

    Timer {
        id: bumpTimer
        interval: 120
        onTriggered: osdWin.bump = false
    }

    Connections {
        target: AudioService
        function onOsdRequested(reqKind, reqValue, reqMuted) {
            osdWin.showOsd(reqKind || "volume", reqValue, reqMuted)
        }
    }

    Connections {
        target: SystemControl
        function onBrightnessOsdRequested(percent) {
            osdWin.showOsd("brightness", percent, false)
        }
        function onDarkModeOsdRequested(darkMode) {
            osdWin.darkModeState = !!darkMode
            osdWin.showOsd("darkmode", darkMode ? 100 : 0, false)
        }
    }

    visible: revealed > 0.01
    color: "transparent"
    clickThrough: !wantsShow

    // Hover-to-dismiss courtesy: immediately get out of the user's way
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: osdWin.wantsShow
        onEntered: osdWin.hide()
    }

    Item {
        id: osdBody
        x: 8
        y: 6
        width: osdWin.cardW
        height: osdWin.cardH
        opacity: Math.max(0, Math.min(1, osdWin.revealed))
        scale: 0.88 + 0.12 * osdWin.revealed
        transformOrigin: Item.Top

        // Outer Hard Drop Shadow
        Rectangle {
            x: 0
            y: 5
            width: parent.width
            height: parent.height
            radius: 26
            color: themeHub.darkInk
        }

        // Main Housing (Navy outline -> White ring -> Surface)
        Rectangle {
            anchors.fill: parent
            radius: 26
            color: "#FFFFFF"
            border.color: themeHub.darkInk
            border.width: 3

            // Inner Surface
            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 20
                color: "#F3F6FF"

                // Plate Drop Shadow
                Rectangle {
                    x: 4
                    y: 7
                    width: parent.width - 8
                    height: parent.height - 11
                    radius: 16
                    color: themeHub.darkInk
                }

                // SekaiPlate (Gradient Face)
                Rectangle {
                    id: plate
                    x: 4
                    y: osdWin.pulse ? 6 : 4
                    width: parent.width - 8
                    height: parent.height - 11
                    radius: 16
                    border.color: themeHub.darkInk
                    border.width: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: osdWin.plateTop }
                        GradientStop { position: 1.0; color: osdWin.plateBottom }
                    }

                    Behavior on y { NumberAnimation { duration: 75; easing.type: Easing.OutQuad } }

                    // Left Keycap Icon Badge
                    Item {
                        id: badgeWrap
                        x: 12
                        y: 10
                        width: 40
                        height: 43

                        Rectangle {
                            x: 0
                            y: 3
                            width: 40
                            height: 40
                            radius: 12
                            color: themeHub.darkInk
                        }

                        Rectangle {
                            x: 0
                            y: osdWin.pulse ? 2 : 0
                            width: 40
                            height: 40
                            radius: 12
                            color: "#FFFFFF"
                            border.color: themeHub.darkInk
                            border.width: 2

                            Behavior on y { NumberAnimation { duration: 75; easing.type: Easing.OutQuad } }

                            Image {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                visible: osdWin.kind !== "mic"
                                source: {
                                    if (osdWin.kind === "brightness")
                                        return "qrc:/qml/icons/sun-dark.svg"
                                    if (osdWin.kind === "darkmode")
                                        return osdWin.darkModeState
                                            ? "qrc:/qml/icons/moon-dark.svg"
                                            : "qrc:/qml/icons/sun-dark.svg"
                                    return osdWin.showsMuted
                                        ? "qrc:/qml/icons/volume-cross-dark.svg"
                                        : "qrc:/qml/icons/volume-loud-dark.svg"
                                }
                                sourceSize.width: 44
                                sourceSize.height: 44
                            }

                            // Crisp Canvas Microphone Icon (for kind === "mic")
                            Canvas {
                                id: micCanvas
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                visible: osdWin.kind === "mic"
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.strokeStyle = themeHub.darkInk
                                    ctx.fillStyle = themeHub.darkInk
                                    ctx.lineCap = "round"
                                    ctx.lineJoin = "round"
                                    ctx.lineWidth = 2.0

                                    // Capsule
                                    ctx.beginPath()
                                    ctx.roundedRect(8, 2.5, 6, 10, 3, 3)
                                    ctx.fill()

                                    // U-cradle
                                    ctx.beginPath()
                                    ctx.arc(11, 10.5, 5.5, 0, Math.PI, false)
                                    ctx.stroke()

                                    // Stem + Base
                                    ctx.beginPath()
                                    ctx.moveTo(11, 16)
                                    ctx.lineTo(11, 19.5)
                                    ctx.moveTo(7.5, 19.5)
                                    ctx.lineTo(14.5, 19.5)
                                    ctx.stroke()

                                    // Mute diagonal slash
                                    if (osdWin.showsMuted) {
                                        ctx.strokeStyle = "#D92652"
                                        ctx.lineWidth = 2.4
                                        ctx.beginPath()
                                        ctx.moveTo(3.5, 18.5)
                                        ctx.lineTo(18.5, 3.5)
                                        ctx.stroke()
                                    }
                                }
                            }
                        }
                    }

                    // Label Text
                    Text {
                        x: 62
                        y: 22
                        text: osdWin.labelText
                        color: osdWin.labelInk
                        font.pixelSize: 12
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1
                    }

                    // Numeric Readout (when not MUTE and not darkmode stamp)
                    Row {
                        id: readout
                        visible: !osdWin.showsMuted && osdWin.kind !== "darkmode"
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: 11
                        spacing: 1
                        scale: osdWin.numberScale
                        transformOrigin: Item.Center

                        Text {
                            text: String(Math.round(osdWin.value))
                            color: osdWin.labelInk
                            font.pixelSize: 28
                            font.weight: Font.Black
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: "%"
                            color: osdWin.labelInk
                            font.pixelSize: 14
                            font.weight: Font.ExtraBold
                        }
                    }

                    // Tilted Stamp Pill (MUTE / DARK / LIGHT)
                    Item {
                        visible: osdWin.showsMuted || osdWin.kind === "darkmode"
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        y: 12
                        width: 74
                        height: 34
                        rotation: 6
                        scale: osdWin.stampScale
                        transformOrigin: Item.Center

                        Rectangle {
                            x: 3
                            y: 3
                            width: parent.width
                            height: parent.height
                            radius: 10
                            color: themeHub.darkInk
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: "#FFFFFF"
                            border.color: themeHub.darkInk
                            border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: osdWin.showsMuted
                                    ? "MUTE"
                                    : (osdWin.darkModeState ? "DARK" : "LIGHT")
                                font.pixelSize: 13
                                font.weight: Font.Black
                                font.letterSpacing: 1
                                color: osdWin.showsMuted ? "#D92652" : themeHub.darkInk
                            }
                        }
                    }

                    // 10 Slanted Parallelogram Gauge Segments (pure QtQuick Canvas)
                    Canvas {
                        id: gaugeCanvas
                        x: 12
                        y: 55
                        width: parent.width - 24
                        height: 24

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)

                            const n = 10
                            const segH = 18
                            const baseY = 4
                            const skew = 0.22
                            const lean = segH * skew
                            const segW = 21 + lean
                            const pitch = (width - segW) / (n - 1)
                            const pct = osdWin.kind === "darkmode"
                                ? (osdWin.darkModeState ? 100 : 100)
                                : osdWin.smoothShown
                            const frontIdx = Math.max(0, Math.min(n - 1, Math.ceil((pct / 100) * n) - 1))

                            function drawParallelogram(px, py, pw, ph, plean) {
                                ctx.beginPath()
                                ctx.moveTo(px + plean, py)
                                ctx.lineTo(px + pw, py)
                                ctx.lineTo(px + pw - plean, py + ph)
                                ctx.lineTo(px, py + ph)
                                ctx.closePath()
                            }

                            for (let i = 0; i < n; ++i) {
                                const sx = i * pitch
                                const lift = (pct > 0 && i === frontIdx) ? (-2.5 * osdWin.frontLift) : 0
                                const sy = baseY + lift

                                // Dim slot
                                drawParallelogram(sx, sy, segW, segH, lean)
                                ctx.fillStyle = "rgba(26, 27, 46, 0.24)"
                                ctx.fill()
                                ctx.lineWidth = 2
                                ctx.strokeStyle = themeHub.darkInk
                                ctx.stroke()

                                // Lit fill fraction 0..1
                                const frac = Math.max(0, Math.min(1, (pct / 100) * n - i))
                                if (frac > 0.01) {
                                    const fillW = frac >= 0.99 ? segW : (lean + Math.max(4, (segW - lean) * frac))
                                    drawParallelogram(sx, sy, fillW, segH, lean)
                                    ctx.fillStyle = osdWin.showsMuted
                                        ? "rgba(255, 255, 255, 0.55)"
                                        : (osdWin.kind === "darkmode" && !osdWin.darkModeState ? "#1A1B2E" : "#FFFFFF")
                                    ctx.fill()
                                    ctx.lineWidth = 2
                                    ctx.strokeStyle = themeHub.darkInk
                                    ctx.stroke()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
