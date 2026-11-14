import QtQuick
import Quickshell
import SekaiDesk

PanelWindow {
    id: visWin

    required property var themeHub
    required property bool fullscreenActive

    readonly property var sizeLabels: ["S", "M", "L", "XL"]
    readonly property var styleOrder: ["sekai", "bars", "ring", "dots", "wave"]
    readonly property var attrPalette: ["#FF5E7E", "#4BC7FF", "#FFE14D", "#C08CFF", "#4AE3B5"]

    readonly property int sizeIdx: Math.max(0, Math.min(3, VisualizerService.sizeIndex))
    readonly property string curStyle: VisualizerService.style || "bars"

    readonly property int cardW: {
        if (curStyle === "ring")
            return [204, 248, 300, 356][sizeIdx]
        return [300, 364, 436, 512][sizeIdx]
    }
    readonly property int cardH: {
        if (curStyle === "ring")
            return [216, 260, 312, 368][sizeIdx]
        if (curStyle === "sekai")
            return [192, 224, 264, 308][sizeIdx]
        return [154, 184, 220, 258][sizeIdx]
    }

    readonly property int shadowPad: 12
    width: cardW + shadowPad
    height: cardH + shadowPad + 4

    readonly property int defaultX: 28
    readonly property int defaultY: Math.max(48, themeHub.screenH - height - (themeHub.screenW < 1280 ? 148 : 38))
    readonly property int clampedX: {
        const unset = (VisualizerService.posX === -1 && VisualizerService.posY === -1)
        const raw = unset ? defaultX : Math.round(VisualizerService.posX)
        const minX = themeHub.virtMinX + 8
        return Math.max(minX, Math.min(Math.max(minX, themeHub.virtMaxX - width - 8), raw))
    }
    readonly property int clampedY: {
        const unset = (VisualizerService.posX === -1 && VisualizerService.posY === -1)
        const raw = unset ? defaultY : Math.round(VisualizerService.posY)
        const minY = themeHub.widgetMinYAt(clampedX, raw)
        return Math.max(minY, Math.min(Math.max(minY, themeHub.virtMaxY - height - 8), raw))
    }

    property bool nativeDragging: false

    onClampedXChanged: if (!nativeDragging) x = clampedX
    onClampedYChanged: if (!nativeDragging) y = clampedY
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

    // Gentle demo pulse in Edit Mode when audio is silent
    property real demoPhase: 0.0
    readonly property bool demoActive: visible && themeHub.editMode && !VisualizerService.audioActive
    Timer {
        interval: 40
        repeat: true
        running: visWin.demoActive
        onTriggered: {
            visWin.demoPhase = (visWin.demoPhase + 0.16) % (Math.PI * 200)
            if (visWin.curStyle === "ring")
                ringCanvas.requestPaint()
            else if (visWin.curStyle === "wave")
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
            if (visWin.curStyle === "ring")
                ringCanvas.requestPaint()
            else if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
    }

    Connections {
        target: VisualizerService
        function onFrameChanged() {
            if (!visWin.visible)
                return
            if (visWin.curStyle === "ring")
                ringCanvas.requestPaint()
            else if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
        function onStyleChanged() {
            if (visWin.curStyle === "ring")
                ringCanvas.requestPaint()
            else if (visWin.curStyle === "wave")
                waveCanvas.requestPaint()
        }
        function onColorModeChanged() {
            if (!visWin.visible)
                return
            if (visWin.curStyle === "ring")
                ringCanvas.requestPaint()
            else if (visWin.curStyle === "wave")
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
        const minX = themeHub.virtMinX + 8
        const minY = themeHub.virtMinY + 8
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

    // Main Card Container
    Item {
        id: stage
        x: 4
        y: 6
        width: visWin.cardW
        height: visWin.cardH
        opacity: visWin.revealP
        scale: 0.90 + 0.10 * visWin.revealP
        transformOrigin: Item.Center

        // Hard SekaiPop Drop Shadow
        Rectangle {
            x: 4
            y: 5
            width: parent.width
            height: parent.height
            radius: visWin.curStyle === "ring" ? Math.round(Math.min(width, height) * 0.5) : 22
            color: themeHub.darkInk
        }

        // Card Housing (Ring uses circular housing; others use rounded comic card)
        Rectangle {
            id: cardFace
            anchors.fill: parent
            radius: visWin.curStyle === "ring" ? Math.round(Math.min(width, height) * 0.5) : 22
            color: visWin.curStyle === "sekai" ? "#FFFFFF" : "#F6F9FF"
            border.color: themeHub.darkInk
            border.width: 3
            clip: true

            // Unlocked desktop drag surface (behind interactive buttons)
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
            // STYLE 2: "bars" — 32 Smooth Vertical SekaiPop Comic Bars
            // =================================================================
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: visWin.curStyle === "bars"

                // Top Micro Header
                Row {
                    id: barsHeader
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
                    y: barsHeader.height + 8
                    width: parent.width
                    height: Math.max(40, parent.height - barsHeader.height - 8)

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

                            // Dim track slot
                            Rectangle {
                                anchors.fill: parent
                                radius: Math.max(2, Math.floor(width * 0.5))
                                color: "#E4EAF6"
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
            // STYLE 3: "ring" — Radial Equalizer Bars Around Rotating Disc
            // =================================================================
            Item {
                anchors.fill: parent
                visible: visWin.curStyle === "ring"

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const cx = width * 0.5
                        const cy = height * 0.5
                        const outerMax = Math.min(width, height) * 0.44
                        const innerR = Math.min(width, height) * 0.25
                        const count = 32
                        for (let i = 0; i < count; ++i) {
                            const angle = (i / count) * Math.PI * 2 - Math.PI * 0.5
                            const val = visWin.bandValue(i)
                            const len = 5 + (outerMax - innerR - 4) * val
                            const x1 = cx + Math.cos(angle) * innerR
                            const y1 = cy + Math.sin(angle) * innerR
                            const x2 = cx + Math.cos(angle) * (innerR + len)
                            const y2 = cy + Math.sin(angle) * (innerR + len)
                            const col = visWin.bandColor(i, count)
                            ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 1.0)
                            ctx.lineWidth = Math.max(3, Math.round(width / 54))
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(x1, y1)
                            ctx.lineTo(x2, y2)
                            ctx.stroke()
                        }
                    }
                }

                // Rotating Vinyl Disc Center
                Rectangle {
                    id: vinylDisc
                    anchors.centerIn: parent
                    width: Math.round(Math.min(parent.width, parent.height) * 0.44)
                    height: width
                    radius: Math.round(width * 0.5)
                    color: themeHub.darkInk
                    border.color: themeHub.accentA
                    border.width: 3

                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 5500
                        loops: Animation.Infinite
                        running: visWin.visible && visWin.curStyle === "ring" && (MediaService.isPlaying || visWin.demoActive)
                    }

                    // Inner vinyl groove ring
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.72)
                        height: width
                        radius: Math.round(width * 0.5)
                        color: "transparent"
                        border.color: "#333759"
                        border.width: 2
                    }

                    // Center label sticker
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.46)
                        height: width
                        radius: Math.round(width * 0.5)
                        color: themeHub.accentB
                        border.color: "#FFFFFF"
                        border.width: 2

                        Image {
                            anchors.centerIn: parent
                            width: Math.round(parent.width * 0.54)
                            height: width
                            source: "qrc:/qml/icons/music-note-dark.svg"
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }
                    }
                }
            }

            // =================================================================
            // STYLE 4: "dots" — 16x8 Segmented LED Matrix
            // =================================================================
            Item {
                anchors.fill: parent
                anchors.margins: 12
                visible: visWin.curStyle === "dots"

                readonly property int cols: 16
                readonly property int rows: 8
                readonly property real cellW: Math.max(8, (width - (cols - 1) * 4) / cols)
                readonly property real cellH: Math.max(6, (height - (rows - 1) * 4) / rows)

                Repeater {
                    model: 16
                    delegate: Item {
                        required property int index
                        readonly property int colIdx: index
                        readonly property real level: visWin.bandValue(Math.min(31, colIdx * 2))
                        readonly property int litRows: Math.max(1, Math.round(level * 8))

                        x: colIdx * (parent.cellW + 4)
                        y: 0
                        width: parent.cellW
                        height: parent.height

                        Repeater {
                            model: 8
                            delegate: Rectangle {
                                required property int index
                                readonly property int rowFromBottom: 7 - index
                                readonly property bool lit: rowFromBottom < litRows
                                x: 0
                                y: index * (parent.parent.cellH + 4)
                                width: parent.width
                                height: parent.parent.cellH
                                radius: 4
                                color: lit ? visWin.bandColor(colIdx, 16) : "#E2E8F5"
                                border.color: lit ? themeHub.darkInk : "#CBD5E1"
                                border.width: lit ? 1 : 0
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
                anchors.margins: 10
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
        // Edit Mode Chrome (Dashed Outline, 4 Corner Diamonds, Tag, Pills, Close)
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
                x: -3
                y: -3
                width: parent.width + 6
                height: parent.height + 6
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
                    const r = 20
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

            // 4 corner diamond handles
            Repeater {
                model: [
                    { cx: -1, cy: -1 },
                    { cx: 1, cy: -1 },
                    { cx: -1, cy: 1 },
                    { cx: 1, cy: 1 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property real tx: modelData.cx < 0 ? 0 : editChrome.width
                    readonly property real ty: modelData.cy < 0 ? 0 : editChrome.height
                    x: Math.round(tx - width * 0.5)
                    y: Math.round(ty - height * 0.5)
                    width: editDragMa.containsMouse ? 12 : 9
                    height: width
                    rotation: 45
                    radius: 2
                    color: editDragMa.containsMouse ? themeHub.accentB : themeHub.accentA
                    border.color: themeHub.darkInk
                    border.width: 2
                    antialiasing: true
                    z: 92
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

            // Top-left Tag Pill
            Rectangle {
                x: 8
                y: -5
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

            // Top-right Action Pills: Size, Style, Close
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 4
                y: -5
                spacing: 4
                z: 95

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
                        text: visWin.sizeLabels[visWin.sizeIdx] || "M"
                        font.pixelSize: 10
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
