import QtQuick
import QtQuick.Effects
import Quickshell
import SekaiDesk

PanelWindow {
    id: visWin

    required property var themeHub
    required property bool fullscreenActive

    readonly property var sizeLabels: ["S", "M", "L", "XL"]
    readonly property var styleOrder: ["tide", "ribbons", "aurora", "pulse", "scope", "mirror", "ring", "dots", "sekai", "bars", "wave"]
    readonly property var attrPalette: ["#FF5E7E", "#4BC7FF", "#FFE14D", "#C08CFF", "#4AE3B5"]

    readonly property int sizeIdx: Math.max(0, Math.min(3, VisualizerService.sizeIndex))
    readonly property string curStyle: VisualizerService.style || "tide"
    readonly property bool isTideStyle: curStyle === "tide"
    readonly property bool isShaderStyle: curStyle === "ribbons" || curStyle === "aurora" || curStyle === "pulse"
        || curStyle === "scope" || curStyle === "mirror" || curStyle === "ring" || curStyle === "dots"
    readonly property bool isCanvasStyle: !isTideStyle && !isShaderStyle
    readonly property bool isFrameless: VisualizerService.transparentBg && curStyle !== "sekai"

    readonly property int presetW: {
        if (curStyle === "ring")
            return [220, 270, 330, 400][sizeIdx]
        if (curStyle === "sekai")
            return [300, 364, 436, 512][sizeIdx]
        return [380, 520, 720, 960][sizeIdx]
    }
    readonly property int presetH: {
        if (curStyle === "ring")
            return [220, 270, 330, 400][sizeIdx]
        if (curStyle === "sekai")
            return [192, 224, 264, 308][sizeIdx]
        return [140, 180, 220, 270][sizeIdx]
    }

    property bool resizing: false
    property int liveW: 0
    property int liveH: 0
    property bool winHovered: false

    readonly property int cardW: resizing ? Math.max(160, liveW) : (VisualizerService.customWidth >= 160 ? Math.min(themeHub.screenW, VisualizerService.customWidth) : presetW)
    readonly property int cardH: resizing ? Math.max(80, liveH) : (VisualizerService.customHeight >= 80 ? Math.min(themeHub.screenH, VisualizerService.customHeight) : presetH)

    readonly property int shadowPad: isFrameless ? 0 : 12
    readonly property int extraH: isFrameless ? 0 : (shadowPad + 4)
    width: cardW + shadowPad
    height: cardH + extraH

    readonly property int defaultX: 28
    readonly property int defaultY: Math.max(48, themeHub.screenH - height - (themeHub.screenW < 1280 ? 148 : 38))
    readonly property int clampedX: {
        const unset = (VisualizerService.posX === -1 && VisualizerService.posY === -1)
        const raw = unset ? defaultX : Math.round(VisualizerService.posX)
        const minX = themeHub.virtMinX
        return Math.max(minX, Math.min(Math.max(minX, themeHub.virtMaxX - width), raw))
    }
    readonly property int clampedY: {
        const unset = (VisualizerService.posX === -1 && VisualizerService.posY === -1)
        const raw = unset ? defaultY : Math.round(VisualizerService.posY)
        const minY = themeHub.widgetMinYAt(clampedX, raw)
        return Math.max(minY, Math.min(Math.max(minY, themeHub.virtMaxY - height), raw))
    }

    property bool nativeDragging: false

    onClampedXChanged: if (!nativeDragging && !resizing) x = clampedX
    onClampedYChanged: if (!nativeDragging && !resizing) y = clampedY
    Component.onCompleted: {
        x = clampedX
        y = clampedY
        refreshExtractedPalette()
    }

    readonly property bool wantVisible: VisualizerService.enabled
        && !fullscreenActive
        && (themeHub.editMode
            || (VisualizerService.stayWhenPaused && MediaService.hasSession)
            || VisualizerService.audioActive
            || VisualizerService.alwaysListen)

    property real revealP: wantVisible ? 1.0 : 0.0
    Behavior on revealP {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    visible: revealP > 0.01
    desktopLayer: true
    color: "transparent"
    clickThrough: !themeHub.editMode && themeHub.widgetsLocked
    mask: (!themeHub.editMode && themeHub.widgetsLocked)
        ? []
        : [{ x: 0, y: 0, width: width, height: height }]

    readonly property color shaderColor1: {
        if (VisualizerService.colorMode === 1) return "#8EE3EF"
        return VisualizerService.colorMode === 2 ? extractedA : themeHub.accentA
    }
    readonly property color shaderColor2: {
        if (VisualizerService.colorMode === 1) return "#A5E6A5"
        return VisualizerService.colorMode === 2 ? extractedB : themeHub.accentB
    }
    readonly property color shaderColor3: {
        if (VisualizerService.colorMode === 1) return "#FF9ECB"
        return Qt.lighter(shaderColor2, 1.18)
    }

    ShaderVisualizerEngine {
        id: shaderEngine
        active: visWin.visible && (visWin.isTideStyle || visWin.isShaderStyle)
        demo: visWin.demoActive
        sensitivity: VisualizerService.sensitivity
        raw: VisualizerService.bands
    }

    // Gentle demo pulse in Edit Mode when audio is silent (Canvas styles only)
    property real demoPhase: 0.0
    readonly property bool demoActive: visible && themeHub.editMode && !VisualizerService.audioActive
    Timer {
        interval: 40
        repeat: true
        running: visWin.demoActive && visWin.isCanvasStyle
        onTriggered: {
            visWin.demoPhase = (visWin.demoPhase + 0.16) % (Math.PI * 200)
            if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
    }

    // Extracted dominant palette for colorMode === 2
    property color extractedA: themeHub.accentA
    property color extractedB: themeHub.accentB
    property string cachedWallPath: ""

    function refreshExtractedPalette() {
        const wp = WallpaperService.currentWallpaper || ""
        if (wp !== "" && wp !== cachedWallPath) {
            cachedWallPath = wp
            const pal = WallpaperService.extractPalette(wp)
            if (pal && pal.accentA)
                extractedA = pal.accentA
            if (pal && pal.accentB)
                extractedB = pal.accentB
        }
    }

    Connections {
        target: WallpaperService
        function onCurrentWallpaperChanged() {
            visWin.refreshExtractedPalette()
        }
    }

    Connections {
        target: themeHub
        function onAccentAChanged() {
            if (!visWin.visible)
                return
            if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
    }

    Connections {
        target: VisualizerService
        function onFrameChanged() {
            if (!visWin.visible)
                return
            if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
        function onStyleChanged() {
            if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
        function onColorModeChanged() {
            if (!visWin.visible)
                return
            if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
    }

    function bandValue(idx) {
        if (demoActive) {
            const p = demoPhase
            const v = 0.28 + 0.24 * Math.sin(p + idx * 0.42) + 0.16 * Math.cos(p * 1.4 - idx * 0.25)
            return Math.max(0.05, Math.min(1.0, v))
        }
        const arr = VisualizerService.bands
        if (!arr || idx < 0 || idx >= arr.length)
            return 0.0
        const raw = Number(arr[idx]) || 0.0
        return Math.max(0.0, Math.min(1.0, raw))
    }

    function bandColor(idx, total) {
        const mode = VisualizerService.colorMode
        if (mode === 1)
            return attrPalette[idx % attrPalette.length]
        const cA = (mode === 2) ? extractedA : themeHub.accentA
        const cB = (mode === 2) ? extractedB : themeHub.accentB
        const t = total > 1 ? (idx / (total - 1)) : 0.0
        return Qt.rgba(
            cB.r + (cA.r - cB.r) * t,
            cB.g + (cA.g - cB.g) * t,
            cB.b + (cA.b - cB.b) * t,
            1.0
        )
    }

    function cycleStyle() {
        const idx = styleOrder.indexOf(curStyle)
        const next = styleOrder[(idx + 1) % styleOrder.length]
        VisualizerService.style = next
    }

    function startDrag() {
        const minX = themeHub.virtMinX
        const minY = themeHub.virtMinY
        const maxW = Math.max(minX + 100, themeHub.virtMaxX - 80)
        const maxH = Math.max(minY + 100, themeHub.virtMaxY - 60)
        nativeDragging = true
        beginNativeDrag(minX, minY, maxW, maxH)
    }

    function finishDrag() {
        if (!nativeDragging)
            return
        nativeDragging = false
        endNativeDrag()
        VisualizerService.setPosition(x, y)
    }

    function applyResize(edgeL, edgeR, edgeT, edgeB, startGX, startGY, curGX, curGY, startWinX, startWinY, startW, startH) {
        const dx = curGX - startGX
        const dy = curGY - startGY
        const minX = themeHub.virtMinX
        const maxRight = themeHub.virtMaxX
        const minY = themeHub.virtMinY
        const maxBottom = themeHub.virtMaxY

        let nx = startWinX
        let nw = startW
        if (edgeL) {
            nx = Math.max(minX, Math.min(startWinX + startW - 160, Math.round(startWinX + dx)))
            nw = startWinX + startW - nx
        } else if (edgeR) {
            nw = Math.max(160, Math.min(maxRight - startWinX - shadowPad, Math.round(startW + dx)))
        }

        let ny = startWinY
        let nh = startH
        if (edgeT) {
            ny = Math.max(minY, Math.min(startWinY + startH - 80, Math.round(startWinY + dy)))
            nh = startWinY + startH - ny
        } else if (edgeB) {
            nh = Math.max(80, Math.min(maxBottom - startWinY - extraH, Math.round(startH + dy)))
        }

        liveW = nw
        liveH = nh
        setPanelGeometry(nx, ny, nw + shadowPad, nh + extraH)
    }

    function toggleFullWidth() {
        const targetW = Math.max(160, themeHub.screenW - shadowPad)
        if (cardW >= targetW - 16) {
            VisualizerService.setCustomSize(0, 0)
        } else {
            const targetH = VisualizerService.customHeight >= 80 ? VisualizerService.customHeight : presetH
            VisualizerService.setPosition(themeHub.virtMinX, y)
            VisualizerService.setCustomSize(targetW, targetH)
        }
    }

    // Main Card Container
    Item {
        id: stage
        x: visWin.isFrameless ? 0 : 4
        y: visWin.isFrameless ? 0 : 6
        width: visWin.cardW
        height: visWin.cardH
        opacity: visWin.revealP
        scale: 0.90 + 0.10 * visWin.revealP
        transformOrigin: Item.Center

        HoverHandler {
            onHoveredChanged: visWin.winHovered = hovered
        }

        // Hard SekaiPop Drop Shadow (Card mode only)
        Rectangle {
            visible: !visWin.isFrameless
            x: 4
            y: 5
            width: parent.width
            height: parent.height
            radius: visWin.curStyle === "ring" ? Math.round(Math.min(width, height) * 0.5) : 22
            color: themeHub.darkInk
        }

        // Card Housing (Frameless transparent by default; optional rounded comic Card)
        Rectangle {
            id: cardFace
            anchors.fill: parent
            radius: visWin.isFrameless ? 0 : (visWin.curStyle === "ring" ? Math.round(Math.min(width, height) * 0.5) : 22)
            color: visWin.isFrameless
                ? "transparent"
                : ((visWin.curStyle === "sekai" || visWin.curStyle === "tide")
                    ? "#FFFFFF"
                    : (visWin.isShaderStyle ? "#151828" : "#F6F9FF"))
            border.color: themeHub.darkInk
            border.width: visWin.isFrameless ? 0 : 3
            clip: true

            // Mask texture for rounded Card mode (zero corner overflow)
            Rectangle {
                id: cardMaskItem
                anchors.fill: shaderWrap
                radius: visWin.isFrameless ? 0 : Math.max(0, cardFace.radius - 3)
                color: "#FFFFFF"
                visible: false
                layer.enabled: !visWin.isFrameless && width > 4 && height > 4
                layer.smooth: true
            }

            Item {
                id: shaderWrap
                anchors.fill: parent
                anchors.margins: visWin.isFrameless ? 0 : 3
                layer.enabled: !visWin.isFrameless && width > 4 && height > 4
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: cardMaskItem
                }

                // #7 GPU SHADER STYLES ("tide" + 7 SekaiPop .frag.qsb effects)
                TideVisualizer {
                    anchors.fill: parent
                    visible: visWin.isTideStyle
                    engine: shaderEngine
                    color1: visWin.shaderColor1
                    color2: visWin.shaderColor2
                    color3: visWin.shaderColor3
                    ink: themeHub.darkInk
                }

                ShaderVisualizerLayer {
                    anchors.fill: parent
                    visible: visWin.isShaderStyle
                    style: visWin.isShaderStyle ? visWin.curStyle : "aurora"
                    engine: shaderEngine
                    color1: visWin.shaderColor1
                    color2: visWin.shaderColor2
                    color3: visWin.shaderColor3
                    ink: themeHub.darkInk
                    artUrl: MediaService.hasSession ? MediaService.artUrl : ""
                }
            }

            // Unlocked desktop drag surface (behind interactive buttons & resize handles)
            MouseArea {
                anchors.fill: parent
                z: 0
                enabled: !themeHub.editMode && !themeHub.widgetsLocked
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: visWin.nativeDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        themeHub.setEditMode(true)
                        return
                    }
                    visWin.startDrag()
                }
                onPositionChanged: {
                    if (visWin.nativeDragging)
                        visWin.stepNativeDrag()
                }
                onReleased: visWin.finishDrag()
                onCanceled: visWin.finishDrag()
            }

            // =================================================================
            // STYLE 1: "sekai" — Pocket Keycap Sheet + Media Deck
            // =================================================================
            Item {
                anchors.fill: parent
                anchors.margins: 10
                visible: visWin.curStyle === "sekai"

                readonly property int deckH: visWin.sizeIdx === 0 ? 32 : 38

                // Dark Keycap Well
                Rectangle {
                    id: keyWell
                    x: 0
                    y: 0
                    width: parent.width
                    height: Math.max(60, parent.height - parent.deckH - 8)
                    radius: 14
                    color: themeHub.darkInk
                    border.color: themeHub.darkInk
                    border.width: 2
                    clip: true

                    // Subtle album art tint inside well
                    Image {
                        anchors.fill: parent
                        source: MediaService.artUrl || ""
                        visible: MediaService.artUrl !== ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 240
                        sourceSize.height: 160
                        opacity: MediaService.isPlaying || visWin.demoActive ? 0.24 : 0.10
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }

                    // 6x4 Keycap Grid (24 keycaps)
                    Grid {
                        id: keyGrid
                        anchors.fill: parent
                        anchors.margins: 7
                        anchors.bottomMargin: 15
                        columns: 6
                        rows: 4
                        spacing: 4

                        readonly property real cellW: Math.max(12, (width - spacing * (columns - 1)) / columns)
                        readonly property real cellH: Math.max(10, (height - spacing * (rows - 1)) / rows)

                        Repeater {
                            model: 24
                            delegate: Item {
                                required property int index
                                width: keyGrid.cellW
                                height: keyGrid.cellH

                                readonly property int col: index % 6
                                readonly property int row: Math.floor(index / 6)
                                readonly property int bandIdx: Math.min(31, col * 5 + (3 - row))
                                readonly property real energy: visWin.bandValue(bandIdx)
                                readonly property real dipPx: Math.min(4.5, energy * 5.2)
                                readonly property color capCol: visWin.bandColor(index, 24)

                                // Keycap shadow base
                                Rectangle {
                                    x: 1
                                    y: 3
                                    width: parent.width - 2
                                    height: parent.height - 3
                                    radius: 5
                                    color: "#0C0D18"
                                }

                                // Keycap face that dips into its shadow on beats
                                Rectangle {
                                    x: 0
                                    y: Math.round(parent.dipPx)
                                    width: parent.width - 2
                                    height: Math.max(6, parent.height - 4)
                                    radius: 5
                                    color: parent.energy > 0.14
                                        ? Qt.lighter(parent.capCol, 1.0 + parent.energy * 0.22)
                                        : Qt.rgba(parent.capCol.r, parent.capCol.g, parent.capCol.b, 0.55)
                                    border.color: "#121324"
                                    border.width: 1

                                    Behavior on y { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }

                                    // Keycap top gloss highlight
                                    Rectangle {
                                        x: 3
                                        y: 2
                                        width: Math.max(4, parent.width - 6)
                                        height: 2
                                        radius: 1
                                        color: "#FFFFFF"
                                        opacity: 0.45
                                    }
                                }
                            }
                        }
                    }

                    // 12 emitter diamonds along bottom foot of well
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        spacing: 6
                        Repeater {
                            model: 12
                            delegate: Rectangle {
                                required property int index
                                readonly property real v: visWin.bandValue(Math.min(31, index * 2))
                                width: 6
                                height: 6
                                rotation: 45
                                radius: 1
                                color: v > 0.22 ? visWin.bandColor(index, 12) : "#474A6B"
                                scale: 0.75 + v * 0.55
                            }
                        }
                    }
                }

                // Bottom Deck Strip (Album Badge + Title + Prev/Play/Next)
                Row {
                    x: 2
                    y: keyWell.height + 8
                    width: parent.width - 4
                    height: parent.deckH
                    spacing: 8
                    z: 5

                    // Album Art / Note Mini Tile
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.height - 2
                        height: parent.height - 2
                        radius: 9
                        color: themeHub.hoverTint
                        border.color: themeHub.darkInk
                        border.width: 2
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: MediaService.artUrl || ""
                            visible: MediaService.artUrl !== ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 72
                            sourceSize.height: 72
                        }
                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            visible: MediaService.artUrl === ""
                            source: "qrc:/qml/icons/music-note-teal.svg"
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }
                    }

                    // Track Info
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(40, parent.width - (parent.height - 2) - 104 - 16)
                        spacing: 1
                        Text {
                            width: parent.width
                            text: MediaService.title !== "" ? MediaService.title : (visWin.demoActive ? "Demo Rhythm" : "Audio Live")
                            elide: Text.ElideRight
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            color: themeHub.darkInk
                        }
                        Text {
                            width: parent.width
                            text: MediaService.artist !== "" ? MediaService.artist : "SekaiPop Visualizer"
                            elide: Text.ElideRight
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: "#555A7A"
                        }
                    }

                    // Keycap Transport Controls
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 8
                            color: prevMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                            border.color: themeHub.darkInk
                            border.width: 2
                            Image {
                                anchors.centerIn: parent
                                width: 13
                                height: 13
                                source: "qrc:/qml/icons/skip-previous-dark.svg"
                                sourceSize.width: 26
                                sourceSize.height: 26
                            }
                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MediaService.previous()
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 28
                            radius: 8
                            color: MediaService.isPlaying ? themeHub.accentA : (playMa.containsMouse ? themeHub.accentB : "#FFFFFF")
                            border.color: themeHub.darkInk
                            border.width: 2
                            Image {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                source: MediaService.isPlaying ? "qrc:/qml/icons/pause-dark.svg" : "qrc:/qml/icons/play-dark.svg"
                                sourceSize.width: 28
                                sourceSize.height: 28
                            }
                            MouseArea {
                                id: playMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MediaService.playPause()
                            }
                        }

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 8
                            color: nextMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                            border.color: themeHub.darkInk
                            border.width: 2
                            Image {
                                anchors.centerIn: parent
                                width: 13
                                height: 13
                                source: "qrc:/qml/icons/skip-next-dark.svg"
                                sourceSize.width: 26
                                sourceSize.height: 26
                            }
                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MediaService.next()
                            }
                        }
                    }
                }
            }

            // =================================================================
            // STYLE 2: "bars" — Smooth Vertical SekaiPop Comic Bars
            // =================================================================
            Item {
                anchors.fill: parent
                anchors.margins: visWin.isFrameless ? 8 : 12
                visible: visWin.curStyle === "bars"

                // Top Micro Header (Card mode only)
                Row {
                    id: barsHeader
                    visible: !visWin.isFrameless
                    x: 0
                    y: 0
                    width: parent.width
                    height: 22
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: barTagTxt.implicitWidth + 12
                        height: 18
                        radius: 9
                        color: themeHub.accentB
                        border.color: themeHub.darkInk
                        border.width: 2
                        Text {
                            id: barTagTxt
                            anchors.centerIn: parent
                            text: "VISUALIZER"
                            font.pixelSize: 9
                            font.weight: Font.Black
                            color: themeHub.darkInk
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(40, parent.width - 110)
                        text: MediaService.title !== "" ? (MediaService.title + (MediaService.artist !== "" ? " — " + MediaService.artist : "")) : "System Audio Spectrum"
                        elide: Text.ElideRight
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                }

                // 32 Bars Area
                Item {
                    x: 0
                    y: visWin.isFrameless ? 0 : (barsHeader.height + 8)
                    width: parent.width
                    height: visWin.isFrameless ? parent.height : Math.max(40, parent.height - barsHeader.height - 8)

                    readonly property int barCount: 32
                    readonly property real gap: 3
                    readonly property real barW: Math.max(3, (width - gap * (barCount - 1)) / barCount)

                    Repeater {
                        model: 32
                        delegate: Item {
                            required property int index
                            x: index * (parent.barW + parent.gap)
                            y: 0
                            width: parent.barW
                            height: parent.height

                            readonly property real val: visWin.bandValue(index)
                            readonly property int barH: Math.max(6, Math.round(height * val))

                            // Dim track slot (Card mode only)
                            Rectangle {
                                anchors.fill: parent
                                radius: Math.max(2, Math.floor(width * 0.5))
                                color: visWin.isFrameless ? "transparent" : "#E4EAF6"
                            }

                            // Active filled bar
                            Rectangle {
                                x: 0
                                y: parent.height - parent.barH
                                width: parent.width
                                height: parent.barH
                                radius: Math.max(2, Math.floor(width * 0.5))
                                color: visWin.bandColor(index, 32)
                                border.color: themeHub.darkInk
                                border.width: parent.width >= 6 ? 1 : 0

                                Behavior on height { NumberAnimation { duration: 48; easing.type: Easing.OutQuad } }
                                Behavior on y { NumberAnimation { duration: 48; easing.type: Easing.OutQuad } }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // STYLE 5: "wave" — Mirrored Smooth Canvas Waveform
            // =================================================================
            Item {
                anchors.fill: parent
                anchors.margins: visWin.isFrameless ? 4 : 10
                visible: visWin.curStyle === "wave"

                Canvas {
                    id: waveCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const midY = height * 0.5
                        const maxAmp = height * 0.42
                        const count = 32
                        const stepX = width / (count - 1)

                        const grad = ctx.createLinearGradient(0, 0, width, 0)
                        grad.addColorStop(0.0, themeHub.accentB)
                        grad.addColorStop(1.0, themeHub.accentA)

                        // Upper + Lower mirrored polygon
                        ctx.beginPath()
                        ctx.moveTo(0, midY)
                        for (let i = 0; i < count; ++i) {
                            const x = i * stepX
                            const amp = Math.max(3, visWin.bandValue(i) * maxAmp)
                            ctx.lineTo(x, midY - amp)
                        }
                        for (let i = count - 1; i >= 0; --i) {
                            const x = i * stepX
                            const amp = Math.max(3, visWin.bandValue(i) * maxAmp)
                            ctx.lineTo(x, midY + amp)
                        }
                        ctx.closePath()
                        ctx.fillStyle = grad
                        ctx.fill()
                        ctx.lineWidth = 2.5
                        ctx.strokeStyle = themeHub.darkInk
                        ctx.stroke()

                        // Center baseline accent
                        ctx.beginPath()
                        ctx.moveTo(4, midY)
                        ctx.lineTo(width - 4, midY)
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = "#FFFFFF"
                        ctx.stroke()
                    }
                }
            }
        }

        // =====================================================================
        // Subtle Unlocked Hover Outline + Quick SE/E/S Resize Grips
        // =====================================================================
        Rectangle {
            anchors.fill: parent
            radius: visWin.isFrameless ? 12 : cardFace.radius
            color: "transparent"
            border.color: Qt.rgba(themeHub.accentA.r, themeHub.accentA.g, themeHub.accentA.b, 0.72)
            border.width: 2
            visible: !themeHub.editMode && !themeHub.widgetsLocked && (visWin.winHovered || visWin.resizing)
            z: 55
        }

        // Quick right, bottom & corner resize grips when unlocked
        Repeater {
            model: (!themeHub.editMode && !themeHub.widgetsLocked && (visWin.winHovered || visWin.resizing))
                ? [
                    { k: "e",  l: false, r: true,  t: false, b: false },
                    { k: "s",  l: false, r: false, t: false, b: true  },
                    { k: "se", l: false, r: true,  t: false, b: true  }
                  ]
                : []
            delegate: Item {
                required property var modelData
                readonly property bool isSE: modelData.r && modelData.b
                x: modelData.r ? (parent.width - width) : 14
                y: modelData.b ? (parent.height - height) : 14
                width: modelData.r ? 12 : Math.max(12, parent.width - 28)
                height: modelData.b ? 12 : Math.max(12, parent.height - 28)
                z: 60

                Rectangle {
                    visible: isSE
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    color: quickGripMa.containsMouse || quickGripMa.pressed ? themeHub.accentB : themeHub.accentA
                    border.width: 2; border.color: themeHub.darkInk
                }

                MouseArea {
                    id: quickGripMa
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: isSE ? Qt.SizeFDiagCursor : (modelData.r ? Qt.SizeHorCursor : Qt.SizeVerCursor)
                    property real startGX: 0
                    property real startGY: 0
                    property int startWinX: 0
                    property int startWinY: 0
                    property int startW: 380
                    property int startH: 140
                    onPressed: mouse => {
                        visWin.resizing = true
                        startWinX = visWin.x
                        startWinY = visWin.y
                        startW = visWin.cardW
                        startH = visWin.cardH
                        visWin.liveW = startW
                        visWin.liveH = startH
                        const gp = quickGripMa.mapToItem(null, mouse.x, mouse.y)
                        startGX = visWin.x + gp.x
                        startGY = visWin.y + gp.y
                    }
                    onPositionChanged: mouse => {
                        if (!visWin.resizing) return
                        const gp = quickGripMa.mapToItem(null, mouse.x, mouse.y)
                        visWin.applyResize(modelData.l, modelData.r, modelData.t, modelData.b,
                                           startGX, startGY, visWin.x + gp.x, visWin.y + gp.y,
                                           startWinX, startWinY, startW, startH)
                    }
                    onReleased: {
                        if (!visWin.resizing) return
                        const fw = visWin.liveW
                        const fh = visWin.liveH
                        VisualizerService.setCustomSize(fw, fh)
                        visWin.resizing = false
                    }
                    onCanceled: visWin.resizing = false
                }
            }
        }

        // Live Dimension HUD while resizing
        Rectangle {
            visible: visWin.resizing
            anchors.centerIn: parent
            width: dimTxt.implicitWidth + 18
            height: 28
            radius: 14
            color: themeHub.darkInk
            border.width: 2
            border.color: themeHub.accentA
            z: 99
            Text {
                id: dimTxt
                anchors.centerIn: parent
                text: Math.round(visWin.cardW) + " × " + Math.round(visWin.cardH)
                font.family: "Consolas"
                font.pixelSize: 12
                font.weight: Font.Black
                color: "#FFFFFF"
            }
        }

        // =====================================================================
        // Edit Mode Chrome (Dashed Outline, 8-Way Resize Handles, Tag, Pills)
        // =====================================================================
        Item {
            id: editChrome
            anchors.fill: parent
            visible: themeHub.editMode
            z: 90

            onVisibleChanged: {
                if (visible)
                    dashBorder.requestPaint()
            }

            Canvas {
                id: dashBorder
                x: 0
                y: 0
                width: parent.width
                height: parent.height
                property color accentCol: themeHub.accentA
                property color inkCol: themeHub.darkInk
                property bool hovered: editDragMa.containsMouse || editDragMa.pressed
                onAccentColChanged: requestPaint()
                onHoveredChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (width <= 8 || height <= 8)
                        return
                    const pad = 2
                    const rw = width - pad * 2
                    const rh = height - pad * 2
                    const r = 18
                    function traceRect() {
                        ctx.beginPath()
                        ctx.moveTo(pad + r, pad)
                        ctx.lineTo(pad + rw - r, pad)
                        ctx.quadraticCurveTo(pad + rw, pad, pad + rw, pad + r)
                        ctx.lineTo(pad + rw, pad + rh - r)
                        ctx.quadraticCurveTo(pad + rw, pad + rh, pad + rw - r, pad + rh)
                        ctx.lineTo(pad + r, pad + rh)
                        ctx.quadraticCurveTo(pad, pad + rh, pad, pad + rh - r)
                        ctx.lineTo(pad, pad + r)
                        ctx.quadraticCurveTo(pad, pad, pad + r, pad)
                        ctx.closePath()
                    }
                    ctx.save()
                    ctx.setLineDash([8, 5])
                    ctx.lineWidth = hovered ? 4.5 : 3.5
                    ctx.strokeStyle = inkCol
                    traceRect()
                    ctx.stroke()
                    ctx.lineWidth = hovered ? 2.5 : 2.0
                    ctx.strokeStyle = accentCol
                    traceRect()
                    ctx.stroke()
                    ctx.restore()
                }
            }

            // Full-card Edit Drag Shield
            MouseArea {
                id: editDragMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: visWin.nativeDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                z: 91

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        VisualizerService.enabled = false
                        return
                    }
                    visWin.startDrag()
                }
                onPositionChanged: {
                    if (visWin.nativeDragging)
                        visWin.stepNativeDrag()
                }
                onReleased: visWin.finishDrag()
                onCanceled: visWin.finishDrag()
            }

            // 8 Interactive Edge & Corner Resize Handles
            Repeater {
                model: [
                    { l: true,  r: false, t: false, b: false, corner: false },
                    { l: false, r: true,  t: false, b: false, corner: false },
                    { l: false, r: false, t: true,  b: false, corner: false },
                    { l: false, r: false, t: false, b: true,  corner: false },
                    { l: true,  r: false, t: true,  b: false, corner: true  },
                    { l: false, r: true,  t: true,  b: false, corner: true  },
                    { l: true,  r: false, t: false, b: true,  corner: true  },
                    { l: false, r: true,  t: false, b: true,  corner: true  }
                ]
                delegate: Item {
                    required property var modelData
                    readonly property bool isC: modelData.corner
                    readonly property int pad: 14
                    x: modelData.l ? 0 : (modelData.r ? Math.max(0, editChrome.width - (isC ? 18 : 10)) : pad)
                    y: modelData.t ? 0 : (modelData.b ? Math.max(0, editChrome.height - (isC ? 18 : 10)) : pad)
                    width: (modelData.l || modelData.r) ? (isC ? 18 : 10) : Math.max(12, editChrome.width - pad * 2)
                    height: (modelData.t || modelData.b) ? (isC ? 18 : 10) : Math.max(12, editChrome.height - pad * 2)
                    z: isC ? 94 : 93

                    Rectangle {
                        visible: isC
                        anchors.centerIn: parent
                        width: edgeMa.containsMouse || edgeMa.pressed ? 13 : 10
                        height: width
                        rotation: 45
                        radius: 2
                        color: edgeMa.containsMouse || edgeMa.pressed ? themeHub.accentB : themeHub.accentA
                        border.color: themeHub.darkInk
                        border.width: 2
                        antialiasing: true
                    }

                    MouseArea {
                        id: edgeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: {
                            if ((modelData.l && modelData.t) || (modelData.r && modelData.b)) return Qt.SizeFDiagCursor
                            if ((modelData.r && modelData.t) || (modelData.l && modelData.b)) return Qt.SizeBDiagCursor
                            return (modelData.l || modelData.r) ? Qt.SizeHorCursor : Qt.SizeVerCursor
                        }
                        property real startGX: 0
                        property real startGY: 0
                        property int startWinX: 0
                        property int startWinY: 0
                        property int startW: 380
                        property int startH: 140
                        onPressed: mouse => {
                            visWin.resizing = true
                            startWinX = visWin.x
                            startWinY = visWin.y
                            startW = visWin.cardW
                            startH = visWin.cardH
                            visWin.liveW = startW
                            visWin.liveH = startH
                            const gp = edgeMa.mapToItem(null, mouse.x, mouse.y)
                            startGX = visWin.x + gp.x
                            startGY = visWin.y + gp.y
                        }
                        onPositionChanged: mouse => {
                            if (!visWin.resizing) return
                            const gp = edgeMa.mapToItem(null, mouse.x, mouse.y)
                            visWin.applyResize(modelData.l, modelData.r, modelData.t, modelData.b,
                                               startGX, startGY, visWin.x + gp.x, visWin.y + gp.y,
                                               startWinX, startWinY, startW, startH)
                        }
                        onReleased: {
                            if (!visWin.resizing) return
                            const fw = visWin.liveW
                            const fh = visWin.liveH
                            if (modelData.l || modelData.t)
                                VisualizerService.setPosition(visWin.x, visWin.y)
                            VisualizerService.setCustomSize(fw, fh)
                            visWin.resizing = false
                        }
                        onCanceled: visWin.resizing = false
                    }
                }
            }

            // Top-left Tag Pill (kept inside card bounds so edges never clip)
            Rectangle {
                x: 8
                y: 6
                visible: editChrome.width >= 260
                width: visTagTxt.implicitWidth + 14
                height: 20
                radius: 10
                color: editDragMa.containsMouse ? themeHub.accentB : themeHub.darkInk
                border.color: themeHub.darkInk
                border.width: 2
                z: 95
                Text {
                    id: visTagTxt
                    anchors.centerIn: parent
                    text: "VISUALIZER · " + visWin.curStyle.toUpperCase()
                    font.pixelSize: 9
                    font.weight: Font.Black
                    color: editDragMa.containsMouse ? themeHub.darkInk : "#FFFFFF"
                }
            }

            // Top-right Action Pills: Clear/Card, Full W, Size, Style, Close
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                y: 6
                spacing: 4
                z: 95

                // Transparent vs Card Toggle Pill
                Rectangle {
                    visible: visWin.curStyle !== "sekai"
                    width: bgModeTxt.implicitWidth + 12
                    height: 22
                    radius: 11
                    color: VisualizerService.transparentBg
                        ? (bgModeMa.containsMouse ? themeHub.hoverTint : "#FFFFFF")
                        : themeHub.accentA
                    border.color: themeHub.darkInk
                    border.width: 2
                    Text {
                        id: bgModeTxt
                        anchors.centerIn: parent
                        text: VisualizerService.transparentBg ? "CLEAR" : "CARD"
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: bgModeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: VisualizerService.transparentBg = !VisualizerService.transparentBg
                    }
                }

                // Full Width Quick Stretch Pill
                Rectangle {
                    width: fullWTxt.implicitWidth + 10
                    height: 22
                    radius: 11
                    color: visWin.cardW >= themeHub.screenW - 24
                        ? themeHub.accentB
                        : (fullWMa.containsMouse ? themeHub.hoverTint : "#FFFFFF")
                    border.color: themeHub.darkInk
                    border.width: 2
                    Text {
                        id: fullWTxt
                        anchors.centerIn: parent
                        text: "FULL W"
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: fullWMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: visWin.toggleFullWidth()
                    }
                }

                // Size Cycle Pill (S/M/L/XL)
                Rectangle {
                    width: sizePillTxt.implicitWidth + 12
                    height: 22
                    radius: 11
                    color: sizeMa.containsMouse ? themeHub.accentB : "#FFFFFF"
                    border.color: themeHub.darkInk
                    border.width: 2
                    Text {
                        id: sizePillTxt
                        anchors.centerIn: parent
                        text: (VisualizerService.customWidth >= 160 || VisualizerService.customHeight >= 80)
                            ? "FIT"
                            : (visWin.sizeLabels[visWin.sizeIdx] || "M")
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: sizeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: VisualizerService.cycleSize()
                    }
                }

                // Style Cycle Pill
                Rectangle {
                    width: stylePillTxt.implicitWidth + 12
                    height: 22
                    radius: 11
                    color: styleMa.containsMouse ? themeHub.accentA : "#FFFFFF"
                    border.color: themeHub.darkInk
                    border.width: 2
                    Text {
                        id: stylePillTxt
                        anchors.centerIn: parent
                        text: visWin.curStyle.toUpperCase()
                        font.pixelSize: 9
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: styleMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: visWin.cycleStyle()
                    }
                }

                // Close Button (×)
                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: closeMa.containsMouse ? "#FF5E7E" : "#FFFFFF"
                    border.color: themeHub.darkInk
                    border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        font.pixelSize: 13
                        font.weight: Font.Black
                        color: closeMa.containsMouse ? "#FFFFFF" : "#D92652"
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: VisualizerService.enabled = false
                    }
                }
            }
        }
    }
}
