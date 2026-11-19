import QtQuick
import Quickshell
import SekaiDesk

// #9: Fullscreen click-through GPU wallpaper transition overlay using SekaiPop .qsb shaders
PanelWindow {
    id: win

    required property var themeHub

    property bool active: false
    property string activeStyle: "sekaiRing"
    property string fromUrl: ""
    property string toUrl: ""
    property string pendingPath: ""
    property real progress: 0.0
    property bool animStarted: false

    visible: active
    x: 0
    y: 0
    width: themeHub.screenW
    height: themeHub.screenH
    desktopLayer: true
    clickThrough: true
    color: "transparent"
    mask: []

    function beginTransition(fromPath, toPath, style) {
        blendAnim.stop()
        warmupTimer.stop()
        commitHoldTimer.stop()
        safetyTimeout.stop()

        activeStyle = style || "sekaiRing"
        fromUrl = WallpaperService.toFileUrl(fromPath)
        toUrl = WallpaperService.toFileUrl(toPath)
        pendingPath = toPath
        progress = 0.0
        animStarted = false

        if (!fromUrl || fromUrl === "" || fromUrl === toUrl) {
            finishNow()
            return
        }

        active = true
        safetyTimeout.restart()
        checkReadyAndStart()
    }

    function checkReadyAndStart() {
        if (!active || animStarted)
            return
        if (imgFrom.status === Image.Ready && imgTo.status === Image.Ready) {
            animStarted = true
            safetyTimeout.stop()
            warmupTimer.restart()
        } else if (imgFrom.status === Image.Error || imgTo.status === Image.Error) {
            finishNow()
        }
    }

    function finishNow() {
        blendAnim.stop()
        warmupTimer.stop()
        safetyTimeout.stop()
        if (pendingPath !== "") {
            WallpaperService.applyWallpaper(pendingPath)
            pendingPath = ""
        }
        commitHoldTimer.restart()
    }

    Connections {
        target: WallpaperService
        function onTransitionRequested(fromPath, toPath, style) {
            win.beginTransition(fromPath, toPath, style)
        }
    }

    Timer {
        id: safetyTimeout
        interval: 2000
        onTriggered: {
            if (!win.animStarted)
                win.finishNow()
        }
    }

    Timer {
        id: warmupTimer
        interval: 32
        onTriggered: {
            if (!win.active)
                return
            blendAnim.from = 0.0
            blendAnim.to = 1.0
            if (win.activeStyle === "sekaiIris") {
                blendAnim.duration = 1900
                blendAnim.easing.type = Easing.Linear
            } else if (win.activeStyle === "sekaiRing" || win.activeStyle === "star" || win.activeStyle === "diagonalBlocks") {
                blendAnim.duration = 1200
                blendAnim.easing.type = Easing.Linear
            } else {
                blendAnim.duration = 750
                blendAnim.easing.type = Easing.InOutQuad
            }
            blendAnim.restart()
        }
    }

    NumberAnimation {
        id: blendAnim
        target: win
        property: "progress"
        onFinished: {
            if (win.pendingPath !== "") {
                WallpaperService.applyWallpaper(win.pendingPath)
                win.pendingPath = ""
            }
            commitHoldTimer.restart()
        }
    }

    // Brief hold after SPI_SETDESKWALLPAPER so Windows DWM repaints underneath cleanly
    Timer {
        id: commitHoldTimer
        interval: 180
        onTriggered: {
            win.active = false
            win.progress = 0.0
            win.fromUrl = ""
            win.toUrl = ""
            win.animStarted = false
        }
    }

    Image {
        id: imgFrom
        visible: true
        width: win.width
        height: win.height
        source: win.fromUrl
        sourceSize: Qt.size(Math.max(1, win.width), Math.max(1, win.height))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: win.checkReadyAndStart()
    }

    Image {
        id: imgTo
        visible: true
        width: win.width
        height: win.height
        source: win.toUrl
        sourceSize: Qt.size(Math.max(1, win.width), Math.max(1, win.height))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        onStatusChanged: win.checkReadyAndStart()
    }

    ShaderEffectSource {
        id: srcFrom
        sourceItem: imgFrom
        hideSource: true
        live: win.active
        smooth: true
    }

    ShaderEffectSource {
        id: srcTo
        sourceItem: imgTo
        hideSource: true
        live: win.active
        smooth: true
    }

    ShaderEffect {
        id: shader
        anchors.fill: parent
        visible: win.active && imgFrom.status === Image.Ready && imgTo.status === Image.Ready

        readonly property string shaderBase: {
            switch (win.activeStyle) {
            case "sekaiIris":      return "sekai_iris"
            case "sekaiRing":      return "sekai_ring"
            case "star":           return "sekai_star"
            case "diagonalBlocks": return "sekai_blocks"
            case "sekaiFlash":     return "sekai_flash"
            default:               return "fade"
            }
        }

        property var source1: srcFrom
        property var source2: srcTo
        property real progress: win.progress
        property real aspect: height > 0 ? (width / height) : 1.0
        property color accentColor: win.themeHub.accentA
        property color colorWhite: "#FFFFFF"
        property color colorPink: win.themeHub.accentB
        property color colorGreen: win.themeHub.accentA
        property color colorCyan: win.themeHub.accentA

        property int transitionStyle: 0
        property real distortion: 1.0
        property real speed: 1.0
        property real ringWidth: 0.44
        property real colorIntensity: 1.0
        property vector2d center: Qt.vector2d(0.5, 0.5)

        property real thickness: 0.2
        property real pointLength: 3.0
        property real curvature: 1.0
        property real elastic: 1.0
        property real spin: 0.5

        property vector2d direction: Qt.vector2d(-1, -1)
        property real bandThickness: 0.2
        property real blockSize: 0.34
        property real stagger: 1.0

        vertexShader: Qt.resolvedUrl("qrc:/qml/shaders/wallpaper/" + shader.shaderBase + ".vert.qsb")
        fragmentShader: Qt.resolvedUrl("qrc:/qml/shaders/wallpaper/" + shader.shaderBase + ".frag.qsb")
    }
}
