import QtQuick
import SekaiDesk

// #8: SekaiPop PillBars / PillWave inline audio visualizer for the TopBar MediaPill
Item {
    id: root

    property string style: "bars" // "bars" | "wave" | "off"
    property bool active: false
    property color inkColor: "#1A1B2E"
    property color peakColor: "#FFFFFF"

    readonly property bool enabledMode: style !== "off" && active
    implicitWidth: enabledMode ? 22 : 0
    width: enabledMode ? 22 : 0
    height: 14
    visible: enabledMode

    property real phase: 0.0

    FrameAnimation {
        running: root.visible && root.enabledMode
        onTriggered: {
            root.phase = (root.phase + frameTime * 6.5) % (Math.PI * 200)
            if (root.style === "wave")
                waveCanvas.requestPaint()
        }
    }

    // Mode 1: 4 Equalizer Bars (reads live WASAPI bands if active, else smooth music pulse)
    Row {
        visible: root.style === "bars"
        anchors.centerIn: parent
        spacing: 2
        height: parent.height

        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 3.5
                radius: 1.75
                color: index % 2 === 0 ? root.inkColor : root.peakColor
                border.width: index % 2 === 1 ? 0.5 : 0
                border.color: root.inkColor
                height: {
                    if (VisualizerService.enabled && VisualizerService.audioActive) {
                        const bands = VisualizerService.bands || []
                        const v = Number(bands[Math.min(31, index * 6 + 1)]) || 0.0
                        return Math.max(3, Math.round(3 + Math.min(1, v * 1.15) * 10))
                    }
                    const s = 0.5 + 0.5 * Math.sin(root.phase * (1.0 + index * 0.23) + index * 1.45)
                    return Math.max(3, Math.round(3 + s * 9.5))
                }
            }
        }
    }

    // Mode 2: Smooth Sine Waveform Canvas
    Canvas {
        id: waveCanvas
        visible: root.style === "wave"
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.enabledMode)
                return
            const midY = height * 0.5
            const ampBase = (VisualizerService.enabled && VisualizerService.audioActive)
                ? (2.0 + Math.min(1.0, VisualizerService.level * 1.6) * 4.5)
                : 3.8
            ctx.beginPath()
            for (let px = 0; px <= width; px += 2) {
                const norm = px / Math.max(1, width)
                const env = Math.sin(norm * Math.PI)
                const y = midY + Math.sin(norm * 10.5 - root.phase * 1.6) * ampBase * env
                if (px === 0)
                    ctx.moveTo(px, y)
                else
                    ctx.lineTo(px, y)
            }
            ctx.lineWidth = 2.0
            ctx.lineCap = "round"
            ctx.strokeStyle = root.inkColor
            ctx.stroke()
        }
    }
}
