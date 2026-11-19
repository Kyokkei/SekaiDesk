import QtQuick

// Port of SekaiPop TideVisualizer + TideShaderLayer using tide.frag.qsb
Item {
    id: root

    required property ShaderVisualizerEngine engine
    property color color1: "#8EE3EF"
    property color color2: "#A5E6A5"
    property color color3: "#FF9ECB"
    property color ink: "#1c2a4a"
    property bool lite: false

    readonly property int cols: root.lite ? 44 : 80
    readonly property real pad: 24
    readonly property real lineW: Math.max(2.5, root.height / 90)
    readonly property real shadowOff: Math.max(4, root.height / 40)
    readonly property color shadowColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.28)

    readonly property var spec: [
        { base: 0.24, amp: 0.55, rad: 9, pass: 4, rate: 2.5, speed: 0.55, len: 3.4 },
        { base: 0.16, amp: 0.78, rad: 6, pass: 3, rate: 5.0, speed: 0.85, len: 4.6 },
        { base: 0.08, amp: 1.0,  rad: 4, pass: 3, rate: 11.0, speed: 1.2, len: 6.2 }
    ]
    readonly property var fills: [
        Qt.rgba(root.color2.r, root.color2.g, root.color2.b, 0.94),
        root.color1,
        Qt.lighter(root.color3, 1 + 0.25 * root.engine.bass)
    ]
    readonly property var laneX: [0.5, 0.4, 0.6, 0.29, 0.71, 0.17, 0.83, 0.05, 0.95]

    property var st: [[], [], []]
    property real lastT: 0
    property real bassSmooth: 0

    function blur(a) {
        const n = a.length
        const out = new Array(n)
        for (let i = 0; i < n; i++) {
            const m2 = a[Math.max(0, i - 2)], m1 = a[Math.max(0, i - 1)]
            const p1 = a[Math.min(n - 1, i + 1)], p2 = a[Math.min(n - 1, i + 2)]
            out[i] = (m2 + 4 * m1 + 6 * a[i] + 4 * p1 + p2) / 16
        }
        return out
    }

    visible: engine.fade > 0.003
    opacity: Math.min(1, engine.fade * 2)
    transform: Translate { y: (1 - Math.min(1, root.engine.fade)) * root.height * 0.18 }

    function resetState() {
        const n = root.cols + 1
        root.st = [new Array(n).fill(0), new Array(n).fill(0), new Array(n).fill(0)]
    }

    onColsChanged: root.resetState()
    Component.onCompleted: root.resetState()

    function rebuild() {
        const e = root.engine
        const W = root.width, H = root.height
        if (W <= 0 || H <= 0)
            return
        const n = root.cols
        if (root.st[0].length !== n + 1)
            root.resetState()
        const nb = e.bandCount > 1 ? e.bandCount : 50
        let dt = e.time - root.lastT
        root.lastT = e.time
        if (dt <= 0 || dt > 0.2)
            dt = 0.03
        const lv = e.levels, pk = e.peaks
        const span = W + 2 * root.pad
        root.bassSmooth += (e.bass - root.bassSmooth) * Math.min(1, dt * 8)
        const ampMul = 1 + 0.35 * root.bassSmooth

        const raw = new Array(n + 1)
        let mean = 0
        for (let c = 0; c <= n; c++) {
            const d = Math.abs(c / n - 0.5) * 2
            const f = d * (nb - 1) * 0.8
            const i0 = Math.floor(f)
            const i1 = Math.min(nb - 1, i0 + 1)
            const t = f - i0
            raw[c] = Math.pow(Math.min(1, (lv[i0] * (1 - t) + lv[i1] * t) * (1 + d * 1.1)), 0.8)
            mean += raw[c] / (n + 1)
        }
        const swellAmp = (0.02 + 0.05 * Math.min(1, mean * 2.5)) * H * e.fade

        const xs = new Array(n + 1)
        for (let c = 0; c <= n; c++)
            xs[c] = -root.pad + c / n * span

        let tops = null
        for (let k = 0; k < 3; k++) {
            const L = root.spec[k]
            const s = root.st[k]
            const a = Math.min(1, dt * L.rate)
            const ys = new Array(n + 1)
            for (let c = 0; c <= n; c++) {
                let sum = 0, cnt = 0
                for (let j = -L.rad; j <= L.rad; j++) {
                    const cc = c + j
                    if (cc < 0 || cc > n)
                        continue
                    sum += raw[cc]
                    cnt++
                }
                s[c] += (sum / cnt - s[c]) * a
            }
            let v = s
            for (let q = 0; q < L.pass; q++)
                v = root.blur(v)
            for (let c = 0; c <= n; c++) {
                const u = xs[c] / W
                const swell = swellAmp * (Math.sin(u * L.len - e.time * L.speed + k * 2.1)
                    + 0.5 * Math.sin(u * L.len * 1.9 + e.time * L.speed * 0.6 + k))
                ys[c] = Math.max(6, H - (L.base * H + v[c] * L.amp * H * 0.68 * ampMul + swell))
            }
            shaderLayer.setSheet(k, ys)
            if (k === 2)
                tops = ys
        }

        const marks = []
        for (let m = 0; m < root.laneX.length; m++) {
            const xf = root.laneX[m]
            const d = Math.abs(xf - 0.5) * 2
            const f = d * (nb - 1) * 0.8
            const p = Math.min(1, Math.max(pk[Math.floor(f)], pk[Math.min(nb - 1, Math.ceil(f))]) * (1 + d * 1.1))
            const col = Math.max(0, Math.min(n, Math.round((xf * W + root.pad) / span * n)))
            const crest = tops[col]
            const lift = 16 + Math.min(34, p * H * 0.16)
            marks.push({ x: xf * W, y: Math.max(10, crest - lift), cy: crest, a: Math.min(1, p * 4) * e.fade, s: p })
        }

        shaderLayer.setPins(marks)
    }

    Connections {
        target: root.engine
        function onFrame() { root.rebuild() }
    }

    ShaderEffect {
        id: shaderLayer
        anchors.fill: parent

        property color ink: root.ink
        property color shadowColor: root.lite ? "transparent" : root.shadowColor
        property color fillBack: root.fills[0]
        property color fillMid: root.fills[1]
        property color fillFront: root.fills[2]
        property real columns: root.cols
        property real pad: root.pad
        property real lineW: root.lineW
        property real shadowDrop: root.shadowOff

        readonly property vector2d resolution: Qt.vector2d(width, height)
        readonly property real ncols: shaderLayer.columns
        readonly property real padX: shaderLayer.pad
        readonly property real shadowOff: shaderLayer.shadowDrop
        readonly property real px: 1 / Math.max(1, Screen.devicePixelRatio || 1)
        readonly property vector4d inkCol: Qt.vector4d(ink.r, ink.g, ink.b, ink.a)
        readonly property vector4d shadowCol: Qt.vector4d(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a)
        readonly property vector4d fill0: Qt.vector4d(fillBack.r, fillBack.g, fillBack.b, fillBack.a)
        readonly property vector4d fill1: Qt.vector4d(fillMid.r, fillMid.g, fillMid.b, fillMid.a)
        readonly property vector4d fill2: Qt.vector4d(fillFront.r, fillFront.g, fillFront.b, fillFront.a)

        property vector4d pin0; property vector4d pin1; property vector4d pin2
        property vector4d pin3; property vector4d pin4; property vector4d pin5
        property vector4d pin6; property vector4d pin7; property vector4d pin8
        property vector4d pinS0; property vector4d pinS1; property vector4d pinS2

        property vector4d h0_0;  property vector4d h0_1;  property vector4d h0_2;  property vector4d h0_3;  property vector4d h0_4;  property vector4d h0_5;  property vector4d h0_6
        property vector4d h0_7;  property vector4d h0_8;  property vector4d h0_9;  property vector4d h0_10; property vector4d h0_11; property vector4d h0_12; property vector4d h0_13
        property vector4d h0_14; property vector4d h0_15; property vector4d h0_16; property vector4d h0_17; property vector4d h0_18; property vector4d h0_19; property vector4d h0_20

        property vector4d h1_0;  property vector4d h1_1;  property vector4d h1_2;  property vector4d h1_3;  property vector4d h1_4;  property vector4d h1_5;  property vector4d h1_6
        property vector4d h1_7;  property vector4d h1_8;  property vector4d h1_9;  property vector4d h1_10; property vector4d h1_11; property vector4d h1_12; property vector4d h1_13
        property vector4d h1_14; property vector4d h1_15; property vector4d h1_16; property vector4d h1_17; property vector4d h1_18; property vector4d h1_19; property vector4d h1_20

        property vector4d h2_0;  property vector4d h2_1;  property vector4d h2_2;  property vector4d h2_3;  property vector4d h2_4;  property vector4d h2_5;  property vector4d h2_6
        property vector4d h2_7;  property vector4d h2_8;  property vector4d h2_9;  property vector4d h2_10; property vector4d h2_11; property vector4d h2_12; property vector4d h2_13
        property vector4d h2_14; property vector4d h2_15; property vector4d h2_16; property vector4d h2_17; property vector4d h2_18; property vector4d h2_19; property vector4d h2_20

        blending: true
        fragmentShader: Qt.resolvedUrl("qrc:/qml/shaders/visualizer/tide.frag.qsb")

        function setSheet(k, ys) {
            const n = ys.length
            for (let j = 0; j < 21; j++) {
                const i = j * 4
                shaderLayer["h" + k + "_" + j] = Qt.vector4d(
                    i < n ? ys[i] : 0, i + 1 < n ? ys[i + 1] : 0,
                    i + 2 < n ? ys[i + 2] : 0, i + 3 < n ? ys[i + 3] : 0
                )
            }
        }

        function setPins(marks) {
            const s = []
            for (let m = 0; m < 9; m++) {
                const k = marks[m]
                shaderLayer["pin" + m] = k ? Qt.vector4d(k.x, k.y, k.cy, k.a) : Qt.vector4d(0, 0, 0, 0)
                s.push(k ? k.s : 0)
            }
            shaderLayer.pinS0 = Qt.vector4d(s[0], s[1], s[2], s[3])
            shaderLayer.pinS1 = Qt.vector4d(s[4], s[5], s[6], s[7])
            shaderLayer.pinS2 = Qt.vector4d(s[8], 0, 0, 0)
        }
    }
}
