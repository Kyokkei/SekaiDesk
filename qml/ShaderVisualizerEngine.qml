import QtQuick

// Port of SekaiPop ShaderVisualizerEngine.qml, adapted to SekaiDesk's 32-band
// VisualizerService.bands (0..1) and smoothly resampled into 50 bands (max 52)
// so all 8 precompiled SekaiPop GPU shaders receive rich spectral energy.
Item {
    id: root
    visible: false

    property bool active: true
    property bool demo: false
    property real sensitivity: 1.0
    property real frameGap: 0
    // 32 normalized floats (0..1) from VisualizerService.bands
    property var raw: []

    readonly property int maxBands: 52
    property int bandCount: 50
    property real time: 0
    property real bass: 0
    property real fade: 0
    readonly property var levels: new Array(maxBands).fill(0)
    readonly property var peaks: new Array(maxBands).fill(0)

    signal frame()

    property real lastSignal: 0
    property real bassAverage: 0
    readonly property var peakHold: new Array(maxBands).fill(0)
    readonly property var resampledRaw: new Array(maxBands).fill(0)

    onRawChanged: {
        if (!root.active || root.demo)
            return
        if (root.raw && root.raw.length > 0)
            root.bandCount = 50
        for (let i = 0; i < (root.raw ? root.raw.length : 0); i++) {
            if (root.raw[i] > 0.001) {
                root.lastSignal = Date.now()
                ticker.running = true
                return
            }
        }
    }

    onDemoChanged: {
        if (root.demo && root.active) {
            root.bandCount = 50
            ticker.running = true
        }
    }

    onActiveChanged: {
        if (root.active && (root.demo || Date.now() - root.lastSignal < 1000 || root.fade > 0.002)) {
            ticker.running = true
        } else if (!root.active) {
            ticker.running = false
            root.fade = 0
        }
    }

    function synth(t) {
        const out = new Array(50).fill(0)
        const kick = Math.exp(-9 * (t % 0.5))
        for (let i = 0; i < 12; i++)
            out[i] += 0.80 * kick * (1 - i / 16)
        const snare = Math.exp(-10 * ((t + 0.5) % 1.0))
        for (let i = 14; i < 28; i++)
            out[i] += 0.60 * snare
        const hat = Math.exp(-14 * ((t + 0.125) % 0.25))
        for (let i = 33; i < 50; i++)
            out[i] += 0.38 * hat * (0.6 + 0.4 * Math.sin(t * 3 + i))
        const mc = 18 + 12 * Math.sin(t * 0.9) + 4 * Math.sin(t * 2.3)
        for (let i = 0; i < 50; i++) {
            const d = (i - mc) / 4.4
            out[i] = Math.min(1.0, out[i] + 0.52 * Math.exp(-d * d) * (0.7 + 0.3 * Math.sin(t * 5)))
        }
        return out
    }

    function buildResampledRaw() {
        const src = root.raw
        const out = root.resampledRaw
        const srcLen = src ? src.length : 0
        if (srcLen <= 0) {
            for (let i = 0; i < root.maxBands; i++)
                out[i] = 0
            return out
        }
        for (let i = 0; i < 50; i++) {
            const pos = (i / 49.0) * (srcLen - 1)
            const i0 = Math.floor(pos)
            const i1 = Math.min(srcLen - 1, i0 + 1)
            const frac = pos - i0
            out[i] = (Number(src[i0]) || 0) * (1.0 - frac) + (Number(src[i1]) || 0) * frac
        }
        out[50] = out[49]
        out[51] = out[49]
        return out
    }

    function step(dt) {
        const playing = root.demo || Date.now() - root.lastSignal < 1000
        const src = root.demo ? root.synth(root.time + dt) : root.buildResampledRaw()
        root.time += dt
        root.fade += ((playing ? 1 : 0) - root.fade) * Math.min(1, dt * (playing ? 4 : 1.5))

        let bassNow = 0
        for (let i = 0; i < root.maxBands; i++) {
            const target = playing && i < src.length
                ? Math.min(1, Math.max(0, src[i] * root.sensitivity))
                : 0
            const level = root.levels[i]
            root.levels[i] = level + (target - level) * Math.min(1, dt * (target > level ? 18 : 5))
            if (root.levels[i] >= root.peaks[i]) {
                root.peaks[i] = root.levels[i]
                root.peakHold[i] = 0.35
            } else if (root.peakHold[i] > 0) {
                root.peakHold[i] -= dt
            } else {
                root.peaks[i] = Math.max(root.levels[i], root.peaks[i] - dt * 0.45)
            }
            if (i < 4)
                bassNow += target / 4
        }

        root.bassAverage += (bassNow - root.bassAverage) * Math.min(1, dt * 1.5)
        if (bassNow > root.bassAverage * 1.3 + 0.04 && bassNow > 0.25)
            root.bass = Math.min(1, root.bass + (bassNow - root.bassAverage) * 2.5)
        root.bass *= Math.exp(-dt * 5)

        root.frame()
        if (!playing && root.fade < 0.002) {
            root.fade = 0
            ticker.running = false
        }
    }

    FrameAnimation {
        id: ticker
        property real acc: 0
        running: false
        onTriggered: {
            acc += frameTime
            if (acc < root.frameGap)
                return
            root.step(Math.min(acc, 0.1))
            acc = 0
        }
    }
}
