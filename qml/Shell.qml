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
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⏮"
                                        font.pixelSize: 10
                                        color: "#1A1B2E"
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
                                    Text {
                                        anchors.centerIn: parent
                                        text: MediaService.isPlaying ? "⏸" : "▶"
                                        font.pixelSize: 10
                                        color: "#1A1B2E"
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
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⏭"
                                        font.pixelSize: 10
                                        color: "#1A1B2E"
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
        anchors.margins.top: 2
        anchors.margins.left: 6
        anchors.margins.right: 6
        height: 30
        reserveTopBar: true
        reserveHeight: 32
        clickThrough: topBarWindow.fullscreenActive

        property string timeText: ""
        property string dateText: ""
        property bool mediaPopupOpen: false
        property double mediaPopupClosedAt: 0
        property real topHideProgress: topBarWindow.fullscreenActive ? 1.0 : 0.0
        Behavior on topHideProgress {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        readonly property real topHideOffsetY: -topHideProgress * 38

        mask: topBarWindow.topHideProgress > 0.95
            ? []
            : [{ x: 0, y: 0, width: topBarWindow.width, height: topBarWindow.height }]

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

            // Hard flat offset shadow (slim 2px)
            Rectangle {
                x: barFrame.x + 2
                y: barFrame.y + 2
                width: barFrame.width
                height: barFrame.height
                radius: barFrame.radius
                color: "#1A1B2E"
            }

            // Single slim SekaiPop Neo-Brutalist bar (28px)
            Rectangle {
                id: barFrame
                x: 0
                y: topBarWindow.topHideOffsetY
                width: Math.max(100, topBarRoot.width - 2)
                height: 28
                radius: 12
                color: "#1A1B2E"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1.5
                    radius: parent.radius - 1.5
                    color: "#FFFFFF"

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: parent.radius - 2
                        color: "#334155"
                    }
                }

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
                        width: Math.max(148, Math.min(280, mediaArtBox.width + mediaDivider.width + 18 + Math.max(mediaTitleTxt.implicitWidth, mediaArtistTxt.visible ? mediaArtistTxt.implicitWidth : 0)))
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

                                Text {
                                    anchors.centerIn: parent
                                    visible: mediaPillCover.status !== Image.Ready
                                    text: MediaService.hasSession ? "♪" : "♫"
                                    font.family: "Segoe UI Symbol"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#1A1B2E"
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

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: -1
                                    opacity: (MediaService.hasSession && !MediaService.isPlaying) ? 0.55 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Text {
                                        id: mediaTitleTxt
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: MediaService.hasSession ? (MediaService.title || "Playing") : "Nothing Playing"
                                        font.family: "Segoe UI"
                                        font.pixelSize: MediaService.hasSession ? 10 : 11
                                        font.weight: Font.ExtraBold
                                        color: "#1A1B2E"
                                    }

                                    Text {
                                        id: mediaArtistTxt
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        visible: MediaService.hasSession && (MediaService.artist || "") !== ""
                                        text: MediaService.artist || ""
                                        font.family: "Segoe UI"
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        color: "#0F172A"
                                        opacity: 0.85
                                    }
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
                            text: "CPU " + WindowTracker.cpuUsage + "%"
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#7DD3FC"
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

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: clockRow.implicitWidth + 12
                        height: 20
                        radius: 8
                        color: "#22D3EE"
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

                                        Text {
                                            anchors.centerIn: parent
                                            visible: popupCoverImg.status !== Image.Ready
                                            text: MediaService.hasSession ? "♪" : "♫"
                                            font.family: "Segoe UI Symbol"
                                            font.pixelSize: 28
                                            color: "#64748B"
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
                            Text {
                                anchors.centerIn: parent
                                text: "⏮"
                                font.family: "Segoe UI Symbol"
                                font.pixelSize: 15
                                color: "#1A1B2E"
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
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: MediaService.isPlaying ? "⏸" : "▶"
                                    font.family: "Segoe UI Symbol"
                                    font.pixelSize: 13
                                    color: "#1A1B2E"
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
                            Text {
                                anchors.centerIn: parent
                                text: "⏭"
                                font.family: "Segoe UI Symbol"
                                font.pixelSize: 15
                                color: "#1A1B2E"
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
}
