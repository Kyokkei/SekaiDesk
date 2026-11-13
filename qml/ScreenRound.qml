import QtQuick
import Quickshell

// 4 lightweight 14x14 click-through screen corners (no full-screen overlay)
Item {
    id: screenRoundRoot
    visible: false

    required property var themeHub
    required property bool fullscreenActive
    property int scrW: 1920
    property int scrH: 1080
    readonly property int cornerSize: 14
    readonly property bool cornersVisible: themeHub.screenRoundEnabled && !fullscreenActive

    PanelWindow {
        visible: screenRoundRoot.cornersVisible
        clickThrough: true
        color: "transparent"
        x: 0
        y: 0
        width: screenRoundRoot.cornerSize
        height: screenRoundRoot.cornerSize

        Canvas {
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#000000"
                ctx.beginPath()
                ctx.moveTo(0, 0)
                ctx.lineTo(width, 0)
                ctx.arcTo(0, 0, 0, height, width)
                ctx.lineTo(0, height)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    PanelWindow {
        visible: screenRoundRoot.cornersVisible
        clickThrough: true
        color: "transparent"
        x: Math.max(0, screenRoundRoot.scrW - screenRoundRoot.cornerSize)
        y: 0
        width: screenRoundRoot.cornerSize
        height: screenRoundRoot.cornerSize

        Canvas {
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#000000"
                ctx.beginPath()
                ctx.moveTo(width, 0)
                ctx.lineTo(0, 0)
                ctx.arcTo(width, 0, width, height, width)
                ctx.lineTo(width, height)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    PanelWindow {
        visible: screenRoundRoot.cornersVisible
        clickThrough: true
        color: "transparent"
        x: 0
        y: Math.max(0, screenRoundRoot.scrH - screenRoundRoot.cornerSize)
        width: screenRoundRoot.cornerSize
        height: screenRoundRoot.cornerSize

        Canvas {
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#000000"
                ctx.beginPath()
                ctx.moveTo(0, height)
                ctx.lineTo(width, height)
                ctx.arcTo(0, height, 0, 0, width)
                ctx.lineTo(0, 0)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    PanelWindow {
        visible: screenRoundRoot.cornersVisible
        clickThrough: true
        color: "transparent"
        x: Math.max(0, screenRoundRoot.scrW - screenRoundRoot.cornerSize)
        y: Math.max(0, screenRoundRoot.scrH - screenRoundRoot.cornerSize)
        width: screenRoundRoot.cornerSize
        height: screenRoundRoot.cornerSize

        Canvas {
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#000000"
                ctx.beginPath()
                ctx.moveTo(width, height)
                ctx.lineTo(0, height)
                ctx.arcTo(width, height, width, 0, width)
                ctx.lineTo(width, 0)
                ctx.closePath()
                ctx.fill()
            }
        }
    }
}
