import QtQuick
import Quickshell
import SekaiDesk

PanelWindow {
    id: wpWin

    required property var themeHub
    required property bool fullscreenActive

    visible: !!themeHub.wallpaperSelectorOpen && !fullscreenActive
    width: Math.min(themeHub.screenW - 64, 940)
    height: Math.min(themeHub.screenH - 96, 560)
    x: Math.round((themeHub.screenW - width) * 0.5)
    y: Math.round((themeHub.screenH - height) * 0.5)
    clickThrough: false
    color: "transparent"

    property string viewMode: "wheel"   // "wheel" | "grid"
    property string searchQuery: ""
    property int selectedIndex: 0
    property string statusBanner: ""
    property bool openGuard: false
    property var previewPalette: null

    readonly property var filteredWallpapers: {
        const list = WallpaperService.wallpapers || []
        const q = searchQuery.trim().toLowerCase()
        if (q === "")
            return list
        const out = []
        for (let i = 0; i < list.length; ++i) {
            const it = list[i]
            const nm = String(it.name || "").toLowerCase()
            if (nm.indexOf(q) >= 0)
                out.push(it)
        }
        return out
    }

    readonly property var selectedItem: (selectedIndex >= 0 && selectedIndex < filteredWallpapers.length)
        ? filteredWallpapers[selectedIndex]
        : null

    onFilteredWallpapersChanged: {
        if (filteredWallpapers.length === 0)
            selectedIndex = 0
        else if (selectedIndex >= filteredWallpapers.length)
            selectedIndex = filteredWallpapers.length - 1
        updatePreviewPalette()
    }

    onSelectedIndexChanged: updatePreviewPalette()

    function updatePreviewPalette() {
        const it = selectedItem
        if (!it || !it.path) {
            previewPalette = null
            return
        }
        previewPalette = WallpaperService.extractPalette(it.path)
    }

    function selectCurrentWallpaper() {
        const cur = WallpaperService.currentWallpaper || ""
        if (cur === "" || filteredWallpapers.length === 0)
            return
        for (let i = 0; i < filteredWallpapers.length; ++i) {
            if (filteredWallpapers[i].path === cur) {
                selectedIndex = i
                return
            }
        }
    }

    function stepSelection(delta) {
        const n = filteredWallpapers.length
        if (n <= 0)
            return
        selectedIndex = (selectedIndex + delta + n) % n
        if (viewMode === "grid")
            wallGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    }

    function selectRandom() {
        const n = filteredWallpapers.length
        if (n <= 1)
            return
        let next = Math.floor(Math.random() * n)
        if (next === selectedIndex)
            next = (next + 1) % n
        selectedIndex = next
        if (viewMode === "grid")
            wallGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    }

    function cycleSort() {
        const cur = WallpaperService.sortBy || "newest"
        if (cur === "newest")
            WallpaperService.sortBy = "name"
        else if (cur === "name")
            WallpaperService.sortBy = "oldest"
        else
            WallpaperService.sortBy = "newest"
    }

    function applySelected(syncColors) {
        const it = selectedItem
        if (!it || !it.path)
            return
        const ok = WallpaperService.applyWallpaper(it.path)
        if (syncColors) {
            const pal = WallpaperService.extractPalette(it.path)
            if (pal && typeof themeHub.applyWallpaperPalette === "function")
                themeHub.applyWallpaperPalette(pal)
            statusBanner = ok ? "Wallpaper + Palette Synced!" : "Apply failed"
        } else {
            statusBanner = ok ? "Wallpaper Applied!" : "Apply failed"
        }
        bannerTimer.restart()
    }

    function closeSelector() {
        themeHub.wallpaperSelectorOpen = false
    }

    onVisibleChanged: {
        if (visible) {
            WallpaperService.refresh()
            focusActivate()
            keyScope.forceActiveFocus()
            selectCurrentWallpaper()
            updatePreviewPalette()
            openGuard = true
            guardTimer.restart()
        } else {
            openGuard = false
            searchInput.focus = false
        }
    }

    Timer {
        id: guardTimer
        interval: 260
        onTriggered: wpWin.openGuard = false
    }

    Timer {
        id: bannerTimer
        interval: 2200
        onTriggered: wpWin.statusBanner = ""
    }

    Timer {
        interval: 120
        repeat: true
        running: wpWin.visible && !wpWin.openGuard
        onTriggered: {
            if (wpWin.isPointerOutsideAndPressed())
                wpWin.closeSelector()
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: {
            if (searchInput.activeFocus && wpWin.searchQuery !== "") {
                searchInput.text = ""
            } else {
                wpWin.closeSelector()
            }
        }
        Keys.onLeftPressed: if (!searchInput.activeFocus) wpWin.stepSelection(-1)
        Keys.onRightPressed: if (!searchInput.activeFocus) wpWin.stepSelection(1)
        Keys.onReturnPressed: if (!searchInput.activeFocus) wpWin.applySelected(false)
        Keys.onEnterPressed: if (!searchInput.activeFocus) wpWin.applySelected(false)

        // Hard SekaiPop Drop Shadow
        Rectangle {
            x: 6
            y: 6
            width: parent.width - 6
            height: parent.height - 6
            radius: 26
            color: themeHub.darkInk
        }

        // Main Comic Card Shell
        Rectangle {
            id: cardShell
            x: 0
            y: 0
            width: parent.width - 6
            height: parent.height - 6
            radius: 26
            color: "#F6F9FF"
            border.color: themeHub.darkInk
            border.width: 3
            clip: true

            // Subtle Comic Dot-Grid Background
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = "rgba(26, 27, 46, 0.045)"
                    const step = 18
                    for (let y = 76; y < height - 60; y += step) {
                        for (let x = 14; x < width - 14; x += step) {
                            ctx.beginPath()
                            ctx.arc(x, y, 1.4, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }
            }

            // =================================================================
            // Top Toolbar Header
            // =================================================================
            Rectangle {
                id: topHeader
                x: 0
                y: 0
                width: parent.width
                height: 62
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: themeHub.accentB }
                    GradientStop { position: 1.0; color: themeHub.accentA }
                }

                // Bottom divider line
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 3
                    color: themeHub.darkInk
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 14
                    spacing: 8

                    // Title + Count Badge
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "WALLPAPERS"
                            font.pixelSize: 16
                            font.weight: Font.Black
                            font.letterSpacing: 1
                            color: themeHub.darkInk
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(26, countTxt.implicitWidth + 12)
                            height: 22
                            radius: 11
                            color: themeHub.darkInk
                            Text {
                                id: countTxt
                                anchors.centerIn: parent
                                text: String(wpWin.filteredWallpapers.length)
                                font.pixelSize: 11
                                font.weight: Font.Black
                                color: "#FFFFFF"
                            }
                        }
                    }

                    // Folder Pill + Folder Pick Button
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 32
                        width: Math.min(200, folderRow.implicitWidth + 16)
                        radius: 16
                        color: "#FFFFFF"
                        border.color: themeHub.darkInk
                        border.width: 2

                        Row {
                            id: folderRow
                            anchors.centerIn: parent
                            spacing: 6
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                source: "qrc:/qml/icons/folder-with-files-dark.svg"
                                sourceSize.width: 28
                                sourceSize.height: 28
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(115, implicitWidth)
                                text: WallpaperService.directoryShort || "Pictures"
                                elide: Text.ElideMiddle
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Folder"
                                font.pixelSize: 11
                                font.weight: Font.Black
                                color: "#2563EB"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wpWin.openGuard = true
                                WallpaperService.pickFolder()
                                guardTimer.restart()
                            }
                        }
                    }

                    // Reset Folder Pill (only when customFolder is active)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: WallpaperService.customFolder
                        width: 30
                        height: 30
                        radius: 15
                        color: resetMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                        border.color: themeHub.darkInk
                        border.width: 2
                        Text {
                            anchors.centerIn: parent
                            text: "↺"
                            font.pixelSize: 14
                            font.weight: Font.Black
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            id: resetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WallpaperService.resetFolder()
                        }
                    }

                    // Search Filter Input
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(130, cardShell.width - 690)
                        height: 32
                        radius: 16
                        color: "#FFFFFF"
                        border.color: searchInput.activeFocus ? themeHub.darkInk : "#475569"
                        border.width: 2

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                source: "qrc:/qml/icons/magnifer-dark.svg"
                                sourceSize.width: 28
                                sourceSize.height: 28
                            }

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                height: 22
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Filter..."
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: "#94A3B8"
                                    visible: searchInput.text === ""
                                }
                                TextInput {
                                    id: searchInput
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: themeHub.darkInk
                                    clip: true
                                    onTextChanged: wpWin.searchQuery = text
                                }
                            }
                        }
                    }

                    // Sort Pill (Newest / Name / Oldest)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: sortTxt.implicitWidth + 20
                        height: 32
                        radius: 16
                        color: sortMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                        border.color: themeHub.darkInk
                        border.width: 2
                        Text {
                            id: sortTxt
                            anchors.centerIn: parent
                            text: {
                                const s = WallpaperService.sortBy || "newest"
                                if (s === "name") return "Name"
                                if (s === "oldest") return "Oldest"
                                return "Newest"
                            }
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            id: sortMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wpWin.cycleSort()
                        }
                    }

                    // View Toggle Pill (Wheel / Grid)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        height: 32
                        radius: 16
                        color: "#FFFFFF"
                        border.color: themeHub.darkInk
                        border.width: 2

                        Row {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 2

                            Rectangle {
                                width: (parent.width - 2) * 0.5
                                height: parent.height
                                radius: 13
                                color: wpWin.viewMode === "wheel" ? themeHub.darkInk : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "Wheel"
                                    font.pixelSize: 10
                                    font.weight: Font.Black
                                    color: wpWin.viewMode === "wheel" ? "#FFFFFF" : themeHub.darkInk
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: wpWin.viewMode = "wheel"
                                }
                            }
                            Rectangle {
                                width: (parent.width - 2) * 0.5
                                height: parent.height
                                radius: 13
                                color: wpWin.viewMode === "grid" ? themeHub.darkInk : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "Grid"
                                    font.pixelSize: 10
                                    font.weight: Font.Black
                                    color: wpWin.viewMode === "grid" ? "#FFFFFF" : themeHub.darkInk
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: wpWin.viewMode = "grid"
                                }
                            }
                        }
                    }

                    // Random Shuffle Button
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        height: 32
                        radius: 16
                        color: randMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                        border.color: themeHub.darkInk
                        border.width: 2
                        Text {
                            anchors.centerIn: parent
                            text: "Random"
                            font.pixelSize: 11
                            font.weight: Font.ExtraBold
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            id: randMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wpWin.selectRandom()
                        }
                    }

                    // Close Button (✕)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: closeBtnMa.containsMouse ? "#FF5E7E" : "#FFFFFF"
                        border.color: themeHub.darkInk
                        border.width: 2
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 13
                            font.weight: Font.Black
                            color: closeBtnMa.containsMouse ? "#FFFFFF" : "#D92652"
                        }
                        MouseArea {
                            id: closeBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wpWin.closeSelector()
                        }
                    }
                }
            }

            // =================================================================
            // Empty State
            // =================================================================
            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: wpWin.filteredWallpapers.length === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No wallpapers found"
                    font.pixelSize: 18
                    font.weight: Font.Black
                    color: themeHub.darkInk
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Pick a folder with PNG, JPG, or WEBP images, or clear the search filter."
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#64748B"
                }
            }

            // =================================================================
            // WHEEL VIEW (3D-Feel Curved Perspective Carousel)
            // =================================================================
            Item {
                id: wheelView
                x: 16
                y: topHeader.height + 10
                width: parent.width - 32
                height: parent.height - topHeader.height - bottomBar.height - 20
                visible: wpWin.viewMode === "wheel" && wpWin.filteredWallpapers.length > 0
                clip: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        if (wheel.angleDelta.y > 0)
                            wpWin.stepSelection(-1)
                        else if (wheel.angleDelta.y < 0)
                            wpWin.stepSelection(1)
                    }
                }

                // Curved Wheel Cards (-2, -1, 0, +1, +2)
                Repeater {
                    model: [-2, -1, 0, 1, 2]
                    delegate: Item {
                        required property int modelData
                        readonly property int offset: modelData
                        readonly property int n: wpWin.filteredWallpapers.length
                        readonly property int itemIdx: n > 0 ? ((wpWin.selectedIndex + offset + n * 10) % n) : -1
                        readonly property var itemData: (itemIdx >= 0 && itemIdx < n) ? wpWin.filteredWallpapers[itemIdx] : null
                        readonly property bool showCard: itemData !== null && (
                            n === 1 ? offset === 0
                            : (n === 2 ? (offset === 0 || offset === 1)
                            : (n <= 4 ? Math.abs(offset) <= 1 : true)))
                        readonly property bool isCenter: offset === 0
                        readonly property bool isActiveWall: itemData && itemData.path === WallpaperService.currentWallpaper

                        visible: showCard
                        width: 416
                        height: 244
                        x: Math.round((wheelView.width - width) * 0.5 + offset * 212)
                        y: Math.round((wheelView.height - height) * 0.5 + Math.abs(offset) * Math.abs(offset) * 18)
                        z: 10 - Math.abs(offset) * 2
                        scale: isCenter ? 1.0 : (Math.abs(offset) === 1 ? 0.78 : 0.60)
                        rotation: offset * 7
                        opacity: isCenter ? 1.0 : (Math.abs(offset) === 1 ? 0.88 : 0.55)
                        transformOrigin: Item.Center

                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        // Hard Shadow
                        Rectangle {
                            x: 5
                            y: 6
                            width: parent.width
                            height: parent.height
                            radius: 20
                            color: themeHub.darkInk
                        }

                        // Card Frame
                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: "#FFFFFF"
                            border.color: isCenter ? themeHub.accentA : themeHub.darkInk
                            border.width: isCenter ? 4 : 3
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: isCenter ? 4 : 3
                                source: itemData ? (itemData.fileUrl || ("file:///" + itemData.path)) : ""
                                asynchronous: true
                                cache: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 480
                                sourceSize.height: 270
                            }

                            // Active Wallpaper Badge
                            Rectangle {
                                visible: isActiveWall
                                x: 12
                                y: 12
                                width: activeTxt.implicitWidth + 16
                                height: 24
                                radius: 12
                                color: themeHub.accentB
                                border.color: themeHub.darkInk
                                border.width: 2
                                Text {
                                    id: activeTxt
                                    anchors.centerIn: parent
                                    text: "✓ ACTIVE"
                                    font.pixelSize: 10
                                    font.weight: Font.Black
                                    color: themeHub.darkInk
                                }
                            }

                            // Center Bottom Caption Strip
                            Rectangle {
                                visible: isCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                height: 32
                                radius: 12
                                color: "#E6FFFFFF"
                                border.color: themeHub.darkInk
                                border.width: 2

                                Text {
                                    anchors.centerIn: parent
                                    width: parent.width - 20
                                    horizontalAlignment: Text.AlignHCenter
                                    text: itemData ? (itemData.name || "") : ""
                                    elide: Text.ElideMiddle
                                    font.pixelSize: 12
                                    font.weight: Font.ExtraBold
                                    color: themeHub.darkInk
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (isCenter)
                                        wpWin.applySelected(false)
                                    else
                                        wpWin.stepSelection(offset)
                                }
                            }
                        }
                    }
                }

                // Prev / Next Floating Buttons
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    z: 20
                    width: 40
                    height: 40
                    radius: 20
                    color: prevArrowMa.containsMouse ? themeHub.accentB : "#FFFFFF"
                    border.color: themeHub.darkInk
                    border.width: 3
                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        font.pixelSize: 22
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: prevArrowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wpWin.stepSelection(-1)
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    z: 20
                    width: 40
                    height: 40
                    radius: 20
                    color: nextArrowMa.containsMouse ? themeHub.accentB : "#FFFFFF"
                    border.color: themeHub.darkInk
                    border.width: 3
                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        font.pixelSize: 22
                        font.weight: Font.Black
                        color: themeHub.darkInk
                    }
                    MouseArea {
                        id: nextArrowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wpWin.stepSelection(1)
                    }
                }
            }

            // =================================================================
            // GRID VIEW (4-Column Scrollable Grid)
            // =================================================================
            GridView {
                id: wallGrid
                x: 18
                y: topHeader.height + 12
                width: parent.width - 36
                height: parent.height - topHeader.height - bottomBar.height - 24
                visible: wpWin.viewMode === "grid" && wpWin.filteredWallpapers.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / 4)
                cellHeight: 146
                model: wpWin.filteredWallpapers

                delegate: Item {
                    required property int index
                    required property var modelData

                    width: wallGrid.cellWidth
                    height: wallGrid.cellHeight

                    readonly property bool isSelected: index === wpWin.selectedIndex
                    readonly property bool isActiveWall: modelData.path === WallpaperService.currentWallpaper

                    Rectangle {
                        x: 6
                        y: 6
                        width: parent.width - 12
                        height: parent.height - 12
                        radius: 14
                        color: themeHub.darkInk
                    }

                    Rectangle {
                        x: 4
                        y: 4
                        width: parent.width - 12
                        height: parent.height - 12
                        radius: 14
                        color: "#FFFFFF"
                        border.color: isSelected ? themeHub.accentA : themeHub.darkInk
                        border.width: isSelected ? 3 : 2
                        clip: true

                        Image {
                            x: 3
                            y: 3
                            width: parent.width - 6
                            height: parent.height - 30
                            source: modelData.fileUrl || ("file:///" + modelData.path)
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 300
                            sourceSize.height: 170
                        }

                        // Active Badge
                        Rectangle {
                            visible: isActiveWall
                            x: 8
                            y: 8
                            width: 24
                            height: 24
                            radius: 12
                            color: themeHub.accentB
                            border.color: themeHub.darkInk
                            border.width: 2
                            Image {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                source: "qrc:/qml/icons/check-circle-dark.svg"
                                sourceSize.width: 28
                                sourceSize.height: 28
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.bottomMargin: 5
                            text: modelData.name || ""
                            elide: Text.ElideMiddle
                            font.pixelSize: 11
                            font.weight: isSelected ? Font.Black : Font.Bold
                            color: themeHub.darkInk
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wpWin.selectedIndex = index
                            onDoubleClicked: {
                                wpWin.selectedIndex = index
                                wpWin.applySelected(false)
                            }
                        }
                    }
                }
            }

            // =================================================================
            // Bottom Action Bar
            // =================================================================
            Rectangle {
                id: bottomBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 64
                color: "#FFFFFF"

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 3
                    color: themeHub.darkInk
                }

                // Selected Info + Palette Swatches
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(340, cardShell.width - 460)
                        spacing: 2
                        Text {
                            width: parent.width
                            text: wpWin.selectedItem ? (wpWin.selectedItem.name || "") : "No wallpaper selected"
                            elide: Text.ElideMiddle
                            font.pixelSize: 13
                            font.weight: Font.Black
                            color: themeHub.darkInk
                        }
                        Text {
                            width: parent.width
                            text: wpWin.statusBanner !== ""
                                ? wpWin.statusBanner
                                : (wpWin.selectedItem ? (wpWin.selectedItem.sizeText || "") : "")
                            elide: Text.ElideRight
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: wpWin.statusBanner !== "" ? "#059669" : "#64748B"
                        }
                    }

                    // Extracted Palette Dots Preview
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: wpWin.previewPalette !== null
                        spacing: 4
                        Repeater {
                            model: wpWin.previewPalette
                                ? [wpWin.previewPalette.accentA, wpWin.previewPalette.accentB, wpWin.previewPalette.border, wpWin.previewPalette.deep]
                                : []
                            delegate: Rectangle {
                                required property var modelData
                                width: 16
                                height: 16
                                radius: 8
                                color: modelData || "#CBD5E1"
                                border.color: themeHub.darkInk
                                border.width: 2
                            }
                        }
                    }
                }

                // Action Buttons
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    // Apply Wallpaper
                    Item {
                        width: 150
                        height: 40
                        enabled: wpWin.selectedItem !== null

                        Rectangle {
                            x: 3
                            y: 3
                            width: parent.width
                            height: parent.height
                            radius: 14
                            color: themeHub.darkInk
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: applyBtnMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                            border.color: themeHub.darkInk
                            border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: "Apply Wallpaper"
                                font.pixelSize: 12
                                font.weight: Font.Black
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                id: applyBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wpWin.applySelected(false)
                            }
                        }
                    }

                    // Apply + Sync Colors
                    Item {
                        width: 196
                        height: 40
                        enabled: wpWin.selectedItem !== null

                        Rectangle {
                            x: 3
                            y: 3
                            width: parent.width
                            height: parent.height
                            radius: 14
                            color: themeHub.darkInk
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            border.color: themeHub.darkInk
                            border.width: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: syncBtnMa.containsMouse ? Qt.lighter(themeHub.accentB, 1.08) : themeHub.accentB }
                                GradientStop { position: 1.0; color: syncBtnMa.containsMouse ? Qt.lighter(themeHub.accentA, 1.08) : themeHub.accentA }
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 15
                                    height: 15
                                    source: "qrc:/qml/icons/palette-dark.svg"
                                    sourceSize.width: 30
                                    sourceSize.height: 30
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Apply + Sync Colors"
                                    font.pixelSize: 12
                                    font.weight: Font.Black
                                    color: themeHub.darkInk
                                }
                            }
                            MouseArea {
                                id: syncBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wpWin.applySelected(true)
                            }
                        }
                    }
                }
            }
        }
    }
}
