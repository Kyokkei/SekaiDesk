import QtQuick
import SekaiDesk

// #9: Landscape Phone integrated Wallpaper Gallery (runs straight-on inside shell landPaper)
Item {
    id: root

    required property var themeHub
    signal backToSettings()
    signal closeRequested()
    signal pickingChanged(bool picking)

    property string searchQuery: ""

    readonly property var filteredWallpapers: {
        const list = WallpaperService.wallpapers || []
        const q = searchQuery.trim().toLowerCase()
        if (q === "")
            return list
        const out = []
        for (let i = 0; i < list.length; ++i) {
            const it = list[i]
            if (String(it.name || "").toLowerCase().indexOf(q) >= 0)
                out.push(it)
        }
        return out
    }

    function normalizeForCompare(p) {
        return String(p || "").trim().replace(/\\/g, "/").toLowerCase()
    }

    // Header Row inside Landscape Phone (shifted x=58 to clear left pill camera notch)
    Item {
        id: galHeader
        x: 58; y: 20
        width: parent.width - 82
        height: 66

        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 10

            // Back to Settings
            Item {
                width: 104; height: 46; anchors.verticalCenter: parent.verticalCenter
                Rectangle { x: 4; y: 4; width: parent.width; height: parent.height; radius: 15; color: "#1A1B2E" }
                Rectangle {
                    x: backSetMa.pressed ? 3 : 0; y: backSetMa.pressed ? 3 : 0
                    width: parent.width; height: parent.height; radius: 15
                    color: backSetMa.containsMouse ? root.themeHub.accentA : "#FFFFFF"
                    border.width: 3; border.color: "#1A1B2E"
                    Text { anchors.centerIn: parent; text: "← SETTINGS"; font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Black; color: "#1A1B2E" }
                    MouseArea { id: backSetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.backToSettings() }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 1
                Text {
                    text: "WALLPAPERS (" + root.filteredWallpapers.length + ")"
                    font.family: "Segoe UI"; font.pixelSize: 22; font.weight: Font.Black; color: "#1A1B2E"
                }
                Text {
                    width: 330; elide: Text.ElideMiddle
                    text: WallpaperService.directory || "Pictures/Wallpapers"
                    font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.DemiBold; color: "#475569"
                }
            }
        }

        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8

            // Search Box
            Rectangle {
                width: 196; height: 42; radius: 13
                color: "#FFFFFF"; border.width: 2.5; border.color: "#1A1B2E"
                clip: true
                TextInput {
                    id: wallSearchInput
                    anchors.fill: parent; anchors.margins: 10
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: "Segoe UI"; font.pixelSize: 13; font.weight: Font.Bold; color: "#1A1B2E"
                    onTextChanged: root.searchQuery = text
                    Text {
                        visible: parent.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter wallpapers..."
                        font.family: "Segoe UI"; font.pixelSize: 13; color: "#94A3B8"
                    }
                }
            }

            // Pick Folder
            Rectangle {
                width: 96; height: 42; radius: 13
                color: pickFolderMa.containsMouse ? root.themeHub.hoverTint : "#FFFFFF"
                border.width: 2.5; border.color: "#1A1B2E"
                Text { anchors.centerIn: parent; text: "📁 FOLDER"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                MouseArea {
                    id: pickFolderMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.pickingChanged(true)
                        WallpaperService.pickFolder()
                        root.pickingChanged(false)
                    }
                }
            }

            // Random Wallpaper
            Rectangle {
                width: 106; height: 42; radius: 13
                color: randWallMa.containsMouse ? root.themeHub.accentB : root.themeHub.accentA
                border.width: 2.5; border.color: "#1A1B2E"
                Text { anchors.centerIn: parent; text: "🎲 RANDOM"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                MouseArea { id: randWallMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperService.nextRandomWallpaper() }
            }

            // Match Theme Palette
            Rectangle {
                width: 92; height: 42; radius: 13
                color: root.themeHub.useCustomPalette ? "#ECFEFF" : "#FFFFFF"
                border.width: 2.5; border.color: "#1A1B2E"
                Text { anchors.centerIn: parent; text: "🎨 MATCH"; font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E" }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const pal = WallpaperService.extractCurrentPalette()
                        if (pal && pal.accentA)
                            root.themeHub.applyWallpaperPalette(pal)
                    }
                }
            }

            // Close
            Rectangle {
                width: 44; height: 42; radius: 13
                color: galCloseMa.containsMouse ? "#FB7185" : "#FFE4E6"
                border.width: 2.5; border.color: "#1A1B2E"
                Text { anchors.centerIn: parent; text: "✕"; font.family: "Segoe UI"; font.pixelSize: 17; font.weight: Font.Black; color: "#1A1B2E" }
                MouseArea { id: galCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
            }
        }
    }

    // Controls Strip: Transition Shader Chips + Sort + Slideshow
    Item {
        x: 58; y: 94
        width: parent.width - 82
        height: 44

        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: "FX:"; font.family: "Consolas"; font.pixelSize: 12; font.weight: Font.Black; color: "#64748B" }
            Repeater {
                model: [
                    { id: "sekaiRing",      l: "RING" },
                    { id: "star",           l: "STAR" },
                    { id: "diagonalBlocks", l: "BLOCKS" },
                    { id: "sekaiIris",      l: "IRIS" },
                    { id: "sekaiFlash",     l: "FLASH" },
                    { id: "fade",           l: "FADE" },
                    { id: "random",         l: "RAND" },
                    { id: "none",           l: "OFF" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: WallpaperService.transitionStyle === modelData.id
                    width: fxLbl.implicitWidth + 18; height: 32; radius: 10
                    color: sel ? root.themeHub.accentB : "#FFFFFF"
                    border.width: sel ? 2.5 : 2; border.color: "#1A1B2E"
                    Text { id: fxLbl; anchors.centerIn: parent; text: modelData.l; font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperService.transitionStyle = modelData.id }
                }
            }
        }

        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Rectangle {
                width: 112; height: 32; radius: 10; color: "#FFFFFF"; border.width: 2; border.color: "#1A1B2E"
                Text { anchors.centerIn: parent; text: "SORT: " + WallpaperService.sortBy.toUpperCase(); font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E" }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const s = WallpaperService.sortBy
                        WallpaperService.sortBy = s === "newest" ? "name" : (s === "name" ? "oldest" : "newest")
                    }
                }
            }
            Rectangle {
                width: 138; height: 32; radius: 10
                color: WallpaperService.slideshowEnabled ? root.themeHub.accentA : "#FFFFFF"
                border.width: 2; border.color: "#1A1B2E"
                Text {
                    anchors.centerIn: parent
                    text: WallpaperService.slideshowEnabled ? ("AUTO: " + WallpaperService.slideshowMinutes + "m") : "SLIDESHOW: OFF"
                    font.family: "Segoe UI"; font.pixelSize: 11; font.weight: Font.Black; color: "#1A1B2E"
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton || WallpaperService.slideshowEnabled) {
                            const mins = [5, 15, 30, 60]
                            const idx = mins.indexOf(WallpaperService.slideshowMinutes)
                            if (WallpaperService.slideshowEnabled && idx === mins.length - 1)
                                WallpaperService.slideshowEnabled = false
                            else {
                                WallpaperService.slideshowMinutes = mins[(idx + 1) % mins.length]
                                WallpaperService.slideshowEnabled = true
                            }
                        } else {
                            WallpaperService.slideshowEnabled = true
                        }
                    }
                }
            }
        }
    }

    // Empty folder notice
    Column {
        visible: root.filteredWallpapers.length === 0
        anchors.centerIn: wallGridWrap
        spacing: 8
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No wallpapers found"; font.family: "Segoe UI"; font.pixelSize: 18; font.weight: Font.Black; color: "#1A1B2E" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Pick a folder containing PNG / JPG / WebP images."; font.family: "Segoe UI"; font.pixelSize: 13; color: "#64748B" }
    }

    // Wallpaper 4-column Thumbnail Grid
    Item {
        id: wallGridWrap
        x: 58; y: 146
        width: parent.width - 82
        height: parent.height - 166

        GridView {
            id: wallGrid
            anchors.fill: parent
            clip: true
            cacheBuffer: 480
            cellWidth: Math.floor(width / 4)
            cellHeight: Math.round((cellWidth - 16) * 0.5625) + 42
            model: root.filteredWallpapers

            delegate: Item {
                id: wallTile
                required property var modelData
                readonly property bool isCurrent: root.normalizeForCompare(modelData.path) === root.normalizeForCompare(WallpaperService.currentWallpaper)
                width: wallGrid.cellWidth
                height: wallGrid.cellHeight

                Rectangle { x: 6; y: 6; width: parent.width - 14; height: parent.height - 12; radius: 16; color: "#1A1B2E" }

                Rectangle {
                    x: tileMa.pressed ? 4 : 0
                    y: tileMa.pressed ? 4 : (tileMa.containsMouse ? -2 : 0)
                    Behavior on y { NumberAnimation { duration: 100 } }
                    width: parent.width - 14
                    height: parent.height - 12
                    radius: 16
                    color: wallTile.isCurrent ? root.themeHub.accentB : (tileMa.containsMouse ? "#F0FDFA" : "#FFFFFF")
                    border.width: wallTile.isCurrent ? 3.5 : 2.5
                    border.color: "#1A1B2E"
                    clip: true

                    Rectangle {
                        id: thumbBox
                        x: 6; y: 6
                        width: parent.width - 12
                        height: parent.height - 38
                        radius: 11
                        color: "#E2E8F0"
                        border.width: 2; border.color: "#1A1B2E"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: modelData.fileUrl || ""
                            sourceSize.width: 360
                            sourceSize.height: 204
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            mipmap: true
                        }

                        Rectangle {
                            visible: wallTile.isCurrent
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                            width: curTag.implicitWidth + 12; height: 20; radius: 10
                            color: root.themeHub.accentA; border.width: 2; border.color: "#1A1B2E"
                            Text { id: curTag; anchors.centerIn: parent; text: "ACTIVE"; font.family: "Consolas"; font.pixelSize: 9; font.weight: Font.Black; color: "#1A1B2E" }
                        }
                    }

                    Text {
                        x: 10; y: thumbBox.y + thumbBox.height + 6
                        width: parent.width - 20; elide: Text.ElideRight
                        text: modelData.name || "Wallpaper"
                        font.family: "Segoe UI"; font.pixelSize: 12; font.weight: Font.Black; color: "#1A1B2E"
                    }

                    MouseArea {
                        id: tileMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WallpaperService.requestWallpaperChange(modelData.path)
                    }
                }
            }
        }
    }
}
