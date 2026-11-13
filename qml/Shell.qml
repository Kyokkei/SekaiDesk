import QtQuick
import Quickshell
import SekaiDesk

// ===========================================================================
// PHASE 1c — Live DWM Window Thumbnails + Zero-Churn Cosine Magnification
//
// - Fixed-width PanelWindow during hover sweep: zero SetWindowPos / SetWindowRgn
//   churn on mouse move (CPU & DWM stay flat).
// - Clamped Cosine Magnification Wave (48px -> 82px keycaps).
// - Live DWM 60fps Window Preview popup when hovering any running app.
// ===========================================================================

PanelWindow {
    id: dockWindow
    visible: true

    readonly property int baseTileSize: 48
    readonly property int maxTileSize: 82
    readonly property int baseIconSize: 34
    readonly property int maxIconSize: 64
    readonly property int tileGap: 8
    readonly property int pillPadX: 14
    readonly property int pillPadY: 10
    readonly property int shadowOffset: 4
    readonly property int headroom: maxTileSize - baseTileSize + 14
    readonly property int hoverPadX: 96

    readonly property real waveRadius: 128.0
    property bool dockHovered: pillHover.hovered
    property real pointerX: 0
    property real waveStrength: (dockHovered && dragFromSlot < 0) ? 1.0 : 0.0

    // Phase 3: Dock Auto-Hide / Dodge Active Window
    property bool dockAutoHideEnabled: true
    readonly property bool dockShouldHide: dockAutoHideEnabled
        && WindowTracker.dockOverlap
        && !WindowTracker.bottomEdgeHovered
        && !dockHovered
        && dragFromSlot < 0
        && !ctxOpen
        && activePreviewTarget === ""
        && !previewCardHovered
    property real hideProgress: dockShouldHide ? 1.0 : 0.0
    Behavior on hideProgress {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
    }
    readonly property real hideOffsetY: hideProgress * (baseTileSize + pillPadY * 2 + shadowOffset + 20)

    // Preview state for Phase 1c
    property string hoveredAppTarget: ""
    property string hoveredAppName: ""
    property real hoveredIconCenterX: 0
    property string activePreviewTarget: ""
    property string activePreviewName: ""
    property var activePreviewWindows: []
    property bool previewCardHovered: false

    // Phase 2: Right-click context menu state
    property bool ctxOpen: false
    property string ctxTarget: ""
    property string ctxName: ""
    property string ctxArgs: ""
    property bool ctxPinned: false
    property bool ctxRunning: false
    property bool ctxIsSeparator: false
    property int ctxPinnedIndex: -1
    property real ctxCenterX: 0

    // Phase 2b: Smooth unified drag-to-reorder across the entire app row
    property int dragFromSlot: -1
    property int dragHoverSlot: -1
    property real dragLiveX: 0
    property real dragGrabOffsetX: 24
    property real dragItemWidth: 48
    property var frozenDockItems: null

    function appSlotCount() {
        const list = dockItems
        let count = 0
        for (let i = 0; i < list.length; ++i) {
            if (list[i].kind === "app")
                count++
            else
                break
        }
        return count
    }

    function updateDragHover(curCenterRowX) {
        const list = dockItems
        if (dragFromSlot < 0)
            return
        let bestIdx = dragFromSlot
        let bestDist = 1e9
        const step = baseTileSize + tileGap
        for (let i = 0; i < list.length; ++i) {
            if (list[i].kind !== "app")
                break
            const cx = i * step + baseTileSize * 0.5
            const d = Math.abs(curCenterRowX - cx)
            if (d < bestDist) {
                bestDist = d
                bestIdx = i
            }
        }
        dragHoverSlot = bestIdx
    }

    function finishDrag() {
        const from = dragFromSlot
        const to = dragHoverSlot
        const list = frozenDockItems || dockItems
        frozenDockItems = null
        dragFromSlot = -1
        dragHoverSlot = -1
        dragLiveX = 0
        if (from >= 0 && to >= 0 && from !== to) {
            const apps = []
            for (let i = 0; i < list.length; ++i) {
                const it = list[i]
                if (it.kind !== "app")
                    break
                apps.push({
                    name: it.name || "App",
                    target: it.target || "",
                    args: it.args || "",
                    pinned: !!it.pinned
                })
            }
            AppLauncher.reorderDock(apps, from, to)
        }
    }

    Behavior on waveStrength {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    // Combined list: pinned apps + (divider + unpinned running apps) + quit key
    readonly property var dockItems: {
        const pinned = AppLauncher.pinnedApps || []
        const running = WindowTracker.runningApps || []
        const items = []
        const seenExe = {}

        function normKey(p) {
            return String(p || "").trim().replace(/\//g, "\\").toLowerCase()
        }

        for (let i = 0; i < pinned.length; ++i) {
            const p = pinned[i]
            if (p.kind === "separator")
                continue
            const k = normKey(p.target)
            if (k !== "")
                seenExe[k] = true
            const st = WindowTracker.stateForTarget(p.target || "")
            items.push({
                kind: "app",
                name: p.name || "",
                target: p.target || "",
                args: p.args || "",
                pinned: true,
                pinnedIndex: i,
                running: !!st.running,
                active: !!st.active,
                minimized: !!st.minimized,
                count: st.count || 0
            })
        }

        const extra = []
        for (let j = 0; j < running.length; ++j) {
            const r = running[j]
            const rk = normKey(r.target)
            if (!seenExe[rk]) {
                extra.push({
                    kind: "app",
                    name: r.name || "",
                    target: r.target || "",
                    args: "",
                    pinned: false,
                    running: true,
                    active: !!r.active,
                    minimized: !!r.minimized,
                    count: r.count || 1
                })
            }
        }

        for (let k = 0; k < extra.length; ++k)
            items.push(extra[k])

        items.push({ kind: "divider" })
        items.push({ kind: "quit" })
        return items
    }

    readonly property real idleTotalWidth: {
        const list = dockItems
        const n = list.length
        let bx = 0
        for (let i = 0; i < n; ++i) {
            const it = list[i]
            const bw = (it.kind === "app" || it.kind === "trash")
                ? baseTileSize
                : (it.kind === "media" ? 124 : (it.kind === "quit" ? 34 : 8))
            bx += bw + (i < n - 1 ? tileGap : 0)
        }
        return Math.max(1, bx)
    }

    // One-pass Cosine Magnification layout solver
    readonly property var layoutData: {
        const list = dockItems
        const n = list.length
        const baseCenters = []
        let bx = 0
        for (let i = 0; i < n; ++i) {
            const it = list[i]
            const bw = (it.kind === "app" || it.kind === "trash")
                ? baseTileSize
                : (it.kind === "media" ? 124 : (it.kind === "quit" ? 34 : 8))
            baseCenters.push(bx + bw * 0.5)
            bx += bw + (i < n - 1 ? tileGap : 0)
        }

        const widths = []
        const xs = []
        const weights = []
        let cx = 0
        for (let i = 0; i < n; ++i) {
            const it = list[i]
            let w = 0.0
            if ((it.kind === "app" || it.kind === "trash") && waveStrength > 0.001) {
                const dist = Math.abs(pointerX - baseCenters[i])
                if (dist < waveRadius) {
                    w = 0.5 * (1.0 + Math.cos(Math.PI * dist / waveRadius)) * waveStrength
                }
            }
            weights.push(w)
            const curW = (it.kind === "app" || it.kind === "trash")
                ? (baseTileSize + (maxTileSize - baseTileSize) * w)
                : (it.kind === "media" ? 124 : (it.kind === "quit" ? 34 : 8))
            widths.push(curW)
            xs.push(cx)
            cx += curW + (i < n - 1 ? tileGap : 0)
        }

        return {
            totalWidth: Math.max(1, cx),
            xs: xs,
            widths: widths,
            weights: weights
        }
    }

    // Fixed window width so mouse sweep NEVER calls SetWindowPos or SetWindowRgn.
    width: idleTotalWidth + pillPadX * 2 + hoverPadX + shadowOffset
    height: headroom + baseTileSize + pillPadY * 2 + shadowOffset

    anchors.bottom: true
    anchors.margins.bottom: 10
    clickThrough: dockWindow.hideProgress > 0.5

    // When hidden, mask is empty (100% click-through). When idle, mask strictly to the static idle pill rect;
    // when hovered, use a static full-window mask so SetWindowRgn is NOT called per mouse pixel.
    mask: dockWindow.hideProgress > 0.95
        ? []
        : (dockWindow.dockHovered || dockWindow.waveStrength > 0.02
            ? [{ x: 0, y: 0, width: dockWindow.width, height: dockWindow.height }]
            : [{
                x: (dockWindow.width - dockWindow.shadowOffset - (dockWindow.idleTotalWidth + dockWindow.pillPadX * 2)) * 0.5,
                y: dockWindow.headroom,
                width: dockWindow.idleTotalWidth + dockWindow.pillPadX * 2 + dockWindow.shadowOffset,
                height: dockWindow.baseTileSize + dockWindow.pillPadY * 2 + dockWindow.shadowOffset
            }])

    Timer {
        id: previewShowTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (dockWindow.hoveredAppTarget !== "") {
                const wins = WindowTracker.windowsForTarget(dockWindow.hoveredAppTarget)
                if (wins && wins.length > 0) {
                    dockWindow.activePreviewTarget = dockWindow.hoveredAppTarget
                    dockWindow.activePreviewName = dockWindow.hoveredAppName
                    dockWindow.activePreviewWindows = wins
                }
            }
        }
    }

    Timer {
        id: previewHideTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (dockWindow.hoveredAppTarget === "" && !dockWindow.previewCardHovered) {
                dockWindow.activePreviewTarget = ""
                dockWindow.activePreviewWindows = []
            }
        }
    }

    function refreshPreviewIfOpen() {
        if (dockWindow.activePreviewTarget !== "") {
            const wins = WindowTracker.windowsForTarget(dockWindow.activePreviewTarget)
            if (!wins || wins.length === 0) {
                dockWindow.activePreviewTarget = ""
                dockWindow.activePreviewWindows = []
            } else {
                dockWindow.activePreviewWindows = wins
            }
        }
    }

    Connections {
        target: WindowTracker
        function onRunningAppsChanged() {
            dockWindow.refreshPreviewIfOpen()
        }
    }

    // Hard flat offset shadow
    Rectangle {
        x: dockPill.x + dockWindow.shadowOffset
        y: dockWindow.headroom + dockWindow.shadowOffset + dockWindow.hideOffsetY
        width: dockPill.width
        height: dockPill.height
        radius: dockPill.radius
        color: "#1A1B2E"
    }

    // Main Dock Pill (centered in fixed dockWindow)
    Rectangle {
        id: dockPill
        x: (dockWindow.width - dockWindow.shadowOffset - width) * 0.5
        y: dockWindow.headroom + dockWindow.hideOffsetY
        width: dockWindow.layoutData.totalWidth + dockWindow.pillPadX * 2
        height: dockWindow.baseTileSize + dockWindow.pillPadY * 2
        radius: 20
        color: "#1A1B2E"

        // White inner ring
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2.5
            radius: parent.radius - 2.5
            color: "#FFFFFF"

            // Pastel body fill
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: parent.radius - 3
                color: "#F1F5FF"
            }
        }

        HoverHandler {
            id: pillHover
            onPointChanged: {
                // Map pointer relative to idle row center so wave centers stay stable
                const idleLeft = (dockPill.width - dockWindow.idleTotalWidth) * 0.5
                dockWindow.pointerX = point.position.x - idleLeft
            }
        }

        Item {
            id: dockRow
            x: dockWindow.pillPadX
            y: dockWindow.pillPadY
            width: dockWindow.layoutData.totalWidth
            height: dockWindow.baseTileSize

            Repeater {
                model: (dockWindow.dragFromSlot >= 0 && dockWindow.frozenDockItems)
                    ? dockWindow.frozenDockItems
                    : dockWindow.dockItems

                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index

                    Component.onDestruction: {
                        if (isDraggingThis) {
                            dockWindow.frozenDockItems = null
                            dockWindow.dragFromSlot = -1
                            dockWindow.dragHoverSlot = -1
                            dockWindow.dragLiveX = 0
                        }
                    }

                    readonly property real wFactor: dockWindow.layoutData.weights[index] || 0
                    readonly property real slotW: dockWindow.layoutData.widths[index] || dockWindow.baseTileSize
                    readonly property real slotX: dockWindow.layoutData.xs[index] || 0
                    readonly property bool isAppItem: modelData.kind === "app"
                    readonly property int pIdx: (modelData.pinned && modelData.pinnedIndex !== undefined)
                        ? modelData.pinnedIndex : -1
                    readonly property bool isDraggingThis: isAppItem && dockWindow.dragFromSlot >= 0 && index === dockWindow.dragFromSlot
                    property real dragShiftX: {
                        const from = dockWindow.dragFromSlot
                        const to = dockWindow.dragHoverSlot
                        if (from < 0 || !isAppItem || isDraggingThis)
                            return 0
                        const step = dockWindow.baseTileSize + dockWindow.tileGap
                        if (from < to && index > from && index <= to)
                            return -step
                        if (from > to && index < from && index >= to)
                            return step
                        return 0
                    }

                    Behavior on dragShiftX {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }

                    z: isDraggingThis ? 100 : 1
                    scale: isDraggingThis ? 1.12 : 1.0
                    y: isDraggingThis ? -6 : 0
                    x: isDraggingThis ? dockWindow.dragLiveX : (slotX + dragShiftX)
                    width: slotW
                    height: dockWindow.baseTileSize

                    Behavior on dragShiftX {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    // --- App Keycap ---
                    Item {
                        id: appBox
                        visible: slot.modelData.kind === "app"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: slot.slotW
                        height: slot.slotW

                        readonly property bool hovered: appArea.containsMouse
                        readonly property bool pressed: appArea.pressed
                        readonly property real curIconSize: dockWindow.baseIconSize
                            + (dockWindow.maxIconSize - dockWindow.baseIconSize) * slot.wFactor

                        onHoveredChanged: {
                            if (hovered && slot.modelData.running) {
                                dockWindow.hoveredAppTarget = slot.modelData.target || ""
                                dockWindow.hoveredAppName = slot.modelData.name || ""
                                dockWindow.hoveredIconCenterX = dockWindow.x + dockPill.x
                                    + dockRow.x + slot.slotX + slot.slotW * 0.5
                                previewHideTimer.stop()
                                previewShowTimer.restart()
                            } else if (!hovered && dockWindow.hoveredAppTarget === (slot.modelData.target || "")) {
                                dockWindow.hoveredAppTarget = ""
                                previewShowTimer.stop()
                                previewHideTimer.restart()
                            }
                        }

                        // Keycap bottom lip
                        Rectangle {
                            anchors.fill: keyCap
                            anchors.topMargin: 2.5
                            anchors.bottomMargin: -2.5
                            radius: keyCap.radius
                            color: "#1A1B2E"
                            opacity: appBox.pressed ? 0.0 : 0.9
                        }

                        Rectangle {
                            id: keyCap
                            width: parent.width
                            height: parent.height
                            y: appBox.pressed ? 2.5 : (appBox.hovered ? -2 : 0)
                            radius: 13 + 5 * slot.wFactor
                            color: appBox.hovered ? "#E0F2FE" : "#FFFFFF"
                            border.width: 2
                            border.color: appBox.hovered ? "#0284C7" : "#1A1B2E"

                            Image {
                                anchors.centerIn: parent
                                width: appBox.curIconSize
                                height: appBox.curIconSize
                                source: "image://winicon/" + encodeURIComponent(slot.modelData.target || "")
                                sourceSize: Qt.size(dockWindow.maxIconSize, dockWindow.maxIconSize)
                                smooth: true
                                mipmap: true
                            }
                        }

                        // Running Diamond Dot
                        Rectangle {
                            visible: !!slot.modelData.running
                            anchors.horizontalCenter: keyCap.horizontalCenter
                            anchors.bottom: keyCap.bottom
                            anchors.bottomMargin: -5
                            width: 6
                            height: 6
                            rotation: 45
                            radius: 1
                            color: slot.modelData.active
                                ? "#06B6D4"
                                : (slot.modelData.minimized ? "#FFFFFF" : "#10B981")
                            border.width: 1.5
                            border.color: "#1A1B2E"
                        }

                        MouseArea {
                            id: appArea
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: slot.isDraggingThis ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            property real pressGlobalX: 0
                            property real grabRatio: 0.5
                            property bool didDrag: false

                            onPressed: (mouse) => {
                                didDrag = false
                                if (mouse.button === Qt.LeftButton) {
                                    pressGlobalX = mapToGlobal(mouse.x, mouse.y).x
                                    grabRatio = Math.max(0.15, Math.min(0.85, mouse.x / Math.max(1, slot.slotW)))
                                }
                            }
                            onPositionChanged: (mouse) => {
                                if (!(mouse.buttons & Qt.LeftButton)) {
                                    if (didDrag || dockWindow.dragFromSlot >= 0) {
                                        didDrag = false
                                        dockWindow.finishDrag()
                                    }
                                    return
                                }
                                const globalX = mapToGlobal(mouse.x, mouse.y).x
                                const dx = globalX - pressGlobalX
                                const rowMouseX = dockRow.mapFromGlobal(globalX, 0).x
                                if (!didDrag && Math.abs(dx) > 6) {
                                    didDrag = true
                                    previewShowTimer.stop()
                                    dockWindow.activePreviewTarget = ""
                                    dockWindow.activePreviewWindows = []
                                    dockWindow.ctxOpen = false
                                    dockWindow.dragItemWidth = dockWindow.baseTileSize
                                    dockWindow.dragGrabOffsetX = grabRatio * dockWindow.baseTileSize
                                    dockWindow.frozenDockItems = dockWindow.dockItems
                                    dockWindow.dragFromSlot = slot.index
                                    dockWindow.dragHoverSlot = slot.index
                                }
                                if (didDrag) {
                                    const maxApps = dockWindow.appSlotCount()
                                    const maxX = Math.max(0, (maxApps - 1) * (dockWindow.baseTileSize + dockWindow.tileGap) + 8)
                                    const rawX = rowMouseX - dockWindow.dragGrabOffsetX
                                    dockWindow.dragLiveX = Math.max(-8, Math.min(maxX, rawX))
                                    dockWindow.updateDragHover(dockWindow.dragLiveX + dockWindow.baseTileSize * 0.5)
                                }
                            }
                            onReleased: {
                                if (didDrag)
                                    dockWindow.finishDrag()
                            }
                            onCanceled: {
                                if (didDrag) {
                                    didDrag = false
                                    dockWindow.finishDrag()
                                }
                            }
                            onClicked: (mouse) => {
                                if (didDrag) {
                                    didDrag = false
                                    return
                                }
                                if (mouse.button === Qt.RightButton) {
                                    previewShowTimer.stop()
                                    dockWindow.activePreviewTarget = ""
                                    dockWindow.activePreviewWindows = []
                                    dockWindow.ctxIsSeparator = false
                                    dockWindow.ctxPinnedIndex = slot.pIdx
                                    dockWindow.ctxTarget = slot.modelData.target || ""
                                    dockWindow.ctxName = slot.modelData.name || "App"
                                    dockWindow.ctxArgs = slot.modelData.args || ""
                                    dockWindow.ctxPinned = !!slot.modelData.pinned
                                    dockWindow.ctxRunning = !!slot.modelData.running
                                    dockWindow.ctxCenterX = dockWindow.x + dockPill.x
                                        + dockRow.x + slot.slotX + slot.slotW * 0.5
                                    dockWindow.ctxOpen = true
                                    ctxAutoHideTimer.restart()
                                    return
                                }
                                dockWindow.ctxOpen = false
                                if (slot.modelData.running) {
                                    WindowTracker.activateOrToggle(slot.modelData.target || "")
                                } else {
                                    AppLauncher.launch(
                                        slot.modelData.target || "",
                                        slot.modelData.args || ""
                                    )
                                }
                            }
                        }
                    }

                    // --- Custom Draggable / Removable Separator (Phase 2b) ---
                    Item {
                        id: customSepBox
                        visible: slot.modelData.kind === "custom_sep"
                        anchors.fill: parent

                        Rectangle {
                            anchors.centerIn: parent
                            width: (customSepArea.containsMouse || slot.isDraggingThis) ? 3 : 2
                            height: dockWindow.baseTileSize - 12
                            radius: 1.5
                            color: (customSepArea.containsMouse || slot.isDraggingThis)
                                ? "#0284C7" : "#94A3B8"
                        }

                        MouseArea {
                            id: customSepArea
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: slot.isDraggingThis ? Qt.ClosedHandCursor : Qt.SizeHorCursor
                            property real pressGlobalX: 0
                            property real startSlotCenterX: 0
                            property bool didDrag: false

                            onPressed: (mouse) => {
                                didDrag = false
                                if (mouse.button === Qt.LeftButton && slot.pIdx >= 0) {
                                    pressGlobalX = mapToGlobal(mouse.x, mouse.y).x
                                    startSlotCenterX = slot.slotX + slot.slotW * 0.5
                                }
                            }
                            onPositionChanged: (mouse) => {
                                if (!(mouse.buttons & Qt.LeftButton) || slot.pIdx < 0)
                                    return
                                const dx = mapToGlobal(mouse.x, mouse.y).x - pressGlobalX
                                if (!didDrag && Math.abs(dx) > 5) {
                                    didDrag = true
                                    dockWindow.ctxOpen = false
                                    dockWindow.dragItemWidth = slot.slotW
                                    dockWindow.dragFromIdx = slot.pIdx
                                    dockWindow.dragUnpinnedSlotIdx = -1
                                    dockWindow.dragHoverIdx = slot.pIdx
                                }
                                if (didDrag) {
                                    dockWindow.dragDeltaX = dx
                                    dockWindow.updateDragHover(startSlotCenterX + dx)
                                }
                            }
                            onReleased: {
                                if (didDrag)
                                    dockWindow.finishDrag()
                            }
                            onCanceled: {
                                if (didDrag) {
                                    didDrag = false
                                    dockWindow.finishDrag()
                                }
                            }
                            onClicked: (mouse) => {
                                if (didDrag) {
                                    didDrag = false
                                    return
                                }
                                if (mouse.button === Qt.RightButton) {
                                    previewShowTimer.stop()
                                    dockWindow.activePreviewTarget = ""
                                    dockWindow.activePreviewWindows = []
                                    dockWindow.ctxIsSeparator = true
                                    dockWindow.ctxPinnedIndex = slot.pIdx
                                    dockWindow.ctxName = "Separator"
                                    dockWindow.ctxTarget = ""
                                    dockWindow.ctxArgs = ""
                                    dockWindow.ctxPinned = true
                                    dockWindow.ctxRunning = false
                                    dockWindow.ctxCenterX = dockWindow.x + dockPill.x
                                        + dockRow.x + slot.slotX + slot.slotW * 0.5
                                    dockWindow.ctxOpen = true
                                    ctxAutoHideTimer.restart()
                                }
                            }
                        }
                    }

                    // --- Divider ---
                    Rectangle {
                        visible: slot.modelData.kind === "divider"
                        anchors.centerIn: parent
                        width: 2
                        height: dockWindow.baseTileSize - 14
                        radius: 1
                        color: "#CBD5E1"
                    }

                    // --- Native Trash Bin Keycap (Phase 1d) ---
                    Item {
                        id: trashBox
                        visible: slot.modelData.kind === "trash"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: slot.slotW
                        height: slot.slotW

                        readonly property bool hovered: trashArea.containsMouse
                        readonly property bool pressed: trashArea.pressed

                        Rectangle {
                            anchors.fill: trashCap
                            anchors.topMargin: 2.5
                            anchors.bottomMargin: -2.5
                            radius: trashCap.radius
                            color: "#1A1B2E"
                            opacity: trashBox.pressed ? 0.0 : 0.9
                        }

                        Rectangle {
                            id: trashCap
                            width: parent.width
                            height: parent.height
                            y: trashBox.pressed ? 2.5 : (trashBox.hovered ? -2 : 0)
                            radius: 13 + 5 * slot.wFactor
                            color: trashBox.hovered ? "#FEF3C7" : "#FFFFFF"
                            border.width: 2
                            border.color: trashBox.hovered ? "#D97706" : "#1A1B2E"

                            // Sticker Trash Can Graphic
                            Item {
                                anchors.centerIn: parent
                                width: parent.width * 0.62
                                height: parent.height * 0.62

                                // Paper peeking out when non-empty
                                Rectangle {
                                    visible: !TrashService.isEmpty
                                    x: parent.width * 0.22
                                    y: parent.height * 0.06
                                    width: parent.width * 0.36
                                    height: parent.height * 0.34
                                    radius: 3
                                    rotation: -10
                                    color: "#BAE6FD"
                                    border.width: 1.5
                                    border.color: "#1A1B2E"
                                }
                                Rectangle {
                                    visible: !TrashService.isEmpty
                                    x: parent.width * 0.44
                                    y: parent.height * 0.08
                                    width: parent.width * 0.34
                                    height: parent.height * 0.32
                                    radius: 3
                                    rotation: 12
                                    color: "#FDE68A"
                                    border.width: 1.5
                                    border.color: "#1A1B2E"
                                }

                                // Bin lid
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height * 0.22
                                    width: parent.width * 0.84
                                    height: Math.max(4, parent.height * 0.14)
                                    radius: 3
                                    color: TrashService.isEmpty ? "#94A3B8" : "#F59E0B"
                                    border.width: 1.5
                                    border.color: "#1A1B2E"
                                }

                                // Bin body
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height * 0.34
                                    width: parent.width * 0.72
                                    height: parent.height * 0.56
                                    radius: 5
                                    color: TrashService.isEmpty ? "#E2E8F0" : "#FDE68A"
                                    border.width: 1.8
                                    border.color: "#1A1B2E"

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Math.max(2, parent.width * 0.14)
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: 2
                                                height: parent.parent.height * 0.52
                                                radius: 1
                                                color: "#64748B"
                                            }
                                        }
                                    }
                                }
                            }

                            // Item count badge
                            Rectangle {
                                visible: !TrashService.isEmpty
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: -4
                                width: Math.max(18, trashBadgeTxt.implicitWidth + 8)
                                height: 18
                                radius: 9
                                color: "#EF4444"
                                border.width: 1.5
                                border.color: "#1A1B2E"

                                Text {
                                    id: trashBadgeTxt
                                    anchors.centerIn: parent
                                    text: TrashService.itemCount > 99 ? "99+" : String(TrashService.itemCount)
                                    color: "#FFFFFF"
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            id: trashArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    TrashService.emptyBin()
                                } else {
                                    TrashService.openBin()
                                }
                            }
                        }
                    }

                    // --- GSMTC Media Controls Pill (Phase 1d) ---
                    Rectangle {
                        visible: slot.modelData.kind === "media"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 124
                        height: dockWindow.baseTileSize - 2
                        radius: 13
                        color: "#FFFFFF"
                        border.width: 2
                        border.color: "#1A1B2E"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 2

                            Text {
                                width: parent.width
                                text: MediaService.title !== "" ? MediaService.title : "Media"
                                color: "#1A1B2E"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.bold: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6

                                Rectangle {
                                    width: 26
                                    height: 20
                                    radius: 7
                                    color: prevArea.containsMouse ? "#E0F2FE" : "#F1F5F9"
                                    border.width: 1.2
                                    border.color: "#1A1B2E"
                                    Image {
                                        anchors.centerIn: parent
                                        width: 11
                                        height: 11
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        smooth: true
                                        source: "qrc:/qml/icons/skip-previous-dark.svg"
                                    }
                                    MouseArea {
                                        id: prevArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: MediaService.previous()
                                    }
                                }

                                Rectangle {
                                    width: 30
                                    height: 20
                                    radius: 7
                                    color: playArea.containsMouse ? "#BAE6FD" : "#38BDF8"
                                    border.width: 1.2
                                    border.color: "#1A1B2E"
                                    Image {
                                        anchors.centerIn: parent
                                        width: 11
                                        height: 11
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        smooth: true
                                        source: MediaService.isPlaying ? "qrc:/qml/icons/pause-dark.svg" : "qrc:/qml/icons/play-dark.svg"
                                    }
                                    MouseArea {
                                        id: playArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: MediaService.playPause()
                                    }
                                }

                                Rectangle {
                                    width: 26
                                    height: 20
                                    radius: 7
                                    color: nextArea.containsMouse ? "#E0F2FE" : "#F1F5F9"
                                    border.width: 1.2
                                    border.color: "#1A1B2E"
                                    Image {
                                        anchors.centerIn: parent
                                        width: 11
                                        height: 11
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        smooth: true
                                        source: "qrc:/qml/icons/skip-next-dark.svg"
                                    }
                                    MouseArea {
                                        id: nextArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: MediaService.next()
                                    }
                                }
                            }
                        }
                    }

                    // --- Compact Quit Button ---
                    Rectangle {
                        visible: slot.modelData.kind === "quit"
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        radius: 15
                        color: quitArea.containsMouse ? "#FEE2E2" : "#E2E8F0"
                        border.width: 1.5
                        border.color: quitArea.containsMouse ? "#EF4444" : "#1A1B2E"

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: quitArea.containsMouse ? "#B91C1C" : "#1A1B2E"
                            font.family: "Segoe UI"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        MouseArea {
                            id: quitArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.quit()
                        }
                    }
                }
            }
        }
    }

    // =======================================================================
    // PHASE 1c — Live DWM Window Preview Popup
    // =======================================================================
    PanelWindow {
        id: previewWindow
        visible: dockWindow.activePreviewWindows.length > 0
        clickThrough: false

        readonly property int tileW: 216
        readonly property int tileH: 152
        readonly property int cardPad: 12
        readonly property int cardShadow: 4
        readonly property int maxTiles: Math.min(4, dockWindow.activePreviewWindows.length)

        width: previewCard.width + cardShadow
        height: previewCard.height + cardShadow

        x: {
            const scrW = dockWindow.screen ? dockWindow.screen.width : 1920
            const rawX = Math.round(dockWindow.hoveredIconCenterX - width * 0.5)
            return Math.max(12, Math.min(scrW - width - 12, rawX))
        }
        y: Math.max(12, dockWindow.y + 4 - height)

        mask: [{ x: 0, y: 0, width: previewCard.width + cardShadow, height: previewCard.height + cardShadow }]

        HoverHandler {
            id: previewHover
            onHoveredChanged: {
                dockWindow.previewCardHovered = hovered
                if (hovered) {
                    previewHideTimer.stop()
                } else {
                    previewHideTimer.restart()
                }
            }
        }

        // Hard offset shadow
        Rectangle {
            x: previewWindow.cardShadow
            y: previewWindow.cardShadow
            width: previewCard.width
            height: previewCard.height
            radius: previewCard.radius
            color: "#1A1B2E"
        }

        Rectangle {
            id: previewCard
            x: 0
            y: 0
            width: previewRow.implicitWidth + previewWindow.cardPad * 2
            height: previewWindow.tileH + previewWindow.cardPad * 2 + 24
            radius: 18
            color: "#1A1B2E"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2.5
                radius: parent.radius - 2.5
                color: "#FFFFFF"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: parent.radius - 3
                    color: "#F1F5FF"
                }
            }

            // App header label
            Text {
                x: previewWindow.cardPad
                y: 8
                text: dockWindow.activePreviewName
                color: "#1A1B2E"
                font.family: "Segoe UI"
                font.pixelSize: 12
                font.bold: true
            }

            Row {
                id: previewRow
                x: previewWindow.cardPad
                y: 28
                spacing: 10

                Repeater {
                    model: dockWindow.activePreviewWindows.slice(0, 4)

                    delegate: Rectangle {
                        id: winTile
                        required property var modelData
                        width: previewWindow.tileW
                        height: previewWindow.tileH
                        radius: 12
                        color: tileHoverArea.containsMouse ? "#E0F2FE" : "#FFFFFF"
                        border.width: modelData.active ? 2 : 1.5
                        border.color: modelData.active ? "#0284C7" : "#1A1B2E"

                        // Title + window action buttons
                        Item {
                            id: titleBar
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 6
                            height: 22

                            Text {
                                anchors.left: parent.left
                                anchors.right: actionBtns.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: winTile.modelData.title || dockWindow.activePreviewName
                                color: "#1E293B"
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Row {
                                id: actionBtns
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: minArea.containsMouse ? "#FEF3C7" : "#E2E8F0"
                                    border.width: 1
                                    border.color: "#1A1B2E"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "–"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: "#1A1B2E"
                                    }
                                    MouseArea {
                                        id: minArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WindowTracker.minimizeHwnd(winTile.modelData.hwnd)
                                    }
                                }

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: closeArea.containsMouse ? "#FEE2E2" : "#E2E8F0"
                                    border.width: 1
                                    border.color: closeArea.containsMouse ? "#EF4444" : "#1A1B2E"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: closeArea.containsMouse ? "#B91C1C" : "#1A1B2E"
                                    }
                                    MouseArea {
                                        id: closeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WindowTracker.closeHwnd(winTile.modelData.hwnd)
                                    }
                                }
                            }
                        }

                        // Live DWM 60fps window stream
                        DwmThumbnail {
                            anchors.top: titleBar.bottom
                            anchors.topMargin: 4
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            sourceHwnd: winTile.modelData.hwnd || 0
                            active: previewWindow.visible
                        }

                        MouseArea {
                            id: tileHoverArea
                            anchors.top: titleBar.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.MiddleButton) {
                                    WindowTracker.closeHwnd(winTile.modelData.hwnd)
                                } else {
                                    WindowTracker.activateHwnd(winTile.modelData.hwnd)
                                    dockWindow.activePreviewTarget = ""
                                    dockWindow.activePreviewWindows = []
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Phase 2: Right-Click Dock Context Menu ---
    Timer {
        id: ctxAutoHideTimer
        interval: 1600
        onTriggered: {
            if (!ctxHoverHandler.hovered)
                dockWindow.ctxOpen = false
        }
    }

    PanelWindow {
        id: contextWindow
        visible: dockWindow.ctxOpen
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        readonly property int menuW: 196
        readonly property var menuActions: {
            const list = []
            list.push({
                id: "launch",
                label: dockWindow.ctxRunning ? "New Window / Open" : "Open App",
                danger: false
            })
            list.push({
                id: "pin",
                label: dockWindow.ctxPinned ? "Unpin from Dock" : "Pin to Dock",
                danger: false
            })
            if (dockWindow.ctxRunning) {
                list.push({ id: "close", label: "Close Window", danger: true })
            }
            return list
        }

        width: menuW + cardShadow
        height: ctxCard.height + cardShadow

        x: {
            const scrW = dockWindow.screen ? dockWindow.screen.width : 1920
            const rawX = Math.round(dockWindow.ctxCenterX - width * 0.5)
            return Math.max(12, Math.min(scrW - width - 12, rawX))
        }
        y: Math.max(12, dockWindow.y + 4 - height)

        mask: [{ x: 0, y: 0, width: menuW + cardShadow, height: ctxCard.height + cardShadow }]

        // Hard sticker drop shadow
        Rectangle {
            x: contextWindow.cardShadow
            y: contextWindow.cardShadow
            width: contextWindow.menuW
            height: ctxCard.height
            radius: 14
            color: "#1A1B2E"
        }

        Rectangle {
            id: ctxCard
            x: 0
            y: 0
            width: contextWindow.menuW
            height: ctxCol.implicitHeight + 14
            radius: 14
            color: "#FFFFFF"
            border.width: 2
            border.color: "#1A1B2E"

            HoverHandler {
                id: ctxHoverHandler
                onHoveredChanged: {
                    if (hovered)
                        ctxAutoHideTimer.stop()
                    else
                        ctxAutoHideTimer.restart()
                }
            }

            Column {
                id: ctxCol
                x: 8
                y: 7
                width: parent.width - 16
                spacing: 4

                // Header with app name + dismiss x
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: ctxDismissBtn.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: dockWindow.ctxName
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        font.bold: true
                        color: "#1E293B"
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: ctxDismissBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 6
                        color: ctxDismissArea.containsMouse ? "#F1F5F9" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#64748B"
                        }
                        MouseArea {
                            id: ctxDismissArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dockWindow.ctxOpen = false
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#E2E8F0"
                }

                Repeater {
                    model: contextWindow.menuActions
                    delegate: Rectangle {
                        id: menuBtn
                        required property var modelData
                        width: parent.width
                        height: 30
                        radius: 8
                        color: menuBtnArea.containsMouse
                            ? (modelData.danger ? "#FEE2E2" : "#E0F2FE")
                            : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuBtn.modelData.label
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: menuBtn.modelData.danger
                                ? (menuBtnArea.containsMouse ? "#B91C1C" : "#DC2626")
                                : (menuBtnArea.containsMouse ? "#0369A1" : "#1E293B")
                        }

                        MouseArea {
                            id: menuBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const act = menuBtn.modelData.id
                                const tgt = dockWindow.ctxTarget
                                const nm = dockWindow.ctxName
                                const ar = dockWindow.ctxArgs
                                dockWindow.ctxOpen = false
                                if (act === "launch") {
                                    AppLauncher.launch(tgt, ar)
                                } else if (act === "pin") {
                                    if (dockWindow.ctxPinned) {
                                        AppLauncher.removePinnedByTarget(tgt)
                                    } else {
                                        AppLauncher.addPinnedApp(nm, tgt, ar)
                                    }
                                } else if (act === "add_sep") {
                                    AppLauncher.insertSeparatorAt(dockWindow.ctxPinnedIndex + 1)
                                } else if (act === "remove_sep") {
                                    AppLauncher.removePinnedApp(dockWindow.ctxPinnedIndex)
                                } else if (act === "close") {
                                    const wins = WindowTracker.windowsForTarget(tgt) || []
                                    for (let i = 0; i < wins.length; ++i) {
                                        WindowTracker.closeHwnd(wins[i].hwnd)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // PHASE 4 — Slim Unified SekaiPop TopBar (28px) + AppBar WorkArea Reserve
    // =========================================================================
    PanelWindow {
        id: topBarWindow
        visible: true
        anchors.top: true
        anchors.left: true
        anchors.right: true
        anchors.margins.top: 0
        anchors.margins.left: 0
        anchors.margins.right: 0
        height: 28
        reserveTopBar: true
        reserveHeight: 28
        clickThrough: topBarWindow.fullscreenActive

        property string timeText: ""
        property string dateText: ""
        property bool mediaPopupOpen: false
        property double mediaPopupClosedAt: 0
        property bool trayPopupOpen: false
        property double trayPopupClosedAt: 0
        property bool quickPanelOpen: false
        property double quickPanelClosedAt: 0
        property bool calendarOpen: false
        property double calendarClosedAt: 0
        property bool wifiPopupOpen: false
        property double wifiPopupClosedAt: 0
        property bool btPopupOpen: false
        property double btPopupClosedAt: 0
        property bool phoneMode: false
        property real topHideProgress: topBarWindow.fullscreenActive ? 1.0 : 0.0

        Connections {
            target: SystemControl
            function onQuickPanelToggleRequested() {
                if (!topBarWindow.quickPanelOpen) {
                    AudioService.refreshSessions()
                    AudioService.refreshOutputDevices()
                    SystemControl.refresh()
                }
                topBarWindow.quickPanelOpen = !topBarWindow.quickPanelOpen
            }
        }
        Behavior on topHideProgress {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        readonly property real topHideOffsetY: -topHideProgress * 38

        blurBehind: !topBarWindow.fullscreenActive && topBarWindow.topHideProgress < 0.95
        blurRadius: 0
        blurInsetX: 0
        blurInsetY: 0
        blurInsetRight: 0
        blurInsetBottom: 0
        blurTint: Qt.rgba(14/255, 18/255, 30/255, 0.35)

        mask: topBarWindow.topHideProgress > 0.95 ? [] : null

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const d = new Date()
                const hh = String(d.getHours()).padStart(2, "0")
                const mm = String(d.getMinutes()).padStart(2, "0")
                const days = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
                const dd = String(d.getDate()).padStart(2, "0")
                const mo = String(d.getMonth() + 1).padStart(2, "0")
                topBarWindow.timeText = hh + ":" + mm
                topBarWindow.dateText = days[d.getDay()] + " " + dd + "/" + mo
            }
        }

        Item {
            id: topBarRoot
            anchors.fill: parent

            // Full-width flush transparent blurred bar (28px)
            Rectangle {
                id: barFrame
                x: 0
                y: topBarWindow.topHideOffsetY
                width: topBarRoot.width
                height: 28
                radius: 0
                color: "transparent"
                border.width: 0

                // --- Left Zone: Active App Badge + SekaiPop MediaPill + Window Title ---
                Row {
                    id: leftContentRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    spacing: 6

                    Rectangle {
                        id: appBadgeRect
                        anchors.verticalCenter: parent.verticalCenter
                        width: appNameTxt.implicitWidth + 14
                        height: 20
                        radius: 8
                        color: "#22D3EE"
                        border.width: 1.5
                        border.color: "#1A1B2E"

                        Text {
                            id: appNameTxt
                            anchors.centerIn: parent
                            text: WindowTracker.activeAppName || "Desktop"
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: "#1A1B2E"
                        }
                    }

                    // --- SekaiPop MediaPill (22px inside 28px TopBar, pinned left next to AppBadge) ---
                    Rectangle {
                        id: mediaPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: true
                        width: Math.max(148, Math.min(280, mediaArtBox.width + mediaDivider.width + 18 + mediaSingleLineTxt.implicitWidth))
                        height: 22
                        radius: 10
                        color: "#1A1B2E"
                        scale: mediaPillArea.pressed ? 0.97 : 1.0

                        Behavior on width {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            id: mediaPillFill
                            anchors.fill: parent
                            anchors.margins: 1.5
                            radius: parent.radius - 1.5
                            clip: true
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: "#5EEAD4" }
                                GradientStop { position: 1.0; color: "#22D3EE" }
                            }

                            Item {
                                id: mediaArtBox
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 24
                                opacity: (MediaService.hasSession && !MediaService.isPlaying) ? 0.55 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Image {
                                    anchors.centerIn: parent
                                    visible: mediaPillCover.status !== Image.Ready
                                    width: 13
                                    height: 13
                                    sourceSize.width: 26
                                    sourceSize.height: 26
                                    smooth: true
                                    source: "qrc:/qml/icons/music-note-dark.svg"
                                }

                                Image {
                                    id: mediaPillCover
                                    anchors.fill: parent
                                    source: MediaService.hasSession ? MediaService.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    cache: false
                                    visible: status === Image.Ready
                                }
                            }

                            Rectangle {
                                id: mediaDivider
                                anchors.left: mediaArtBox.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 1.5
                                color: "#1A1B2E"
                            }

                            Item {
                                anchors.left: mediaDivider.right
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                clip: true

                                Text {
                                    id: mediaSingleLineTxt
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    opacity: (MediaService.hasSession && !MediaService.isPlaying) ? 0.55 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    text: {
                                        if (!MediaService.hasSession)
                                            return "Nothing Playing"
                                        const t = MediaService.title || "Playing"
                                        const a = (MediaService.artist || "").trim()
                                        return a !== "" ? (t + "  ·  " + a) : t
                                    }
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#1A1B2E"
                                }
                            }
                        }

                        MouseArea {
                            id: mediaPillArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    if (!topBarWindow.mediaPopupOpen && (Date.now() - topBarWindow.mediaPopupClosedAt) < 220)
                                        return
                                    topBarWindow.mediaPopupOpen = !topBarWindow.mediaPopupOpen
                                } else if (mouse.button === Qt.RightButton) {
                                    MediaService.next()
                                } else if (mouse.button === Qt.MiddleButton) {
                                    MediaService.playPause()
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (WindowTracker.activeWindowTitle || "") !== ""
                        text: WindowTracker.activeWindowTitle || ""
                        width: Math.min(implicitWidth, Math.max(40, rightContentRow.x - leftContentRow.x - appBadgeRect.width - mediaPill.width - 30))
                        elide: Text.ElideRight
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        color: "#E2E8F0"
                    }
                }

                // --- Right Zone: CPU, RAM, Date & Clock ---
                Row {
                    id: rightContentRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: cpuTxt.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: "#1E293B"
                        border.width: 1
                        border.color: "#38BDF8"
                        Text {
                            id: cpuTxt
                            anchors.centerIn: parent
                            text: "CPU " + (WindowTracker.cpuTemp >= 0 ? (WindowTracker.cpuTemp + "°C") : "--°C")
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: WindowTracker.cpuTemp >= 80 ? "#FCA5A5" : "#7DD3FC"
                        }
                    }

                    Rectangle {
                        visible: WindowTracker.gpuTemp >= 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: gpuTxt.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: "#1E293B"
                        border.width: 1
                        border.color: "#A78BFA"
                        Text {
                            id: gpuTxt
                            anchors.centerIn: parent
                            text: "GPU " + WindowTracker.gpuTemp + "°C"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: WindowTracker.gpuTemp >= 80 ? "#FCA5A5" : "#C4B5FD"
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: ramTxt.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: "#1E293B"
                        border.width: 1
                        border.color: "#F472B6"
                        Text {
                            id: ramTxt
                            anchors.centerIn: parent
                            text: "RAM " + WindowTracker.ramUsage + "%"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#F9A8D4"
                        }
                    }

                    // --- System Tray Pill (click to open Tray Popup) ---
                    Rectangle {
                        id: trayPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: trayPillRow.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: topBarWindow.trayPopupOpen ? "#22D3EE" : (trayPillMouse.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: "#64748B"

                        Row {
                            id: trayPillRow
                            anchors.centerIn: parent
                            spacing: 4
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10
                                height: 10
                                sourceSize.width: 20
                                sourceSize.height: 20
                                smooth: true
                                source: topBarWindow.trayPopupOpen
                                    ? "qrc:/qml/icons/alt-arrow-down-dark.svg"
                                    : "qrc:/qml/icons/alt-arrow-up-light.svg"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Tray" + (TrayService.items.length > 0 ? (" " + TrayService.items.length) : "")
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: topBarWindow.trayPopupOpen ? "#1A1B2E" : "#E2E8F0"
                            }
                        }

                        MouseArea {
                            id: trayPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!topBarWindow.trayPopupOpen && (Date.now() - topBarWindow.trayPopupClosedAt) < 220)
                                    return
                                if (!topBarWindow.trayPopupOpen)
                                    TrayService.refresh()
                                topBarWindow.trayPopupOpen = !topBarWindow.trayPopupOpen
                            }
                        }
                    }

                    // --- Network / Wi-Fi Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 20
                        radius: 7
                        color: topBarWindow.wifiPopupOpen ? "#22D3EE" : (wifiPillMouse.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: "#38BDF8"
                        Image {
                            anchors.centerIn: parent
                            width: 13
                            height: 13
                            sourceSize.width: 26
                            sourceSize.height: 26
                            smooth: true
                            source: topBarWindow.wifiPopupOpen
                                ? (SystemControl.networkType === "Wi-Fi" ? "qrc:/qml/icons/wifi-dark.svg" : "qrc:/qml/icons/network-dark.svg")
                                : (SystemControl.networkType === "Wi-Fi" ? "qrc:/qml/icons/wifi-light.svg" : "qrc:/qml/icons/network-light.svg")
                        }
                        MouseArea {
                            id: wifiPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!topBarWindow.wifiPopupOpen && (Date.now() - topBarWindow.wifiPopupClosedAt) < 220)
                                    return
                                if (!topBarWindow.wifiPopupOpen) {
                                    SystemControl.refresh()
                                    SystemControl.refreshWifi()
                                }
                                topBarWindow.wifiPopupOpen = !topBarWindow.wifiPopupOpen
                            }
                        }
                    }

                    // --- Bluetooth Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 20
                        radius: 7
                        color: topBarWindow.btPopupOpen ? "#22D3EE" : (btPillMouse.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: "#818CF8"
                        Image {
                            anchors.centerIn: parent
                            width: 13
                            height: 13
                            sourceSize.width: 26
                            sourceSize.height: 26
                            smooth: true
                            opacity: SystemControl.bluetoothEnabled ? 1.0 : 0.6
                            source: topBarWindow.btPopupOpen ? "qrc:/qml/icons/bt-dark.svg" : "qrc:/qml/icons/bt-light.svg"
                        }
                        MouseArea {
                            id: btPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!topBarWindow.btPopupOpen && (Date.now() - topBarWindow.btPopupClosedAt) < 220)
                                    return
                                if (!topBarWindow.btPopupOpen)
                                    SystemControl.refreshBluetooth()
                                topBarWindow.btPopupOpen = !topBarWindow.btPopupOpen
                            }
                        }
                    }

                    // --- Volume Pill (wheel = master vol, right click = mute, left click = Quick Panel) ---
                    Rectangle {
                        id: volPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: volPillTxt.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: volPillMouse.containsMouse ? "#334155" : "#1E293B"
                        border.width: 1
                        border.color: AudioService.masterMuted ? "#F59E0B" : "#5EEAD4"

                        Text {
                            id: volPillTxt
                            anchors.centerIn: parent
                            text: AudioService.masterMuted ? "MUTE" : ("VOL " + AudioService.masterVolume + "%")
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: AudioService.masterMuted ? "#FCD34D" : "#5EEAD4"
                        }

                        MouseArea {
                            id: volPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    AudioService.toggleMasterMute()
                                } else {
                                    if (!topBarWindow.quickPanelOpen && (Date.now() - topBarWindow.quickPanelClosedAt) < 220)
                                        return
                                    if (!topBarWindow.quickPanelOpen) {
                                        AudioService.refreshSessions()
                                        AudioService.refreshOutputDevices()
                                        SystemControl.refresh()
                                    }
                                    topBarWindow.quickPanelOpen = !topBarWindow.quickPanelOpen
                                }
                            }
                            onWheel: wheel => {
                                const step = wheel.angleDelta.y > 0 ? 4 : -4
                                AudioService.setMasterVolume(AudioService.masterVolume + step)
                                wheel.accepted = true
                            }
                        }
                    }

                    Rectangle {
                        id: clockPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: clockRow.implicitWidth + 12
                        height: 20
                        radius: 8
                        color: topBarWindow.calendarOpen ? "#5EEAD4" : (clockPillMouse.containsMouse ? "#67E8F9" : "#22D3EE")
                        border.width: 1.5
                        border.color: "#1A1B2E"

                        Row {
                            id: clockRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: topBarWindow.dateText
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: "#1A1B2E"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: topBarWindow.timeText
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#1A1B2E"
                            }
                        }

                        MouseArea {
                            id: clockPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!topBarWindow.calendarOpen && (Date.now() - topBarWindow.calendarClosedAt) < 220)
                                    return
                                topBarWindow.calendarOpen = !topBarWindow.calendarOpen
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SekaiPop MediaPopup Card (click MediaPill to open)
    // =========================================================================
    PanelWindow {
        id: mediaPopupWindow
        visible: topBarWindow.mediaPopupOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        readonly property int pad: 14
        readonly property int innerW: 344
        readonly property int coverSize: 82

        property bool scrubbing: false
        property real scrubFrac: 0
        property real settleFrac: -1
        property bool showLeft: false
        property real livePos: MediaService.positionSec

        Connections {
            target: MediaService
            function onTimelineChanged() {
                if (!mediaPopupWindow.scrubbing)
                    mediaPopupWindow.livePos = MediaService.positionSec
            }
            function onMediaChanged() {
                mediaPopupWindow.settleFrac = -1
                mediaPopupWindow.livePos = MediaService.positionSec
            }
        }

        Timer {
            interval: 1000
            repeat: true
            running: mediaPopupWindow.visible && MediaService.hasSession && MediaService.isPlaying && !mediaPopupWindow.scrubbing
            onTriggered: {
                if (MediaService.durationSec > 0)
                    mediaPopupWindow.livePos = Math.min(MediaService.durationSec, mediaPopupWindow.livePos + 1.0)
                else
                    mediaPopupWindow.livePos = mediaPopupWindow.livePos + 1.0
            }
        }
        Timer {
            id: mediaSettleTimer
            interval: 1200
            onTriggered: mediaPopupWindow.settleFrac = -1
        }

        readonly property bool hasLen: MediaService.hasSession && MediaService.durationSec > 0
        readonly property real frac: scrubbing ? scrubFrac
            : (settleFrac >= 0 ? settleFrac : (hasLen ? Math.max(0, Math.min(1, livePos / MediaService.durationSec)) : 0))
        readonly property real shownSec: hasLen ? frac * MediaService.durationSec : livePos

        function fmtSec(s) {
            const tot = Math.max(0, Math.floor(s))
            const h = Math.floor(tot / 3600)
            const m = Math.floor((tot % 3600) / 60)
            const sec = tot % 60
            const pad2 = n => (n < 10 ? "0" + n : "" + n)
            return h > 0 ? (h + ":" + pad2(m) + ":" + pad2(sec)) : (m + ":" + pad2(sec))
        }

        function appDisplayName() {
            const raw = MediaService.sourceApp || ""
            const low = raw.toLowerCase()
            if (low.indexOf("firefox") !== -1 || low.indexOf("308046b0af4a39cb") !== -1) return "FIREFOX"
            if (low.indexOf("spotify") !== -1) return "SPOTIFY"
            if (low.indexOf("chrome") !== -1) return "CHROME"
            if (low.indexOf("msedge") !== -1 || low.indexOf("edge") !== -1) return "EDGE"
            if (low.indexOf("vlc") !== -1) return "VLC"
            if (raw === "") return "MEDIA"
            const base = raw.split("!").pop().replace(/\.exe$/i, "")
            return base.slice(0, 14).toUpperCase()
        }

        width: innerW + pad * 2 + cardShadow
        height: popupStack.implicitHeight + pad * 2 + cardShadow

        x: {
            const scrW = topBarWindow.screen ? topBarWindow.screen.width : 1920
            const targetX = topBarWindow.anchors.margins.left + leftContentRow.x + appBadgeRect.width + 6
            return Math.max(8, Math.min(scrW - width - 8, targetX))
        }
        y: 34

        property double openedAt: 0
        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                requestActivate()
            }
        }
        onWindowDeactivated: {
            if (topBarWindow.mediaPopupOpen) {
                topBarWindow.mediaPopupClosedAt = Date.now()
                topBarWindow.mediaPopupOpen = false
            }
        }
        Timer {
            interval: 60
            repeat: true
            running: mediaPopupWindow.visible
            onTriggered: {
                if ((Date.now() - mediaPopupWindow.openedAt) > 220 && mediaPopupWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.mediaPopupClosedAt = Date.now()
                    topBarWindow.mediaPopupOpen = false
                }
            }
        }

        // Hard offset shadow
        Rectangle {
            x: mediaPopupFrame.x + mediaPopupWindow.cardShadow
            y: mediaPopupFrame.y + mediaPopupWindow.cardShadow
            width: mediaPopupFrame.width
            height: mediaPopupFrame.height
            radius: mediaPopupFrame.radius
            color: "#1A1B2E"
        }

        // Main SekaiPopup frame
        Rectangle {
            id: mediaPopupFrame
            x: 0
            y: 0
            width: mediaPopupWindow.innerW + mediaPopupWindow.pad * 2
            height: popupStack.implicitHeight + mediaPopupWindow.pad * 2
            radius: 20
            color: "#1A1B2E"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                color: "#FFFFFF"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: parent.radius - 3
                    color: "#F1F5FF"
                }
            }

            Column {
                id: popupStack
                x: mediaPopupWindow.pad
                y: mediaPopupWindow.pad
                width: mediaPopupWindow.innerW
                spacing: 12

                // Multi-player tabs (only shown when > 1 GSMTC session exists)
                Row {
                    id: mediaTabRow
                    visible: MediaService.players && MediaService.players.length > 1
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: MediaService.players || []
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isCurrent: modelData.id === MediaService.sourceApp
                            width: tabLbl.implicitWidth + 18
                            height: 24
                            radius: 10
                            color: isCurrent ? "#22D3EE" : "#FFFFFF"
                            border.width: 1.5
                            border.color: "#1A1B2E"

                            Text {
                                id: tabLbl
                                anchors.centerIn: parent
                                text: modelData.label || "Media"
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#1A1B2E"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!isCurrent && modelData.id)
                                        MediaService.selectSession(modelData.id)
                                }
                            }
                        }
                    }
                }

                // ===== SekaiPlate: Tilted Cover Jacket + App + State Chip + Title/Artist =====
                Item {
                    id: sekaiPlateWrap
                    width: popupStack.width
                    height: 114

                    // Plate hard shadow
                    Rectangle {
                        x: 3
                        y: 3
                        width: sekaiPlate.width
                        height: sekaiPlate.height
                        radius: sekaiPlate.radius
                        color: "#1A1B2E"
                    }

                    Rectangle {
                        id: sekaiPlate
                        width: parent.width - 3
                        height: 110
                        radius: 16
                        color: "#1A1B2E"

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.radius - 2
                            color: "#FFFFFF"

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: parent.radius - 2
                                gradient: Gradient {
                                    orientation: Gradient.Vertical
                                    GradientStop { position: 0.0; color: "#5EEAD4" }
                                    GradientStop { position: 1.0; color: "#22D3EE" }
                                }
                            }
                        }

                        // Tilted Cover Art Keycap (raised when playing, pressed when paused)
                        Item {
                            id: jacketBox
                            x: 13
                            y: 13
                            width: mediaPopupWindow.coverSize
                            height: mediaPopupWindow.coverSize + 3
                            rotation: -4
                            transformOrigin: Item.Center

                            readonly property bool isPressed: jacketMouse.pressed || !MediaService.isPlaying

                            // Keycap shadow
                            Rectangle {
                                x: 0
                                y: 3
                                width: jacketBox.width
                                height: mediaPopupWindow.coverSize
                                radius: 16
                                color: "#1A1B2E"
                            }

                            Rectangle {
                                id: jacketCap
                                x: 0
                                y: jacketBox.isPressed ? 3 : 0
                                width: jacketBox.width
                                height: mediaPopupWindow.coverSize
                                radius: 16
                                color: "#1A1B2E"

                                Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: parent.radius - 2
                                    color: "#FFFFFF"

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        radius: parent.radius - 2
                                        color: "#E2E8F0"
                                        clip: true

                                        Image {
                                            anchors.centerIn: parent
                                            visible: popupCoverImg.status !== Image.Ready
                                            width: 30
                                            height: 30
                                            sourceSize.width: 60
                                            sourceSize.height: 60
                                            smooth: true
                                            opacity: 0.65
                                            source: "qrc:/qml/icons/music-note-dark.svg"
                                        }

                                        Image {
                                            id: popupCoverImg
                                            anchors.fill: parent
                                            source: MediaService.hasSession ? MediaService.artUrl : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            mipmap: true
                                            cache: false
                                        }

                                        // Hover overlay
                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#55000000"
                                            opacity: jacketMouse.containsMouse && MediaService.hasSession ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: MediaService.isPlaying ? "⏸" : "▶"
                                                font.family: "Segoe UI Symbol"
                                                font.pixelSize: 24
                                                color: "#FFFFFF"
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: jacketMouse
                                anchors.fill: parent
                                enabled: MediaService.hasSession
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: MediaService.playPause()
                            }
                        }

                        // App badge (top-right area)
                        Row {
                            x: mediaPopupWindow.coverSize + 28
                            y: 13
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7
                                height: 7
                                rotation: 45
                                color: "#FFFFFF"
                                border.width: 1.5
                                border.color: "#1A1B2E"
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: mediaPopupWindow.appDisplayName()
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.weight: Font.ExtraBold
                                font.letterSpacing: 1.2
                                color: "#1A1B2E"
                                opacity: 0.85
                            }
                        }

                        // Tilted State Chip (PLAYING / PAUSED / IDLE)
                        Rectangle {
                            id: stateChip
                            x: sekaiPlate.width - width - 11
                            y: 7
                            width: stateChipRow.implicitWidth + 18
                            height: 24
                            radius: 9
                            color: "#FFFFFF"
                            border.width: 2
                            border.color: "#1A1B2E"
                            rotation: 3
                            transformOrigin: Item.Center

                            Row {
                                id: stateChipRow
                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6
                                    height: 6
                                    rotation: 45
                                    color: MediaService.isPlaying ? "#10B981" : "#94A3B8"
                                    border.width: 1
                                    border.color: "#1A1B2E"
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: MediaService.isPlaying ? "PLAYING" : (MediaService.hasSession ? "PAUSED" : "IDLE")
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.weight: Font.ExtraBold
                                    font.letterSpacing: 0.8
                                    color: "#1A1B2E"
                                }
                            }
                        }

                        // Song Title & Artist / Album
                        Column {
                            x: mediaPopupWindow.coverSize + 28
                            y: 38
                            width: sekaiPlate.width - x - 12
                            spacing: 3

                            Text {
                                width: parent.width
                                text: MediaService.hasSession ? (MediaService.title || "Playing") : "Nothing playing"
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                lineHeight: 0.98
                                font.family: "Segoe UI"
                                font.pixelSize: 15
                                font.weight: Font.ExtraBold
                                color: "#1A1B2E"
                            }

                            Text {
                                width: parent.width
                                text: {
                                    if (!MediaService.hasSession)
                                        return "Start a song or video"
                                    const a = MediaService.artist || ""
                                    const alb = MediaService.album || ""
                                    if (a !== "" && alb !== "") return a + "  ·  " + alb
                                    return a !== "" ? a : (alb !== "" ? alb : mediaPopupWindow.appDisplayName())
                                }
                                elide: Text.ElideRight
                                font.family: "Segoe UI"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: "#1E293B"
                                opacity: 0.85
                            }
                        }
                    }
                }

                // ===== Seek Lane: [elapsed] ====<>---- [length] =====
                Item {
                    id: seekLane
                    width: popupStack.width
                    height: 30
                    opacity: mediaPopupWindow.hasLen ? 1.0 : 0.45

                    // Elapsed chip (tilted -3)
                    Rectangle {
                        x: 0
                        y: mediaPopupWindow.scrubbing ? 2 : 0
                        width: 58
                        height: 28
                        radius: 10
                        color: "#FFFFFF"
                        border.width: 2
                        border.color: "#1A1B2E"
                        rotation: -3

                        Text {
                            anchors.centerIn: parent
                            text: mediaPopupWindow.hasLen ? mediaPopupWindow.fmtSec(mediaPopupWindow.shownSec) : "--:--"
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            color: "#1A1B2E"
                        }
                    }

                    // Groove + Trail + Diamond Playhead
                    Item {
                        id: seekTrack
                        x: 66
                        width: seekLane.width - 132
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter

                        readonly property real headSize: 13
                        readonly property real headX: Math.min(seekTrack.width - headSize, Math.max(0, seekTrack.width * mediaPopupWindow.frac - headSize / 2))

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 11
                            radius: 5.5
                            color: "#E2E8F0"
                            border.width: 2
                            border.color: "#1A1B2E"
                        }

                        Rectangle {
                            x: 2
                            anchors.verticalCenter: parent.verticalCenter
                            height: 7
                            radius: 3.5
                            width: Math.max(0, seekTrack.headX + seekTrack.headSize / 2 - 2)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#5EEAD4" }
                                GradientStop { position: 1.0; color: "#22D3EE" }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: seekTrack.headX
                            width: seekTrack.headSize
                            height: seekTrack.headSize
                            radius: 3
                            rotation: 45
                            color: "#22D3EE"
                            border.width: 2
                            border.color: "#1A1B2E"
                            scale: mediaPopupWindow.scrubbing ? 1.3 : (seekMouse.containsMouse ? 1.15 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                        }

                        MouseArea {
                            id: seekMouse
                            anchors.fill: parent
                            enabled: mediaPopupWindow.hasLen && MediaService.canSeek
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                            function fracAt(mx) {
                                return Math.max(0, Math.min(1, mx / Math.max(1, width)))
                            }
                            onPressed: mouse => {
                                mediaPopupWindow.scrubFrac = fracAt(mouse.x)
                                mediaPopupWindow.scrubbing = true
                            }
                            onPositionChanged: mouse => {
                                if (pressed)
                                    mediaPopupWindow.scrubFrac = fracAt(mouse.x)
                            }
                            onReleased: mouse => {
                                if (mediaPopupWindow.scrubbing) {
                                    const f = fracAt(mouse.x)
                                    mediaPopupWindow.settleFrac = f
                                    const targetSec = f * MediaService.durationSec
                                    mediaPopupWindow.livePos = targetSec
                                    MediaService.seek(targetSec)
                                    mediaSettleTimer.restart()
                                }
                                mediaPopupWindow.scrubbing = false
                            }
                            onCanceled: mediaPopupWindow.scrubbing = false
                        }
                    }

                    // Total / Remaining chip (tilted +3, click to toggle)
                    Rectangle {
                        x: seekLane.width - width
                        y: totalChipMouse.pressed && mediaPopupWindow.hasLen ? 2 : 0
                        width: 58
                        height: 28
                        radius: 10
                        color: totalChipMouse.containsMouse && mediaPopupWindow.hasLen ? "#E0F2FE" : "#FFFFFF"
                        border.width: 2
                        border.color: "#1A1B2E"
                        rotation: 3

                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (!mediaPopupWindow.hasLen) return "--:--"
                                if (mediaPopupWindow.showLeft) {
                                    const rem = Math.max(0, MediaService.durationSec - mediaPopupWindow.shownSec)
                                    return "-" + mediaPopupWindow.fmtSec(rem)
                                }
                                return mediaPopupWindow.fmtSec(MediaService.durationSec)
                            }
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            color: "#1A1B2E"
                        }

                        MouseArea {
                            id: totalChipMouse
                            anchors.fill: parent
                            enabled: mediaPopupWindow.hasLen
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: mediaPopupWindow.showLeft = !mediaPopupWindow.showLeft
                        }
                    }
                }

                // ===== Transport Keys: [ prev ] [ > Play / || Pause ] [ next ] [ close ] =====
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    // Prev key
                    Item {
                        width: 56
                        height: 40
                        opacity: MediaService.hasSession && MediaService.canPrev ? 1.0 : 0.45

                        Rectangle { x: 2; y: 2; width: 54; height: 38; radius: 12; color: "#1A1B2E" }
                        Rectangle {
                            x: prevKeyArea.pressed ? 2 : 0
                            y: prevKeyArea.pressed ? 2 : 0
                            width: 54
                            height: 38
                            radius: 12
                            color: prevKeyArea.containsMouse ? "#E0F2FE" : "#FFFFFF"
                            border.width: 2
                            border.color: "#1A1B2E"
                            Image {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                smooth: true
                                source: "qrc:/qml/icons/skip-previous-dark.svg"
                            }
                        }
                        MouseArea {
                            id: prevKeyArea
                            anchors.fill: parent
                            enabled: MediaService.hasSession && MediaService.canPrev
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: MediaService.previous()
                        }
                    }

                    // Primary Play/Pause key
                    Item {
                        width: 112
                        height: 40
                        opacity: MediaService.hasSession ? 1.0 : 0.55

                        Rectangle { x: 2; y: 2; width: 110; height: 38; radius: 12; color: "#1A1B2E" }
                        Rectangle {
                            x: playKeyArea.pressed ? 2 : 0
                            y: playKeyArea.pressed ? 2 : 0
                            width: 110
                            height: 38
                            radius: 12
                            border.width: 2
                            border.color: "#1A1B2E"
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: "#5EEAD4" }
                                GradientStop { position: 1.0; color: "#22D3EE" }
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14
                                    height: 14
                                    sourceSize.width: 28
                                    sourceSize.height: 28
                                    smooth: true
                                    source: MediaService.isPlaying ? "qrc:/qml/icons/pause-dark.svg" : "qrc:/qml/icons/play-dark.svg"
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: MediaService.isPlaying ? "Pause" : "Play"
                                    font.family: "Segoe UI"
                                    font.pixelSize: 13
                                    font.weight: Font.ExtraBold
                                    color: "#1A1B2E"
                                }
                            }
                        }
                        MouseArea {
                            id: playKeyArea
                            anchors.fill: parent
                            enabled: MediaService.hasSession
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: MediaService.playPause()
                        }
                    }

                    // Next key
                    Item {
                        width: 56
                        height: 40
                        opacity: MediaService.hasSession && MediaService.canNext ? 1.0 : 0.45

                        Rectangle { x: 2; y: 2; width: 54; height: 38; radius: 12; color: "#1A1B2E" }
                        Rectangle {
                            x: nextKeyArea.pressed ? 2 : 0
                            y: nextKeyArea.pressed ? 2 : 0
                            width: 54
                            height: 38
                            radius: 12
                            color: nextKeyArea.containsMouse ? "#E0F2FE" : "#FFFFFF"
                            border.width: 2
                            border.color: "#1A1B2E"
                            Image {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                smooth: true
                                source: "qrc:/qml/icons/skip-next-dark.svg"
                            }
                        }
                        MouseArea {
                            id: nextKeyArea
                            anchors.fill: parent
                            enabled: MediaService.hasSession && MediaService.canNext
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: MediaService.next()
                        }
                    }

                    // Close popup key
                    Item {
                        width: 40
                        height: 40

                        Rectangle { x: 2; y: 2; width: 38; height: 38; radius: 12; color: "#1A1B2E" }
                        Rectangle {
                            x: closeKeyArea.pressed ? 2 : 0
                            y: closeKeyArea.pressed ? 2 : 0
                            width: 38
                            height: 38
                            radius: 12
                            color: closeKeyArea.containsMouse ? "#FEE2E2" : "#FFFFFF"
                            border.width: 2
                            border.color: "#1A1B2E"
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.family: "Segoe UI"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                color: "#1A1B2E"
                            }
                        }
                        MouseArea {
                            id: closeKeyArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: topBarWindow.mediaPopupOpen = false
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // System Tray Popup (TopBar Tray ▲)
    // =========================================================================
    PanelWindow {
        id: trayPopupWindow
        visible: topBarWindow.trayPopupOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        readonly property int cardW: 248
        property double openedAt: 0

        width: cardW + cardShadow
        height: Math.max(92, trayCol.implicitHeight + 24) + cardShadow
        x: {
            const barRight = topBarWindow.anchors.margins.left + topBarWindow.width
            const target = topBarWindow.anchors.margins.left + rightContentRow.x + trayPill.x + Math.round((trayPill.width - cardW) * 0.5)
            return Math.max(8, Math.min(barRight - width, target))
        }
        y: 34

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                TrayService.refresh()
                requestActivate()
            }
        }
        Timer {
            interval: 60
            repeat: true
            running: trayPopupWindow.visible
            onTriggered: {
                if ((Date.now() - trayPopupWindow.openedAt) > 220 && trayPopupWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.trayPopupClosedAt = Date.now()
                    topBarWindow.trayPopupOpen = false
                }
            }
        }

        Rectangle {
            x: trayPopupFrame.x + trayPopupWindow.cardShadow
            y: trayPopupFrame.y + trayPopupWindow.cardShadow
            width: trayPopupFrame.width
            height: trayPopupFrame.height
            radius: trayPopupFrame.radius
            color: "#1A1B2E"
        }

        Rectangle {
            id: trayPopupFrame
            x: 0
            y: 0
            width: trayPopupWindow.cardW
            height: Math.max(92, trayCol.implicitHeight + 24)
            radius: 16
            color: "#1A1B2E"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                color: "#FFFFFF"
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: parent.radius - 2
                    color: "#F1F5FF"
                }
            }

            Column {
                id: trayCol
                x: 12
                y: 12
                width: trayPopupFrame.width - 24
                spacing: 6

                Text {
                    text: "SYSTEM TRAY (" + TrayService.items.length + ")"
                    font.family: "Segoe UI"
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1
                    color: "#475569"
                }

                Text {
                    visible: TrayService.items.length === 0
                    width: parent.width
                    text: "No Windows tray icons found.\n(Explorer taskbar tray inactive)"
                    wrapMode: Text.Wrap
                    font.family: "Segoe UI"
                    font.pixelSize: 11
                    color: "#64748B"
                }

                Flickable {
                    width: parent.width
                    height: Math.min(360, trayListCol.implicitHeight)
                    contentWidth: width
                    contentHeight: trayListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: trayListCol
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: TrayService.items
                            delegate: Rectangle {
                                required property var modelData
                                width: trayListCol.width
                                height: 30
                                radius: 9
                                color: trayRowArea.containsMouse ? "#E0F2FE" : "#FFFFFF"
                                border.width: 1.5
                                border.color: "#1A1B2E"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16
                                        height: 16
                                        source: modelData.iconUrl || ""
                                        smooth: true
                                        mipmap: true
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 28
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                        text: (modelData.tip || "Tray App").replace(/\r?\n+/g, " · ")
                                        font.family: "Segoe UI"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: "#1A1B2E"
                                    }
                                }

                                MouseArea {
                                    id: trayRowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        TrayService.activateItem(modelData.index, mouse.button === Qt.RightButton)
                                        topBarWindow.trayPopupOpen = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Phase 4: Quick Panel & Sekai 2.5D Phone (Clock Pill or Ctrl+Alt+A)
    // =========================================================================
    PanelWindow {
        id: quickPanelWindow
        visible: topBarWindow.quickPanelOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 5
        readonly property int pad: 14
        readonly property int innerW: 332
        property double openedAt: 0

        width: innerW + pad * 2 + (topBarWindow.phoneMode ? 16 : 0) + cardShadow
        height: qpStack.implicitHeight + pad * 2 + (topBarWindow.phoneMode ? 36 : 0) + cardShadow

        x: {
            const barRight = topBarWindow.anchors.margins.left + topBarWindow.width
            return Math.max(8, barRight - width)
        }
        y: 34

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                AudioService.refreshSessions()
                SystemControl.refresh()
                requestActivate()
            }
        }

        Timer {
            interval: 600
            repeat: true
            running: quickPanelWindow.visible
            onTriggered: AudioService.refreshSessions()
        }

        Timer {
            interval: 60
            repeat: true
            running: quickPanelWindow.visible
            onTriggered: {
                if ((Date.now() - quickPanelWindow.openedAt) > 220 && quickPanelWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.quickPanelClosedAt = Date.now()
                    topBarWindow.quickPanelOpen = false
                }
            }
        }

        // Hard offset shadow
        Rectangle {
            x: qpFrame.x + quickPanelWindow.cardShadow
            y: qpFrame.y + quickPanelWindow.cardShadow
            width: qpFrame.width
            height: qpFrame.height
            radius: qpFrame.radius
            color: "#1A1B2E"
        }

        // Main Frame (Classic Flat Card OR Sekai 2.5D Phone Chassis)
        Rectangle {
            id: qpFrame
            x: 0
            y: 0
            width: quickPanelWindow.width - quickPanelWindow.cardShadow
            height: quickPanelWindow.height - quickPanelWindow.cardShadow
            radius: topBarWindow.phoneMode ? 30 : 20
            color: "#1A1B2E"

            Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                anchors.margins: topBarWindow.phoneMode ? 5 : 2
                radius: parent.radius - (topBarWindow.phoneMode ? 5 : 2)
                color: topBarWindow.phoneMode ? "#334155" : "#FFFFFF"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: parent.radius - 3
                    color: "#F1F5FF"
                }
            }

            // Phone Notch when Sekai 2.5D Phone mode is active
            Rectangle {
                visible: topBarWindow.phoneMode
                anchors.top: parent.top
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96
                height: 16
                radius: 8
                color: "#1A1B2E"
                z: 5
                Rectangle {
                    anchors.centerIn: parent
                    width: 28
                    height: 4
                    radius: 2
                    color: "#475569"
                }
            }

            Column {
                id: qpStack
                x: quickPanelWindow.pad + (topBarWindow.phoneMode ? 8 : 0)
                y: quickPanelWindow.pad + (topBarWindow.phoneMode ? 24 : 0)
                width: quickPanelWindow.innerW
                spacing: 10

                // Header: Control Center + Phone Chassis Switch + Close
                Item {
                    width: parent.width
                    height: 28

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            rotation: 45
                            color: "#22D3EE"
                            border.width: 1.5
                            border.color: "#1A1B2E"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: topBarWindow.phoneMode ? "SEKAI PHONE" : "QUICK PANEL"
                            font.family: "Segoe UI"
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1
                            color: "#1A1B2E"
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            width: phoneModeLbl.implicitWidth + 14
                            height: 24
                            radius: 9
                            color: topBarWindow.phoneMode ? "#5EEAD4" : "#FFFFFF"
                            border.width: 1.5
                            border.color: "#1A1B2E"
                            Text {
                                id: phoneModeLbl
                                anchors.centerIn: parent
                                text: topBarWindow.phoneMode ? "2.5D Phone" : "Flat Card"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#1A1B2E"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: topBarWindow.phoneMode = !topBarWindow.phoneMode
                            }
                        }

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 9
                            color: qpCloseMouse.containsMouse ? "#FEE2E2" : "#FFFFFF"
                            border.width: 1.5
                            border.color: "#1A1B2E"
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#1A1B2E"
                            }
                            MouseArea {
                                id: qpCloseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: topBarWindow.quickPanelOpen = false
                            }
                        }
                    }
                }

                // ===== Master Volume Slider + Output Switcher =====
                Rectangle {
                    width: parent.width
                    height: masterVolCol.implicitHeight + 16
                    radius: 14
                    color: "#FFFFFF"
                    border.width: 2
                    border.color: "#1A1B2E"

                    Column {
                        id: masterVolCol
                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 16
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: AudioService.masterMuted ? "MASTER VOLUME (MUTED)" : "MASTER VOLUME"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.ExtraBold
                                color: "#1A1B2E"
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: AudioService.masterVolume + "%"
                                font.family: "Consolas"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#0891B2"
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Rectangle {
                                width: 24
                                height: 18
                                radius: 6
                                color: AudioService.masterMuted ? "#FDE68A" : "#E0F2FE"
                                border.width: 1.5
                                border.color: "#1A1B2E"
                                Image {
                                    anchors.centerIn: parent
                                    width: 12
                                    height: 12
                                    sourceSize.width: 24
                                    sourceSize.height: 24
                                    smooth: true
                                    source: AudioService.masterMuted ? "qrc:/qml/icons/volume-cross-dark.svg" : "qrc:/qml/icons/volume-loud-dark.svg"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: AudioService.toggleMasterMute()
                                }
                            }
                            Item {
                                width: parent.width - 32
                                height: 18
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 10
                                    radius: 5
                                    color: "#E2E8F0"
                                    border.width: 1.5
                                    border.color: "#1A1B2E"
                                    Rectangle {
                                        x: 1
                                        y: 1
                                        height: 8
                                        radius: 4
                                        width: Math.max(0, (parent.width - 2) * (AudioService.masterVolume / 100.0))
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "#5EEAD4" }
                                            GradientStop { position: 1.0; color: "#22D3EE" }
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    function setFromX(mx) {
                                        const pct = Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100)
                                        AudioService.setMasterVolume(pct)
                                    }
                                    onPressed: mouse => setFromX(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) setFromX(mouse.x) }
                                }
                            }
                        }

                        Flow {
                            visible: AudioService.outputDevices.length > 0
                            width: parent.width
                            spacing: 5
                            Repeater {
                                model: AudioService.outputDevices
                                delegate: Rectangle {
                                    required property var modelData
                                    width: Math.min(masterVolCol.width, devRow.implicitWidth + 14)
                                    height: 22
                                    radius: 8
                                    color: modelData.isDefault ? "#5EEAD4" : (devMouse.containsMouse ? "#E2E8F0" : "#F8FAFC")
                                    border.width: 1.5
                                    border.color: "#1A1B2E"

                                    Row {
                                        id: devRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Image {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 11
                                            height: 11
                                            sourceSize.width: 22
                                            sourceSize.height: 22
                                            smooth: true
                                            source: "qrc:/qml/icons/headphones-round-dark.svg"
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(implicitWidth, masterVolCol.width - 30)
                                            elide: Text.ElideRight
                                            text: (modelData.isDefault ? "✓ " : "") + (modelData.name || "Output")
                                            font.family: "Segoe UI"
                                            font.pixelSize: 10
                                            font.weight: modelData.isDefault ? Font.Bold : Font.Medium
                                            color: "#1A1B2E"
                                        }
                                    }

                                    MouseArea {
                                        id: devMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.callLater(function() { AudioService.setDefaultOutputDevice(modelData.id) })
                                    }
                                }
                            }
                        }
                    }
                }

                // ===== Multi-Monitor DDC/CI Brightness + Screen Mirroring + Network IP =====
                Repeater {
                    model: SystemControl.monitors
                    delegate: Rectangle {
                        required property var modelData
                        width: qpStack.width
                        height: 50
                        radius: 14
                        color: "#FFFFFF"
                        border.width: 2
                        border.color: "#1A1B2E"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Item {
                                width: parent.width
                                height: 16
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "DISPLAY · " + (modelData.name || "Monitor")
                                    width: parent.width - 42
                                    elide: Text.ElideRight
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.weight: Font.ExtraBold
                                    color: "#1A1B2E"
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.brightness + "%"
                                    font.family: "Consolas"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#D97706"
                                }
                            }

                            Item {
                                width: parent.width
                                height: 16
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 10
                                    radius: 5
                                    color: "#E2E8F0"
                                    border.width: 1.5
                                    border.color: "#1A1B2E"
                                    Rectangle {
                                        x: 1
                                        y: 1
                                        height: 8
                                        radius: 4
                                        width: Math.max(0, (parent.width - 2) * (modelData.brightness / 100.0))
                                        color: "#FBBF24"
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    function setBr(mx) {
                                        const pct = Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100)
                                        SystemControl.setMonitorBrightness(modelData.index, pct)
                                    }
                                    onPressed: mouse => setBr(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) setBr(mouse.x) }
                                }
                            }
                        }
                    }
                }

                // ===== Screen Mirroring + Dark Mode =====
                Rectangle {
                    width: parent.width
                    height: netMirCol.implicitHeight + 14
                    radius: 14
                    color: "#FFFFFF"
                    border.width: 2
                    border.color: "#1A1B2E"

                    Column {
                        id: netMirCol
                        x: 8
                        y: 7
                        width: parent.width - 16
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 20
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "SCREEN MIRROR"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.ExtraBold
                                color: "#1A1B2E"
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: dmTxt.implicitWidth + 14
                                height: 20
                                radius: 8
                                color: SystemControl.darkMode ? "#5EEAD4" : "#F1F5F9"
                                border.width: 1.5
                                border.color: "#1A1B2E"
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12
                                        height: 12
                                        sourceSize.width: 24
                                        sourceSize.height: 24
                                        smooth: true
                                        source: SystemControl.darkMode ? "qrc:/qml/icons/moon-dark.svg" : "qrc:/qml/icons/sun-dark.svg"
                                    }
                                    Text {
                                        id: dmTxt
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: SystemControl.darkMode ? "Dark Mode" : "Light Mode"
                                        font.family: "Segoe UI"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#1A1B2E"
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SystemControl.toggleDarkMode()
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 5
                            Repeater {
                                model: [
                                    { label: "Main", mode: "internal" },
                                    { label: "Dup", mode: "clone" },
                                    { label: "Extend", mode: "extend" },
                                    { label: "2nd Only", mode: "external" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: Math.floor((parent.width - 15) / 4)
                                    height: 22
                                    radius: 8
                                    color: mirMouse.containsMouse ? "#5EEAD4" : "#F1F5F9"
                                    border.width: 1.5
                                    border.color: "#1A1B2E"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: "Segoe UI"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: "#1A1B2E"
                                    }
                                    MouseArea {
                                        id: mirMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: SystemControl.setDisplayMode(modelData.mode)
                                    }
                                }
                            }
                        }
                    }
                }

                // ===== Per-App Volume Mixer (IAudioSessionManager2) =====
                Rectangle {
                    width: parent.width
                    height: Math.max(54, mixerCol.implicitHeight + 16)
                    radius: 14
                    color: "#FFFFFF"
                    border.width: 2
                    border.color: "#1A1B2E"

                    Column {
                        id: mixerCol
                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 6

                        Text {
                            text: "APP VOLUME MIXER (" + AudioService.sessions.length + ")"
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.ExtraBold
                            color: "#475569"
                        }

                        Text {
                            visible: AudioService.sessions.length === 0
                            text: "No active audio apps"
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            color: "#94A3B8"
                        }

                        Repeater {
                            model: AudioService.sessions
                            delegate: Row {
                                required property var modelData
                                width: mixerCol.width
                                height: 24
                                spacing: 6

                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16
                                    source: modelData.iconUrl || ""
                                    smooth: true
                                    mipmap: true
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 82
                                    elide: Text.ElideRight
                                    text: modelData.name || "App"
                                    font.family: "Segoe UI"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: "#1A1B2E"
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20
                                    height: 18
                                    radius: 5
                                    color: modelData.muted ? "#FDE68A" : "#F1F5F9"
                                    border.width: 1
                                    border.color: "#1A1B2E"
                                    Image {
                                        anchors.centerIn: parent
                                        width: 11
                                        height: 11
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        smooth: true
                                        source: modelData.muted ? "qrc:/qml/icons/volume-cross-dark.svg" : "qrc:/qml/icons/volume-loud-dark.svg"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AudioService.toggleAppMute(modelData.id)
                                    }
                                }

                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(40, parent.width - 174)
                                    height: 18
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: 8
                                        radius: 4
                                        color: "#E2E8F0"
                                        border.width: 1.5
                                        border.color: "#1A1B2E"
                                        Rectangle {
                                            x: 1
                                            y: 1
                                            height: 6
                                            radius: 3
                                            width: Math.max(0, (parent.width - 2) * (modelData.volume / 100.0))
                                            color: modelData.muted ? "#94A3B8" : "#22D3EE"
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        function setAppV(mx) {
                                            const pct = Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100)
                                            AudioService.setAppVolume(modelData.id, pct)
                                        }
                                        onPressed: mouse => setAppV(mouse.x)
                                        onPositionChanged: mouse => { if (pressed) setAppV(mouse.x) }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.volume + "%"
                                    font.family: "Consolas"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#334155"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SekaiPop Calendar Popup (click Date/Clock pill on TopBar)
    // =========================================================================
    PanelWindow {
        id: calendarPopupWindow
        visible: topBarWindow.calendarOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        property double openedAt: 0
        property int viewYear: (new Date()).getFullYear()
        property int viewMonth: (new Date()).getMonth() // 0..11

        readonly property var monthNames: [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        readonly property var dayShortNames: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        readonly property var dayFullNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

        function isoWeekNumber(d) {
            const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
            const dayNum = tmp.getUTCDay() || 7
            tmp.setUTCDate(tmp.getUTCDate() + 4 - dayNum)
            const yearStart = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1))
            return Math.ceil((((tmp - yearStart) / 86400000) + 1) / 7)
        }

        function currentWeekRow(year, month) {
            const now = new Date()
            if (now.getFullYear() !== year || now.getMonth() !== month)
                return -1
            const firstDow = (new Date(year, month, 1).getDay() + 6) % 7
            return Math.floor((firstDow + now.getDate() - 1) / 7)
        }

        function buildCells(year, month) {
            const first = new Date(year, month, 1)
            const dow = (first.getDay() + 6) % 7
            const daysInMonth = new Date(year, month + 1, 0).getDate()
            const prevDays = new Date(year, month, 0).getDate()
            const now = new Date()
            const todayY = now.getFullYear(), todayM = now.getMonth(), todayD = now.getDate()
            const out = []
            for (let i = 0; i < 42; ++i) {
                let d, m = month, y = year, inMonth = true
                if (i < dow) {
                    d = prevDays - dow + i + 1
                    m = month - 1
                    if (m < 0) { m = 11; y -= 1 }
                    inMonth = false
                } else if (i >= dow + daysInMonth) {
                    d = i - dow - daysInMonth + 1
                    m = month + 1
                    if (m > 11) { m = 0; y += 1 }
                    inMonth = false
                } else {
                    d = i - dow + 1
                }
                const isToday = (y === todayY && m === todayM && d === todayD)
                const isWeekend = (i % 7 >= 5)
                out.push({ day: d, inMonth: inMonth, isToday: isToday, isWeekend: isWeekend })
            }
            return out
        }

        width: 288 + cardShadow
        height: calCol.implicitHeight + 24 + cardShadow
        x: Math.max(8, (topBarWindow.anchors.margins.left + topBarWindow.width) - width - 6)
        y: 34

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                const now = new Date()
                viewYear = now.getFullYear()
                viewMonth = now.getMonth()
                requestActivate()
            }
        }

        Timer {
            interval: 60
            repeat: true
            running: calendarPopupWindow.visible
            onTriggered: {
                if ((Date.now() - calendarPopupWindow.openedAt) > 220 && calendarPopupWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.calendarClosedAt = Date.now()
                    topBarWindow.calendarOpen = false
                }
            }
        }

        // Hard offset shadow
        Rectangle {
            x: calendarPopupWindow.cardShadow
            y: calendarPopupWindow.cardShadow
            width: calendarPopupWindow.width - calendarPopupWindow.cardShadow
            height: calendarPopupWindow.height - calendarPopupWindow.cardShadow
            radius: 18
            color: "#0B0F19"
        }

        // Dark Navy SekaiPop Calendar Card
        Rectangle {
            x: 0
            y: 0
            width: calendarPopupWindow.width - calendarPopupWindow.cardShadow
            height: calendarPopupWindow.height - calendarPopupWindow.cardShadow
            radius: 18
            color: "#1B1E2E"
            border.width: 2.5
            border.color: "#E2E8F0"

            Column {
                id: calCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                // ===== Top Cyan Gradient Banner =====
                Rectangle {
                    width: parent.width
                    height: 76
                    radius: 14
                    border.width: 2
                    border.color: "#0F172A"
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#22D3EE" }
                        GradientStop { position: 1.0; color: "#5EEAD4" }
                    }

                    // Tilted Day Badge (Click to return to Today)
                    Rectangle {
                        id: calDayBadge
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        height: 54
                        radius: 12
                        rotation: -4
                        color: "#333951"
                        border.width: 2
                        border.color: "#0F172A"

                        Column {
                            anchors.centerIn: parent
                            spacing: -2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: calendarPopupWindow.dayShortNames[(new Date()).getDay()]
                                font.family: "Segoe UI"
                                font.pixelSize: 9
                                font.weight: Font.ExtraBold
                                color: "#CBD5E1"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String((new Date()).getDate())
                                font.family: "Segoe UI"
                                font.pixelSize: 22
                                font.weight: Font.Black
                                color: "#5EEAD4"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const now = new Date()
                                calendarPopupWindow.viewYear = now.getFullYear()
                                calendarPopupWindow.viewMonth = now.getMonth()
                            }
                        }
                    }

                    Column {
                        anchors.left: calDayBadge.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: calendarPopupWindow.monthNames[calendarPopupWindow.viewMonth]
                                font.family: "Segoe UI"
                                font.pixelSize: 16
                                font.weight: Font.Black
                                color: "#0F172A"
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: calYearTxt.implicitWidth + 12
                                height: 18
                                radius: 9
                                color: "#272B40"
                                border.width: 1.5
                                border.color: "#0F172A"
                                Text {
                                    id: calYearTxt
                                    anchors.centerIn: parent
                                    text: String(calendarPopupWindow.viewYear)
                                    font.family: "Consolas"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#E2E8F0"
                                }
                            }
                        }

                        Text {
                            readonly property var nowDate: new Date()
                            text: calendarPopupWindow.dayFullNames[nowDate.getDay()] + " · Week " + calendarPopupWindow.isoWeekNumber(nowDate)
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#0F172A"
                        }

                        Text {
                            readonly property var nowDate: new Date()
                            readonly property int daysLeft: new Date(nowDate.getFullYear(), nowDate.getMonth() + 1, 0).getDate() - nowDate.getDate()
                            text: daysLeft + " days left in " + calendarPopupWindow.monthNames[nowDate.getMonth()]
                            font.family: "Segoe UI"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: "#1E293B"
                            opacity: 0.85
                        }
                    }
                }

                // ===== Weekday Header Pill =====
                Rectangle {
                    width: parent.width
                    height: 24
                    radius: 8
                    color: "#25293E"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 2
                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                            delegate: Item {
                                required property string modelData
                                required property int index
                                readonly property bool isTodayDow: {
                                    const now = new Date()
                                    const dow = (now.getDay() + 6) % 7
                                    return calendarPopupWindow.viewYear === now.getFullYear()
                                        && calendarPopupWindow.viewMonth === now.getMonth()
                                        && dow === index
                                }
                                width: Math.floor((parent.width - 12) / 7)
                                height: 24
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 16
                                    radius: 6
                                    visible: isTodayDow
                                    color: "#22D3EE"
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.weight: Font.ExtraBold
                                    color: isTodayDow ? "#0F172A" : (index >= 5 ? "#FB7185" : "#94A3B8")
                                }
                            }
                        }
                    }
                }

                // ===== 6x7 Calendar Grid with Current-Week Row & Weekend Tint =====
                Item {
                    width: parent.width
                    height: 178

                    readonly property int cellW: Math.floor((width - 12 - 12) / 7)
                    readonly property int weekRow: calendarPopupWindow.currentWeekRow(calendarPopupWindow.viewYear, calendarPopupWindow.viewMonth)

                    // Weekend vertical column tint (Sa + Su)
                    Rectangle {
                        x: 6 + (parent.cellW + 2) * 5 - 2
                        y: 0
                        width: parent.cellW * 2 + 6
                        height: parent.height
                        radius: 10
                        color: "#2A2238"
                        opacity: 0.7
                    }

                    // Current week row highlight pill
                    Rectangle {
                        visible: parent.weekRow >= 0
                        x: 2
                        y: parent.weekRow * 29 + 1
                        width: parent.width - 4
                        height: 27
                        radius: 10
                        color: "#223A4A"
                        opacity: 0.85
                    }

                    Grid {
                        x: 6
                        y: 2
                        columns: 7
                        columnSpacing: 2
                        rowSpacing: 3
                        width: parent.width - 12
                        Repeater {
                            model: calendarPopupWindow.buildCells(calendarPopupWindow.viewYear, calendarPopupWindow.viewMonth)
                            delegate: Item {
                                required property var modelData
                                width: Math.floor((parent.width - 12) / 7)
                                height: 26

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    radius: 8
                                    visible: modelData.isToday
                                    color: "#22D3EE"
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.day
                                    font.family: "Segoe UI"
                                    font.pixelSize: 11
                                    font.weight: modelData.isToday ? Font.Black : Font.Bold
                                    color: modelData.isToday
                                        ? "#0F172A"
                                        : (!modelData.inMonth ? "#475569" : (modelData.isWeekend ? "#FB7185" : "#E2E8F0"))
                                }
                            }
                        }
                    }
                }

                // ===== Footer: <  [12 Month Diamonds]  > =====
                Item {
                    width: parent.width
                    height: 26

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 8
                        color: calPrevMouse.containsMouse ? "#334155" : "#25293E"
                        border.width: 1.5
                        border.color: "#475569"
                        Text {
                            anchors.centerIn: parent
                            text: "<"
                            font.family: "Consolas"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#E2E8F0"
                        }
                        MouseArea {
                            id: calPrevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (calendarPopupWindow.viewMonth === 0) {
                                    calendarPopupWindow.viewMonth = 11
                                    calendarPopupWindow.viewYear -= 1
                                } else {
                                    calendarPopupWindow.viewMonth -= 1
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: monthDotsRow.implicitWidth + 16
                        height: 22
                        radius: 11
                        color: "#25293E"
                        border.width: 1
                        border.color: "#334155"

                        Row {
                            id: monthDotsRow
                            anchors.centerIn: parent
                            spacing: 4
                            Repeater {
                                model: 12
                                delegate: Text {
                                    required property int index
                                    text: "◆"
                                    font.family: "Segoe UI Symbol"
                                    font.pixelSize: index === calendarPopupWindow.viewMonth ? 11 : 8
                                    color: index === calendarPopupWindow.viewMonth ? "#22D3EE" : "#475569"
                                    anchors.verticalCenter: parent.verticalCenter
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: calendarPopupWindow.viewMonth = index
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 8
                        color: calNextMouse.containsMouse ? "#334155" : "#25293E"
                        border.width: 1.5
                        border.color: "#475569"
                        Text {
                            anchors.centerIn: parent
                            text: ">"
                            font.family: "Consolas"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#E2E8F0"
                        }
                        MouseArea {
                            id: calNextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (calendarPopupWindow.viewMonth === 11) {
                                    calendarPopupWindow.viewMonth = 0
                                    calendarPopupWindow.viewYear += 1
                                } else {
                                    calendarPopupWindow.viewMonth += 1
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SekaiPop Network / Wi-Fi Popup
    // =========================================================================
    PanelWindow {
        id: wifiPopupWindow
        visible: topBarWindow.wifiPopupOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        property double openedAt: 0

        width: 268 + cardShadow
        height: wifiCol.implicitHeight + 24 + cardShadow
        x: Math.max(8, (topBarWindow.anchors.margins.left + topBarWindow.width) - width - 6)
        y: 34

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                SystemControl.refresh()
                SystemControl.refreshWifi()
                requestActivate()
            }
        }

        Timer {
            interval: 60
            repeat: true
            running: wifiPopupWindow.visible
            onTriggered: {
                if ((Date.now() - wifiPopupWindow.openedAt) > 220 && wifiPopupWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.wifiPopupClosedAt = Date.now()
                    topBarWindow.wifiPopupOpen = false
                }
            }
        }

        Rectangle {
            x: wifiPopupWindow.cardShadow
            y: wifiPopupWindow.cardShadow
            width: wifiPopupWindow.width - wifiPopupWindow.cardShadow
            height: wifiPopupWindow.height - wifiPopupWindow.cardShadow
            radius: 16
            color: "#1A1B2E"
        }

        Rectangle {
            x: 0
            y: 0
            width: wifiPopupWindow.width - wifiPopupWindow.cardShadow
            height: wifiPopupWindow.height - wifiPopupWindow.cardShadow
            radius: 16
            color: "#F8FAFC"
            border.width: 2
            border.color: "#1A1B2E"

            Column {
                id: wifiCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 12
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        spacing: 2
                        Row {
                            spacing: 6
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                sourceSize.width: 28
                                sourceSize.height: 28
                                smooth: true
                                source: SystemControl.networkType === "Wi-Fi" ? "qrc:/qml/icons/wifi-dark.svg" : "qrc:/qml/icons/network-dark.svg"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: SystemControl.networkType
                                font.family: "Segoe UI"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#1A1B2E"
                            }
                        }
                        Text {
                            text: SystemControl.localIp ? SystemControl.localIp : "No IPv4 address"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            color: "#64748B"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 12
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"

                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: SystemControl.wifiSupported ? "Wi-Fi" : "Wi-Fi (No adapter)"
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: "#1A1B2E"
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 22
                        radius: 11
                        color: SystemControl.wifiEnabled ? "#22D3EE" : "#CBD5E1"
                        border.width: 1.5
                        border.color: "#1A1B2E"
                        Rectangle {
                            x: SystemControl.wifiEnabled ? 20 : 2
                            y: 2
                            width: 16
                            height: 16
                            radius: 8
                            color: "#FFFFFF"
                            border.width: 1
                            border.color: "#1A1B2E"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: SystemControl.wifiSupported
                            onClicked: SystemControl.toggleWifi()
                        }
                    }
                }

                Flickable {
                    visible: SystemControl.wifiSupported && SystemControl.wifiEnabled
                    width: parent.width
                    height: Math.min(200, Math.max(28, wifiNetCol.implicitHeight))
                    contentWidth: width
                    contentHeight: wifiNetCol.implicitHeight
                    clip: true

                    Column {
                        id: wifiNetCol
                        width: parent.width
                        spacing: 4
                        Text {
                            visible: SystemControl.wifiNetworks.length === 0
                            text: "Scanning networks..."
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            color: "#64748B"
                        }
                        Repeater {
                            model: SystemControl.wifiNetworks
                            delegate: Rectangle {
                                required property var modelData
                                width: wifiNetCol.width
                                height: 28
                                radius: 9
                                color: modelData.connected ? "#5EEAD4" : (wnMouse.containsMouse ? "#E0F2FE" : "#FFFFFF")
                                border.width: 1.5
                                border.color: "#1A1B2E"

                                Row {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 54
                                    spacing: 6
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12
                                        height: 12
                                        sourceSize.width: 24
                                        sourceSize.height: 24
                                        smooth: true
                                        source: "qrc:/qml/icons/wifi-dark.svg"
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 18
                                        elide: Text.ElideRight
                                        text: (modelData.connected ? "✓ " : "") + modelData.ssid
                                        font.family: "Segoe UI"
                                        font.pixelSize: 11
                                        font.weight: modelData.connected ? Font.Bold : Font.Medium
                                        color: "#1A1B2E"
                                    }
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.signal + "%"
                                    font.family: "Consolas"
                                    font.pixelSize: 10
                                    color: "#475569"
                                }
                                MouseArea {
                                    id: wnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SystemControl.connectWifi(modelData.profile || modelData.ssid)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 28
                    radius: 10
                    color: netSetMouse.containsMouse ? "#E0F2FE" : "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"
                    Text {
                        anchors.centerIn: parent
                        text: "Network Settings"
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: "#1A1B2E"
                    }
                    MouseArea {
                        id: netSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            topBarWindow.wifiPopupOpen = false
                            SystemControl.openSettings("ms-settings:network")
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SekaiPop Bluetooth Popup
    // =========================================================================
    PanelWindow {
        id: btPopupWindow
        visible: topBarWindow.btPopupOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        property double openedAt: 0

        width: 256 + cardShadow
        height: btCol.implicitHeight + 24 + cardShadow
        x: Math.max(8, (topBarWindow.anchors.margins.left + topBarWindow.width) - width - 6)
        y: 34

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                SystemControl.refreshBluetooth()
                requestActivate()
            }
        }

        Timer {
            interval: 60
            repeat: true
            running: btPopupWindow.visible
            onTriggered: {
                if ((Date.now() - btPopupWindow.openedAt) > 220 && btPopupWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.btPopupClosedAt = Date.now()
                    topBarWindow.btPopupOpen = false
                }
            }
        }

        Rectangle {
            x: btPopupWindow.cardShadow
            y: btPopupWindow.cardShadow
            width: btPopupWindow.width - btPopupWindow.cardShadow
            height: btPopupWindow.height - btPopupWindow.cardShadow
            radius: 16
            color: "#1A1B2E"
        }

        Rectangle {
            x: 0
            y: 0
            width: btPopupWindow.width - btPopupWindow.cardShadow
            height: btPopupWindow.height - btPopupWindow.cardShadow
            radius: 16
            color: "#F8FAFC"
            border.width: 2
            border.color: "#1A1B2E"

            Column {
                id: btCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 12
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"

                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: SystemControl.bluetoothSupported ? "Bluetooth" : "Bluetooth (Unavailable)"
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: "#1A1B2E"
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 22
                        radius: 11
                        color: SystemControl.bluetoothEnabled ? "#818CF8" : "#CBD5E1"
                        border.width: 1.5
                        border.color: "#1A1B2E"
                        Rectangle {
                            x: SystemControl.bluetoothEnabled ? 20 : 2
                            y: 2
                            width: 16
                            height: 16
                            radius: 8
                            color: "#FFFFFF"
                            border.width: 1
                            border.color: "#1A1B2E"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: SystemControl.bluetoothSupported
                            onClicked: SystemControl.toggleBluetooth()
                        }
                    }
                }

                Flickable {
                    visible: SystemControl.bluetoothSupported && SystemControl.bluetoothEnabled
                    width: parent.width
                    height: Math.min(180, Math.max(26, btDevCol.implicitHeight))
                    contentWidth: width
                    contentHeight: btDevCol.implicitHeight
                    clip: true

                    Column {
                        id: btDevCol
                        width: parent.width
                        spacing: 4
                        Text {
                            visible: SystemControl.bluetoothDevices.length === 0
                            text: "No paired devices"
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            color: "#64748B"
                        }
                        Repeater {
                            model: SystemControl.bluetoothDevices
                            delegate: Rectangle {
                                required property var modelData
                                width: btDevCol.width
                                height: 28
                                radius: 9
                                color: modelData.connected ? "#C7D2FE" : "#FFFFFF"
                                border.width: 1.5
                                border.color: "#1A1B2E"

                                Row {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 74
                                    spacing: 6
                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12
                                        height: 12
                                        sourceSize.width: 24
                                        sourceSize.height: 24
                                        smooth: true
                                        source: "qrc:/qml/icons/bt-dark.svg"
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 18
                                        elide: Text.ElideRight
                                        text: modelData.name
                                        font.family: "Segoe UI"
                                        font.pixelSize: 11
                                        font.weight: modelData.connected ? Font.Bold : Font.Medium
                                        color: "#1A1B2E"
                                    }
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.connected ? "Connected" : "Paired"
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    color: modelData.connected ? "#3730A3" : "#64748B"
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 28
                    radius: 10
                    color: btSetMouse.containsMouse ? "#E0E7FF" : "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"
                    Text {
                        anchors.centerIn: parent
                        text: "Bluetooth Settings"
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: "#1A1B2E"
                    }
                    MouseArea {
                        id: btSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            topBarWindow.btPopupOpen = false
                            SystemControl.openSettings("ms-settings:bluetooth")
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Phase 4/5 Bonus: SekaiPop OSD Volume Sticker
    // =========================================================================
    PanelWindow {
        id: osdVolumeWindow
        visible: false
        clickThrough: true
        color: "transparent"

        width: 224
        height: 52
        x: Math.round((topBarWindow.anchors.margins.left + topBarWindow.width - width) * 0.5)
        y: dockWindow.y > 100 ? (dockWindow.y - 68) : 720

        property int shownVol: AudioService.masterVolume
        property bool shownMuted: AudioService.masterMuted

        Connections {
            target: AudioService
            function onVolumeOsdRequested(volume, muted) {
                osdVolumeWindow.shownVol = volume
                osdVolumeWindow.shownMuted = muted
                osdVolumeWindow.visible = true
                osdHideTimer.restart()
            }
        }

        Timer {
            id: osdHideTimer
            interval: 1600
            onTriggered: osdVolumeWindow.visible = false
        }

        Rectangle {
            x: 3
            y: 3
            width: 220
            height: 48
            radius: 14
            color: "#1A1B2E"
        }

        Rectangle {
            width: 220
            height: 48
            radius: 14
            color: "#1A1B2E"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 12
                color: "#FFFFFF"
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 10
                    color: "#F1F5FF"
                }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    sourceSize.width: 36
                    sourceSize.height: 36
                    smooth: true
                    source: osdVolumeWindow.shownMuted ? "qrc:/qml/icons/volume-cross-dark.svg" : "qrc:/qml/icons/volume-loud-dark.svg"
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 70
                    height: 12
                    radius: 6
                    color: "#E2E8F0"
                    border.width: 2
                    border.color: "#1A1B2E"
                    Rectangle {
                        x: 2
                        y: 2
                        height: 8
                        radius: 4
                        width: Math.max(0, (parent.width - 4) * (osdVolumeWindow.shownVol / 100.0))
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#5EEAD4" }
                            GradientStop { position: 1.0; color: "#22D3EE" }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    horizontalAlignment: Text.AlignRight
                    text: osdVolumeWindow.shownMuted ? "MUTE" : (osdVolumeWindow.shownVol + "%")
                    font.family: "Consolas"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#1A1B2E"
                }
            }
        }
    }
}
