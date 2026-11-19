import QtQuick
import "ScopeMath.js" as SM

// Direct port of SekaiPop ShaderVisualizerLayer.qml driving precompiled .frag.qsb shaders:
// ribbons, aurora, pulse, scope, mirror, ring, dots.
ShaderEffect {
    id: root

    required property string style
    required property ShaderVisualizerEngine engine
    property color color1: "#33CCBB"
    property color color2: "#FF66AA"
    property color color3: "#FFCC33"
    property color ink: "#1c2a4a"
    property string artUrl: ""
    property real lite: 0

    // Internal album art texture provider for the "ring" shader
    Image {
        id: coverImg
        visible: true
        width: 192
        height: 192
        sourceSize.width: 192
        sourceSize.height: 192
        source: root.style === "ring" ? (root.artUrl || "") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    ShaderEffectSource {
        id: coverSrc
        sourceItem: coverImg
        hideSource: true
        live: root.style === "ring" && coverImg.status === Image.Ready
        smooth: true
    }

    property var cover: coverSrc
    readonly property real hasCover: (root.style === "ring" && coverImg.status === Image.Ready) ? 1.0 : 0.0

    readonly property real time: engine.time
    readonly property bool soft: style === "ribbons"
    readonly property bool punch: style === "scope" || style === "pulse"
    property real kick: 0
    property real kickAvg: 0
    property real speed: 0.5
    readonly property var scopeOut: new Array(192).fill(0)
    property real softBass: 0
    property real lastTime: 0
    property real travel: 0
    readonly property var softLevels: new Array(52).fill(0)
    readonly property real bass: punch ? kick : (soft ? softBass : engine.bass)

    // Scope traces (4 traces x 48 samples = 12 vector4d each)
    property vector4d s0_0;  property vector4d s0_1;  property vector4d s0_2;  property vector4d s0_3
    property vector4d s0_4;  property vector4d s0_5;  property vector4d s0_6;  property vector4d s0_7
    property vector4d s0_8;  property vector4d s0_9;  property vector4d s0_10; property vector4d s0_11
    property vector4d s1_0;  property vector4d s1_1;  property vector4d s1_2;  property vector4d s1_3
    property vector4d s1_4;  property vector4d s1_5;  property vector4d s1_6;  property vector4d s1_7
    property vector4d s1_8;  property vector4d s1_9;  property vector4d s1_10; property vector4d s1_11
    property vector4d s2_0;  property vector4d s2_1;  property vector4d s2_2;  property vector4d s2_3
    property vector4d s2_4;  property vector4d s2_5;  property vector4d s2_6;  property vector4d s2_7
    property vector4d s2_8;  property vector4d s2_9;  property vector4d s2_10; property vector4d s2_11
    property vector4d s3_0;  property vector4d s3_1;  property vector4d s3_2;  property vector4d s3_3
    property vector4d s3_4;  property vector4d s3_5;  property vector4d s3_6;  property vector4d s3_7
    property vector4d s3_8;  property vector4d s3_9;  property vector4d s3_10; property vector4d s3_11

    readonly property real fade: engine.fade
    readonly property real bandCount: engine.bandCount
    readonly property vector2d resolution: Qt.vector2d(width, height)
    readonly property real px: 1 / Math.max(1, Screen.devicePixelRatio || 1)

    property vector4d b0;  property vector4d b1;  property vector4d b2;  property vector4d b3
    property vector4d b4;  property vector4d b5;  property vector4d b6;  property vector4d b7
    property vector4d b8;  property vector4d b9;  property vector4d b10; property vector4d b11
    property vector4d b12
    property vector4d p0;  property vector4d p1;  property vector4d p2;  property vector4d p3
    property vector4d p4;  property vector4d p5;  property vector4d p6;  property vector4d p7
    property vector4d p8;  property vector4d p9;  property vector4d p10; property vector4d p11
    property vector4d p12

    visible: fade > 0.001
    blending: true
    fragmentShader: Qt.resolvedUrl("qrc:/qml/shaders/visualizer/" + style + ".frag.qsb")

    Connections {
        target: root.engine
        function onFrame() {
            const l = root.engine.levels
            const p = root.engine.peaks
            if (root.punch) {
                const dt = Math.min(0.1, Math.max(0, root.engine.time - root.lastTime))
                root.lastTime = root.engine.time
                let low = 0
                for (let i = 0; i < 6; i++)
                    low += l[i] / 6
                root.kickAvg += (low - root.kickAvg) * Math.min(1, dt * 1.2)
                const hit = Math.max(0, Math.min(1, (low - root.kickAvg * 1.15 - 0.02) * 4))
                root.kick = Math.max(root.kick * Math.exp(-dt * 7), hit)
                if (root.style === "scope") {
                    const weight = (l[0] + l[1] + l[2] + l[3]) / 4
                    root.speed += (0.5 + 1.2 * weight + 1.8 * root.kick - root.speed) * Math.min(1, dt * 7)
                    root.travel = (root.travel + dt * root.speed) % 62.83185307
                    const o = root.scopeOut
                    SM.fill(o, l, root.travel, root.kick, root.lite > 0.5 ? 1 : SM.TRACES)
                    for (let tr = 0; tr < SM.TRACES; tr++) {
                        for (let j = 0; j < 12; j++) {
                            const i = tr * SM.N + j * 4
                            root["s" + tr + "_" + j] = Qt.vector4d(o[i], o[i + 1], o[i + 2], o[i + 3])
                        }
                    }
                    return
                }
            }
            if (root.soft) {
                const dt = Math.min(0.1, Math.max(0, root.engine.time - root.lastTime))
                root.lastTime = root.engine.time
                const s = root.softLevels
                for (let i = 0; i < 52; i++)
                    s[i] += (l[i] - s[i]) * Math.min(1, dt * (l[i] > s[i] ? 11 : 4))
                root.softBass += (root.engine.bass - root.softBass) * Math.min(1, dt * (root.engine.bass > root.softBass ? 14 : 6))
                const weight = (s[0] + s[1] + s[2] + s[3]) / 4
                root.travel = (root.travel + dt * (1 + 2.2 * weight + 1.2 * root.softBass)) % 62.83185307
                for (let k = 0; k < 13; k++) {
                    const i = k * 4
                    root["b" + k] = Qt.vector4d(s[i], s[i + 1], s[i + 2], s[i + 3])
                    root["p" + k] = Qt.vector4d(p[i], p[i + 1], p[i + 2], p[i + 3])
                }
                return
            }
            for (let k = 0; k < 13; k++) {
                const i = k * 4
                root["b" + k] = Qt.vector4d(l[i], l[i + 1], l[i + 2], l[i + 3])
                root["p" + k] = Qt.vector4d(p[i], p[i + 1], p[i + 2], p[i + 3])
            }
        }
    }
}
