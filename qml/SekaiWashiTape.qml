import QtQuick

// Decorative washi tape strip with torn ends and subtle diagonal sheen (ported from SekaiPop WashiTape).
Item {
    id: root

    property color color: "#6EE7B7"
    property real toothSize: 6
    property real softness: 1.4
    property int quality: 4
    readonly property real pad: 2

    width: 84
    height: 26

    onColorChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()

    Canvas {
        id: cv
        x: -root.pad
        y: -root.pad
        width: (root.width + root.pad * 2) * root.quality
        height: (root.height + root.pad * 2) * root.quality
        scale: 1 / root.quality
        transformOrigin: Item.TopLeft
        smooth: true
        antialiasing: true
        Component.onCompleted: requestPaint()

        function roundedPoly(ctx, pts, r) {
            const n = pts.length
            ctx.beginPath()
            ctx.moveTo((pts[n - 1][0] + pts[0][0]) / 2, (pts[n - 1][1] + pts[0][1]) / 2)
            for (let i = 0; i < n; i++) {
                const p = pts[i], q = pts[(i + 1) % n]
                ctx.arcTo(p[0], p[1], (p[0] + q[0]) / 2, (p[1] + q[1]) / 2, r)
            }
            ctx.closePath()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (root.width < 8 || root.height < 4)
                return

            const q = root.quality
            ctx.scale(q, q)
            ctx.translate(root.pad, root.pad)

            const w = root.width, h = root.height
            const t = Math.min(root.toothSize, w / 5)
            const teeth = 3

            const pts = [[t, 0], [w - t, 0]]
            for (let i = 0; i < teeth; i++) {
                const y0 = (i / teeth) * h
                const y1 = ((i + 1) / teeth) * h
                const mid = (y0 + y1) / 2
                pts.push([i % 2 === 0 ? w : w - t, mid])
                pts.push([w - t, y1])
            }
            pts.push([t, h])
            for (let i = teeth; i > 0; i--) {
                const y0 = (i / teeth) * h
                const y1 = ((i - 1) / teeth) * h
                const mid = (y0 + y1) / 2
                pts.push([i % 2 === 0 ? 0 : t, mid])
                pts.push([t, y1])
            }

            if (root.softness > 0) {
                cv.roundedPoly(ctx, pts, root.softness)
            } else {
                ctx.beginPath()
                ctx.moveTo(pts[0][0], pts[0][1])
                for (let i = 1; i < pts.length; i++)
                    ctx.lineTo(pts[i][0], pts[i][1])
                ctx.closePath()
            }

            ctx.globalAlpha = 0.86
            ctx.fillStyle = root.color
            ctx.fill()

            ctx.save()
            ctx.clip()
            ctx.globalAlpha = 0.16
            ctx.fillStyle = "#ffffff"
            for (let sx = -h; sx < w + h; sx += 9) {
                ctx.beginPath()
                ctx.moveTo(sx, 0)
                ctx.lineTo(sx + h * 0.6, h)
                ctx.lineTo(sx + h * 0.6 + 3, h)
                ctx.lineTo(sx + 3, 0)
                ctx.closePath()
                ctx.fill()
            }
            ctx.restore()
        }
    }
}
