import QtQuick
import QtQuick.Window
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

    readonly property int baseTileSize: themeHub.dockTileSize
    readonly property int maxTileSize: themeHub.dockMagnify ? Math.round(themeHub.dockTileSize * 1.65) : themeHub.dockTileSize
    readonly property int baseIconSize: Math.round(baseTileSize * 0.7)
    readonly property int maxIconSize: Math.round(maxTileSize * 0.78)
    readonly property int tileGap: 8
    readonly property int pillPadX: 14
    readonly property int pillPadY: 10
    readonly property int shadowOffset: 4
    readonly property int headroom: Math.max(14, maxTileSize - baseTileSize + 14)
    readonly property int hoverPadX: 96

    readonly property real waveRadius: 128.0
    property bool dockHovered: pillHover.hovered
    property real pointerX: 0
    property real waveStrength: (dockHovered && dragFromSlot < 0) ? 1.0 : 0.0

    Item {
        id: screenMetrics
        visible: false
    }

    ThemeHub {
        id: themeHub
        screenW: screenMetrics.Screen.width > 0 ? screenMetrics.Screen.width : (topBarWindow.width > 0 ? topBarWindow.width : 1920)
        screenH: screenMetrics.Screen.height > 0 ? screenMetrics.Screen.height : 1080
    }

    // Phase 3: Dock Auto-Hide / Dodge Active Window (plus unconditional fullscreen hide)
    property bool dockAutoHideEnabled: themeHub.dockAutoHide
    readonly property bool dockShouldHide: topBarWindow.fullscreenActive
        || (dockAutoHideEnabled
            && WindowTracker.dockOverlap
            && !WindowTracker.bottomEdgeHovered
            && !dockHovered
            && dragFromSlot < 0
            && !ctxOpen
            && activePreviewTarget === ""
            && !previewCardHovered)
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

        const hasTools = themeHub.dockShowFinder || themeHub.dockShowClipboard || themeHub.dockShowDropShelf || themeHub.dockShowTrash
        if (hasTools && items.length > 0)
            items.push({ kind: "divider" })
        if (themeHub.dockShowFinder)
            items.push({ kind: "finder", name: "Spotlight" })
        if (themeHub.dockShowClipboard)
            items.push({ kind: "clipboard", name: "Clipboard" })
        if (themeHub.dockShowDropShelf)
            items.push({ kind: "dropshelf", name: "Drop Shelf" })
        if (themeHub.dockShowTrash)
            items.push({ kind: "trash", name: "Trash" })

        return items
    }

    function isDockKeycapKind(k) {
        return k === "app" || k === "trash" || k === "finder" || k === "clipboard" || k === "dropshelf"
    }

    readonly property real idleTotalWidth: {
        const list = dockItems
        const n = list.length
        let bx = 0
        for (let i = 0; i < n; ++i) {
            const it = list[i]
            const bw = isDockKeycapKind(it.kind)
                ? baseTileSize
                : (it.kind === "media" ? 124 : 8)
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
            const bw = isDockKeycapKind(it.kind)
                ? baseTileSize
                : (it.kind === "media" ? 124 : 8)
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
            if (themeHub.dockMagnify && isDockKeycapKind(it.kind) && waveStrength > 0.001) {
                const dist = Math.abs(pointerX - baseCenters[i])
                if (dist < waveRadius) {
                    w = 0.5 * (1.0 + Math.cos(Math.PI * dist / waveRadius)) * waveStrength
                }
            }
            weights.push(w)
            const curW = isDockKeycapKind(it.kind)
                ? (baseTileSize + (maxTileSize - baseTileSize) * w)
                : (it.kind === "media" ? 124 : 8)
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
    clickThrough: topBarWindow.fullscreenActive || dockWindow.hideProgress > 0.5

    // When hidden (or fullscreen active), mask is empty (100% click-through). When idle, mask strictly to the static idle pill rect;
    // when hovered, use a static full-window mask so SetWindowRgn is NOT called per mouse pixel.
    mask: topBarWindow.fullscreenActive
        ? []
        : (dockWindow.hideProgress > 0.95
            ? []
            : (dockWindow.dockHovered || dockWindow.waveStrength > 0.02
                ? [{ x: 0, y: 0, width: dockWindow.width, height: dockWindow.height }]
                : [{
                    x: (dockWindow.width - dockWindow.shadowOffset - (dockWindow.idleTotalWidth + dockWindow.pillPadX * 2)) * 0.5,
                    y: dockWindow.headroom,
                    width: dockWindow.idleTotalWidth + dockWindow.pillPadX * 2 + dockWindow.shadowOffset,
                    height: dockWindow.baseTileSize + dockWindow.pillPadY * 2 + dockWindow.shadowOffset
                }]))

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
        visible: themeHub.dockStyle !== "transparent"
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
        radius: themeHub.dockStyle === "capsule" ? Math.round(height * 0.5) : 20
        color: themeHub.dockStyle === "transparent" ? Qt.rgba(26/255, 27/255, 46/255, 0.28) : "#1A1B2E"

        // White inner ring
        Rectangle {
            visible: themeHub.dockStyle !== "transparent"
            anchors.fill: parent
            anchors.margins: 2.5
            radius: Math.max(4, parent.radius - 2.5)
            color: "#FFFFFF"

            // Pastel body fill
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: Math.max(4, parent.radius - 3)
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

                    // --- Utility Tool Keycaps (Spotlight / Clipboard / Drop Shelf) ---
                    Item {
                        id: utilToolBox
                        visible: slot.modelData.kind === "finder" || slot.modelData.kind === "clipboard" || slot.modelData.kind === "dropshelf"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: slot.slotW
                        height: slot.slotW

                        readonly property bool hovered: utilToolMa.containsMouse
                        readonly property bool pressed: utilToolMa.pressed
                        readonly property bool activeTool: (slot.modelData.kind === "finder" && themeHub.spotlightOpen)
                            || (slot.modelData.kind === "clipboard" && themeHub.clipboardOpen)
                            || (slot.modelData.kind === "dropshelf" && themeHub.dropShelfOpen)

                        Rectangle {
                            anchors.fill: utilCap
                            anchors.topMargin: 2.5
                            anchors.bottomMargin: -2.5
                            radius: utilCap.radius
                            color: "#1A1B2E"
                            opacity: utilToolBox.pressed ? 0.0 : 0.9
                        }

                        Rectangle {
                            id: utilCap
                            width: parent.width
                            height: parent.height
                            y: utilToolBox.pressed ? 2.5 : (utilToolBox.hovered ? -2 : 0)
                            radius: 13 + 5 * slot.wFactor
                            color: utilToolBox.activeTool ? themeHub.accentA : (utilToolBox.hovered ? themeHub.hoverTint : "#FFFFFF")
                            border.width: 2
                            border.color: "#1A1B2E"

                            Image {
                                anchors.centerIn: parent
                                width: Math.round(parent.width * 0.54)
                                height: Math.round(parent.height * 0.54)
                                sourceSize.width: 48
                                sourceSize.height: 48
                                smooth: true
                                source: slot.modelData.kind === "finder"
                                    ? "qrc:/qml/icons/magnifer-dark.svg"
                                    : (slot.modelData.kind === "clipboard"
                                        ? "qrc:/qml/icons/clipboard-text-dark.svg"
                                        : "qrc:/qml/icons/folder-with-files-dark.svg")
                            }

                            Rectangle {
                                visible: slot.modelData.kind === "dropshelf" && DropShelfService.count > 0
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: -4
                                width: Math.max(18, dsDockBadge.implicitWidth + 8)
                                height: 18
                                radius: 9
                                color: themeHub.accentB
                                border.width: 1.5
                                border.color: "#1A1B2E"
                                Text {
                                    id: dsDockBadge
                                    anchors.centerIn: parent
                                    text: String(DropShelfService.count)
                                    font.family: "Segoe UI"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: "#1A1B2E"
                                }
                            }
                        }

                        MouseArea {
                            id: utilToolMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (slot.modelData.kind === "finder") {
                                    themeHub.clipboardOpen = false
                                    themeHub.dropShelfOpen = false
                                    themeHub.spotlightOpen = !themeHub.spotlightOpen
                                } else if (slot.modelData.kind === "clipboard") {
                                    themeHub.spotlightOpen = false
                                    themeHub.dropShelfOpen = false
                                    themeHub.clipboardOpen = !themeHub.clipboardOpen
                                } else if (slot.modelData.kind === "dropshelf") {
                                    themeHub.spotlightOpen = false
                                    themeHub.clipboardOpen = false
                                    themeHub.dropShelfOpen = !themeHub.dropShelfOpen
                                }
                            }
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
        visible: !topBarWindow.fullscreenActive && dockWindow.activePreviewWindows.length > 0
        clickThrough: false

        readonly property int tileW: 216
        readonly property int tileH: 152
        readonly property int cardPad: 12
        readonly property int cardShadow: 4
        readonly property int maxTiles: Math.min(4, dockWindow.activePreviewWindows.length)

        width: previewCard.width + cardShadow
        height: previewCard.height + cardShadow

        x: {
            const scrW = themeHub.screenW
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
            const scrW = themeHub.screenW
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
        height: themeHub.barStyle === "float" ? 34 : 28
        reserveTopBar: !themeHub.barAutoHide && !topBarWindow.fullscreenActive
        reserveHeight: (themeHub.barAutoHide || topBarWindow.fullscreenActive) ? 0 : (themeHub.barStyle === "float" ? 34 : 28)
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
        property bool volumePopupOpen: false
        property double volumePopupClosedAt: 0
        readonly property bool phoneMode: themeHub.phoneMode
        readonly property bool anyPopupOpen: mediaPopupOpen || trayPopupOpen || quickPanelOpen || calendarOpen || wifiPopupOpen || btPopupOpen || volumePopupOpen
        readonly property bool autoHideTriggered: themeHub.barAutoHide
                                                  && WindowTracker.topOverlap
                                                  && !topBarHover.hovered
                                                  && !WindowTracker.topEdgeHovered
                                                  && !anyPopupOpen
        property real topHideProgress: (topBarWindow.fullscreenActive || topBarWindow.autoHideTriggered) ? 1.0 : 0.0

        Connections {
            target: SystemControl
            function onQuickPanelToggleRequested() {
                if (themeHub.settingsOpen) {
                    themeHub.settingsOpen = false
                    topBarWindow.quickPanelClosedAt = Date.now()
                    topBarWindow.quickPanelOpen = false
                    return
                }
                if (!topBarWindow.quickPanelOpen && (Date.now() - topBarWindow.quickPanelClosedAt) < 120)
                    return
                if (topBarWindow.quickPanelOpen)
                    topBarWindow.quickPanelClosedAt = Date.now()
                topBarWindow.quickPanelOpen = !topBarWindow.quickPanelOpen
            }
        }
        Behavior on topHideProgress {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        readonly property real topHideOffsetY: -topHideProgress * 38

        blurBehind: !topBarWindow.fullscreenActive && topBarWindow.topHideProgress < 0.95
        blurRadius: themeHub.barStyle === "capsule" ? 14 : (themeHub.barStyle === "float" ? 10 : 0)
        blurInsetX: themeHub.barStyle === "float" ? 8 : (themeHub.barStyle === "capsule" ? 14 : 0)
        blurInsetY: themeHub.barStyle === "float" ? 4 : 0
        blurInsetRight: themeHub.barStyle === "float" ? 8 : (themeHub.barStyle === "capsule" ? 14 : 0)
        blurInsetBottom: themeHub.barStyle === "float" ? 2 : 0
        blurTint: themeHub.barStyle === "transparent"
                  ? Qt.rgba(14/255, 18/255, 30/255, 0.35)
                  : Qt.rgba(16/255, 20/255, 36/255, 0.84)

        mask: topBarWindow.fullscreenActive
              ? []
              : (topBarWindow.topHideProgress > 0.95
                 ? (themeHub.barAutoHide ? [{ x: 0, y: 0, width: Math.max(1, topBarWindow.width), height: 3 }] : [])
                 : null)

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

            HoverHandler {
                id: topBarHover
            }

            // Styled TopBar frame (transparent / straight / float / capsule)
            Rectangle {
                id: barFrame
                x: themeHub.barStyle === "float" ? 8 : (themeHub.barStyle === "capsule" ? 14 : 0)
                y: (themeHub.barStyle === "float" ? 4 : 0) + topBarWindow.topHideOffsetY
                width: topBarRoot.width - x * 2
                height: 28
                radius: themeHub.barStyle === "capsule" ? 14 : (themeHub.barStyle === "float" ? 10 : 0)
                color: {
                    if (themeHub.barStyle === "transparent")
                        return "transparent"
                    if (themeHub.barStyle === "straight")
                        return Qt.rgba(14/255, 18/255, 32/255, 0.78)
                    return Qt.rgba(18/255, 22/255, 38/255, 0.88)
                }
                border.width: (themeHub.barStyle === "float" || themeHub.barStyle === "capsule") ? 2 : 0
                border.color: themeHub.barStyle === "capsule" ? themeHub.accentA : "#1A1B2E"

                Rectangle {
                    visible: themeHub.barStyle === "straight"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    color: "#1A1B2E"
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
                        visible: themeHub.barShowActiveWindow
                        anchors.verticalCenter: parent.verticalCenter
                        width: appNameTxt.implicitWidth + 14
                        height: 20
                        radius: 8
                        color: themeHub.accentA
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
                        visible: themeHub.barShowMedia
                        width: Math.max(148, Math.min(280, 5 + mediaArtBox.width + 4 + mediaDivider.width + 20 + mediaSingleLineTxt.implicitWidth))
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
                            anchors.margins: 2
                            radius: 8
                            clip: true
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: themeHub.accentB }
                                GradientStop { position: 1.0; color: themeHub.accentA }
                            }

                            Item {
                                id: mediaArtBox
                                anchors.left: parent.left
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                clip: true
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
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                    fillMode: Image.PreserveAspectCrop
                                    clip: true
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
                                anchors.leftMargin: 4
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
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

                        Rectangle {
                            z: 5
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 2
                            border.color: "#1A1B2E"
                            antialiasing: true
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
                        visible: themeHub.barShowActiveWindow && (WindowTracker.activeWindowTitle || "") !== ""
                        text: WindowTracker.activeWindowTitle || ""
                        width: Math.min(implicitWidth, Math.max(40, rightContentRow.x - leftContentRow.x - (appBadgeRect.visible ? appBadgeRect.width : 0) - (mediaPill.visible ? mediaPill.width : 0) - 30))
                        elide: Text.ElideRight
                        font.family: "Segoe UI"
                        font.pixelSize: 11
                        color: "#E2E8F0"
                    }
                }

                // --- Right Zone: PowerTools, Hardware, Tray, Audio, Clock ---
                Row {
                    id: rightContentRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    spacing: 5

                    // --- Band Theme / Settings Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: bandPillRow.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: themeHub.settingsOpen ? themeHub.accentA : (bandPillMa.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: themeHub.accentA
                        Row {
                            id: bandPillRow
                            anchors.centerIn: parent
                            spacing: 4
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 11
                                height: 11
                                sourceSize.width: 22
                                sourceSize.height: 22
                                smooth: true
                                source: themeHub.settingsOpen ? "qrc:/qml/icons/palette-dark.svg" : "qrc:/qml/icons/palette-light.svg"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: themeHub.bandShort
                                font.family: "Consolas"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.settingsOpen ? themeHub.darkInk : themeHub.accentA
                            }
                        }
                        MouseArea {
                            id: bandPillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!themeHub.settingsOpen && (Date.now() - themeHub.settingsClosedAt) < 220)
                                    return
                                themeHub.spotlightOpen = false
                                themeHub.clipboardOpen = false
                                themeHub.settingsOpen = !themeHub.settingsOpen
                            }
                        }
                    }

                    // --- Edit Desktop Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: editPillTxt.implicitWidth + 12
                        height: 20
                        radius: 7
                        color: themeHub.editMode ? themeHub.accentB : (editPillMa.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: themeHub.editMode ? themeHub.accentA : "#64748B"
                        Text {
                            id: editPillTxt
                            anchors.centerIn: parent
                            text: themeHub.editMode ? "Editing" : "Edit"
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: themeHub.editMode ? "#1A1B2E" : "#E2E8F0"
                        }
                        MouseArea {
                            id: editPillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themeHub.setEditMode(!themeHub.editMode)
                        }
                    }

                    // --- Spotlight Search Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 20
                        radius: 7
                        color: themeHub.spotlightOpen ? themeHub.accentA : (spotPillMa.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: "#64748B"
                        Image {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            sourceSize.width: 24
                            sourceSize.height: 24
                            smooth: true
                            source: themeHub.spotlightOpen ? "qrc:/qml/icons/magnifer-dark.svg" : "qrc:/qml/icons/magnifer-light.svg"
                        }
                        MouseArea {
                            id: spotPillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!themeHub.spotlightOpen && (Date.now() - themeHub.spotlightClosedAt) < 220)
                                    return
                                themeHub.settingsOpen = false
                                themeHub.clipboardOpen = false
                                themeHub.spotlightOpen = !themeHub.spotlightOpen
                            }
                        }
                    }

                    // --- Clipboard History Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 20
                        radius: 7
                        color: themeHub.clipboardOpen ? themeHub.accentA : (clipPillMa.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: "#64748B"
                        Image {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            sourceSize.width: 24
                            sourceSize.height: 24
                            smooth: true
                            source: themeHub.clipboardOpen ? "qrc:/qml/icons/clipboard-text-dark.svg" : "qrc:/qml/icons/clipboard-text-light.svg"
                        }
                        MouseArea {
                            id: clipPillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!themeHub.clipboardOpen && (Date.now() - themeHub.clipboardClosedAt) < 220)
                                    return
                                themeHub.settingsOpen = false
                                themeHub.spotlightOpen = false
                                themeHub.clipboardOpen = !themeHub.clipboardOpen
                            }
                        }
                    }

                    // --- Drop Shelf Pill ---
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: DropShelfService.count > 0 ? (shelfPillRow.implicitWidth + 10) : 22
                        height: 20
                        radius: 7
                        color: themeHub.dropShelfOpen ? themeHub.accentB : (shelfPillMa.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: DropShelfService.count > 0 ? themeHub.accentB : "#64748B"
                        Row {
                            id: shelfPillRow
                            anchors.centerIn: parent
                            spacing: 3
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                sourceSize.width: 24
                                sourceSize.height: 24
                                smooth: true
                                source: themeHub.dropShelfOpen ? "qrc:/qml/icons/folder-with-files-dark.svg" : "qrc:/qml/icons/folder-with-files-light.svg"
                            }
                            Text {
                                visible: DropShelfService.count > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "" + DropShelfService.count
                                font.family: "Consolas"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.dropShelfOpen ? themeHub.darkInk : themeHub.accentB
                            }
                        }
                        MouseArea {
                            id: shelfPillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!themeHub.dropShelfOpen && (Date.now() - themeHub.dropShelfClosedAt) < 220)
                                    return
                                themeHub.dropShelfOpen = !themeHub.dropShelfOpen
                            }
                        }
                    }

                    Rectangle {
                        visible: themeHub.barShowStats
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
                        visible: themeHub.barShowStats && WindowTracker.gpuTemp >= 0
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
                        visible: themeHub.barShowStats
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
                        visible: themeHub.barShowTray
                        anchors.verticalCenter: parent.verticalCenter
                        width: trayPillRow.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: topBarWindow.trayPopupOpen ? themeHub.accentA : (trayPillMouse.containsMouse ? "#334155" : "#1E293B")
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
                        color: topBarWindow.wifiPopupOpen ? themeHub.accentA : (wifiPillMouse.containsMouse ? "#334155" : "#1E293B")
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
                        color: topBarWindow.btPopupOpen ? themeHub.accentA : (btPillMouse.containsMouse ? "#334155" : "#1E293B")
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

                    // --- Volume Pill (wheel = master vol, right click = mute, left click = Volume Mixer Popup) ---
                    Rectangle {
                        id: volPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: volPillTxt.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: topBarWindow.volumePopupOpen
                            ? themeHub.accentB
                            : (volPillMouse.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: AudioService.masterMuted ? "#F59E0B" : themeHub.accentB

                        Text {
                            id: volPillTxt
                            anchors.centerIn: parent
                            text: AudioService.masterMuted ? "MUTE" : ("VOL " + AudioService.masterVolume + "%")
                            font.family: "Consolas"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: topBarWindow.volumePopupOpen
                                ? "#1A1B2E"
                                : (AudioService.masterMuted ? "#FCD34D" : themeHub.accentB)
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
                                    if (!topBarWindow.volumePopupOpen && (Date.now() - topBarWindow.volumePopupClosedAt) < 220)
                                        return
                                    if (!topBarWindow.volumePopupOpen) {
                                        AudioService.refreshSessions()
                                        AudioService.refreshOutputDevices()
                                    }
                                    topBarWindow.volumePopupOpen = !topBarWindow.volumePopupOpen
                                }
                            }
                            onWheel: wheel => {
                                const step = wheel.angleDelta.y > 0 ? 4 : -4
                                AudioService.setMasterVolume(AudioService.masterVolume + step)
                                wheel.accepted = true
                            }
                        }
                    }

                    // --- QuickPanel / Notifications Pill (left click = Phone QuickPanel) ---
                    Rectangle {
                        id: qpPill
                        anchors.verticalCenter: parent.verticalCenter
                        width: qpPillRow.implicitWidth + 10
                        height: 20
                        radius: 7
                        color: topBarWindow.quickPanelOpen
                            ? themeHub.accentA
                            : (qpPillMouse.containsMouse ? "#334155" : "#1E293B")
                        border.width: 1
                        border.color: NotificationService.count > 0 ? "#FB7185" : themeHub.accentA

                        Row {
                            id: qpPillRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "🔔"
                                font.family: "Segoe UI Emoji"
                                font.pixelSize: 10
                                color: topBarWindow.quickPanelOpen ? "#1A1B2E" : themeHub.accentA
                            }

                            Rectangle {
                                visible: NotificationService.count > 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(14, qpCountTxt.implicitWidth + 6)
                                height: 14
                                radius: 7
                                color: "#E11D48"
                                Text {
                                    id: qpCountTxt
                                    anchors.centerIn: parent
                                    text: NotificationService.count > 9 ? "9+" : String(NotificationService.count)
                                    font.family: "Segoe UI"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: "#FFFFFF"
                                }
                            }
                        }

                        MouseArea {
                            id: qpPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!topBarWindow.quickPanelOpen && (Date.now() - topBarWindow.quickPanelClosedAt) < 220)
                                    return
                                if (!topBarWindow.quickPanelOpen) {
                                    AudioService.refreshSessions()
                                    AudioService.refreshOutputDevices()
                                    SystemControl.refresh()
                                    SystemControl.refreshWifi()
                                    SystemControl.refreshBluetooth()
                                    NotificationService.refresh()
                                }
                                topBarWindow.quickPanelOpen = !topBarWindow.quickPanelOpen
                            }
                        }
                    }

                    Rectangle {
                        id: barWeatherPill
                        visible: themeHub.barShowWeather
                        anchors.verticalCenter: parent.verticalCenter
                        width: barWeatherTxt.implicitWidth + 12
                        height: 20
                        radius: 7
                        color: barWeatherMouse.containsMouse ? "#334155" : "#1E293B"
                        border.width: 1
                        border.color: themeHub.accentA

                        Text {
                            id: barWeatherTxt
                            anchors.centerIn: parent
                            text: (WeatherService.isDay ? "☀ " : "🌙 ") + themeHub.formatTemp(WeatherService.temperature) + "°"
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#E2E8F0"
                        }

                        MouseArea {
                            id: barWeatherMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WeatherService.refresh()
                        }
                    }

                    Rectangle {
                        id: clockPill
                        visible: themeHub.barShowClock
                        anchors.verticalCenter: parent.verticalCenter
                        width: clockRow.implicitWidth + 12
                        height: 20
                        radius: 8
                        color: topBarWindow.calendarOpen ? themeHub.accentB : (clockPillMouse.containsMouse ? "#67E8F9" : themeHub.accentA)
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
            const scrW = themeHub.screenW
            const targetX = topBarWindow.anchors.margins.left + leftContentRow.x + appBadgeRect.width + 6
            return Math.max(8, Math.min(scrW - width - 8, targetX))
        }
        y: 34

        property double openedAt: 0
        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                focusActivate()
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
                            color: isCurrent ? themeHub.accentA : "#FFFFFF"
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
                                    GradientStop { position: 0.0; color: themeHub.accentB }
                                    GradientStop { position: 1.0; color: themeHub.accentA }
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
                                GradientStop { position: 0.0; color: themeHub.accentB }
                                GradientStop { position: 1.0; color: themeHub.accentA }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: seekTrack.headX
                            width: seekTrack.headSize
                            height: seekTrack.headSize
                            radius: 3
                            rotation: 45
                            color: themeHub.accentA
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
                                GradientStop { position: 0.0; color: themeHub.accentB }
                                GradientStop { position: 1.0; color: themeHub.accentA }
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
                focusActivate()
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
    // Phase 4: SekaiPop 2.5D Tilted Smartphone Control Center (Bottom-Up Pop + 3D Tilt)
    // =========================================================================
    PanelWindow {
        id: quickPanelWindow
        visible: !topBarWindow.fullscreenActive && (topBarWindow.quickPanelOpen || stageLift < hiddenLift || themeHub.settingsOpen || flipProgress > 0.001 || flipPrepTimer.running || flipAnim.running || flipRingAnim.running || settingsEnterAnim.running || settingsExitAnim.running)
        clickThrough: !panelWanted && !settingsWanted
        color: "transparent"

        // PhoneMath (4x4 perspective matrix helpers, pure JS)
        function pmMul(a, b) {
            const r = new Array(16)
            for (let i = 0; i < 4; i++) {
                for (let j = 0; j < 4; j++) {
                    let s = 0
                    for (let k = 0; k < 4; k++)
                        s += a[i * 4 + k] * b[k * 4 + j]
                    r[i * 4 + j] = s
                }
            }
            return r
        }
        function pmTrans(x, y, z) {
            return [1, 0, 0, x,  0, 1, 0, y,  0, 0, 1, z,  0, 0, 0, 1]
        }
        function pmRotX(deg) {
            const r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r)
            return [1, 0, 0, 0,  0, c, -s, 0,  0, s, c, 0,  0, 0, 0, 1]
        }
        function pmRotY(deg) {
            const r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r)
            return [c, 0, s, 0,  0, 1, 0, 0,  -s, 0, c, 0,  0, 0, 0, 1]
        }
        function pmRotZ(deg) {
            const r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r)
            return [c, -s, 0, 0,  s, c, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1]
        }
        function pmPersp(d) {
            return [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, -1 / d, 1]
        }
        function pmFlatZ() {
            return [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 0, 0,  0, 0, 0, 1]
        }
        function pmApply(m, x, y, z) {
            const X = m[0] * x + m[1] * y + m[2] * z + m[3]
            const Y = m[4] * x + m[5] * y + m[6] * z + m[7]
            const W = m[12] * x + m[13] * y + m[14] * z + m[15]
            return { x: X / W, y: Y / W }
        }
        function pmZOffset(m, z) {
            return [m[0], m[1], m[2], m[3] + z * m[2],
                    m[4], m[5], m[6], m[7] + z * m[6],
                    m[8], m[9], m[10], m[11] + z * m[10],
                    m[12], m[13], m[14], m[15] + z * m[14]]
        }
        function pmBuildPose(W, H, T, R, yaw, pitch, d, pad) {
            const rot = pmMul(pmRotY(-yaw), pmRotX(pitch))
            const c = pmMul(pmPersp(d), pmMul(rot, pmTrans(-W / 2, -H / 2, T / 2)))
            const pts = []
            const cs = [[R, R, Math.PI], [W - R, R, 1.5 * Math.PI],
                        [W - R, H - R, 0], [R, H - R, 0.5 * Math.PI]]
            for (let ci = 0; ci < cs.length; ci++) {
                for (let i = 0; i <= 6; i++) {
                    const a = cs[ci][2] + (i / 6) * Math.PI / 2
                    pts.push([cs[ci][0] + R * Math.cos(a), cs[ci][1] + R * Math.sin(a)])
                }
            }
            let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
            for (let zi = 0; zi < 2; zi++) {
                const z = zi === 0 ? 0 : -T
                for (let i = 0; i < pts.length; i++) {
                    const p = pmApply(c, pts[i][0], pts[i][1], z)
                    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x)
                    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y)
                }
            }
            const off = pmTrans(-minX + pad, -minY + pad, 0)
            return {
                base: pmMul(pmFlatZ(), pmMul(off, c)),
                w: maxX - minX + 2 * pad,
                h: maxY - minY + 2 * pad,
                minX: minX,
                minY: minY,
                pad: pad
            }
        }
        function pmBaseFor(W, H, T, yaw, pitch, roll, d, rest) {
            const rot = pmMul(pmRotY(-yaw), pmMul(pmRotX(pitch), pmRotZ(roll)))
            const c = pmMul(pmPersp(d), pmMul(rot, pmTrans(-W / 2, -H / 2, T / 2)))
            const off = pmTrans(-rest.minX + rest.pad, -rest.minY + rest.pad, 0)
            return pmMul(pmFlatZ(), pmMul(off, c))
        }
        function pmBaseForCenter(W, H, T, yaw, pitch, roll, d) {
            const rot = pmMul(pmRotY(-yaw), pmMul(pmRotX(pitch), pmRotZ(roll)))
            return pmMul(pmFlatZ(), pmMul(pmPersp(d), pmMul(rot, pmTrans(-W / 2, -H / 2, T / 2))))
        }
        function toQtMat(m) {
            return Qt.matrix4x4(m[0], m[1], m[2], m[3],
                                m[4], m[5], m[6], m[7],
                                m[8], m[9], m[10], m[11],
                                m[12], m[13], m[14], m[15])
        }
        // FlipMath (exact SekaiPop FlipMath.js parity)
        function fmClamp01(v) {
            return v < 0 ? 0 : (v > 1 ? 1 : v)
        }
        function fmLerp(a, b, t) {
            return a + (b - a) * t
        }
        function fmSmooth(a, b, v) {
            const t = fmClamp01((v - a) / (b - a))
            return t * t * (3 - 2 * t)
        }
        function fmDip(p, depth) {
            return 1.0 - depth * Math.sin(Math.PI * fmClamp01(p))
        }
        function fmQuickScale(p, qFit, sFit, depth) {
            return fmLerp(qFit, 1.16 * sFit, p) * fmDip(p, depth)
        }
        function fmQuickAlpha(p) {
            return 1.0 - fmSmooth(0.35, 0.92, p)
        }
        function fmSettingsAlpha(p) {
            return fmSmooth(0.02, 0.55, p)
        }
        function formatRate(bps) {
            const v = Number(bps) || 0
            if (v >= 1048576) return (v / 1048576).toFixed(1) + " MB/s"
            if (v >= 1024) return Math.round(v / 1024) + " KB/s"
            return Math.round(v) + " B/s"
        }

        // Design-space constants matching SekaiPop PhoneBody (654x1214) & SettingsStage (1440x760)
        readonly property real faceW: 654
        readonly property real faceH: 1214
        readonly property real cornerR: 100
        readonly property real rimW: 10
        readonly property real bezelW: 16
        readonly property real screenInset: rimW + bezelW
        readonly property real thickness: topBarWindow.phoneMode ? 92 : 0
        readonly property real poseYaw: topBarWindow.phoneMode ? 33 : 0
        readonly property real posePitch: topBarWindow.phoneMode ? 18 : 0
        readonly property real tiltRoll: topBarWindow.phoneMode ? 12 : 0
        readonly property real tiltPitch: topBarWindow.phoneMode ? 10 : 0
        readonly property real tiltYaw: topBarWindow.phoneMode ? -6 : 0
        readonly property real curPersp: 3400 + 2600 * fmClamp01(flipProgress)
        readonly property var phonePose: pmBuildPose(faceW, faceH, thickness, cornerR, poseYaw, posePitch, 3400, 14)
        readonly property real fitScale: Math.min(0.49, Math.max(0.32, (themeHub.screenH - 104) / Math.max(1214, phonePose.h)))

        readonly property int phoneBoxW: Math.ceil(phonePose.w * fitScale) + 18
        readonly property int phoneBoxH: Math.ceil(phonePose.h * fitScale) + 10
        readonly property int railPad: 74
        readonly property real bounce: 34
        readonly property real headroom: 44
        readonly property int bottomPad: 56
        readonly property real enterFrom: phoneBoxH + bottomPad + 2
        readonly property real exitTail: Math.ceil(phoneBoxH * 0.3)
        readonly property real hiddenLift: enterFrom + exitTail

        // Landscape Settings Chassis constants (1440x760 rotated 90 deg CCW from portrait)
        readonly property real landW: 1440
        readonly property real landH: 760
        readonly property real landCornerR: 92
        readonly property real landThickness: topBarWindow.phoneMode ? 135 : 0
        readonly property real landYaw: topBarWindow.phoneMode ? 24 : 0
        readonly property real landPitch: topBarWindow.phoneMode ? 12 : 0
        readonly property real landTiltYaw: topBarWindow.phoneMode ? -22 : 0
        readonly property real landTiltPitch: topBarWindow.phoneMode ? 14 : 0
        readonly property real landTiltRoll: topBarWindow.phoneMode ? 7 : 0
        readonly property real landPopFrom: 0.55
        readonly property real landScale: Math.min(0.76, Math.max(0.42, Math.min((themeHub.screenW - 96) / landW, (themeHub.screenH - 84) / landH)))
        readonly property int portWinW: phoneBoxW + railPad * 2
        readonly property int portWinH: phoneBoxH + headroom + bottomPad
        readonly property int portWinX: Math.round((themeHub.screenW - portWinW) * 0.5)
        readonly property int portWinY: Math.max(0, themeHub.screenH - portWinH)

        readonly property real flipDip: 0.12
        readonly property int flipMs: 200
        readonly property real flipWobble: 2.5
        readonly property int flipRingMs: 380

        property real flipProgress: 0.0
        property real flipWob: 0.0
        property real ringSign: -1.0
        property real sPop: 1.0
        property real sAlpha: 1.0
        property real sTilt: 0.0
        property real flipTarget: 0.0
        property bool settingsOpenedFromQuick: false
        property bool standaloneSettings: false
        readonly property bool flipping: flipPrepTimer.running || flipAnim.running
        readonly property bool settingsAnimating: settingsEnterAnim.running || settingsExitAnim.running
        readonly property bool inLandscapeStage: themeHub.settingsOpen || flipProgress > 0.001 || flipping || flipRingAnim.running || settingsAnimating

        property real powerShiftX: powerMenuOpen ? Math.round(railPad * 0.4) : railPad
        Behavior on powerShiftX { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
        readonly property real portStageX: portWinX + powerShiftX
        readonly property real portOx: -phonePose.minX + phonePose.pad
        readonly property real portOy: -phonePose.minY + phonePose.pad
        readonly property real portCenterX: portStageX + 4 + portOx * fitScale
        readonly property real portCenterY: portWinY + headroom + 4 + stageLift + portOy * fitScale
        readonly property real landCenterX: themeHub.screenW * 0.5
        readonly property real landCenterY: themeHub.screenH * 0.5
        readonly property real curCenterX: portCenterX + (landCenterX - portCenterX) * flipProgress
        readonly property real curCenterY: portCenterY + (landCenterY - portCenterY) * flipProgress
        readonly property real curQuickScale: fmQuickScale(flipProgress, fitScale, landScale, flipDip)
        readonly property real curQuickAlpha: fmQuickAlpha(flipProgress)
        readonly property real curSettingsAlpha: sAlpha * fmSettingsAlpha(flipProgress)
        readonly property real curLandScale: (curQuickScale / 1.16) * (landPopFrom + (1.0 - landPopFrom) * sPop)
        readonly property real curYaw: poseYaw + (landYaw - poseYaw) * flipProgress
        readonly property real curPitch: posePitch + (landPitch - posePitch) * flipProgress
        readonly property real wobRoll: topBarWindow.phoneMode ? flipWob : 0.0
        readonly property real wobPitch: topBarWindow.phoneMode ? (flipWob * 0.5) : 0.0

        readonly property var liveBase: pmBaseFor(
            faceW, faceH, thickness,
            curYaw + stageTilt * tiltYaw,
            curPitch + stageTilt * tiltPitch + wobPitch,
            stageTilt * tiltRoll - 90.0 * flipProgress + wobRoll,
            curPersp,
            phonePose
        )

        property real stageLift: hiddenLift
        property real stageTilt: 1.0
        property real exitPeak: 0
        property int exitPeakMs: 130
        readonly property bool animating: enterAnim.running || exitAnim.running
        readonly property bool panelWanted: topBarWindow.quickPanelOpen && !topBarWindow.fullscreenActive
        readonly property bool settingsWanted: themeHub.settingsOpen && !topBarWindow.fullscreenActive

        property double openedAt: 0
        property bool pickingFile: false
        property bool powerMenuOpen: false
        property string bottomTab: "notifications" // "notifications" | "display"
        property string subDialog: ""              // "" | "wifi" | "bt"
        property int selectedMonitorIdx: 0

        // Single persistent full-screen overlay window: zero Win32 resize/jump during Portrait <-> Landscape flip
        x: 0
        y: 0
        width: themeHub.screenW
        height: themeHub.screenH

        mask: (panelWanted || settingsWanted || stageLift < hiddenLift || inLandscapeStage || exitAnim.running || settingsExitAnim.running)
            ? null
            : [
                {
                    x: 0,
                    y: 0,
                    width: 1,
                    height: 1
                }
              ]

        onVisibleChanged: {
            SystemControl.setNetSpeedActive(visible)
        }

        onWindowDeactivated: {
            if (pickingFile)
                return
            if ((Date.now() - openedAt) < 250)
                return
            topBarWindow.quickPanelClosedAt = Date.now()
            topBarWindow.quickPanelOpen = false
            if (themeHub.settingsOpen)
                themeHub.settingsOpen = false
        }

        function turnTo(targetFlip) {
            flipRingAnim.stop()
            flipAnim.stop()
            flipTarget = targetFlip
            flipPrepTimer.ticks = 0
            flipPrepTimer.restart()
        }

        onSettingsWantedChanged: {
            if (settingsWanted) {
                settingsExitAnim.stop()
                flipPrepTimer.stop()
                flipAnim.stop()
                flipRingAnim.stop()
                flipWob = 0.0
                powerMenuOpen = false
                subDialog = ""
                openedAt = Date.now()
                AudioService.refreshSessions()
                AudioService.refreshOutputDevices()
                SystemControl.refresh()
                SystemControl.refreshWifi()
                SystemControl.refreshBluetooth()
                NotificationService.refresh()
                WeatherService.refresh()
                const wasQuickOpen = topBarWindow.quickPanelOpen && stageLift < enterFrom * 0.55
                settingsOpenedFromQuick = wasQuickOpen
                if (wasQuickOpen) {
                    standaloneSettings = false
                    enterAnim.stop()
                    exitAnim.stop()
                    stageLift = 0
                    stageTilt = 0
                    sPop = 1.0
                    sAlpha = 1.0
                    sTilt = 0.0
                    turnTo(1.0)
                } else {
                    standaloneSettings = true
                    topBarWindow.quickPanelOpen = false
                    stageLift = hiddenLift
                    flipProgress = 1.0
                    sPop = 0.0
                    sTilt = 1.0
                    sAlpha = 0.0
                    settingsEnterAnim.restart()
                }
                focusActivate()
                qpKeyCatcher.forceActiveFocus()
            } else {
                flipPrepTimer.stop()
                flipAnim.stop()
                flipRingAnim.stop()
                settingsEnterAnim.stop()
                if (topBarWindow.fullscreenActive) {
                    themeHub.settingsOpen = false
                    topBarWindow.quickPanelOpen = false
                    flipProgress = 0.0
                    flipWob = 0.0
                    sPop = 1.0
                    sAlpha = 1.0
                    sTilt = 0.0
                    standaloneSettings = false
                    settingsOpenedFromQuick = false
                    stageLift = hiddenLift
                    return
                }
                if (settingsOpenedFromQuick && topBarWindow.quickPanelOpen) {
                    standaloneSettings = false
                    openedAt = Date.now()
                    sPop = 1.0
                    sAlpha = 1.0
                    sTilt = 0.0
                    stageLift = 0
                    stageTilt = 0
                    turnTo(0.0)
                    focusActivate()
                    qpKeyCatcher.forceActiveFocus()
                } else {
                    flipPrepTimer.stop()
                    flipAnim.stop()
                    flipRingAnim.stop()
                    if (flipProgress > 0.5) {
                        flipProgress = 1.0
                        settingsExitAnim.restart()
                    } else {
                        flipProgress = 0.0
                        flipWob = 0.0
                        settingsOpenedFromQuick = false
                        standaloneSettings = false
                        if (!panelWanted) {
                            stageLift = hiddenLift
                            stageTilt = 1.0
                        }
                    }
                }
            }
        }

        onPanelWantedChanged: {
            if (panelWanted) {
                exitAnim.stop()
                openedAt = Date.now()
                powerMenuOpen = false
                subDialog = ""
                AudioService.refreshSessions()
                AudioService.refreshOutputDevices()
                SystemControl.refresh()
                SystemControl.refreshWifi()
                SystemControl.refreshBluetooth()
                NotificationService.refresh()
                if (themeHub.settingsOpen)
                    return
                standaloneSettings = false
                if (stageLift > enterFrom)
                    stageLift = enterFrom
                enterAnim.restart()
                focusActivate()
                qpKeyCatcher.forceActiveFocus()
            } else {
                enterAnim.stop()
                powerMenuOpen = false
                subDialog = ""
                if (topBarWindow.fullscreenActive) {
                    topBarWindow.quickPanelOpen = false
                    stageLift = hiddenLift
                    stageTilt = 1.0
                    return
                }
                if (themeHub.settingsOpen)
                    return
                flipPrepTimer.stop()
                flipAnim.stop()
                flipRingAnim.stop()
                flipProgress = 0.0
                flipWob = 0.0
                settingsOpenedFromQuick = false
                standaloneSettings = false
                const rising = stageLift > 20
                exitPeak = rising ? stageLift : -bounce * 0.7
                exitPeakMs = rising ? 1 : 130
                exitAnim.restart()
            }
        }

        Timer {
            id: flipPrepTimer
            interval: 16
            repeat: true
            property int ticks: 0
            onTriggered: {
                ticks++
                if (ticks < 2)
                    return
                stop()
                quickPanelWindow.ringSign = quickPanelWindow.flipTarget > 0.5 ? -1.0 : 1.0
                flipAnim.to = quickPanelWindow.flipTarget
                flipAnim.restart()
                flipRingAnim.restart()
            }
        }

        SequentialAnimation {
            id: flipRingAnim
            PauseAnimation {
                duration: Math.round(quickPanelWindow.flipMs * 0.62)
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "flipWob"
                to: quickPanelWindow.ringSign * quickPanelWindow.flipWobble
                duration: Math.round(quickPanelWindow.flipRingMs * 0.42)
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "flipWob"
                to: -quickPanelWindow.ringSign * quickPanelWindow.flipWobble * 0.1
                duration: Math.round(quickPanelWindow.flipRingMs * 0.38)
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "flipWob"
                to: 0.0
                duration: Math.round(quickPanelWindow.flipRingMs * 0.2)
                easing.type: Easing.InOutSine
            }
        }

        NumberAnimation {
            id: flipAnim
            target: quickPanelWindow
            property: "flipProgress"
            duration: quickPanelWindow.flipMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.30, 0.0, 0.20, 1.0, 1.0, 1.0]
            onFinished: {
                if (!themeHub.settingsOpen && quickPanelWindow.flipProgress < 0.05) {
                    quickPanelWindow.flipProgress = 0.0
                    quickPanelWindow.settingsOpenedFromQuick = false
                    quickPanelWindow.standaloneSettings = false
                    if (quickPanelWindow.panelWanted) {
                        quickPanelWindow.openedAt = Date.now()
                        quickPanelWindow.focusActivate()
                        qpKeyCatcher.forceActiveFocus()
                    }
                } else if (themeHub.settingsOpen) {
                    quickPanelWindow.focusActivate()
                    qpKeyCatcher.forceActiveFocus()
                }
            }
        }

        ParallelAnimation {
            id: settingsEnterAnim
            NumberAnimation {
                target: quickPanelWindow
                property: "sPop"
                to: 1.0
                duration: 560
                easing.type: Easing.OutBack
                easing.overshoot: 1.5
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "sTilt"
                to: 0.0
                duration: 900
                easing.type: Easing.OutElastic
                easing.amplitude: 1.0
                easing.period: 0.45
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "sAlpha"
                to: 1.0
                duration: 140
                easing.type: Easing.OutQuad
            }
        }

        ParallelAnimation {
            id: settingsExitAnim
            onFinished: {
                if (!themeHub.settingsOpen) {
                    quickPanelWindow.flipProgress = 0.0
                    quickPanelWindow.flipWob = 0.0
                    quickPanelWindow.sPop = 1.0
                    quickPanelWindow.sAlpha = 1.0
                    quickPanelWindow.sTilt = 0.0
                    quickPanelWindow.settingsOpenedFromQuick = false
                    quickPanelWindow.standaloneSettings = false
                    if (!quickPanelWindow.panelWanted) {
                        quickPanelWindow.stageLift = quickPanelWindow.hiddenLift
                        quickPanelWindow.stageTilt = 1.0
                    }
                }
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "sPop"
                to: 0.0
                duration: 340
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "sAlpha"
                to: 0.0
                duration: 290
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "sTilt"
                to: 0.8
                duration: 340
                easing.type: Easing.InOutQuad
            }
        }

        ParallelAnimation {
            id: enterAnim
            SequentialAnimation {
                NumberAnimation {
                    target: quickPanelWindow
                    property: "stageLift"
                    to: -quickPanelWindow.bounce
                    duration: 340
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: quickPanelWindow
                    property: "stageLift"
                    to: 0
                    duration: 170
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: quickPanelWindow
                    property: "stageLift"
                    to: -quickPanelWindow.bounce * 0.14
                    duration: 110
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: quickPanelWindow
                    property: "stageLift"
                    to: 0
                    duration: 110
                    easing.type: Easing.InQuad
                }
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "stageTilt"
                to: 0
                duration: 820
                easing.type: Easing.OutElastic
                easing.amplitude: 1.0
                easing.period: 0.4
            }
        }

        ParallelAnimation {
            id: exitAnim
            SequentialAnimation {
                NumberAnimation {
                    target: quickPanelWindow
                    property: "stageLift"
                    to: quickPanelWindow.exitPeak
                    duration: quickPanelWindow.exitPeakMs
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: quickPanelWindow
                    property: "stageLift"
                    to: quickPanelWindow.hiddenLift
                    duration: 340
                    easing.type: Easing.InCubic
                }
            }
            NumberAnimation {
                target: quickPanelWindow
                property: "stageTilt"
                to: 1.0
                duration: 440
                easing.type: Easing.InQuad
            }
        }

        Timer {
            id: outsideClickWatcher
            interval: 20
            repeat: true
            running: quickPanelWindow.panelWanted && !quickPanelWindow.pickingFile && !quickPanelWindow.inLandscapeStage
            onTriggered: {
                if ((Date.now() - quickPanelWindow.openedAt) > 220 && quickPanelWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.quickPanelClosedAt = Date.now()
                    topBarWindow.quickPanelOpen = false
                }
            }
        }

        Item {
            id: qpKeyCatcher
            focus: quickPanelWindow.panelWanted || quickPanelWindow.settingsWanted
            Keys.onEscapePressed: event => {
                if (themeHub.settingsOpen) {
                    if (themeHub.settingsSection !== "") {
                        themeHub.settingsSection = ""
                    } else {
                        themeHub.settingsOpen = false
                    }
                } else if (quickPanelWindow.subDialog !== "") {
                    quickPanelWindow.subDialog = ""
                } else if (quickPanelWindow.powerMenuOpen) {
                    quickPanelWindow.powerMenuOpen = false
                } else {
                    topBarWindow.quickPanelClosedAt = Date.now()
                    topBarWindow.quickPanelOpen = false
                }
                event.accepted = true
            }
        }

        // Power Menu Pill Rail (pops out beside the phone's side Power button)
        Item {
            id: powerRail
            x: quickPanelWindow.portStageX + quickPanelWindow.phoneBoxW + 4
            y: quickPanelWindow.portWinY + quickPanelWindow.headroom + Math.round(138 * quickPanelWindow.fitScale / 0.46) + quickPanelWindow.stageLift
            width: 64
            height: 332
            visible: quickPanelWindow.powerMenuOpen && !quickPanelWindow.inLandscapeStage
            opacity: quickPanelWindow.powerMenuOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            z: 20

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Repeater {
                    model: [
                        { label: "Lock",     glyph: "🔒", col: "#E0F2FE", act: "lock" },
                        { label: "Sleep",    glyph: "🌙", col: "#EDE9FE", act: "sleep" },
                        { label: "Hibern.",  glyph: "❄",  col: "#E0E7FF", act: "hibernate" },
                        { label: "Sign Out", glyph: "↪",  col: "#FEF3C7", act: "signout" },
                        { label: "Restart",  glyph: "↻",  col: "#FFEDD5", act: "restart" },
                        { label: "Shut Dn",  glyph: "⏻",  col: "#FFE4E6", act: "shutdown" }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: 58
                        height: 46
                        Rectangle {
                            x: 3; y: 3; width: 54; height: 42; radius: 14; color: "#1A1B2E"
                        }
                        Rectangle {
                            x: pBtnMa.pressed ? 2 : 0
                            y: pBtnMa.pressed ? 2 : 0
                            width: 54; height: 42; radius: 14
                            color: pBtnMa.containsMouse ? themeHub.accentB : modelData.col
                            border.width: 2.5; border.color: "#1A1B2E"
                            Column {
                                anchors.centerIn: parent; spacing: 0
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.glyph; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.pixelSize: 9; font.weight: Font.Black; color: "#1A1B2E" }
                            }
                            MouseArea {
                                id: pBtnMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    topBarWindow.quickPanelOpen = false
                                    if (modelData.act === "lock") SystemControl.lockScreen()
                                    else if (modelData.act === "sleep") SystemControl.sleepPc()
                                    else if (modelData.act === "hibernate") SystemControl.hibernatePc()
                                    else if (modelData.act === "signout") SystemControl.signOut()
                                    else if (modelData.act === "restart") SystemControl.restartPc()
                                    else if (modelData.act === "shutdown") SystemControl.shutdownPc()
                                }
                            }
                        }
                    }
                }
            }
        }

        // Phone Chassis Stage (slides up from bottom with SekaiPop spring & cross-fades cleanly during FlipMath turn)
        Item {
            id: phoneStage
            visible: !quickPanelWindow.standaloneSettings && quickPanelWindow.curQuickAlpha > 0.001 && (quickPanelWindow.panelWanted || quickPanelWindow.stageLift < quickPanelWindow.hiddenLift || quickPanelWindow.flipProgress > 0.001)
            opacity: quickPanelWindow.curQuickAlpha
            enabled: !themeHub.settingsOpen
            anchors.fill: parent

            // Full-screen transparent backdrop dismisses Portrait Phone on 1st empty-zone click
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    topBarWindow.quickPanelClosedAt = Date.now()
                    topBarWindow.quickPanelOpen = false
                    if (themeHub.settingsOpen)
                        themeHub.settingsOpen = false
                }
            }

            // Scaled 2.5D Phone Body (654x1214 design space scaled by curQuickScale around center pivot)
            Item {
                id: phoneRoot
                x: quickPanelWindow.curCenterX - quickPanelWindow.portOx
                y: quickPanelWindow.curCenterY - quickPanelWindow.portOy
                width: quickPanelWindow.phonePose.w
                height: quickPanelWindow.phonePose.h
                transform: Scale {
                    origin.x: quickPanelWindow.portOx; origin.y: quickPanelWindow.portOy
                    xScale: quickPanelWindow.curQuickScale
                    yScale: quickPanelWindow.curQuickScale
                }

                // Soft grounded shadow behind phone
                Rectangle {
                    visible: topBarWindow.phoneMode
                    x: 12; y: 18
                    width: quickPanelWindow.faceW
                    height: quickPanelWindow.faceH
                    radius: quickPanelWindow.cornerR
                    color: Qt.rgba(0.06, 0.07, 0.14, 0.24)
                    transform: Matrix4x4 {
                        matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmZOffset(quickPanelWindow.liveBase, -quickPanelWindow.thickness - 4))
                    }
                }

                // 1) Solid 3D Extruded Side Wall (38 depth slices from back to front)
                Repeater {
                    model: topBarWindow.phoneMode ? 38 : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property real depth: (38 - index) / 38.0
                        width: quickPanelWindow.faceW
                        height: quickPanelWindow.faceH
                        radius: quickPanelWindow.cornerR
                        antialiasing: depth < 0.22
                        color: {
                            if (depth < 0.08) return "#8E92B8"
                            if (depth < 0.22) return "#5D6184"
                            if (depth < 0.55) return "#3D405B"
                            return "#24263A"
                        }
                        transform: Matrix4x4 {
                            matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmZOffset(quickPanelWindow.liveBase, -depth * quickPanelWindow.thickness))
                        }
                    }
                }

                // 2) Right-Edge Side Buttons (Interactive Power Button + Broad Volume Rocker)
                Item {
                    visible: topBarWindow.phoneMode
                    width: quickPanelWindow.thickness
                    height: quickPanelWindow.faceH
                    transform: Matrix4x4 {
                        matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmMul(quickPanelWindow.liveBase, [
                            0, 0, 0, quickPanelWindow.faceW,
                            0, 1, 0, 0,
                            -1, 0, 0, 0,
                            0, 0, 0, 1
                        ]))
                    }

                    // Lower Volume Rocker
                    Rectangle {
                        x: quickPanelWindow.thickness * 0.24
                        y: 704
                        width: quickPanelWindow.thickness * 0.44
                        height: 168
                        radius: width * 0.5
                        color: "#5D6184"
                        border.width: 2
                        border.color: "#1A1B2E"
                        antialiasing: true
                    }
                }

                // Protruding 3D Power Button Stack (animated inward press!)
                Repeater {
                    model: topBarWindow.phoneMode ? 6 : 0
                    delegate: Item {
                        id: pwrBtnSlice
                        required property int index
                        readonly property bool isCap: index === 5
                        readonly property real stick: quickPanelWindow.powerMenuOpen ? 10 : 16
                        width: quickPanelWindow.thickness
                        height: quickPanelWindow.faceH
                        transform: Matrix4x4 {
                            matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmMul(quickPanelWindow.liveBase, [
                                0, 0, 0, quickPanelWindow.faceW + (index + 1) * pwrBtnSlice.stick / 6.0,
                                0, 1, 0, 0,
                                -1, 0, 0, 0,
                                0, 0, 0, 1
                            ]))
                        }
                        Rectangle {
                            x: quickPanelWindow.thickness * 0.32
                            y: 338
                            width: quickPanelWindow.thickness * 0.28
                            height: 150
                            radius: width * 0.5
                            color: !pwrBtnSlice.isCap ? "#3D405B" : (pwrSideMa.pressed ? themeHub.accentA : (quickPanelWindow.powerMenuOpen || pwrSideMa.containsMouse ? themeHub.accentB : "#9DA3C9"))
                            border.width: pwrBtnSlice.isCap ? 2 : 0
                            border.color: "#1A1B2E"
                            antialiasing: true

                            MouseArea {
                                id: pwrSideMa
                                enabled: pwrBtnSlice.isCap
                                anchors.fill: parent
                                anchors.margins: -14
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: quickPanelWindow.powerMenuOpen = !quickPanelWindow.powerMenuOpen
                            }
                        }
                    }
                }

                // 3) Bottom Edge USB-C Port & Speaker Holes
                Item {
                    visible: topBarWindow.phoneMode
                    width: quickPanelWindow.faceW
                    height: quickPanelWindow.thickness
                    transform: Matrix4x4 {
                        matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmMul(quickPanelWindow.liveBase, [
                            1, 0, 0, 0,
                            0, 0, 0, quickPanelWindow.faceH,
                            0, -1, 0, 0,
                            0, 0, 0, 1
                        ]))
                    }
                    Rectangle {
                        x: quickPanelWindow.faceW * 0.5 - 46
                        y: quickPanelWindow.thickness * 0.5 - quickPanelWindow.thickness * 0.20
                        width: 92; height: quickPanelWindow.thickness * 0.40; radius: height * 0.5
                        color: "#131422"
                    }
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            required property int index
                            width: 22; height: 22; radius: 11
                            x: quickPanelWindow.faceW * 0.5 + 78 + index * 30
                            y: quickPanelWindow.thickness * 0.5 - 11
                            color: "#131422"
                        }
                    }
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 22; height: 22; radius: 11
                            x: quickPanelWindow.faceW * 0.5 - 100 - index * 30
                            y: quickPanelWindow.thickness * 0.5 - 11
                            color: "#131422"
                        }
                    }
                }

                // Flat-mode side Power Tab when 2.5D is off
                Rectangle {
                    visible: !topBarWindow.phoneMode
                    x: quickPanelWindow.faceW - 4
                    y: 338
                    width: 20; height: 150; radius: 8
                    color: quickPanelWindow.powerMenuOpen || flatPwrMa.containsMouse ? themeHub.accentB : "#9DA3C9"
                    border.width: 3; border.color: "#1A1B2E"
                    transform: Matrix4x4 {
                        matrix: quickPanelWindow.toQtMat(quickPanelWindow.liveBase)
                    }
                    MouseArea {
                        id: flatPwrMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: quickPanelWindow.powerMenuOpen = !quickPanelWindow.powerMenuOpen
                    }
                }

                // 4) Front Screen Plane (layered for crisp antialiased tilted rendering)
                Item {
                    id: phoneFrontFace
                    width: quickPanelWindow.faceW
                    height: quickPanelWindow.faceH
                    transform: Matrix4x4 {
                        matrix: quickPanelWindow.toQtMat(quickPanelWindow.liveBase)
                    }
                    layer.enabled: true
                    layer.smooth: true
                    layer.samples: 4
                    layer.textureSize: Qt.size(Math.ceil(width * 1.1), Math.ceil(height * 1.1))

                    // Eat clicks on empty areas of the phone body so backdrop doesn't dismiss it
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {}
                    }

                    // Outer metal rim + specular highlight
                    Rectangle {
                        anchors.fill: parent
                        radius: quickPanelWindow.cornerR
                        color: "#555473"
                        border.width: 3
                        border.color: "#1A1B2E"
                        antialiasing: true
                    }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 3
                        radius: quickPanelWindow.cornerR - 3
                        color: "transparent"
                        border.width: 2; border.color: "#88FFFFFF"
                        antialiasing: true
                    }
                    // Dark glass bezel
                    Rectangle {
                        anchors.fill: parent; anchors.margins: quickPanelWindow.rimW
                        radius: quickPanelWindow.cornerR - quickPanelWindow.rimW
                        color: "#1A1B2E"
                        antialiasing: true
                    }
                    // Inner phone screen background
                    Rectangle {
                        id: phoneScreenBg
                        anchors.fill: parent; anchors.margins: quickPanelWindow.screenInset
                        radius: quickPanelWindow.cornerR - quickPanelWindow.screenInset
                        color: "#F3F6FD"
                        clip: true
                        antialiasing: true
                    }

                    // === SCREEN CONTENT (654 x 1214 design space) ===
                    Item {
                        id: phoneScreenContent
                        anchors.fill: parent

                        // ---- Banner Header Card ----
                        Item {
                            id: qpBannerBox
                            x: 28; y: 28; width: 598; height: 222

                            // Gradient fallback when no banner image is set
                            Rectangle {
                                anchors.fill: parent
                                topLeftRadius: 72; topRightRadius: 72
                                bottomLeftRadius: 42; bottomRightRadius: 42
                                border.width: 3; border.color: "#1A1B2E"
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: themeHub.accentA }
                                    GradientStop { position: 1.0; color: themeHub.accentB }
                                }
                                visible: themeHub.quickPanelBannerUrl === ""
                            }

                            // Rounded-clipped custom banner image via Canvas
                            Canvas {
                                id: qpBannerCanvas
                                anchors.fill: parent
                                visible: themeHub.quickPanelBannerUrl !== ""
                                property string src: themeHub.quickPanelBannerUrl
                                onSrcChanged: {
                                    if (src !== "")
                                        loadImage(src)
                                    requestPaint()
                                }
                                onImageLoaded: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    if (src === "" || !isImageLoaded(src))
                                        return
                                    ctx.save()
                                    ctx.beginPath()
                                    ctx.moveTo(72, 0)
                                    ctx.lineTo(width - 72, 0)
                                    ctx.quadraticCurveTo(width, 0, width, 72)
                                    ctx.lineTo(width, height - 42)
                                    ctx.quadraticCurveTo(width, height, width - 42, height)
                                    ctx.lineTo(42, height)
                                    ctx.quadraticCurveTo(0, height, 0, height - 42)
                                    ctx.lineTo(0, 72)
                                    ctx.quadraticCurveTo(0, 0, 72, 0)
                                    ctx.closePath()
                                    ctx.clip()
                                    ctx.drawImage(src, 0, 0, width, height)
                                    ctx.fillStyle = "rgba(26, 27, 46, 0.28)"
                                    ctx.fillRect(0, 0, width, height)
                                    ctx.restore()
                                }
                            }

                            // Click banner to pick custom wallpaper
                            MouseArea {
                                id: qpBannerMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    quickPanelWindow.pickingFile = true
                                    const url = SystemControl.pickImageFile("Select Phone Banner Image")
                                    quickPanelWindow.pickingFile = false
                                    if (url !== "")
                                        themeHub.setQuickPanelBanner(url)
                                    quickPanelWindow.focusActivate()
                                }
                            }

                            // Clock + Date (Top-Left on banner)
                            Column {
                                x: 32; y: 20; spacing: -2
                                Text {
                                    text: topBarWindow.timeText
                                    font.family: "Segoe UI"
                                    font.pixelSize: 28
                                    font.weight: Font.Black
                                    color: themeHub.quickPanelBannerUrl !== "" ? "#FFFFFF" : "#1A1B2E"
                                    style: themeHub.quickPanelBannerUrl !== "" ? Text.Outline : Text.Normal
                                    styleColor: "#1A1B2E"
                                }
                                Text {
                                    text: topBarWindow.dateText
                                    font.family: "Segoe UI"
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    color: themeHub.quickPanelBannerUrl !== "" ? "#FFFFFF" : "#1A1B2E"
                                    style: themeHub.quickPanelBannerUrl !== "" ? Text.Outline : Text.Normal
                                    styleColor: "#1A1B2E"
                                }
                            }

                            // Live Net Speed (Top-Right on banner)
                            Column {
                                anchors.right: parent.right; anchors.rightMargin: 30; y: 22; spacing: 0
                                Text {
                                    anchors.right: parent.right
                                    text: "▼ " + quickPanelWindow.formatRate(SystemControl.downloadBps)
                                    font.family: "Consolas"
                                    font.pixelSize: 17
                                    font.weight: Font.Black
                                    color: themeHub.quickPanelBannerUrl !== "" ? "#FFFFFF" : "#1A1B2E"
                                    style: themeHub.quickPanelBannerUrl !== "" ? Text.Outline : Text.Normal
                                    styleColor: "#1A1B2E"
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: "▲ " + quickPanelWindow.formatRate(SystemControl.uploadBps)
                                    font.family: "Consolas"
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    color: themeHub.quickPanelBannerUrl !== "" ? "#E2E8F0" : "#1A1B2E"
                                    style: themeHub.quickPanelBannerUrl !== "" ? Text.Outline : Text.Normal
                                    styleColor: "#1A1B2E"
                                }
                            }

                            // Banner Hover Change / Reset pills
                            Row {
                                visible: qpBannerMa.containsMouse || qpBannerResetMa.containsMouse
                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.rightMargin: 20; anchors.bottomMargin: 14
                                spacing: 8
                                Rectangle {
                                    width: 90; height: 34; radius: 17
                                    color: "#FFFFFF"; border.width: 2.5; border.color: "#1A1B2E"
                                    Text { anchors.centerIn: parent; text: "Banner"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                }
                                Rectangle {
                                    visible: themeHub.quickPanelBannerUrl !== ""
                                    width: 34; height: 34; radius: 17
                                    color: "#FFE4E6"; border.width: 2.5; border.color: "#1A1B2E"
                                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 18; font.weight: Font.Black; color: "#D92652" }
                                    MouseArea {
                                        id: qpBannerResetMa
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: themeHub.setQuickPanelBanner("")
                                    }
                                }
                            }
                        }

                        // ---- Circular Avatar overlapping bottom-left of banner ----
                        Item {
                            id: qpAvatarBox
                            x: 58; y: 182; width: 116; height: 116

                            Rectangle {
                                anchors.fill: parent; radius: 58
                                color: themeHub.accentB
                                border.width: 4; border.color: "#1A1B2E"
                            }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 4; radius: 54
                                color: "transparent"
                                border.width: 4; border.color: "#FFFFFF"
                                z: 5
                            }

                            Text {
                                visible: themeHub.quickPanelAvatarUrl === ""
                                anchors.centerIn: parent
                                text: (WindowTracker.userName || "Y").charAt(0).toUpperCase()
                                font.family: "Segoe UI"
                                font.pixelSize: 44
                                font.weight: Font.Black
                                color: "#1A1B2E"
                            }

                            Canvas {
                                id: qpAvatarCanvas
                                anchors.fill: parent; anchors.margins: 6
                                visible: themeHub.quickPanelAvatarUrl !== ""
                                property string src: themeHub.quickPanelAvatarUrl
                                onSrcChanged: {
                                    if (src !== "")
                                        loadImage(src)
                                    requestPaint()
                                }
                                onImageLoaded: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    if (src === "" || !isImageLoaded(src))
                                        return
                                    ctx.save()
                                    ctx.beginPath()
                                    ctx.arc(width * 0.5, height * 0.5, width * 0.5, 0, Math.PI * 2)
                                    ctx.clip()
                                    ctx.drawImage(src, 0, 0, width, height)
                                    ctx.restore()
                                }
                            }

                            MouseArea {
                                id: qpAvatarMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    quickPanelWindow.pickingFile = true
                                    const url = SystemControl.pickImageFile("Select Phone Avatar Image")
                                    quickPanelWindow.pickingFile = false
                                    if (url !== "")
                                        themeHub.setQuickPanelAvatar(url)
                                    quickPanelWindow.focusActivate()
                                }
                            }

                            Rectangle {
                                visible: themeHub.quickPanelAvatarUrl !== "" && (qpAvatarMa.containsMouse || qpAvResetMa.containsMouse)
                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                width: 32; height: 32; radius: 16
                                color: "#FFE4E6"; border.width: 2.5; border.color: "#1A1B2E"; z: 8
                                Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 16; font.weight: Font.Black; color: "#D92652" }
                                MouseArea {
                                    id: qpAvResetMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: themeHub.setQuickPanelAvatar("")
                                }
                            }
                        }

                        // ---- User@Host Identity ----
                        Text {
                            x: 58; y: 304; width: 256; elide: Text.ElideRight
                            text: (WindowTracker.userName || "user") + "@" + (WindowTracker.machineName || "pc")
                            font.family: "Segoe UI"
                            font.pixelSize: 20
                            font.weight: Font.Black
                            color: "#1A1B2E"
                        }

                        // ---- 3 Header Square Pill Action Buttons (Settings / Refresh / Edit Desktop) ----
                        Row {
                            x: 326; y: 262; spacing: 14
                            Repeater {
                                model: [
                                    { label: "Settings", icon: "⚙", act: "settings", active: false },
                                    { label: "Refresh",  icon: "↻", act: "refresh",  active: false },
                                    { label: "Edit",     icon: "✎", act: "edit",     active: themeHub.editMode }
                                ]
                                delegate: Item {
                                    required property var modelData
                                    width: 84; height: 68
                                    Rectangle { x: 4; y: 3; width: 80; height: 64; radius: 22; color: "#1A1B2E" }
                                    Rectangle {
                                        x: hdrActMa.pressed ? 3 : 0
                                        y: hdrActMa.pressed ? 2 : 0
                                        width: 80; height: 64; radius: 22
                                        color: modelData.active || hdrActMa.containsMouse ? themeHub.accentB : "#FFFFFF"
                                        border.width: 3.5; border.color: "#1A1B2E"
                                        Rectangle {
                                            anchors.fill: parent; anchors.margins: 4; radius: 18
                                            color: "transparent"; border.width: 2; border.color: "#99FFFFFF"
                                        }
                                        Column {
                                            anchors.centerIn: parent; spacing: 0
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; font.pixelSize: 22; font.weight: Font.Black; color: "#1A1B2E" }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                        }
                                        MouseArea {
                                            id: hdrActMa
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.act === "settings") {
                                                    themeHub.openSettings("")
                                                } else if (modelData.act === "refresh") {
                                                    AudioService.refreshSessions()
                                                    AudioService.refreshOutputDevices()
                                                    SystemControl.refresh()
                                                    SystemControl.refreshWifi()
                                                    SystemControl.refreshBluetooth()
                                                } else if (modelData.act === "edit") {
                                                    topBarWindow.quickPanelOpen = false
                                                    themeHub.setEditMode(true)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- 2-Column Toggles & Sliders Container ----
                        Rectangle {
                            id: qpControlsCard
                            x: 36; y: 348; width: 582; height: 422
                            radius: 36
                            color: "#E8EDF7"
                            border.width: 3
                            border.color: "#1A1B2E"

                            Column {
                                x: 16; y: 16; width: parent.width - 32; spacing: 12

                                // Row 1: Network & Bluetooth (2-Column Thick-Bordered Tiles)
                                Row {
                                    width: parent.width; spacing: 14

                                    // Tile 1: Wi-Fi / Network
                                    Item {
                                        id: wifiTile
                                        width: 268; height: 74
                                        readonly property bool isOn: SystemControl.networkType !== "Offline" && (SystemControl.networkType !== "Wi-Fi" || SystemControl.wifiEnabled)
                                        Rectangle { x: wifiTile.isOn ? 5 : 3; y: wifiTile.isOn ? 2 : 1; width: 263; height: 70; radius: 35; color: "#1A1B2E" }
                                        Rectangle {
                                            x: wifiTileMa.pressed ? 3 : 0
                                            y: wifiTileMa.pressed ? 2 : 0
                                            width: 263; height: 70; radius: 35
                                            border.width: wifiTile.isOn ? 4.5 : 3; border.color: "#1A1B2E"
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: wifiTile.isOn ? themeHub.accentB : "#FFFFFF" }
                                                GradientStop { position: 1.0; color: wifiTile.isOn ? themeHub.accentA : "#FFFFFF" }
                                            }
                                            Rectangle {
                                                visible: wifiTile.isOn
                                                anchors.fill: parent; anchors.margins: 4; radius: 31
                                                color: "transparent"; border.width: 4; border.color: "#AAFFFFFF"
                                            }
                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 18
                                                anchors.right: wifiMoreBtn.left; anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 10
                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 26; height: 26; sourceSize.width: 48; sourceSize.height: 48; smooth: true
                                                    source: SystemControl.networkType === "Wi-Fi" ? "qrc:/qml/icons/wifi-dark.svg" : "qrc:/qml/icons/network-dark.svg"
                                                }
                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 36
                                                    Text { text: SystemControl.networkType === "Offline" ? "Wi-Fi" : SystemControl.networkType; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text { width: parent.width; elide: Text.ElideRight; text: SystemControl.localIp || (SystemControl.wifiEnabled ? "Connected" : "OFF"); font.pixelSize: 13; font.weight: Font.Bold; color: "#331A1B2E" }
                                                }
                                            }
                                            MouseArea {
                                                id: wifiTileMa
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        SystemControl.refreshWifi()
                                                        quickPanelWindow.subDialog = "wifi"
                                                    } else {
                                                        SystemControl.toggleWifi()
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                id: wifiMoreBtn
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 28; height: 28; radius: 14
                                                color: "#66FFFFFF"; border.width: 2; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "▾"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { SystemControl.refreshWifi(); quickPanelWindow.subDialog = "wifi" }
                                                }
                                            }
                                        }
                                    }

                                    // Tile 2: Bluetooth
                                    Item {
                                        id: btTile
                                        width: 268; height: 74
                                        readonly property bool isOn: SystemControl.bluetoothSupported && SystemControl.bluetoothEnabled
                                        Rectangle { x: btTile.isOn ? 5 : 3; y: btTile.isOn ? 2 : 1; width: 263; height: 70; radius: 35; color: "#1A1B2E" }
                                        Rectangle {
                                            x: btTileMa.pressed ? 3 : 0
                                            y: btTileMa.pressed ? 2 : 0
                                            width: 263; height: 70; radius: 35
                                            border.width: btTile.isOn ? 4.5 : 3; border.color: "#1A1B2E"
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: btTile.isOn ? themeHub.accentB : "#FFFFFF" }
                                                GradientStop { position: 1.0; color: btTile.isOn ? themeHub.accentA : "#FFFFFF" }
                                            }
                                            Rectangle {
                                                visible: btTile.isOn
                                                anchors.fill: parent; anchors.margins: 4; radius: 31
                                                color: "transparent"; border.width: 4; border.color: "#AAFFFFFF"
                                            }
                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 18
                                                anchors.right: btMoreBtn.left; anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 10
                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 24; height: 24; sourceSize.width: 48; sourceSize.height: 48; smooth: true
                                                    source: "qrc:/qml/icons/bt-dark.svg"
                                                }
                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 34
                                                    Text { text: "Bluetooth"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text {
                                                        width: parent.width; elide: Text.ElideRight
                                                        text: !SystemControl.bluetoothSupported ? "Unavailable" : (btTile.isOn ? ("ON · " + SystemControl.bluetoothDevices.length + " dev") : "OFF")
                                                        font.pixelSize: 13; font.weight: Font.Bold; color: "#331A1B2E"
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                id: btTileMa
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => {
                                                    if (mouse.button === Qt.RightButton) {
                                                        SystemControl.refreshBluetooth()
                                                        quickPanelWindow.subDialog = "bt"
                                                    } else if (SystemControl.bluetoothSupported) {
                                                        SystemControl.toggleBluetooth()
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                id: btMoreBtn
                                                anchors.right: parent.right; anchors.rightMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 28; height: 28; radius: 14
                                                color: "#66FFFFFF"; border.width: 2; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "▾"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { SystemControl.refreshBluetooth(); quickPanelWindow.subDialog = "bt" }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Row 2: Dark Mode & Keep Awake (2-Column Thick-Bordered Tiles)
                                Row {
                                    width: parent.width; spacing: 14

                                    // Tile 3: Dark Mode
                                    Item {
                                        id: dmTile
                                        width: 268; height: 74
                                        readonly property bool isOn: SystemControl.darkMode
                                        Rectangle { x: dmTile.isOn ? 5 : 3; y: dmTile.isOn ? 2 : 1; width: 263; height: 70; radius: 35; color: "#1A1B2E" }
                                        Rectangle {
                                            x: dmTileMa.pressed ? 3 : 0
                                            y: dmTileMa.pressed ? 2 : 0
                                            width: 263; height: 70; radius: 35
                                            border.width: dmTile.isOn ? 4.5 : 3; border.color: "#1A1B2E"
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: dmTile.isOn ? themeHub.accentB : "#FFFFFF" }
                                                GradientStop { position: 1.0; color: dmTile.isOn ? themeHub.accentA : "#FFFFFF" }
                                            }
                                            Rectangle {
                                                visible: dmTile.isOn
                                                anchors.fill: parent; anchors.margins: 4; radius: 31
                                                color: "transparent"; border.width: 4; border.color: "#AAFFFFFF"
                                            }
                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 18
                                                anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 24; height: 24; sourceSize.width: 48; sourceSize.height: 48; smooth: true
                                                    source: dmTile.isOn ? "qrc:/qml/icons/moon-dark.svg" : "qrc:/qml/icons/sun-dark.svg"
                                                }
                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text { text: "Theme"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text { text: dmTile.isOn ? "Dark Mode" : "Light Mode"; font.pixelSize: 13; font.weight: Font.Bold; color: "#331A1B2E" }
                                                }
                                            }
                                            MouseArea {
                                                id: dmTileMa
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: SystemControl.toggleDarkMode()
                                            }
                                        }
                                    }

                                    // Tile 4: Keep Awake
                                    Item {
                                        id: kaTile
                                        width: 268; height: 74
                                        readonly property bool isOn: SystemControl.keepAwake
                                        Rectangle { x: kaTile.isOn ? 5 : 3; y: kaTile.isOn ? 2 : 1; width: 263; height: 70; radius: 35; color: "#1A1B2E" }
                                        Rectangle {
                                            x: kaTileMa.pressed ? 3 : 0
                                            y: kaTileMa.pressed ? 2 : 0
                                            width: 263; height: 70; radius: 35
                                            border.width: kaTile.isOn ? 4.5 : 3; border.color: "#1A1B2E"
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: kaTile.isOn ? themeHub.accentB : "#FFFFFF" }
                                                GradientStop { position: 1.0; color: kaTile.isOn ? themeHub.accentA : "#FFFFFF" }
                                            }
                                            Rectangle {
                                                visible: kaTile.isOn
                                                anchors.fill: parent; anchors.margins: 4; radius: 31
                                                color: "transparent"; border.width: 4; border.color: "#AAFFFFFF"
                                            }
                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 18
                                                anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: "☕"; font.pixelSize: 24; color: "#1A1B2E" }
                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text { text: "Keep Awake"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text { text: kaTile.isOn ? "Active (No Sleep)" : "OFF"; font.pixelSize: 13; font.weight: Font.Bold; color: "#331A1B2E" }
                                                }
                                            }
                                            MouseArea {
                                                id: kaTileMa
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: SystemControl.toggleKeepAwake()
                                            }
                                        }
                                    }
                                }

                                // Row 3: Microphone & Speaker Chunky Pill Sliders (2-Column)
                                Row {
                                    width: parent.width; spacing: 14

                                    // Microphone Slider
                                    Item {
                                        id: micSlider
                                        width: 268; height: 104
                                        readonly property bool active: AudioService.micSupported && !AudioService.micMuted
                                        Rectangle { x: micSlider.active ? 4 : 3; y: 2; width: 263; height: 68; radius: 34; color: "#1A1B2E" }
                                        Rectangle {
                                            x: micCapMa.pressed ? 2 : 0; y: micCapMa.pressed ? 2 : 0
                                            width: 263; height: 68; radius: 34
                                            border.width: micSlider.active ? 4.5 : 3; border.color: "#1A1B2E"
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: micSlider.active ? themeHub.accentB : "#FFFFFF" }
                                                GradientStop { position: 1.0; color: micSlider.active ? themeHub.accentA : "#FFFFFF" }
                                            }
                                            Rectangle {
                                                visible: micSlider.active
                                                anchors.fill: parent; anchors.margins: 4; radius: 30
                                                color: "transparent"; border.width: 3.5; border.color: "#AAFFFFFF"
                                            }
                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 18
                                                anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: AudioService.micMuted ? "🔇" : "🎙"; font.pixelSize: 22; color: "#1A1B2E" }
                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text { text: "Microphone"; font.pixelSize: 17; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text {
                                                        text: !AudioService.micSupported ? "No Mic" : (AudioService.micMuted ? "Muted" : (AudioService.micVolume + "%"))
                                                        font.pixelSize: 13; font.weight: Font.Black; color: "#331A1B2E"
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                id: micCapMa
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: if (AudioService.micSupported) AudioService.toggleMicMute()
                                            }
                                        }
                                        // Pill track
                                        Item {
                                            x: 4; y: 76; width: 256; height: 24
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width; height: 18; radius: 9
                                                color: "#FFFFFF"; border.width: 3; border.color: "#1A1B2E"
                                                Rectangle {
                                                    x: 3; y: 3; height: 12; radius: 6
                                                    width: Math.max(0, (parent.width - 6) * (AudioService.micVolume / 100.0))
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: themeHub.accentB }
                                                        GradientStop { position: 1.0; color: themeHub.accentA }
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                enabled: AudioService.micSupported
                                                function setMic(mx) {
                                                    AudioService.setMicVolume(Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100))
                                                }
                                                onPressed: mouse => setMic(mouse.x)
                                                onPositionChanged: mouse => { if (pressed) setMic(mouse.x) }
                                            }
                                        }
                                    }

                                    // Speaker Slider (left-click mutes; standalone mixer lives in TopBar volumePopupWindow)
                                    Item {
                                        id: spkSlider
                                        width: 268; height: 104
                                        readonly property bool active: !AudioService.masterMuted
                                        Rectangle { x: spkSlider.active ? 4 : 3; y: 2; width: 263; height: 68; radius: 34; color: "#1A1B2E" }
                                        Rectangle {
                                            x: spkCapMa.pressed ? 2 : 0; y: spkCapMa.pressed ? 2 : 0
                                            width: 263; height: 68; radius: 34
                                            border.width: spkSlider.active ? 4.5 : 3; border.color: "#1A1B2E"
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: spkSlider.active ? themeHub.accentB : "#FFFFFF" }
                                                GradientStop { position: 1.0; color: spkSlider.active ? themeHub.accentA : "#FFFFFF" }
                                            }
                                            Rectangle {
                                                visible: spkSlider.active
                                                anchors.fill: parent; anchors.margins: 4; radius: 30
                                                color: "transparent"; border.width: 3.5; border.color: "#AAFFFFFF"
                                            }
                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 18
                                                anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 24; height: 24; sourceSize.width: 48; sourceSize.height: 48; smooth: true
                                                    source: AudioService.masterMuted ? "qrc:/qml/icons/volume-cross-dark.svg" : "qrc:/qml/icons/volume-loud-dark.svg"
                                                }
                                                Column {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text { text: "Speaker"; font.pixelSize: 17; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text {
                                                        text: AudioService.masterMuted ? "Muted" : (AudioService.masterVolume + "%")
                                                        font.pixelSize: 13; font.weight: Font.Black; color: "#331A1B2E"
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                id: spkCapMa
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: AudioService.toggleMasterMute()
                                            }
                                        }
                                        // Pill track
                                        Item {
                                            x: 4; y: 76; width: 256; height: 24
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width; height: 18; radius: 9
                                                color: "#FFFFFF"; border.width: 3; border.color: "#1A1B2E"
                                                Rectangle {
                                                    x: 3; y: 3; height: 12; radius: 6
                                                    width: Math.max(0, (parent.width - 6) * (AudioService.masterVolume / 100.0))
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: themeHub.accentB }
                                                        GradientStop { position: 1.0; color: themeHub.accentA }
                                                    }
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                function setSpk(mx) {
                                                    AudioService.setMasterVolume(Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100))
                                                }
                                                onPressed: mouse => setSpk(mouse.x)
                                                onPositionChanged: mouse => { if (pressed) setSpk(mouse.x) }
                                            }
                                        }
                                    }
                                }

                                // Row 4: Full-Width Dual-Accent Brightness Bar (supports multi-monitor DDC/CI)
                                Item {
                                    id: brControl
                                    width: parent.width; height: 64
                                    readonly property var monList: SystemControl.monitors || []
                                    readonly property int monIdx: Math.min(quickPanelWindow.selectedMonitorIdx, Math.max(0, brControl.monList.length - 1))
                                    readonly property var curMon: (brControl.monList.length > 0 && brControl.monIdx >= 0) ? brControl.monList[brControl.monIdx] : null
                                    readonly property int curBrightness: brControl.curMon ? brControl.curMon.brightness : SystemControl.brightness

                                    Item {
                                        width: parent.width; height: 26
                                        Row {
                                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                            Text { text: "☀ BRIGHTNESS"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                            Text {
                                                text: brControl.curMon ? ("· " + (brControl.curMon.name || "Monitor")) : ""
                                                font.pixelSize: 13; font.weight: Font.Bold; color: "#475569"
                                            }
                                            Repeater {
                                                model: brControl.monList.length > 1 ? brControl.monList.length : 0
                                                delegate: Rectangle {
                                                    required property int index
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 30; height: 22; radius: 8
                                                    color: index === brControl.monIdx ? themeHub.accentA : "#FFFFFF"
                                                    border.width: 2; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: "M" + (index + 1); font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: quickPanelWindow.selectedMonitorIdx = index }
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            text: brControl.curBrightness + "%"
                                            font.family: "Consolas"; font.pixelSize: 16; font.weight: Font.Black; color: "#1A1B2E"
                                        }
                                    }

                                    Item {
                                        y: 30; width: parent.width; height: 28
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width; height: 22; radius: 11
                                            color: "#FFFFFF"; border.width: 3; border.color: "#1A1B2E"
                                            Rectangle {
                                                x: 3; y: 3; height: 16; radius: 8
                                                width: Math.max(0, (parent.width - 6) * (brControl.curBrightness / 100.0))
                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: "#FFD166" }
                                                    GradientStop { position: 1.0; color: themeHub.accentA }
                                                }
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            function setBr(mx) {
                                                const pct = Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100)
                                                if (brControl.curMon)
                                                    SystemControl.setMonitorBrightness(brControl.curMon.index, pct)
                                                else
                                                    SystemControl.setBrightness(pct)
                                            }
                                            onPressed: mouse => setBr(mouse.x)
                                            onPositionChanged: mouse => { if (pressed) setBr(mouse.x) }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Bottom Notifications & Utilities Card ----
                        Rectangle {
                            id: qpBottomCard
                            x: 36; y: 786; width: 582; height: 392
                            radius: 36
                            color: "#FFFFFF"
                            border.width: 3; border.color: "#1A1B2E"
                            clip: true

                            Column {
                                anchors.fill: parent; anchors.margins: 18; spacing: 12

                                // Bottom Header: Tabs + 2.5D / 2D Toggle
                                Item {
                                    width: parent.width; height: 38
                                    Row {
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                        Repeater {
                                            model: [
                                                { id: "notifications", label: NotificationService.count > 0 ? ("NOTIFS (" + NotificationService.count + ")") : "NOTIFICATIONS" },
                                                { id: "display",       label: "DISPLAY" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property bool act: quickPanelWindow.bottomTab === modelData.id
                                                width: btLbl.implicitWidth + 22; height: 34; radius: 17
                                                color: act ? themeHub.accentB : "#F1F5F9"
                                                border.width: 2.5; border.color: "#1A1B2E"
                                                Text { id: btLbl; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: quickPanelWindow.bottomTab = modelData.id }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: pmSwLbl.implicitWidth + 20; height: 32; radius: 16
                                        color: topBarWindow.phoneMode ? "#1A1B2E" : "#F1F5F9"
                                        border.width: 2; border.color: "#1A1B2E"
                                        Text {
                                            id: pmSwLbl; anchors.centerIn: parent
                                            text: topBarWindow.phoneMode ? "2.5D" : "2D"
                                            font.pixelSize: 13; font.weight: Font.Black
                                            color: topBarWindow.phoneMode ? themeHub.accentB : "#1A1B2E"
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setPhoneMode(!themeHub.phoneMode) }
                                    }
                                }

                                // TAB A: LIVE OS NOTIFICATIONS + COMPACT MEDIA / TELEMETRY STRIP
                                Column {
                                    visible: quickPanelWindow.bottomTab === "notifications"
                                    width: parent.width; spacing: 8

                                    // Compact Now Playing + Telemetry Strip (44px)
                                    Rectangle {
                                        width: parent.width; height: 44; radius: 14
                                        color: "#F4F7FC"; border.width: 2; border.color: "#1A1B2E"
                                        Row {
                                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 8
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 28; height: 28; radius: 8
                                                color: themeHub.accentA; border.width: 2; border.color: "#1A1B2E"; clip: true
                                                Image {
                                                    anchors.fill: parent
                                                    source: MediaService.hasSession ? MediaService.artUrl : ""
                                                    fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                                                    visible: status === Image.Ready
                                                }
                                                Text { visible: !MediaService.hasSession; anchors.centerIn: parent; text: "♪"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.max(100, parent.width - 260)
                                                elide: Text.ElideRight
                                                text: MediaService.hasSession ? (MediaService.title || "Playing") : ("CPU " + WindowTracker.cpuUsage + "% · RAM " + WindowTracker.ramUsage + "%")
                                                font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E"
                                            }
                                            Row {
                                                anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                                Rectangle {
                                                    width: 28; height: 28; radius: 14; color: themeHub.accentB; border.width: 2; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: MediaService.isPlaying ? "❚❚" : "▶"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: MediaService.playPause() }
                                                }
                                                Rectangle {
                                                    width: 28; height: 28; radius: 14; color: "#FFFFFF"; border.width: 2; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: "⏭"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: MediaService.next() }
                                                }
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: spotMiniLbl.implicitWidth + 14; height: 28; radius: 14
                                                color: spotMiniMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                                                border.width: 2; border.color: "#1A1B2E"
                                                Text { id: spotMiniLbl; anchors.centerIn: parent; text: "Spotlight"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    id: spotMiniMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { topBarWindow.quickPanelOpen = false; themeHub.spotlightOpen = true }
                                                }
                                            }
                                        }
                                    }

                                    // Notifications Header + Clear All
                                    Item {
                                        width: parent.width; height: 28
                                        Text {
                                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                            text: "Notifications (" + NotificationService.count + ")"
                                            font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E"
                                        }
                                        Row {
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                            Rectangle {
                                                width: refNotifLbl.implicitWidth + 14; height: 24; radius: 12
                                                color: refNotifMa.containsMouse ? themeHub.hoverTint : "#F1F5F9"
                                                border.width: 2; border.color: "#1A1B2E"
                                                Text { id: refNotifLbl; anchors.centerIn: parent; text: "↻"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    id: refNotifMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: NotificationService.refresh()
                                                }
                                            }
                                            Rectangle {
                                                visible: NotificationService.count > 0
                                                width: clrNotifLbl.implicitWidth + 16; height: 24; radius: 12
                                                color: clrNotifMa.containsMouse ? "#FCA5A5" : "#FFE4E6"
                                                border.width: 2; border.color: "#1A1B2E"
                                                Text { id: clrNotifLbl; anchors.centerIn: parent; text: "Clear all"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    id: clrNotifMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: NotificationService.clearAll()
                                                }
                                            }
                                        }
                                    }

                                    // Notification Feed / Access / Empty State (202px)
                                    Item {
                                        width: parent.width; height: 202

                                        // Permission denied / not granted
                                        Rectangle {
                                            visible: !NotificationService.accessGranted
                                            anchors.fill: parent; radius: 18
                                            color: "#FFF7ED"; border.width: 2.5; border.color: "#1A1B2E"
                                            Column {
                                                anchors.centerIn: parent; width: parent.width - 32; spacing: 8
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "Notification access required"
                                                    font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E"
                                                }
                                                Text {
                                                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                                                    text: "Enable Windows notification access so SekaiDesk can display live toasts here."
                                                    font.pixelSize: 12; font.weight: Font.DemiBold; color: "#475569"
                                                }
                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                                                    Rectangle {
                                                        width: 116; height: 30; radius: 15; color: themeHub.accentB; border.width: 2; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: "Open Settings"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: SystemControl.openSettings("ms-settings:privacy-notifications") }
                                                    }
                                                    Rectangle {
                                                        width: 78; height: 30; radius: 15; color: "#FFFFFF"; border.width: 2; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: "Retry"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.refresh() }
                                                    }
                                                }
                                            }
                                        }

                                        // Empty feed state
                                        Rectangle {
                                            visible: NotificationService.accessGranted && NotificationService.count === 0
                                            anchors.fill: parent; radius: 18
                                            color: "#F8FAFC"; border.width: 2; border.color: "#CBD5E1"
                                            Column {
                                                anchors.centerIn: parent; spacing: 6
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "All caught up"
                                                    font.pixelSize: 16; font.weight: Font.Black; color: "#1A1B2E"
                                                }
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "Live Windows notifications will show up here · " + themeHub.bandName
                                                    font.pixelSize: 12; font.weight: Font.DemiBold; color: "#64748B"
                                                }
                                            }
                                        }

                                        // Live Notifications ListView
                                        ListView {
                                            visible: NotificationService.accessGranted && NotificationService.count > 0
                                            anchors.fill: parent
                                            clip: true
                                            spacing: 8
                                            boundsBehavior: Flickable.StopAtBounds
                                            model: NotificationService.notifications
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: ListView.view.width
                                                height: Math.max(60, notifTextCol.implicitHeight + 16)
                                                radius: 16
                                                color: "#F8FAFC"
                                                border.width: 2.5; border.color: "#1A1B2E"

                                                Row {
                                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                                    anchors.topMargin: 8; anchors.bottomMargin: 8
                                                    spacing: 10

                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 36; height: 36; radius: 11
                                                        color: themeHub.accentB
                                                        border.width: 2; border.color: "#1A1B2E"
                                                        clip: true
                                                        Image {
                                                            id: notifAppImg
                                                            anchors.fill: parent; anchors.margins: 3
                                                            source: modelData.iconUrl || ""
                                                            fillMode: Image.PreserveAspectFit
                                                            asynchronous: true; cache: true; mipmap: true
                                                            visible: source !== "" && status === Image.Ready
                                                        }
                                                        Text {
                                                            visible: !notifAppImg.visible
                                                            anchors.centerIn: parent
                                                            text: (modelData.app || "?").trim().charAt(0).toUpperCase() || "?"
                                                            font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E"
                                                        }
                                                    }

                                                    Column {
                                                        id: notifTextCol
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - 82
                                                        spacing: 2

                                                        Row {
                                                            width: parent.width; spacing: 6
                                                            Text {
                                                                width: Math.min(implicitWidth, parent.width - timeLbl.implicitWidth - 10)
                                                                elide: Text.ElideRight
                                                                text: modelData.app || "App"
                                                                font.pixelSize: 11; font.weight: Font.Black; color: "#475569"
                                                            }
                                                            Text {
                                                                id: timeLbl
                                                                text: modelData.timeText ? ("· " + modelData.timeText) : ""
                                                                font.pixelSize: 11; font.weight: Font.DemiBold; color: "#64748B"
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            elide: Text.ElideRight
                                                            maximumLineCount: 1
                                                            text: modelData.title || modelData.app || "Notification"
                                                            font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E"
                                                        }

                                                        Text {
                                                            visible: (modelData.body || "") !== ""
                                                            width: parent.width
                                                            wrapMode: Text.Wrap
                                                            maximumLineCount: 2
                                                            elide: Text.ElideRight
                                                            text: modelData.body || ""
                                                            font.pixelSize: 12; font.weight: Font.DemiBold; color: "#334155"
                                                        }
                                                    }

                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 26; height: 26; radius: 13
                                                        color: notifDismissMa.containsMouse ? "#FCA5A5" : "#FFFFFF"
                                                        border.width: 2; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea {
                                                            id: notifDismissMa
                                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: NotificationService.dismiss(modelData.id)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // TAB C: SCREEN MIRROR + MULTI-MONITOR DISPLAYS
                                Column {
                                    visible: quickPanelWindow.bottomTab === "display"
                                    width: parent.width; spacing: 12

                                    Text { text: "SCREEN MIRRORING"; font.pixelSize: 13; font.weight: Font.Black; color: "#64748B" }
                                    Row {
                                        width: parent.width; spacing: 8
                                        Repeater {
                                            model: [
                                                { label: "Main", mode: "internal" },
                                                { label: "Duplicate", mode: "clone" },
                                                { label: "Extend", mode: "extend" },
                                                { label: "2nd Only", mode: "external" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: Math.floor((parent.width - 24) / 4); height: 44; radius: 14
                                                color: mirPhoneMa.containsMouse ? themeHub.accentB : "#F1F5F9"
                                                border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: modelData.label; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    id: mirPhoneMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: SystemControl.setDisplayMode(modelData.mode)
                                                }
                                            }
                                        }
                                    }

                                    Text { text: "MONITORS (" + SystemControl.monitors.length + ")"; font.pixelSize: 13; font.weight: Font.Black; color: "#64748B" }
                                    Flickable {
                                        width: parent.width; height: 150; contentWidth: width; contentHeight: monListCol.implicitHeight + 8; clip: true
                                        Column {
                                            id: monListCol; width: parent.width; spacing: 10
                                            Repeater {
                                                model: SystemControl.monitors
                                                delegate: Column {
                                                    required property var modelData
                                                    width: monListCol.width; spacing: 4
                                                    Item {
                                                        width: parent.width; height: 22
                                                        Text { anchors.left: parent.left; text: modelData.name || "Monitor"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                        Text { anchors.right: parent.right; text: modelData.brightness + "%"; font.family: "Consolas"; font.pixelSize: 14; font.weight: Font.Black; color: "#D97706" }
                                                    }
                                                    Item {
                                                        width: parent.width; height: 22
                                                        Rectangle {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width; height: 16; radius: 8
                                                            color: "#E2E8F0"; border.width: 2; border.color: "#1A1B2E"
                                                            Rectangle {
                                                                x: 2; y: 2; height: 12; radius: 6
                                                                width: Math.max(0, (parent.width - 4) * (modelData.brightness / 100.0))
                                                                color: "#FBBF24"
                                                            }
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            function setMb(mx) {
                                                                SystemControl.setMonitorBrightness(modelData.index, Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100))
                                                            }
                                                            onPressed: mouse => setMb(mouse.x)
                                                            onPositionChanged: mouse => { if (pressed) setMb(mouse.x) }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Inline Wi-Fi / Bluetooth Picker Overlay inside the Phone Screen ----
                        Rectangle {
                            visible: quickPanelWindow.subDialog !== ""
                            x: 34; y: 346; width: 586; height: 834
                            radius: 36
                            color: "#FFFDF9"
                            border.width: 3.5; border.color: "#1A1B2E"
                            z: 30

                            Column {
                                anchors.fill: parent; anchors.margins: 22; spacing: 14

                                Item {
                                    width: parent.width; height: 46
                                    Rectangle {
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        width: 94; height: 38; radius: 19
                                        color: "#F1F5F9"; border.width: 2.5; border.color: "#1A1B2E"
                                        Text { anchors.centerIn: parent; text: "← Back"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: quickPanelWindow.subDialog = "" }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: quickPanelWindow.subDialog === "wifi" ? "WI-FI NETWORKS" : "BLUETOOTH DEVICES"
                                        font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E"
                                    }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 82; height: 38; radius: 19
                                        color: themeHub.accentB; border.width: 2.5; border.color: "#1A1B2E"
                                        Text { anchors.centerIn: parent; text: "Scan"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (quickPanelWindow.subDialog === "wifi") SystemControl.refreshWifi()
                                                else SystemControl.refreshBluetooth()
                                            }
                                        }
                                    }
                                }

                                Flickable {
                                    width: parent.width; height: parent.height - 120
                                    contentWidth: width; contentHeight: subListCol.implicitHeight + 10; clip: true

                                    Column {
                                        id: subListCol; width: parent.width; spacing: 10

                                        // Wi-Fi list
                                        Repeater {
                                            model: quickPanelWindow.subDialog === "wifi" ? SystemControl.wifiNetworks : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: subListCol.width; height: 56; radius: 20
                                                color: modelData.connected ? themeHub.accentB : "#FFFFFF"
                                                border.width: 2.5; border.color: "#1A1B2E"
                                                Text {
                                                    x: 18; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 130; elide: Text.ElideRight
                                                    text: (modelData.connected ? "✓ " : "") + (modelData.ssid || "Hidden Network")
                                                    font.pixelSize: 16; font.weight: Font.Black; color: "#1A1B2E"
                                                }
                                                Text {
                                                    anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                                                    text: (modelData.signal || 0) + "%"
                                                    font.family: "Consolas"; font.pixelSize: 15; font.weight: Font.Black; color: "#334155"
                                                }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: SystemControl.connectWifi(modelData.ssid)
                                                }
                                            }
                                        }

                                        // Bluetooth list
                                        Repeater {
                                            model: quickPanelWindow.subDialog === "bt" ? SystemControl.bluetoothDevices : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: subListCol.width; height: 56; radius: 20
                                                color: modelData.connected ? themeHub.accentA : "#FFFFFF"
                                                border.width: 2.5; border.color: "#1A1B2E"
                                                Text {
                                                    x: 18; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 140; elide: Text.ElideRight
                                                    text: modelData.name || "Bluetooth Device"
                                                    font.pixelSize: 16; font.weight: Font.Black; color: "#1A1B2E"
                                                }
                                                Text {
                                                    anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.connected ? "Connected" : "Paired"
                                                    font.pixelSize: 14; font.weight: Font.Black; color: "#334155"
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: parent.width; height: 48; radius: 24
                                    color: "#F1F5F9"; border.width: 2.5; border.color: "#1A1B2E"
                                    Text {
                                        anchors.centerIn: parent
                                        text: quickPanelWindow.subDialog === "wifi" ? "Open Windows Wi-Fi Settings" : "Open Windows Bluetooth Settings"
                                        font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E"
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            topBarWindow.quickPanelOpen = false
                                            SystemControl.openSettings(quickPanelWindow.subDialog === "wifi" ? "ms-settings:network-wifi" : "ms-settings:bluetooth")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 5) Phone Top Notch + Camera Lens + Glint
                    Item {
                        x: 202
                        y: quickPanelWindow.screenInset - 12
                        width: 249
                        height: 49 + 12
                        clip: true
                        z: 50

                        Rectangle {
                            y: -27
                            width: parent.width
                            height: parent.height + 27
                            radius: 27
                            color: "#1A1B2E"
                            antialiasing: true
                        }
                        Rectangle {
                            x: 24; y: 15 + 12
                            width: 22; height: 22; radius: 11
                            color: "#0F172A"
                            Rectangle {
                                anchors.centerIn: parent
                                width: 10; height: 10; radius: 5
                                color: "#1E3A5F"
                                Rectangle { x: 2; y: 2; width: 3; height: 3; radius: 2; color: "#93C5FD" }
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // Landscape Settings Stage (90 deg CCW 2.5D Phone Flip + 1440x760 Tablet)
        // =====================================================================
        Item {
            id: landStage
            visible: quickPanelWindow.curSettingsAlpha > 0.001 || themeHub.settingsOpen || quickPanelWindow.settingsAnimating
            enabled: themeHub.settingsOpen && quickPanelWindow.flipProgress >= 0.95 && !quickPanelWindow.flipping
            anchors.fill: parent

            // Soft dim desktop backdrop behind landscape Settings phone
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(10 / 255, 14 / 255, 28 / 255, 0.42 * quickPanelWindow.curSettingsAlpha)
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        topBarWindow.quickPanelClosedAt = Date.now()
                        topBarWindow.quickPanelOpen = false
                        themeHub.settingsOpen = false
                    }
                }
            }

            // Center-origin 2.5D pivot (0px jump from Portrait phoneStage center)
            Item {
                id: landPivot
                x: quickPanelWindow.curCenterX
                y: quickPanelWindow.curCenterY
                width: 0
                height: 0
                opacity: quickPanelWindow.curSettingsAlpha
                transform: Scale {
                    origin.x: 0; origin.y: 0
                    xScale: quickPanelWindow.curLandScale
                    yScale: quickPanelWindow.curLandScale
                }

                // ---- Landscape 2.5D Settings Chassis (SekaiPop SettingsStage parity) ----
                Item {
                    id: flipLandBody
                    visible: quickPanelWindow.curSettingsAlpha > 0.001
                    readonly property var mat: quickPanelWindow.pmBaseForCenter(
                        quickPanelWindow.landW,
                        quickPanelWindow.landH,
                        quickPanelWindow.landThickness,
                        quickPanelWindow.curYaw + quickPanelWindow.sTilt * quickPanelWindow.landTiltYaw,
                        quickPanelWindow.curPitch + quickPanelWindow.sTilt * quickPanelWindow.landTiltPitch + quickPanelWindow.wobPitch,
                        90.0 * (1.0 - quickPanelWindow.flipProgress) + quickPanelWindow.wobRoll + quickPanelWindow.sTilt * quickPanelWindow.landTiltRoll,
                        quickPanelWindow.curPersp
                    )

                    // Grounded comic drop shadow
                    Rectangle {
                        x: 12; y: 14
                        width: quickPanelWindow.landW
                        height: quickPanelWindow.landH
                        radius: quickPanelWindow.landCornerR
                        color: Qt.rgba(0.06, 0.07, 0.14, 0.30)
                        transform: Matrix4x4 {
                            matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmZOffset(flipLandBody.mat, -quickPanelWindow.landThickness - 4))
                        }
                    }

                    // Solid 3D rim slices (extruded wall)
                    Repeater {
                        model: topBarWindow.phoneMode ? 18 : 0
                        delegate: Rectangle {
                            required property int index
                            readonly property real depth: (18 - index) / 18.0
                            width: quickPanelWindow.landW
                            height: quickPanelWindow.landH
                            radius: quickPanelWindow.landCornerR
                            antialiasing: depth < 0.28
                            color: depth < 0.16 ? "#8E92B8" : (depth < 0.55 ? "#4C5073" : "#24263A")
                            transform: Matrix4x4 {
                                matrix: quickPanelWindow.toQtMat(quickPanelWindow.pmZOffset(flipLandBody.mat, -depth * quickPanelWindow.landThickness))
                            }
                        }
                    }

                    // Landscape Screen Face (1440x760)
                    Item {
                        id: landScreenFace
                        width: quickPanelWindow.landW
                        height: quickPanelWindow.landH
                        transform: Matrix4x4 {
                            matrix: quickPanelWindow.toQtMat(flipLandBody.mat)
                        }

                        // Eat clicks inside tilted chassis so backdrop doesn't dismiss
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {}
                        }

                        // Outer titanium rim + bezel
                        Rectangle {
                            anchors.fill: parent
                            radius: quickPanelWindow.landCornerR
                            color: "#2E3148"
                            border.width: 4
                            border.color: "#1A1B2E"
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 10
                            radius: quickPanelWindow.landCornerR - 10
                            color: "#1A1B2E"
                        }

                        // Paper screen interior
                        Rectangle {
                            id: landPaper
                            anchors.fill: parent
                            anchors.margins: 24
                            radius: quickPanelWindow.landCornerR - 24
                            color: "#FAFAFF"
                            border.width: 3
                            border.color: "#1A1B2E"
                            clip: true

                            // Top-right comic halftone dots
                            Canvas {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                width: 320; height: 210
                                opacity: 0.16
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = themeHub.accentA
                                    for (let r = 0; r < 10; r++) {
                                        for (let c = 0; c < 14; c++) {
                                            const rad = Math.max(0.8, 5.2 - r * 0.42 - (13 - c) * 0.25)
                                            if (rad <= 0.8) continue
                                            ctx.beginPath()
                                            ctx.arc(width - 14 - c * 22, 14 + r * 20, rad, 0, Math.PI * 2)
                                            ctx.fill()
                                        }
                                    }
                                }
                            }

                            // ---- Header Bar inside Landscape Phone ----
                            Item {
                                id: landHeader
                                x: 58; y: 20
                                width: parent.width - 82
                                height: 66

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 14

                                    // Back button (subpage -> Hub, or Hub -> Phone if opened from QuickPanel)
                                    Item {
                                        visible: themeHub.settingsSection !== "" || quickPanelWindow.settingsOpenedFromQuick
                                        width: backLbl.implicitWidth + 32; height: 48
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { x: 4; y: 4; width: parent.width; height: parent.height; radius: 16; color: "#1A1B2E" }
                                        Rectangle {
                                            x: landBackMa.pressed ? 3 : 0; y: landBackMa.pressed ? 3 : 0
                                            width: parent.width; height: parent.height; radius: 16
                                            color: landBackMa.containsMouse ? themeHub.accentA : "#FFFFFF"
                                            border.width: 3; border.color: "#1A1B2E"
                                            Text {
                                                id: backLbl
                                                anchors.centerIn: parent
                                                text: themeHub.settingsSection !== "" ? "← HUB" : "← PHONE"
                                                font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E"
                                            }
                                            MouseArea {
                                                id: landBackMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (themeHub.settingsSection !== "")
                                                        themeHub.settingsSection = ""
                                                    else
                                                        themeHub.settingsOpen = false
                                                }
                                            }
                                        }
                                    }

                                    // Section badge + title
                                    Rectangle {
                                        width: 48; height: 48; radius: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: themeHub.accentA
                                        border.width: 3; border.color: "#1A1B2E"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "⚙"
                                            font.pixelSize: 24; font.weight: Font.Black; color: "#1A1B2E"
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Text {
                                            text: {
                                                const s = themeHub.settingsSection
                                                if (s === "quick") return "01 · QUICK"
                                                if (s === "general") return "02 · GENERAL"
                                                if (s === "bar") return "03 · BAR"
                                                if (s === "desktop") return "04 · DESKTOP"
                                                if (s === "system") return "05 · HOTKEYS & SYSTEM"
                                                if (s === "about") return "06 · ABOUT"
                                                return "SEKAIDESK SETTINGS"
                                            }
                                            font.family: "Segoe UI"; font.pixelSize: 24; font.weight: Font.Black; color: "#1A1B2E"
                                        }
                                        Text {
                                            text: themeHub.settingsSection === ""
                                                  ? "Choose a category card to customize your desktop"
                                                  : "Changes apply live and save automatically"
                                            font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#475569"
                                        }
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    // Quick Palette Band Swatches
                                    Repeater {
                                        model: themeHub.bands
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 30; height: 30; radius: 15
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: modelData.A
                                            border.width: (!themeHub.useCustomPalette && themeHub.bandId === modelData.id) ? 4 : 2
                                            border.color: "#1A1B2E"
                                            scale: bandDotMa.containsMouse ? 1.12 : 1.0
                                            MouseArea {
                                                id: bandDotMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: themeHub.setBand(modelData.id)
                                            }
                                        }
                                    }

                                    // Edit Mode shortcut pill
                                    Item {
                                        width: 112; height: 44
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { x: 4; y: 4; width: parent.width; height: parent.height; radius: 14; color: "#1A1B2E" }
                                        Rectangle {
                                            x: landEditMa.pressed ? 3 : 0; y: landEditMa.pressed ? 3 : 0
                                            width: parent.width; height: parent.height; radius: 14
                                            color: themeHub.editMode ? themeHub.accentB : (landEditMa.containsMouse ? "#E0F2FE" : "#FFFFFF")
                                            border.width: 3; border.color: "#1A1B2E"
                                            Text {
                                                anchors.centerIn: parent
                                                text: themeHub.editMode ? "✎ EDITING" : "✎ EDIT"
                                                font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E"
                                            }
                                            MouseArea {
                                                id: landEditMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    themeHub.setEditMode(!themeHub.editMode)
                                                    if (themeHub.editMode) {
                                                        themeHub.settingsOpen = false
                                                        topBarWindow.quickPanelOpen = false
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Close button
                                    Item {
                                        width: 48; height: 44
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle { x: 4; y: 4; width: parent.width; height: parent.height; radius: 14; color: "#1A1B2E" }
                                        Rectangle {
                                            x: landCloseMa.pressed ? 3 : 0; y: landCloseMa.pressed ? 3 : 0
                                            width: parent.width; height: parent.height; radius: 14
                                            color: landCloseMa.containsMouse ? "#FB7185" : "#FFE4E6"
                                            border.width: 3; border.color: "#1A1B2E"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E"
                                            }
                                            MouseArea {
                                                id: landCloseMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: themeHub.settingsOpen = false
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- Divider line ----
                            Rectangle {
                                x: 58; y: 94
                                width: parent.width - 82; height: 3
                                color: "#1A1B2E"
                                opacity: 0.14
                            }

                            // ---- Page Area ----
                            Item {
                                x: 58; y: 110
                                width: parent.width - 82
                                height: parent.height - 130

                                // ==== HUB (3x2 Comic Cards) ====
                                Grid {
                                    visible: themeHub.settingsSection === ""
                                    anchors.centerIn: parent
                                    columns: 3
                                    columnSpacing: 24
                                    rowSpacing: 24

                                    Repeater {
                                        model: [
                                            { id: "quick",   num: "01", title: "Quick",            sub: "Notify style, OSD, 2.5D mode & audio",      accent: "#06B6D4", glyph: "⚡" },
                                            { id: "general", num: "02", title: "General",          sub: "Theme bands, wallpaper palette & clock",    accent: "#F43F5E", glyph: "🎨" },
                                            { id: "bar",     num: "03", title: "Bar",              sub: "TopBar style, auto-hide & status modules",  accent: "#F59E0B", glyph: "▭"  },
                                            { id: "desktop", num: "04", title: "Desktop",          sub: "Dock layout, widgets, visualizer & walls",  accent: "#8B5CF6", glyph: "🖥" },
                                            { id: "system",  num: "05", title: "Hotkeys & System", sub: "Shortcuts, hardware info & system tools",   accent: "#10B981", glyph: "⌨" },
                                            { id: "about",   num: "06", title: "About",            sub: "SekaiDesk version, build & credits",        accent: "#EC4899", glyph: "✦"  }
                                        ]
                                        delegate: Item {
                                            required property var modelData
                                            width: 404; height: 256
                                            Rectangle { x: 7; y: 7; width: parent.width; height: parent.height; radius: 28; color: "#1A1B2E" }
                                            Rectangle {
                                                x: cardMa.pressed ? 4 : 0
                                                y: cardMa.pressed ? 4 : 0
                                                width: parent.width; height: parent.height; radius: 28
                                                color: cardMa.containsMouse ? "#F0FDFA" : "#FFFFFF"

                                                // Accent top ribbon clipped strictly inside the rounded card & 4px border
                                                Item {
                                                    anchors.top: parent.top; anchors.topMargin: 4
                                                    anchors.left: parent.left; anchors.leftMargin: 4
                                                    anchors.right: parent.right; anchors.rightMargin: 4
                                                    height: 14
                                                    clip: true
                                                    Rectangle {
                                                        width: parent.width
                                                        height: 56
                                                        radius: 24
                                                        color: modelData.accent
                                                    }
                                                }
                                                // Number badge
                                                Rectangle {
                                                    x: 24; y: 36; width: 64; height: 64; radius: 20
                                                    color: modelData.accent
                                                    border.width: 3.5; border.color: "#1A1B2E"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.num
                                                        font.family: "Consolas"; font.pixelSize: 26; font.weight: Font.Black; color: "#FFFFFF"
                                                    }
                                                }
                                                // Glyph watermark
                                                Text {
                                                    anchors.right: parent.right; anchors.rightMargin: 24; y: 32
                                                    text: modelData.glyph
                                                    font.pixelSize: 48; font.weight: Font.Black; color: modelData.accent; opacity: 0.35
                                                }
                                                // Title & Description
                                                Text {
                                                    x: 24; y: 120; width: parent.width - 48
                                                    text: modelData.title
                                                    font.family: "Segoe UI"; font.pixelSize: 26; font.weight: Font.Black; color: "#1A1B2E"
                                                }
                                                Text {
                                                    x: 24; y: 158; width: parent.width - 48
                                                    text: modelData.sub
                                                    wrapMode: Text.WordWrap
                                                    font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.DemiBold; color: "#475569"
                                                }
                                                // Open indicator pill
                                                Rectangle {
                                                    anchors.right: parent.right; anchors.rightMargin: 22
                                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                                                    width: 84; height: 32; radius: 12
                                                    color: cardMa.containsMouse ? modelData.accent : "#F1F5F9"
                                                    border.width: 2.5; border.color: "#1A1B2E"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "OPEN →"
                                                        font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black
                                                        color: cardMa.containsMouse ? "#FFFFFF" : "#1A1B2E"
                                                    }
                                                }
                                                // Crisp rounded card border rendered on top of the clipped ribbon
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 28
                                                    color: "transparent"
                                                    border.width: 4
                                                    border.color: "#1A1B2E"
                                                    z: 10
                                                }
                                                MouseArea {
                                                    id: cardMa
                                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    z: 20
                                                    onClicked: themeHub.settingsSection = modelData.id
                                                }
                                            }
                                        }
                                    }
                                }

                                // ==== SUBPAGE 01: QUICK ====
                                Row {
                                    visible: themeHub.settingsSection === "quick"
                                    anchors.fill: parent
                                    spacing: 24

                                    // Left column: Notifications & Peek
                                    Rectangle {
                                        width: (parent.width - 24) * 0.5; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 18
                                            Text { text: "NOTIFICATIONS & PEEK"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                            Text { text: "Choose how arriving notifications appear without interfering with the Dock."; wrapMode: Text.WordWrap; width: parent.width; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#475569" }

                                            Column {
                                                width: parent.width; spacing: 10
                                                Repeater {
                                                    model: [
                                                        { val: "peek",  title: "Phone Peek (Bottom-Right)",  desc: "Mini phone rises bottom-right; auto-falls back to Popup if tight." },
                                                        { val: "popup", title: "Popup Stack (Top-Right)",   desc: "Clean stacked SekaiPop cards below the TopBar." },
                                                        { val: "off",   title: "Off (Tray Only)",           desc: "Silent collection in QuickPanel notification inbox." }
                                                    ]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: parent.width; height: 70; radius: 16
                                                        color: themeHub.notifyStyle === modelData.val ? "#ECFEFF" : "#F8FAFC"
                                                        border.width: themeHub.notifyStyle === modelData.val ? 3.5 : 2
                                                        border.color: themeHub.notifyStyle === modelData.val ? themeHub.accentA : "#CBD5E1"
                                                        Column {
                                                            anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16; spacing: 2
                                                            Text { text: modelData.title; font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                            Text { text: modelData.desc; width: parent.width; elide: Text.ElideRight; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#64748B" }
                                                        }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setNotifyStyle(modelData.val) }
                                                    }
                                                }
                                            }

                                            // Quiet Fullscreen toggle
                                            Rectangle {
                                                width: parent.width; height: 56; radius: 16
                                                color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "Quiet Notifications in Fullscreen"; font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                Rectangle {
                                                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                                    width: 72; height: 32; radius: 16
                                                    color: themeHub.notifyQuietFullscreen ? themeHub.accentA : "#CBD5E1"
                                                    border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: themeHub.notifyQuietFullscreen ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setNotifyQuietFullscreen(!themeHub.notifyQuietFullscreen) }
                                            }

                                            // Test notification button
                                            Rectangle {
                                                width: parent.width; height: 50; radius: 16
                                                color: testNotifMa.containsMouse ? themeHub.accentB : themeHub.accentA
                                                border.width: 3; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "🔔 SEND TEST NOTIFICATION"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    id: testNotifMa
                                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: NotificationService.emitTestNotification()
                                                }
                                            }
                                        }
                                    }

                                    // Right column: OSD, Phone 2.5D & Quick Hardware
                                    Rectangle {
                                        width: (parent.width - 24) * 0.5; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 18
                                            Text { text: "CHASSIS, OSD & QUICK TOGGLES"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }

                                            Repeater {
                                                model: [
                                                    { label: "2.5D Tilted Phone Chassis", sub: "Extruded metallic depth walls & 3D flip", val: themeHub.phoneMode, act: "phone" },
                                                    { label: "SekaiPop On-Screen Display (OSD)", sub: "Show pill HUD on Volume / Brightness / Dark Mode", val: themeHub.osdEnabled, act: "osd" },
                                                    { label: "System Dark Mode", sub: "Toggle Windows dark/light app theme", val: SystemControl.darkMode, act: "dark" },
                                                    { label: "Master Audio Mute", sub: "Current volume: " + AudioService.masterVolume + "%", val: AudioService.masterMuted, act: "mute" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: parent.width; height: 74; radius: 16
                                                    color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Column {
                                                        anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: swBadge.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                                        Text { text: modelData.label; font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                        Text { text: modelData.sub; width: parent.width; elide: Text.ElideRight; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#64748B" }
                                                    }
                                                    Rectangle {
                                                        id: swBadge
                                                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                                        width: 72; height: 32; radius: 16
                                                        color: modelData.val ? themeHub.accentA : "#CBD5E1"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.val ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.act === "phone") themeHub.setPhoneMode(!themeHub.phoneMode)
                                                            else if (modelData.act === "osd") themeHub.setOsdEnabled(!themeHub.osdEnabled)
                                                            else if (modelData.act === "dark") SystemControl.toggleDarkMode()
                                                            else if (modelData.act === "mute") AudioService.toggleMasterMute()
                                                        }
                                                    }
                                                }
                                            }

                                            // Mic Mute quick pill
                                            Rectangle {
                                                visible: AudioService.micSupported
                                                width: parent.width; height: 54; radius: 16
                                                color: AudioService.micMuted ? "#FFE4E6" : "#ECFDF5"
                                                border.width: 2.5; border.color: "#1A1B2E"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: AudioService.micMuted ? "🎙 MICROPHONE MUTED (CLICK TO UNMUTE)" : "🎙 MICROPHONE ACTIVE (" + AudioService.micVolume + "%)"
                                                    font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E"
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.toggleMicMute() }
                                            }
                                        }
                                    }
                                }

                                // ==== SUBPAGE 02: GENERAL ====
                                Row {
                                    visible: themeHub.settingsSection === "general"
                                    anchors.fill: parent
                                    spacing: 24

                                    // Left: Theme Bands & Wallpaper Match
                                    Rectangle {
                                        width: (parent.width - 24) * 0.5; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                                            Text { text: "UNIT BAND PALETTES"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                            Grid {
                                                columns: 2; columnSpacing: 12; rowSpacing: 12; width: parent.width
                                                Repeater {
                                                    model: themeHub.bands
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        readonly property bool sel: !themeHub.useCustomPalette && themeHub.bandId === modelData.id
                                                        width: (parent.width - 12) * 0.5; height: 74; radius: 16
                                                        color: sel ? "#F0FDFA" : "#F8FAFC"
                                                        border.width: sel ? 3.5 : 2; border.color: sel ? modelData.A : "#1A1B2E"
                                                        Row {
                                                            anchors.fill: parent; anchors.margins: 12; spacing: 10
                                                            Rectangle {
                                                                width: 44; height: 44; radius: 14; anchors.verticalCenter: parent.verticalCenter
                                                                gradient: Gradient {
                                                                    GradientStop { position: 0.0; color: modelData.B }
                                                                    GradientStop { position: 1.0; color: modelData.A }
                                                                }
                                                                border.width: 2.5; border.color: "#1A1B2E"
                                                            }
                                                            Column {
                                                                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                                                Text { text: modelData.shortName; font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Black; color: modelData.A }
                                                                Text { text: modelData.name; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                            }
                                                        }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setBand(modelData.id) }
                                                    }
                                                }
                                            }

                                            // Wallpaper Match button
                                            Rectangle {
                                                width: parent.width; height: 64; radius: 16
                                                color: themeHub.useCustomPalette ? "#ECFEFF" : "#F8FAFC"
                                                border.width: themeHub.useCustomPalette ? 3.5 : 2.5; border.color: "#1A1B2E"
                                                Row {
                                                    anchors.centerIn: parent; spacing: 10
                                                    Text { text: "🎨"; font.pixelSize: 20 }
                                                    Text {
                                                        text: themeHub.useCustomPalette ? "WALLPAPER MATCH ACTIVE (CLICK TO RE-EXTRACT)" : "MATCH PALETTE TO CURRENT WALLPAPER"
                                                        font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E"
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const pal = WallpaperService.extractCurrentPalette()
                                                        if (pal && pal.accentA)
                                                            themeHub.applyWallpaperPalette(pal)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Right: Clock & Weather Settings
                                    Rectangle {
                                        width: (parent.width - 24) * 0.5; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                                            Text { text: "CLOCK & WEATHER"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }

                                            // Weather City input
                                            Row {
                                                width: parent.width; spacing: 10
                                                Rectangle {
                                                    width: parent.width - 208; height: 48; radius: 14
                                                    color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                    clip: true
                                                    TextInput {
                                                        id: landCityInput
                                                        anchors.fill: parent; anchors.margins: 12
                                                        verticalAlignment: Text.AlignVCenter
                                                        clip: true
                                                        selectByMouse: true
                                                        text: WeatherService.city
                                                        font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Bold; color: "#1A1B2E"
                                                        onAccepted: WeatherService.setCity(text.trim())
                                                        Keys.onEscapePressed: event => {
                                                            qpKeyCatcher.forceActiveFocus()
                                                            event.accepted = true
                                                        }
                                                        Connections {
                                                            target: WeatherService
                                                            function onWeatherChanged() {
                                                                if (!landCityInput.activeFocus)
                                                                    landCityInput.text = WeatherService.city
                                                            }
                                                        }
                                                    }
                                                }
                                                Rectangle {
                                                    width: 94; height: 48; radius: 14; color: themeHub.accentA; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: "APPLY"; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WeatherService.setCity(landCityInput.text.trim()) }
                                                }
                                                Rectangle {
                                                    width: 94; height: 48; radius: 14; color: "#F1F5F9"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: "↻ SYNC"; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WeatherService.refresh() }
                                                }
                                            }

                                            // Weather Unit + Style pills
                                            Row {
                                                width: parent.width; spacing: 10
                                                Repeater {
                                                    model: [{ l: "°C", v: "C" }, { l: "°F", v: "F" }]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: 72; height: 42; radius: 12
                                                        color: themeHub.weatherUnit === modelData.v ? themeHub.accentA : "#F1F5F9"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWeatherUnit(modelData.v) }
                                                    }
                                                }
                                                Item { width: 8; height: 1 }
                                                Repeater {
                                                    model: [{ l: "CARD", v: "card" }, { l: "COMPACT", v: "compact" }]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: 112; height: 42; radius: 12
                                                        color: themeHub.weatherStyle === modelData.v ? themeHub.accentB : "#F1F5F9"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWeatherStyle(modelData.v) }
                                                    }
                                                }
                                            }

                                            // Clock style pills (0=KEYS, 1=TOWER, 2=STICKER, 3=STACK)
                                            Row {
                                                width: parent.width; spacing: 10
                                                Repeater {
                                                    model: [{ l: "KEYS", v: 0 }, { l: "TOWER", v: 1 }, { l: "STICKER", v: 2 }, { l: "STACK", v: 3 }]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: (parent.width - 30) / 4; height: 44; radius: 12
                                                        color: themeHub.clockStyle === modelData.v ? themeHub.accentA : "#F1F5F9"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setClockStyle(modelData.v) }
                                                    }
                                                }
                                            }

                                            // Clock toggles
                                            Repeater {
                                                model: [
                                                    { l: "24-Hour Clock Format", val: themeHub.clock24h, k: "24h" },
                                                    { l: "Show Seconds on Clock Widget", val: themeHub.clockSeconds, k: "sec" },
                                                    { l: "Show Date on Clock Widget", val: themeHub.clockShowDate, k: "date" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: parent.width; height: 52; radius: 14
                                                    color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Rectangle {
                                                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                                        width: 68; height: 30; radius: 15
                                                        color: modelData.val ? themeHub.accentA : "#CBD5E1"; border.width: 2; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.val ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.k === "24h") themeHub.setClock24h(!themeHub.clock24h)
                                                            else if (modelData.k === "sec") themeHub.setClockSeconds(!themeHub.clockSeconds)
                                                            else if (modelData.k === "date") themeHub.setClockShowDate(!themeHub.clockShowDate)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ==== SUBPAGE 03: BAR ====
                                Row {
                                    visible: themeHub.settingsSection === "bar"
                                    anchors.fill: parent
                                    spacing: 24

                                    Rectangle {
                                        width: (parent.width - 24) * 0.45; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 16
                                            Text { text: "TOPBAR STYLE & BEHAVIOR"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                            Grid {
                                                columns: 2; columnSpacing: 12; rowSpacing: 12; width: parent.width
                                                Repeater {
                                                    model: [
                                                        { id: "float",       name: "Float",       desc: "Rounded detached bar" },
                                                        { id: "straight",    name: "Straight",    desc: "Flush crisp edge" },
                                                        { id: "capsule",     name: "Capsule",     desc: "Pill-outlined frame" },
                                                        { id: "transparent", name: "Transparent", desc: "Pure blur overlay" }
                                                    ]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        readonly property bool sel: themeHub.barStyle === modelData.id
                                                        width: (parent.width - 12) * 0.5; height: 92; radius: 16
                                                        color: sel ? "#FEF3C7" : "#F8FAFC"
                                                        border.width: sel ? 3.5 : 2; border.color: "#1A1B2E"
                                                        Column {
                                                            anchors.centerIn: parent; spacing: 4; width: parent.width - 20
                                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.family: "Segoe UI"; font.pixelSize: 16; font.weight: Font.Black; color: "#1A1B2E" }
                                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.desc; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#64748B" }
                                                        }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setBarStyle(modelData.id) }
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                width: parent.width; height: 74; radius: 16
                                                color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Column {
                                                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                                    Text { text: "Auto-Hide TopBar on Overlap"; font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text { text: "Slides away when maximized windows reach top edge"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#64748B" }
                                                }
                                                Rectangle {
                                                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                                    width: 72; height: 32; radius: 16
                                                    color: themeHub.barAutoHide ? themeHub.accentA : "#CBD5E1"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: themeHub.barAutoHide ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setBarAutoHide(!themeHub.barAutoHide) }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: (parent.width - 24) * 0.55; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 12
                                            Text { text: "VISIBLE TOPBAR MODULES"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                            Repeater {
                                                model: [
                                                    { label: "Active App Badge & Window Title", val: themeHub.barShowActiveWindow, k: "win" },
                                                    { label: "SekaiPop Media Pill",             val: themeHub.barShowMedia,        k: "media" },
                                                    { label: "CPU / GPU / RAM Telemetry Pills", val: themeHub.barShowStats,        k: "stats" },
                                                    { label: "System Tray Pill",                val: themeHub.barShowTray,         k: "tray" },
                                                    { label: "Weather Temperature Pill",        val: themeHub.barShowWeather,      k: "weather" },
                                                    { label: "Date & Clock Pill",               val: themeHub.barShowClock,        k: "clock" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: parent.width; height: 64; radius: 16
                                                    color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Rectangle {
                                                        anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                                                        width: 72; height: 32; radius: 16
                                                        color: modelData.val ? themeHub.accentA : "#CBD5E1"; border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.val ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.k === "win") themeHub.setBarShowActiveWindow(!themeHub.barShowActiveWindow)
                                                            else if (modelData.k === "media") themeHub.setBarShowMedia(!themeHub.barShowMedia)
                                                            else if (modelData.k === "stats") themeHub.setBarShowStats(!themeHub.barShowStats)
                                                            else if (modelData.k === "tray") themeHub.setBarShowTray(!themeHub.barShowTray)
                                                            else if (modelData.k === "weather") themeHub.setBarShowWeather(!themeHub.barShowWeather)
                                                            else if (modelData.k === "clock") themeHub.setBarShowClock(!themeHub.barShowClock)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ==== SUBPAGE 04: DESKTOP ====
                                Row {
                                    visible: themeHub.settingsSection === "desktop"
                                    anchors.fill: parent
                                    spacing: 24

                                    // Left: Dock customization
                                    Rectangle {
                                        width: (parent.width - 24) * 0.5; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                                            Text { text: "DOCK & UTILITY KEYCAPS"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }

                                            Row {
                                                width: parent.width; spacing: 10
                                                Repeater {
                                                    model: [{ id: "float", l: "FLOAT" }, { id: "capsule", l: "CAPSULE" }, { id: "transparent", l: "CLEAR" }]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: (parent.width - 20) / 3; height: 46; radius: 14
                                                        color: themeHub.dockStyle === modelData.id ? themeHub.accentA : "#F1F5F9"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setDockStyle(modelData.id) }
                                                    }
                                                }
                                            }

                                            // Dock Tile Size stepped slider (40..64)
                                            Rectangle {
                                                width: parent.width; height: 64; radius: 16
                                                color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Row {
                                                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "ICON SIZE (" + themeHub.dockTileSize + "px)"; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E"; width: 144 }
                                                    Repeater {
                                                        model: [40, 44, 48, 52, 56, 60, 64]
                                                        delegate: Rectangle {
                                                            required property int modelData
                                                            width: 46; height: 34; radius: 10; anchors.verticalCenter: parent.verticalCenter
                                                            color: themeHub.dockTileSize === modelData ? themeHub.accentB : "#FFFFFF"
                                                            border.width: 2; border.color: "#1A1B2E"
                                                            Text { anchors.centerIn: parent; text: String(modelData); font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setDockTileSize(modelData) }
                                                        }
                                                    }
                                                }
                                            }

                                            // Magnification toggle
                                            Rectangle {
                                                width: parent.width; height: 52; radius: 14; color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "Dock Hover Magnification"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                Rectangle {
                                                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                                    width: 68; height: 30; radius: 15; color: themeHub.dockMagnify ? themeHub.accentA : "#CBD5E1"; border.width: 2; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: themeHub.dockMagnify ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setDockMagnify(!themeHub.dockMagnify) }
                                            }

                                            // Auto-hide / Dodge overlapping windows toggle
                                            Rectangle {
                                                width: parent.width; height: 52; radius: 14; color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "Dodge Overlapping Windows"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                Rectangle {
                                                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                                    width: 68; height: 30; radius: 15; color: themeHub.dockAutoHide ? themeHub.accentA : "#CBD5E1"; border.width: 2; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: themeHub.dockAutoHide ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setDockAutoHide(!themeHub.dockAutoHide) }
                                            }

                                            // Dock utility keycap pills (2x2 grid)
                                            Grid {
                                                columns: 2; columnSpacing: 12; rowSpacing: 12; width: parent.width
                                                Repeater {
                                                    model: [
                                                        { l: "Finder",    val: themeHub.dockShowFinder,    k: "finder" },
                                                        { l: "Clipboard", val: themeHub.dockShowClipboard, k: "clip" },
                                                        { l: "DropShelf", val: themeHub.dockShowDropShelf, k: "drop" },
                                                        { l: "Trash",     val: themeHub.dockShowTrash,     k: "trash" }
                                                    ]
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: (parent.width - 12) * 0.5; height: 52; radius: 14
                                                        color: modelData.val ? "#ECFDF5" : "#F8FAFC"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                        Rectangle {
                                                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                                            width: 58; height: 28; radius: 14; color: modelData.val ? themeHub.accentA : "#CBD5E1"; border.width: 2; border.color: "#1A1B2E"
                                                            Text { anchors.centerIn: parent; text: modelData.val ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (modelData.k === "finder") themeHub.setDockShowFinder(!themeHub.dockShowFinder)
                                                                else if (modelData.k === "clip") themeHub.setDockShowClipboard(!themeHub.dockShowClipboard)
                                                                else if (modelData.k === "drop") themeHub.setDockShowDropShelf(!themeHub.dockShowDropShelf)
                                                                else if (modelData.k === "trash") themeHub.setDockShowTrash(!themeHub.dockShowTrash)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Right: Widgets, Visualizer & Wallpaper Selector
                                    Rectangle {
                                        width: (parent.width - 24) * 0.5; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                                            Text { text: "WIDGETS, VISUALIZER & WALLPAPER"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }

                                            // Desktop widgets grid (all 7 SekaiDesk widgets)
                                            Grid {
                                                columns: 4; columnSpacing: 8; rowSpacing: 8; width: parent.width
                                                Repeater {
                                                    model: [
                                                        { k: "clock",    l: "Clock" },
                                                        { k: "weather",  l: "Weather" },
                                                        { k: "calendar", l: "Calendar" },
                                                        { k: "profile",  l: "Profile" },
                                                        { k: "todo",     l: "To-Do" },
                                                        { k: "notes",    l: "Notes" },
                                                        { k: "lyrics",   l: "Lyrics" }
                                                    ]
                                                    delegate: Rectangle {
                                                        id: widChip
                                                        required property var modelData
                                                        readonly property bool on: themeHub.widgetVisible(modelData.k)
                                                        width: (parent.width - 24) / 4; height: 44; radius: 13
                                                        color: widChip.on ? themeHub.accentA : "#F1F5F9"
                                                        border.width: 2.5; border.color: "#1A1B2E"
                                                        Text { anchors.centerIn: parent; text: (widChip.on ? "✓ " : "") + modelData.l; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.setWidgetVisible(modelData.k, !widChip.on) }
                                                    }
                                                }
                                            }

                                            // Visualizer toggle + styles
                                            Rectangle {
                                                width: parent.width; height: 112; radius: 16; color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Column {
                                                    anchors.fill: parent; anchors.margins: 14; spacing: 10
                                                    Item {
                                                        width: parent.width; height: 30
                                                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "AUDIO VISUALIZER"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                        Rectangle {
                                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                                            width: 72; height: 30; radius: 15; color: VisualizerService.enabled ? themeHub.accentA : "#CBD5E1"; border.width: 2; border.color: "#1A1B2E"
                                                            Text { anchors.centerIn: parent; text: VisualizerService.enabled ? "ON" : "OFF"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: VisualizerService.enabled = !VisualizerService.enabled }
                                                        }
                                                    }
                                                    Row {
                                                        width: parent.width; spacing: 8
                                                        Repeater {
                                                            model: ["sekai", "bars", "ring", "dots", "wave"]
                                                            delegate: Rectangle {
                                                                required property string modelData
                                                                width: (parent.width - 32) / 5; height: 38; radius: 10
                                                                color: VisualizerService.style === modelData ? themeHub.accentB : "#FFFFFF"
                                                                border.width: 2; border.color: "#1A1B2E"
                                                                Text { anchors.centerIn: parent; text: modelData.toUpperCase(); font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: VisualizerService.style = modelData }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Wallpaper Selector + Random + Profile avatar picker buttons
                                            Rectangle {
                                                width: parent.width; height: 54; radius: 16
                                                color: openWallMa.containsMouse ? themeHub.accentB : themeHub.accentA
                                                border.width: 3; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "🖼 OPEN WALLPAPER SELECTOR"; font.family: "Segoe UI"; font.pixelSize: 15; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea {
                                                    id: openWallMa
                                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        themeHub.settingsOpen = false
                                                        topBarWindow.quickPanelOpen = false
                                                        themeHub.wallpaperSelectorOpen = true
                                                    }
                                                }
                                            }
                                            Row {
                                                width: parent.width; spacing: 12
                                                Rectangle {
                                                    width: (parent.width - 12) * 0.5; height: 48; radius: 14; color: "#F1F5F9"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: "🎲 RANDOM WALLPAPER"; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperService.nextRandomWallpaper() }
                                                }
                                                Rectangle {
                                                    width: (parent.width - 12) * 0.5; height: 48; radius: 14; color: "#F1F5F9"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Text { anchors.centerIn: parent; text: "🖼 PICK PROFILE AVATAR"; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            quickPanelWindow.pickingFile = true
                                                            const p = SystemControl.pickImageFile("Choose Profile Avatar Image")
                                                            quickPanelWindow.pickingFile = false
                                                            if (p && p.length > 0) themeHub.setProfileAvatar(p)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ==== SUBPAGE 05: HOTKEYS & SYSTEM ====
                                Row {
                                    visible: themeHub.settingsSection === "system"
                                    anchors.fill: parent
                                    spacing: 24

                                    Rectangle {
                                        width: (parent.width - 24) * 0.52; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                                            Text { text: "GLOBAL SHORTCUTS"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                            Repeater {
                                                model: [
                                                    { keys: "ALT + SPACE",     desc: "Open Spotlight Search & PowerTools" },
                                                    { keys: "CTRL + ALT + V",  desc: "Open Clipboard History & Snippets" },
                                                    { keys: "CTRL + ALT + A",  desc: "Toggle 2.5D QuickPanel Smartphone" },
                                                    { keys: "TOPBAR BAND",     desc: "Enter Edit Desktop Mode (Scrapbook)" },
                                                    { keys: "ESC",             desc: "Back out of active overlay / modal" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: parent.width; height: 64; radius: 16; color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                    Row {
                                                        anchors.fill: parent; anchors.margins: 14; spacing: 14
                                                        Rectangle {
                                                            width: 156; height: 34; radius: 10; anchors.verticalCenter: parent.verticalCenter
                                                            color: themeHub.accentA; border.width: 2; border.color: "#1A1B2E"
                                                            Text { anchors.centerIn: parent; text: modelData.keys; font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                                                        }
                                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.desc; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.DemiBold; color: "#1A1B2E" }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: (parent.width - 24) * 0.48; height: parent.height
                                        radius: 24; color: "#FFFFFF"; border.width: 3.5; border.color: "#1A1B2E"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 24; spacing: 14
                                            Text { text: "HARDWARE & ACTIONS"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
                                            Rectangle {
                                                width: parent.width; height: 152; radius: 18; color: "#F8FAFC"; border.width: 2.5; border.color: "#1A1B2E"
                                                Column {
                                                    anchors.fill: parent; anchors.margins: 18; spacing: 8
                                                    Text { text: "Machine: " + (WindowTracker.machineName || "Windows PC") + "  ·  User: " + (WindowTracker.userName || "User"); font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                    Text { text: "Uptime: " + (WindowTracker.uptimeText || "--"); font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "#475569" }
                                                    Text { text: "CPU: " + WindowTracker.cpuUsage + "%  (" + (WindowTracker.cpuTemp >= 0 ? WindowTracker.cpuTemp + "°C" : "--") + ")   ·   RAM: " + WindowTracker.ramUsage + "%"; font.family: "Consolas"; font.pixelSize: 13; font.weight: Font.Bold; color: "#0F172A" }
                                                    Text { text: "Display: " + themeHub.screenW + " x " + themeHub.screenH + "   ·   Band: " + themeHub.currentBand.name; font.family: "Consolas"; font.pixelSize: 13; font.weight: Font.Bold; color: "#0F172A" }
                                                }
                                            }
                                            Rectangle {
                                                width: parent.width; height: 52; radius: 16; color: "#E0F2FE"; border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "⚙ OPEN WINDOWS SYSTEM SETTINGS"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: SystemControl.openSettings("ms-settings:") }
                                            }
                                            Rectangle {
                                                width: parent.width; height: 52; radius: 16; color: "#FEF3C7"; border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "↺ RESET ALL WIDGET POSITIONS"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: themeHub.resetWidgetPositions() }
                                            }
                                            Rectangle {
                                                width: parent.width; height: 52; radius: 16; color: "#FFE4E6"; border.width: 2.5; border.color: "#1A1B2E"
                                                Text { anchors.centerIn: parent; text: "⏻ QUIT SEKAIDESK SHELL"; font.family: "Segoe UI"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.quit() }
                                            }
                                        }
                                    }
                                }

                                // ==== SUBPAGE 06: ABOUT ====
                                Item {
                                    id: aboutSubpage
                                    visible: themeHub.settingsSection === "about"
                                    anchors.fill: parent
                                    property int comboCount: 0
                                    readonly property int activeWidgetCount:
                                        (themeHub.wClockVisible ? 1 : 0)
                                        + (themeHub.wWeatherVisible ? 1 : 0)
                                        + (themeHub.wTodoVisible ? 1 : 0)
                                        + (themeHub.wNotesVisible ? 1 : 0)
                                        + (themeHub.wLyricsVisible ? 1 : 0)
                                        + (themeHub.wProfileVisible ? 1 : 0)
                                        + (themeHub.wCalendarVisible ? 1 : 0)

                                    Column {
                                        anchors.fill: parent
                                        spacing: 18

                                        // Hero SekaiPlate Banner
                                        Item {
                                            width: parent.width
                                            height: 152

                                            Rectangle {
                                                x: 5; y: 5
                                                width: parent.width - 5
                                                height: parent.height - 5
                                                radius: 24
                                                color: "#1A1B2E"
                                            }

                                            Rectangle {
                                                width: parent.width - 5
                                                height: parent.height - 5
                                                radius: 24
                                                border.width: 3.5
                                                border.color: "#1A1B2E"
                                                clip: true
                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: themeHub.accentA }
                                                    GradientStop { position: 1.0; color: themeHub.accentB }
                                                }

                                                // Subtle slanted stage-light bands
                                                Rectangle {
                                                    x: parent.width * 0.56; y: -40
                                                    width: 72; height: parent.height + 90
                                                    rotation: 18
                                                    color: Qt.rgba(1, 1, 1, 0.18)
                                                }
                                                Rectangle {
                                                    x: parent.width * 0.67; y: -40
                                                    width: 28; height: parent.height + 90
                                                    rotation: 18
                                                    color: Qt.rgba(1, 1, 1, 0.14)
                                                }

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 22
                                                    anchors.rightMargin: 22
                                                    spacing: 20

                                                    // Interactive rotating SekaiDesk emblem (click for combo bounce!)
                                                    Item {
                                                        width: 96; height: 96
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Rectangle {
                                                            x: 4; y: 4; width: 92; height: 92; radius: 26
                                                            color: "#1A1B2E"
                                                            rotation: (aboutSubpage.comboCount % 2 === 0) ? -4 : 4
                                                            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                        }
                                                        Rectangle {
                                                            id: abtEmblemCard
                                                            width: 92; height: 92; radius: 26
                                                            color: "#FFFDF7"
                                                            border.width: 3.5; border.color: "#1A1B2E"
                                                            rotation: (aboutSubpage.comboCount % 2 === 0) ? -4 : 4
                                                            scale: abtEmblemMa.pressed ? 0.91 : (abtEmblemMa.containsMouse ? 1.06 : 1.0)
                                                            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: 62; height: 62; radius: 18
                                                                color: "#1A1B2E"
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "✦"
                                                                    font.pixelSize: 38
                                                                    font.weight: Font.Black
                                                                    color: themeHub.accentA
                                                                    rotation: aboutSubpage.comboCount * 45
                                                                    Behavior on rotation { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
                                                                }
                                                            }
                                                            MouseArea {
                                                                id: abtEmblemMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: aboutSubpage.comboCount += 1
                                                            }
                                                        }
                                                    }

                                                    // Center Title & Feature Chips
                                                    Column {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - 96 - 196 - 40
                                                        spacing: 6

                                                        Row {
                                                            spacing: 10
                                                            Text {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: "SEKAIDESK SHELL"
                                                                font.family: "Segoe UI"; font.pixelSize: 30; font.weight: Font.Black
                                                                color: "#1A1B2E"
                                                            }
                                                            Rectangle {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: abtVerTxt.implicitWidth + 18; height: 26; radius: 13
                                                                color: "#1A1B2E"
                                                                Text { id: abtVerTxt; anchors.centerIn: parent; text: "v0.1.0 · WIN64"; font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black; color: "#FFFFFF" }
                                                            }
                                                            Rectangle {
                                                                visible: aboutSubpage.comboCount > 0
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                width: abtComboTxt.implicitWidth + 16; height: 26; radius: 13
                                                                color: "#FEF3C7"; border.width: 2; border.color: "#1A1B2E"
                                                                Text { id: abtComboTxt; anchors.centerIn: parent; text: "WONDERHOY ×" + aboutSubpage.comboCount + "!"; font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            elide: Text.ElideRight
                                                            text: "SekaiPop-Comic Desktop Environment for Windows · Qt 6.8.2 Quick & C++20 Win32 Layer"
                                                            font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Bold
                                                            color: Qt.rgba(26/255, 27/255, 46/255, 0.86)
                                                        }

                                                        Row {
                                                            spacing: 8
                                                            topPadding: 2
                                                            Repeater {
                                                                model: ["2.5D Phone Center", "SekaiOsd", "Live Visualizer", "Sticker Lyrics", "Weather Card"]
                                                                delegate: Rectangle {
                                                                    required property string modelData
                                                                    width: abtFeatTxt.implicitWidth + 16; height: 24; radius: 12
                                                                    color: Qt.rgba(1, 1, 1, 0.82); border.width: 2; border.color: "#1A1B2E"
                                                                    Text { id: abtFeatTxt; anchors.centerIn: parent; text: modelData; font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: "#1A1B2E" }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Right Active Band Sticker Card
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 196; height: 86; radius: 18
                                                        color: "#FFFDF7"; border.width: 3; border.color: "#1A1B2E"
                                                        Column {
                                                            anchors.centerIn: parent
                                                            width: parent.width - 20
                                                            spacing: 4
                                                            Text {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                text: "ACTIVE UNIT THEME"
                                                                font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Black
                                                                color: "#64748B"
                                                            }
                                                            Text {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                width: parent.width
                                                                horizontalAlignment: Text.AlignHCenter
                                                                elide: Text.ElideRight
                                                                text: themeHub.bandName.toUpperCase()
                                                                font.family: "Segoe UI"; font.pixelSize: 16; font.weight: Font.Black
                                                                color: "#1A1B2E"
                                                            }
                                                            Rectangle {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                width: abtShortTxt.implicitWidth + 18; height: 22; radius: 11
                                                                color: themeHub.accentA; border.width: 2; border.color: "#1A1B2E"
                                                                Text { id: abtShortTxt; anchors.centerIn: parent; text: themeHub.bandShort; font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Bottom Twin Cards: Creator Passport + Active Loadout
                                        Row {
                                            width: parent.width
                                            height: parent.height - 170
                                            spacing: 20

                                            // Left Card: Creator Passport & Handwritten Signature
                                            Rectangle {
                                                width: (parent.width - 20) * 0.52
                                                height: parent.height
                                                radius: 24
                                                color: "#FFFFFF"
                                                border.width: 3.5
                                                border.color: "#1A1B2E"

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: 22
                                                    spacing: 14

                                                    Row {
                                                        width: parent.width
                                                        spacing: 10
                                                        Rectangle {
                                                            width: abtPassLbl.implicitWidth + 18; height: 26; radius: 13
                                                            color: themeHub.accentA; border.width: 2; border.color: "#1A1B2E"
                                                            Text { id: abtPassLbl; anchors.centerIn: parent; text: "CREATOR PASSPORT"; font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                                                        }
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "WINDOWS PORT & CUSTOM STUDIO"
                                                            font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Bold; color: "#64748B"
                                                        }
                                                    }

                                                    // Profile / Attribution Row
                                                    Row {
                                                        width: parent.width
                                                        spacing: 14

                                                        Rectangle {
                                                            width: 64; height: 64; radius: 32
                                                            color: "#F1F5F9"; border.width: 3; border.color: "#1A1B2E"
                                                            clip: true
                                                            Image {
                                                                anchors.fill: parent
                                                                anchors.margins: 2
                                                                source: themeHub.profileAvatarUrl !== "" ? themeHub.profileAvatarUrl : themeHub.quickPanelAvatarUrl
                                                                fillMode: Image.PreserveAspectCrop
                                                                smooth: true
                                                                visible: status === Image.Ready
                                                            }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "✦"
                                                                font.pixelSize: 26; font.weight: Font.Black; color: "#1A1B2E"
                                                                visible: (themeHub.profileAvatarUrl === "" && themeHub.quickPanelAvatarUrl === "")
                                                            }
                                                        }

                                                        Column {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: parent.width - 78
                                                            spacing: 3
                                                            Row {
                                                                spacing: 8
                                                                Text {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: themeHub.profileName || "Yozora"
                                                                    font.family: "Segoe UI"; font.pixelSize: 20; font.weight: Font.Black; color: "#1A1B2E"
                                                                }
                                                                Rectangle {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: 64; height: 20; radius: 10
                                                                    color: themeHub.accentB; border.width: 2; border.color: "#1A1B2E"
                                                                    Text { anchors.centerIn: parent; text: "AUTHOR"; font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Black; color: "#1A1B2E" }
                                                                }
                                                            }
                                                            Text {
                                                                width: parent.width
                                                                elide: Text.ElideRight
                                                                text: "Windows Desktop Port, C++ Win32 & QML Craft"
                                                                font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Bold; color: "#334155"
                                                            }
                                                            Text {
                                                                width: parent.width
                                                                elide: Text.ElideRight
                                                                text: "Inspired by SekaiPop (Hyprland) · Aesthetic Pop-Comic Shell"
                                                                font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#64748B"
                                                            }
                                                        }
                                                    }

                                                    // Handwritten Signature Box
                                                    Rectangle {
                                                        width: parent.width
                                                        height: Math.max(108, parent.height - 118)
                                                        radius: 18
                                                        color: "#FFFDF7"
                                                        border.width: 2.5
                                                        border.color: "#1A1B2E"
                                                        clip: true

                                                        Text {
                                                            anchors.left: parent.left; anchors.leftMargin: 14
                                                            anchors.top: parent.top; anchors.topMargin: 10
                                                            text: "SIGNATURE // AUTHENTICATED"
                                                            font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Black
                                                            color: "#94A3B8"
                                                        }

                                                        Image {
                                                            anchors.centerIn: parent
                                                            anchors.verticalCenterOffset: 4
                                                            width: parent.width - 48
                                                            height: parent.height - 34
                                                            source: "qrc:/qml/icons/handsig-yozora.png"
                                                            fillMode: Image.PreserveAspectFit
                                                            smooth: true
                                                            mipmap: true
                                                        }

                                                        Rectangle {
                                                            anchors.right: parent.right; anchors.rightMargin: 14
                                                            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                                                            width: abtSealTxt.implicitWidth + 14; height: 22; radius: 11
                                                            rotation: -4
                                                            color: themeHub.accentB; border.width: 2; border.color: "#1A1B2E"
                                                            Text { id: abtSealTxt; anchors.centerIn: parent; text: "✦ SEKAI CERTIFIED"; font.family: "Consolas"; font.pixelSize: 9; font.weight: Font.Black; color: "#1A1B2E" }
                                                        }
                                                    }
                                                }
                                            }

                                            // Right Card: Active Loadout & Stack
                                            Rectangle {
                                                width: (parent.width - 20) * 0.48
                                                height: parent.height
                                                radius: 24
                                                color: "#FFFFFF"
                                                border.width: 3.5
                                                border.color: "#1A1B2E"

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: 22
                                                    spacing: 14

                                                    Text {
                                                        text: "ACTIVE SHELL & STACK"
                                                        font.family: "Segoe UI"; font.pixelSize: 17; font.weight: Font.Black; color: "#1A1B2E"
                                                    }

                                                    Grid {
                                                        width: parent.width
                                                        columns: 2
                                                        columnSpacing: 12
                                                        rowSpacing: 12
                                                        Repeater {
                                                            model: [
                                                                { k: "TOP BAR",       v: themeHub.barStyle.toUpperCase() + (themeHub.barAutoHide ? " · AUTO" : "") },
                                                                { k: "BOTTOM DOCK",   v: themeHub.dockStyle.toUpperCase() + (themeHub.dockAutoHide ? " · DODGE" : "") },
                                                                { k: "NOTIFICATIONS", v: themeHub.notifyStyle.toUpperCase() + (themeHub.osdEnabled ? " · OSD" : "") },
                                                                { k: "DISPLAY",       v: themeHub.screenW + "×" + themeHub.screenH + " · " + aboutSubpage.activeWidgetCount + "/7 WGT" }
                                                            ]
                                                            delegate: Rectangle {
                                                                required property var modelData
                                                                width: (parent.width - 12) * 0.5
                                                                height: 62
                                                                radius: 14
                                                                color: "#F8FAFC"
                                                                border.width: 2.5
                                                                border.color: "#1A1B2E"
                                                                Column {
                                                                    anchors.centerIn: parent
                                                                    width: parent.width - 18
                                                                    spacing: 2
                                                                    Text { text: modelData.k; font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Black; color: "#64748B" }
                                                                    Text { width: parent.width; elide: Text.ElideRight; text: modelData.v; font.family: "Consolas"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        text: "ENGINE & TECHNOLOGIES"
                                                        font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black; color: "#64748B"
                                                    }

                                                    Flow {
                                                        width: parent.width
                                                        spacing: 8
                                                        Repeater {
                                                            model: ["Qt 6.8.2 Quick", "C++20 / Win32", "D3D11 RHI", "DWM Blur", "WASAPI Peak", "SMTC Media", "LRCLIB Sync", "Open-Meteo"]
                                                            delegate: Rectangle {
                                                                required property string modelData
                                                                width: abtTechTxt.implicitWidth + 18; height: 28; radius: 14
                                                                color: "#F8FAFC"; border.width: 2; border.color: "#1A1B2E"
                                                                Text { id: abtTechTxt; anchors.centerIn: parent; text: modelData; font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Bold; color: "#1A1B2E" }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Left-side Phone Pill Notch + Camera Lens + Glint
                        Item {
                            x: 16
                            y: (parent.height - 196) * 0.5
                            width: 40
                            height: 196
                            z: 50
                            Rectangle {
                                x: -16; y: 0; width: 52; height: 196; radius: 26
                                color: "#1A1B2E"
                            }
                            Rectangle {
                                x: 8; y: 24; width: 20; height: 20; radius: 10
                                color: "#0F172A"
                                Rectangle {
                                    anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: "#1E3A5F"
                                    Rectangle { x: 2; y: 2; width: 3; height: 3; radius: 2; color: "#93C5FD" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // #2 Dock-Safe Notification Peek (Bottom-Right Mini Phone) & Popup Stack
    // =========================================================================
    PanelWindow {
        id: notifPeekWindow
        readonly property bool quietNow: themeHub.notifyQuietFullscreen && topBarWindow.fullscreenActive
        readonly property real dockRightEdge: dockWindow.x > 0
                                              ? (dockWindow.x + dockWindow.width)
                                              : ((themeHub.screenW + dockWindow.width) * 0.5)
        readonly property bool usePopupMode: themeHub.notifyStyle === "popup"
                                             || ((dockRightEdge + 372) > themeHub.screenW)

        property var peekItem: null
        property real peekProgress: 0.0
        property bool peekHovered: false
        property var popupItems: []
        property bool stackHovered: false

        visible: !quietNow
                 && themeHub.notifyStyle !== "off"
                 && (!usePopupMode
                     ? (peekItem !== null || peekProgress > 0.005)
                     : popupItems.length > 0)
        clickThrough: false
        color: "transparent"

        width: usePopupMode ? 356 : 348
        height: usePopupMode ? Math.min(380, Math.max(108, popupItems.length * 108 + 16)) : 156
        x: Math.max(0, themeHub.screenW - width - (usePopupMode ? 16 : 20))
        y: usePopupMode ? 38 : Math.max(0, themeHub.screenH - height)

        mask: usePopupMode
              ? [{ x: 0, y: 0, width: width, height: height }]
              : [{ x: 0, y: Math.max(0, Math.round((1.0 - peekProgress) * height)), width: width, height: Math.max(1, Math.round(peekProgress * height)) }]

        function pushNotification(item) {
            if (!item || themeHub.notifyStyle === "off" || quietNow)
                return
            if (usePopupMode) {
                const next = popupItems.slice(0)
                next.unshift(item)
                if (next.length > 3)
                    next.length = 3
                popupItems = next
                popupDismissTimer.restart()
            } else {
                peekItem = item
                peekExitAnim.stop()
                peekEnterAnim.restart()
                peekDismissTimer.restart()
            }
        }

        function dismissPeek() {
            peekDismissTimer.stop()
            peekEnterAnim.stop()
            peekExitAnim.restart()
        }

        function dismissPopupAt(idx) {
            const next = popupItems.slice(0)
            if (idx >= 0 && idx < next.length)
                next.splice(idx, 1)
            popupItems = next
            if (next.length === 0)
                popupDismissTimer.stop()
        }

        Connections {
            target: NotificationService
            function onNewNotificationReceived(item) {
                notifPeekWindow.pushNotification(item)
            }
        }

        NumberAnimation {
            id: peekEnterAnim
            target: notifPeekWindow
            property: "peekProgress"
            to: 1.0
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 0.9
        }

        NumberAnimation {
            id: peekExitAnim
            target: notifPeekWindow
            property: "peekProgress"
            to: 0.0
            duration: 190
            easing.type: Easing.InCubic
            onFinished: {
                if (notifPeekWindow.peekProgress <= 0.01)
                    notifPeekWindow.peekItem = null
            }
        }

        Timer {
            id: peekDismissTimer
            interval: 4800
            repeat: false
            running: notifPeekWindow.visible && !notifPeekWindow.usePopupMode && notifPeekWindow.peekItem !== null && !notifPeekWindow.peekHovered
            onTriggered: notifPeekWindow.dismissPeek()
        }

        Timer {
            id: popupDismissTimer
            interval: 4800
            repeat: true
            running: notifPeekWindow.visible && notifPeekWindow.usePopupMode && notifPeekWindow.popupItems.length > 0 && !notifPeekWindow.stackHovered
            onTriggered: {
                if (notifPeekWindow.popupItems.length > 0)
                    notifPeekWindow.dismissPopupAt(notifPeekWindow.popupItems.length - 1)
            }
        }

        // ---- Mode A: Bottom-Right Mini 2.5D Phone Peek ----
        Item {
            visible: !notifPeekWindow.usePopupMode && notifPeekWindow.peekItem !== null
            width: 332
            height: 150
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((1.0 - notifPeekWindow.peekProgress) * notifPeekWindow.height) + 8

            HoverHandler {
                id: peekHoverHandler
                onHoveredChanged: notifPeekWindow.peekHovered = hovered
            }

            // Outer mini phone bezel rising cleanly from screen bottom edge
            Rectangle {
                anchors.fill: parent
                topLeftRadius: 28
                topRightRadius: 28
                bottomLeftRadius: 0
                bottomRightRadius: 0
                color: "#2E3148"
                border.width: 3
                border.color: "#1A1B2E"
            }
            Rectangle {
                x: 8; y: 8
                width: parent.width - 16
                height: parent.height - 4
                topLeftRadius: 22
                topRightRadius: 22
                color: "#FAFAFF"
                border.width: 2.5
                border.color: "#1A1B2E"
                clip: true

                // Top notch pill
                Rectangle {
                    x: (parent.width - 84) * 0.5
                    y: -6
                    width: 84; height: 18; radius: 9
                    color: "#1A1B2E"
                    Rectangle { x: 14; y: 8; width: 6; height: 6; radius: 3; color: "#38BDF8" }
                }

                // Accent left bar
                Rectangle {
                    x: 12; y: 20; width: 5; height: parent.height - 34; radius: 3
                    color: themeHub.accentA
                }

                // Header row: App badge + Time + Close
                Row {
                    x: 24; y: 18
                    width: parent.width - 36
                    spacing: 8
                    Rectangle {
                        height: 20
                        width: Math.min(168, peekAppTxt.implicitWidth + 14)
                        radius: 8
                        color: themeHub.accentA
                        border.width: 1.5; border.color: "#1A1B2E"
                        Text {
                            id: peekAppTxt
                            anchors.centerIn: parent
                            width: parent.width - 10
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            text: (notifPeekWindow.peekItem && notifPeekWindow.peekItem.app ? notifPeekWindow.peekItem.app : "NOTIFICATION").toUpperCase()
                            font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black; color: "#1A1B2E"
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: notifPeekWindow.peekItem && notifPeekWindow.peekItem.timeText ? notifPeekWindow.peekItem.timeText : ""
                        font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Bold; color: "#64748B"
                    }
                }

                // Title & Body
                Text {
                    x: 24; y: 44
                    width: parent.width - 52
                    elide: Text.ElideRight
                    text: notifPeekWindow.peekItem ? (notifPeekWindow.peekItem.title || "") : ""
                    font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E"
                }
                Text {
                    x: 24; y: 66
                    width: parent.width - 38
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    text: notifPeekWindow.peekItem ? (notifPeekWindow.peekItem.body || "") : ""
                    font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#475569"
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            notifPeekWindow.dismissPeek()
                        } else {
                            notifPeekWindow.dismissPeek()
                            quickPanelWindow.bottomTab = "notifications"
                            topBarWindow.quickPanelOpen = true
                            NotificationService.refresh()
                        }
                    }
                }

                // Close pill
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.top: parent.top; anchors.topMargin: 12
                    width: 24; height: 24; radius: 12
                    color: peekCloseMa.containsMouse ? "#FB7185" : "#F1F5F9"
                    border.width: 2; border.color: "#1A1B2E"
                    Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                    MouseArea {
                        id: peekCloseMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: notifPeekWindow.dismissPeek()
                    }
                }
            }
        }

        // ---- Mode B: Top-Right Popup Card Stack (<= 3 cards) ----
        Column {
            visible: notifPeekWindow.usePopupMode
            anchors.top: parent.top
            anchors.right: parent.right
            spacing: 8
            width: parent.width

            HoverHandler {
                onHoveredChanged: notifPeekWindow.stackHovered = hovered
            }

            Repeater {
                model: notifPeekWindow.popupItems
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: notifPeekWindow.width
                    height: 98

                    Rectangle { x: 4; y: 4; width: parent.width - 6; height: parent.height - 4; radius: 18; color: "#1A1B2E" }
                    Rectangle {
                        width: parent.width - 6; height: parent.height - 4; radius: 18
                        color: "#FAFAFF"; border.width: 3; border.color: "#1A1B2E"
                        clip: true

                        Rectangle { x: 0; y: 0; width: 8; height: parent.height; color: themeHub.accentA }

                        Row {
                            x: 16; y: 10; spacing: 8
                            Rectangle {
                                height: 20; width: Math.min(180, stAppTxt.implicitWidth + 14); radius: 8
                                color: themeHub.accentA; border.width: 1.5; border.color: "#1A1B2E"
                                Text {
                                    id: stAppTxt
                                    anchors.centerIn: parent
                                    width: parent.width - 8; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                                    text: (modelData.app || "NOTIFICATION").toUpperCase()
                                    font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black; color: "#1A1B2E"
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.timeText || ""
                                font.family: "Consolas"; font.pixelSize: 10; font.weight: Font.Bold; color: "#64748B"
                            }
                        }

                        Text {
                            x: 16; y: 36; width: parent.width - 48; elide: Text.ElideRight
                            text: modelData.title || ""
                            font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E"
                        }
                        Text {
                            x: 16; y: 56; width: parent.width - 28; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                            text: modelData.body || ""
                            font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#475569"
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    notifPeekWindow.dismissPopupAt(index)
                                } else {
                                    notifPeekWindow.dismissPopupAt(index)
                                    quickPanelWindow.bottomTab = "notifications"
                                    topBarWindow.quickPanelOpen = true
                                    NotificationService.refresh()
                                }
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.top: parent.top; anchors.topMargin: 8
                            width: 24; height: 24; radius: 12
                            color: stCloseMa.containsMouse ? "#FB7185" : "#F1F5F9"
                            border.width: 2; border.color: "#1A1B2E"
                            Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 14; font.weight: Font.Black; color: "#1A1B2E" }
                            MouseArea {
                                id: stCloseMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: notifPeekWindow.dismissPopupAt(index)
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
                focusActivate()
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
                        GradientStop { position: 0.0; color: themeHub.accentA }
                        GradientStop { position: 1.0; color: themeHub.accentB }
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
                                color: themeHub.accentB
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
                                    color: themeHub.accentA
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
                                    color: themeHub.accentA
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
                                    color: index === calendarPopupWindow.viewMonth ? themeHub.accentA : "#475569"
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
                focusActivate()
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
                        color: SystemControl.wifiEnabled ? themeHub.accentA : "#CBD5E1"
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
                                color: modelData.connected ? themeHub.accentB : (wnMouse.containsMouse ? "#E0F2FE" : "#FFFFFF")
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
                focusActivate()
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
    // Independent TopBar Volume & Per-App Mixer Popup (decoupled from Phone)
    // =========================================================================
    PanelWindow {
        id: volumePopupWindow
        visible: topBarWindow.volumePopupOpen && !topBarWindow.fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardShadow: 4
        property double openedAt: 0

        width: 344 + cardShadow
        height: Math.min(540, volPopupCol.implicitHeight + 24) + cardShadow
        x: Math.max(8, (topBarWindow.anchors.margins.left + topBarWindow.width) - width - 6)
        y: 34

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                AudioService.refreshOutputDevices()
                AudioService.refreshSessions()
                focusActivate()
            }
        }

        Timer {
            interval: 60
            repeat: true
            running: volumePopupWindow.visible
            onTriggered: {
                if ((Date.now() - volumePopupWindow.openedAt) > 220 && volumePopupWindow.isPointerOutsideAndPressed()) {
                    topBarWindow.volumePopupClosedAt = Date.now()
                    topBarWindow.volumePopupOpen = false
                }
            }
        }

        Timer {
            interval: 650
            repeat: true
            running: volumePopupWindow.visible
            onTriggered: AudioService.refreshSessions()
        }

        Rectangle {
            x: volumePopupWindow.cardShadow
            y: volumePopupWindow.cardShadow
            width: volumePopupWindow.width - volumePopupWindow.cardShadow
            height: volumePopupWindow.height - volumePopupWindow.cardShadow
            radius: 16
            color: "#1A1B2E"
        }

        Rectangle {
            x: 0
            y: 0
            width: volumePopupWindow.width - volumePopupWindow.cardShadow
            height: volumePopupWindow.height - volumePopupWindow.cardShadow
            radius: 16
            color: "#F8FAFC"
            border.width: 2
            border.color: "#1A1B2E"

            Column {
                id: volPopupCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                // Master Volume Card
                Rectangle {
                    width: parent.width
                    height: 62
                    radius: 12
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 24
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Rectangle {
                                    width: 24; height: 24; radius: 8
                                    color: AudioService.masterMuted ? "#FEE2E2" : themeHub.accentB
                                    border.width: 1.5; border.color: "#1A1B2E"
                                    Image {
                                        anchors.centerIn: parent; width: 14; height: 14; sourceSize.width: 28; sourceSize.height: 28; smooth: true
                                        source: AudioService.masterMuted ? "qrc:/qml/icons/volume-cross-dark.svg" : "qrc:/qml/icons/volume-loud-dark.svg"
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.toggleMasterMute() }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Master Volume"
                                    font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E"
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: AudioService.masterMuted ? "Muted" : (AudioService.masterVolume + "%")
                                font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Black
                                color: AudioService.masterMuted ? "#DC2626" : "#1A1B2E"
                            }
                        }

                        Item {
                            width: parent.width; height: 16
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 12; radius: 6
                                color: "#E2E8F0"; border.width: 1.5; border.color: "#1A1B2E"
                                Rectangle {
                                    x: 2; y: 2; height: 8; radius: 4
                                    width: Math.max(0, (parent.width - 4) * (AudioService.masterVolume / 100.0))
                                    color: AudioService.masterMuted ? "#94A3B8" : themeHub.accentA
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                function applyMaster(mx) {
                                    AudioService.setMasterVolume(Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100))
                                }
                                onPressed: mouse => applyMaster(mouse.x)
                                onPositionChanged: mouse => { if (pressed) applyMaster(mouse.x) }
                            }
                        }
                    }
                }

                // Microphone Card (if supported)
                Rectangle {
                    visible: AudioService.micSupported
                    width: parent.width
                    height: 58
                    radius: 12
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 5

                        Item {
                            width: parent.width
                            height: 22
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Rectangle {
                                    width: 22; height: 22; radius: 7
                                    color: AudioService.micMuted ? "#FEE2E2" : "#E0F2FE"
                                    border.width: 1.5; border.color: "#1A1B2E"
                                    Text {
                                        anchors.centerIn: parent
                                        text: AudioService.micMuted ? "🔇" : "🎙"
                                        font.pixelSize: 12
                                        color: "#1A1B2E"
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.toggleMicMute() }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Microphone"
                                    font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Bold; color: "#1A1B2E"
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: AudioService.micMuted ? "Muted" : (AudioService.micVolume + "%")
                                font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black
                                color: AudioService.micMuted ? "#DC2626" : "#1A1B2E"
                            }
                        }

                        Item {
                            width: parent.width; height: 14
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 10; radius: 5
                                color: "#E2E8F0"; border.width: 1.5; border.color: "#1A1B2E"
                                Rectangle {
                                    x: 2; y: 2; height: 6; radius: 3
                                    width: Math.max(0, (parent.width - 4) * (AudioService.micVolume / 100.0))
                                    color: AudioService.micMuted ? "#94A3B8" : themeHub.accentB
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                function applyMic(mx) {
                                    AudioService.setMicVolume(Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100))
                                }
                                onPressed: mouse => applyMic(mouse.x)
                                onPositionChanged: mouse => { if (pressed) applyMic(mouse.x) }
                            }
                        }
                    }
                }

                // Output Device Picker
                Text {
                    visible: AudioService.outputDevices.length > 0
                    text: "OUTPUT DEVICE"
                    font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black; color: "#64748B"
                }

                Flow {
                    visible: AudioService.outputDevices.length > 0
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: AudioService.outputDevices
                        delegate: Rectangle {
                            required property var modelData
                            width: Math.min(volPopupCol.width, vpDevLbl.implicitWidth + 18)
                            height: 26; radius: 10
                            color: modelData.isDefault ? themeHub.accentB : (vpDevMa.containsMouse ? themeHub.hoverTint : "#FFFFFF")
                            border.width: 1.5; border.color: "#1A1B2E"
                            Text {
                                id: vpDevLbl
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, volPopupCol.width - 20)
                                elide: Text.ElideRight
                                text: (modelData.isDefault ? "✓ " : "") + (modelData.name || "Output")
                                font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: "#1A1B2E"
                            }
                            MouseArea {
                                id: vpDevMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.callLater(function() { AudioService.setDefaultOutputDevice(modelData.id) })
                            }
                        }
                    }
                }

                // Per-App Volume Mixer
                Text {
                    text: "APP MIXER (" + AudioService.sessions.length + ")"
                    font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black; color: "#64748B"
                }

                Flickable {
                    width: parent.width
                    height: Math.min(196, Math.max(30, vpMixCol.implicitHeight + 4))
                    contentWidth: width
                    contentHeight: vpMixCol.implicitHeight + 4
                    clip: true

                    Column {
                        id: vpMixCol
                        width: parent.width
                        spacing: 6

                        Text {
                            visible: AudioService.sessions.length === 0
                            text: "No active audio apps right now."
                            font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.DemiBold; color: "#64748B"
                        }

                        Repeater {
                            model: AudioService.sessions
                            delegate: Row {
                                required property var modelData
                                width: vpMixCol.width
                                height: 30
                                spacing: 8

                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18; height: 18
                                    source: modelData.iconUrl || ""
                                    smooth: true; mipmap: true
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 94; elide: Text.ElideRight
                                    text: modelData.name || "App"
                                    font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: "#1A1B2E"
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24; height: 22; radius: 7
                                    color: modelData.muted ? "#FDE68A" : "#FFFFFF"
                                    border.width: 1.5; border.color: "#1A1B2E"
                                    Image {
                                        anchors.centerIn: parent; width: 12; height: 12; sourceSize.width: 24; sourceSize.height: 24; smooth: true
                                        source: modelData.muted ? "qrc:/qml/icons/volume-cross-dark.svg" : "qrc:/qml/icons/volume-loud-dark.svg"
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.toggleAppMute(modelData.id) }
                                }
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 196; height: 18
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 10; radius: 5
                                        color: "#E2E8F0"; border.width: 1.5; border.color: "#1A1B2E"
                                        Rectangle {
                                            x: 2; y: 2; height: 6; radius: 3
                                            width: Math.max(0, (parent.width - 4) * (modelData.volume / 100.0))
                                            color: modelData.muted ? "#94A3B8" : themeHub.accentA
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        function setSessionVol(mx) {
                                            AudioService.setAppVolume(modelData.id, Math.round(Math.max(0, Math.min(1, mx / Math.max(1, width))) * 100))
                                        }
                                        onPressed: mouse => setSessionVol(mouse.x)
                                        onPositionChanged: mouse => { if (pressed) setSessionVol(mouse.x) }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 36; horizontalAlignment: Text.AlignRight
                                    text: modelData.volume + "%"
                                    font.family: "Consolas"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E"
                                }
                            }
                        }
                    }
                }

                // Sound Settings Footer
                Rectangle {
                    width: parent.width
                    height: 28
                    radius: 10
                    color: volSetMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                    border.width: 1.5
                    border.color: "#1A1B2E"
                    Text {
                        anchors.centerIn: parent
                        text: "Sound Settings"
                        font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Bold; color: "#1A1B2E"
                    }
                    MouseArea {
                        id: volSetMa
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            topBarWindow.volumePopupOpen = false
                            SystemControl.openSettings("ms-settings:sound")
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Round 5 Modules (@qml-mods-5): SekaiOsd, VisualizerOverlay, WallpaperSelector
    // =========================================================================
    VisualizerOverlay {
        themeHub: themeHub
        fullscreenActive: topBarWindow.fullscreenActive
    }

    SekaiOsd {
        themeHub: themeHub
        fullscreenActive: topBarWindow.fullscreenActive
    }

    ScreenRound {
        themeHub: themeHub
        fullscreenActive: topBarWindow.fullscreenActive
        scrW: themeHub.screenW
        scrH: themeHub.screenH
    }

    PowerTools {
        themeHub: themeHub
        fullscreenActive: topBarWindow.fullscreenActive
    }

    WallpaperSelector {
        themeHub: themeHub
        fullscreenActive: topBarWindow.fullscreenActive
    }

    DesktopWidgets {
        themeHub: themeHub
        fullscreenActive: topBarWindow.fullscreenActive
    }
}
