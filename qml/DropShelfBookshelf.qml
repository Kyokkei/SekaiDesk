import QtQuick
import Quickshell
import SekaiDesk
import "ShelfMath.js" as SM

// Collectible Sticker Bookshelf DropShelf (SekaiPop DockShelfCard parity).
// Uses native WM_DROPFILES via PanelWindow.acceptFileDrops — NEVER QML DropArea.
PanelWindow {
    id: shelfWin

    required property var themeHub
    required property bool fullscreenActive

    property bool shown: false
    property real popK: 0.0

    readonly property var items: DropShelfService.items || []
    readonly property int listW: 360
    readonly property int pad: 16
    readonly property int vpMargin: 18
    readonly property int topRoom: 14
    readonly property int shadowOff: 5

    readonly property real bookGap: 4
    readonly property real bookMaxH: 120
    readonly property real lift: 8
    readonly property real areaH: bookMaxH + lift
    readonly property real nameH: 22
    readonly property real plankH: 18
    readonly property real ledgeBlock: 8 + plankH
    readonly property real unitH: areaH + 10 + plankH + 12
    readonly property int headerH: 36

    readonly property var packed: SM.pack(items, listW, bookGap)
    readonly property int shelfCount: Math.max(1, packed.length)

    property string hoverId: ""
    readonly property var hoverItem: {
        for (let i = 0; i < items.length; ++i) {
            if (items[i].id === hoverId)
                return items[i]
        }
        return null
    }
    property bool copiedAll: false
    property string hintText: ""
    property int lastCount: 0

    function closeShelf() {
        themeHub.dropShelfClosedAt = Date.now()
        themeHub.dropShelfOpen = false
    }

    onItemsChanged: {
        if (items.length > lastCount)
            shelves.currentIndex = 0
        lastCount = items.length
        if (shelves.currentIndex > shelfCount - 1)
            shelves.currentIndex = shelfCount - 1
    }

    readonly property bool wanted: !!themeHub.dropShelfOpen && !fullscreenActive
    onWantedChanged: {
        if (wanted) {
            exitAnim.stop()
            shown = true
            shelves.currentIndex = 0
            enterAnim.restart()
        } else if (shown) {
            enterAnim.stop()
            exitAnim.restart()
        }
    }

    NumberAnimation {
        id: enterAnim
        target: shelfWin
        property: "popK"
        from: shelfWin.popK
        to: 1.0
        duration: 240
        easing.type: Easing.OutBack
        easing.overshoot: 1.35
    }

    NumberAnimation {
        id: exitAnim
        target: shelfWin
        property: "popK"
        from: shelfWin.popK
        to: 0.0
        duration: 150
        easing.type: Easing.InCubic
        onFinished: {
            if (!shelfWin.wanted) {
                shelfWin.shown = false
                shelfWin.hoverId = ""
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: shelfWin.copiedAll = false
    }

    visible: shown && !fullscreenActive
    clickThrough: false
    acceptFileDrops: true
    color: "transparent"

    onFilesDropped: paths => DropShelfService.addPaths(paths)

    readonly property int cardW: listW + pad * 2
    readonly property int cardH: pad + headerH + 12
        + (items.length === 0 ? (44 + ledgeBlock) : (nameH + 6 + unitH))
        + pad

    width: cardW + shadowOff + 8
    height: topRoom + cardH + shadowOff + 8
    x: Math.max(12, themeHub.screenW - width - 16)
    y: 44

    Item {
        id: cardRoot
        x: 4
        y: shelfWin.topRoom
        width: shelfWin.cardW
        height: shelfWin.cardH
        scale: 0.88 + 0.12 * Math.min(1.06, shelfWin.popK)
        opacity: Math.max(0.0, Math.min(1.0, shelfWin.popK))
        transformOrigin: Item.TopRight

        // Hard offset shadow
        Rectangle {
            x: shelfWin.shadowOff
            y: shelfWin.shadowOff
            width: parent.width
            height: parent.height
            radius: 22
            color: themeHub.darkInk
            antialiasing: true
        }

        // Main card plate
        Rectangle {
            id: cardBody
            anchors.fill: parent
            radius: 22
            color: "#FFFFFF"
            border.width: 3
            border.color: themeHub.darkInk
            antialiasing: true

            // Halftone dot wall
            SekaiDotField {
                anchors.fill: parent
                anchors.margins: 8
                corner: "tr"
                spacing: 18
                maxRadius: 2.6
                dotColor: Qt.rgba(0.102, 0.106, 0.180, 0.07)
            }

            // Header bar
            Item {
                id: header
                x: shelfWin.pad
                y: shelfWin.pad
                width: shelfWin.listW
                height: shelfWin.headerH

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13
                        height: 13
                        radius: 4
                        rotation: 45
                        color: themeHub.accentB
                        border.width: 2
                        border.color: themeHub.darkInk
                        antialiasing: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Shelf"
                        color: "#1A1B2E"
                        font.family: "Segoe UI"
                        font.pixelSize: 17
                        font.weight: Font.Black
                    }

                    Rectangle {
                        visible: shelfWin.items.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(24, countLbl.implicitWidth + 12)
                        height: 20
                        radius: 10
                        color: themeHub.accentA
                        border.width: 2
                        border.color: themeHub.darkInk
                        Text {
                            id: countLbl
                            anchors.centerIn: parent
                            text: shelfWin.items.length
                            font.family: "Consolas"
                            font.pixelSize: 11
                            font.weight: Font.Black
                            color: "#1A1B2E"
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Add Files button
                    Rectangle {
                        width: 32; height: 32; radius: 11
                        color: addHover.containsMouse ? themeHub.accentA : "#F1F5F9"
                        border.width: 2; border.color: themeHub.darkInk
                        antialiasing: true
                        Image {
                            anchors.centerIn: parent; width: 17; height: 17; smooth: true
                            source: "qrc:/qml/icons/folder-with-files-dark.svg"
                        }
                        MouseArea {
                            id: addHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: shelfWin.hintText = "Add files from Explorer"
                            onExited: shelfWin.hintText = ""
                            onClicked: DropShelfService.pickFiles()
                        }
                    }

                    // Paste Clipboard button
                    Rectangle {
                        width: 32; height: 32; radius: 11
                        color: pasteHover.containsMouse ? themeHub.accentB : "#F1F5F9"
                        border.width: 2; border.color: themeHub.darkInk
                        antialiasing: true
                        Image {
                            anchors.centerIn: parent; width: 17; height: 17; smooth: true
                            source: "qrc:/qml/icons/clipboard-add-dark.svg"
                        }
                        MouseArea {
                            id: pasteHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: shelfWin.hintText = "Add file or text from clipboard"
                            onExited: shelfWin.hintText = ""
                            onClicked: DropShelfService.pasteFromClipboard()
                        }
                    }

                    // Copy All button
                    Rectangle {
                        visible: shelfWin.items.length > 0
                        width: 32; height: 32; radius: 11
                        color: shelfWin.copiedAll ? themeHub.accentB : (copyAllHover.containsMouse ? themeHub.accentA : "#F1F5F9")
                        border.width: 2; border.color: themeHub.darkInk
                        antialiasing: true
                        Image {
                            anchors.centerIn: parent; width: 17; height: 17; smooth: true
                            source: shelfWin.copiedAll ? "qrc:/qml/icons/check-read-dark.svg" : "qrc:/qml/icons/copy-dark.svg"
                        }
                        MouseArea {
                            id: copyAllHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: shelfWin.hintText = "Copy everything on the shelf"
                            onExited: shelfWin.hintText = ""
                            onClicked: {
                                DropShelfService.copyAllPaths()
                                shelfWin.copiedAll = true
                                copiedTimer.restart()
                            }
                        }
                    }

                    // Clear button
                    Rectangle {
                        visible: shelfWin.items.length > 0
                        width: 32; height: 32; radius: 11
                        color: clearHover.containsMouse ? "#FECDD3" : "#F1F5F9"
                        border.width: 2; border.color: themeHub.darkInk
                        antialiasing: true
                        Image {
                            anchors.centerIn: parent; width: 16; height: 16; smooth: true
                            source: "qrc:/qml/icons/trash-bin-trash-dark.svg"
                        }
                        MouseArea {
                            id: clearHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: shelfWin.hintText = "Clear the shelf"
                            onExited: shelfWin.hintText = ""
                            onClicked: DropShelfService.clear()
                        }
                    }

                    // Close button
                    Rectangle {
                        width: 32; height: 32; radius: 11
                        color: closeHover.containsMouse ? "#FFE4E6" : "#F1F5F9"
                        border.width: 2; border.color: themeHub.darkInk
                        antialiasing: true
                        Image {
                            anchors.centerIn: parent; width: 17; height: 17; smooth: true
                            source: "qrc:/qml/icons/close-circle-dark.svg"
                        }
                        MouseArea {
                            id: closeHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: shelfWin.closeShelf()
                        }
                    }
                }
            }

            // Empty state message + resting plank
            Item {
                visible: shelfWin.items.length === 0
                x: shelfWin.pad
                y: shelfWin.pad + shelfWin.headerH + 12
                width: shelfWin.listW
                height: 44 + shelfWin.ledgeBlock

                Text {
                    x: 0; y: 2
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: shelfWin.hintText !== "" ? shelfWin.hintText : "Drop files here from Explorer, or press Add / Paste."
                    color: "#475569"
                    font.family: "Segoe UI"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Item {
                    readonly property real grow: 0.7 + 0.3 * Math.min(1.12, shelfWin.popK)
                    readonly property real fullW: shelfWin.listW + 16
                    width: fullW * grow
                    height: shelfWin.plankH + 4
                    x: -8 + (fullW - width) / 2
                    y: 44
                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            x: index === 0 ? 26 : parent.width - 26 - 12
                            y: shelfWin.plankH - 5
                            width: 12; height: 12; radius: 3; rotation: 45
                            color: "#FFFFFF"; border.width: 2; border.color: themeHub.darkInk; antialiasing: true
                        }
                    }
                    Rectangle {
                        y: 3; width: parent.width; height: shelfWin.plankH; radius: 7; color: themeHub.darkInk; antialiasing: true
                    }
                    Rectangle {
                        width: parent.width; height: shelfWin.plankH; radius: 7
                        border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: themeHub.accentB }
                            GradientStop { position: 1.0; color: themeHub.accentA }
                        }
                        Rectangle { x: 22; y: 4; width: Math.max(0, parent.width - 44); height: 2; radius: 1; color: "#FFFFFF"; opacity: 0.45 }
                    }
                }
            }

            // Item name / hint + shelf page indicator
            Item {
                visible: shelfWin.items.length > 0
                x: shelfWin.pad
                y: shelfWin.pad + shelfWin.headerH + 12
                width: shelfWin.listW
                height: shelfWin.nameH

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (moreTag.visible ? moreTag.width + 10 : 0)
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                    text: shelfWin.hoverItem ? shelfWin.hoverItem.name : (shelfWin.hintText !== "" ? shelfWin.hintText : "Pick one to open or copy")
                    color: (shelfWin.hoverItem || shelfWin.hintText !== "") ? "#1A1B2E" : "#64748B"
                    font.family: "Segoe UI"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    id: moreTag
                    visible: shelfWin.shelfCount > 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: (shelves.currentIndex + 1) + " / " + shelfWin.shelfCount
                    color: "#64748B"
                    font.family: "Consolas"
                    font.pixelSize: 12
                    font.weight: Font.Black
                }
            }

            // Shelves ListView (multi-row snapping bookshelves)
            ListView {
                id: shelves
                visible: shelfWin.items.length > 0
                x: shelfWin.pad - shelfWin.vpMargin
                y: shelfWin.pad + shelfWin.headerH + 12 + shelfWin.nameH + 6
                width: shelfWin.listW + 2 * shelfWin.vpMargin
                height: shelfWin.unitH
                clip: true
                interactive: shelfWin.shelfCount > 1
                boundsBehavior: Flickable.StopAtBounds
                model: shelfWin.shelfCount
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: 0
                highlightMoveDuration: 240
                cacheBuffer: shelfWin.unitH

                delegate: Item {
                    id: shelf
                    required property int index
                    readonly property var books: shelfWin.packed[shelf.index] ?? []
                    width: shelves.width
                    height: shelfWin.unitH

                    // Row of collectible props on plank
                    Item {
                        id: shelfRow
                        x: shelfWin.vpMargin
                        y: 10
                        width: shelfWin.listW
                        height: shelfWin.areaH

                        Repeater {
                            model: shelf.books
                            delegate: Item {
                                id: propSlot
                                required property var modelData
                                required property int index

                                readonly property var it: propSlot.modelData.item
                                readonly property int origIdx: propSlot.modelData.origIdx
                                readonly property string kind: propSlot.modelData.kind
                                readonly property bool isFile: propSlot.it.kind !== "text"
                                readonly property int seed: propSlot.modelData.seed
                                readonly property color tint: SM.tintOf(propSlot.seed)
                                readonly property bool lifted: propHover.hovered
                                readonly property bool rowButtons: SM.specOf(propSlot.kind).buttons === "row"
                                readonly property real btnS: propSlot.rowButtons ? 18 : 22

                                x: propSlot.modelData.x
                                y: shelfWin.areaH - propSlot.height
                                width: propSlot.modelData.w
                                height: propSlot.modelData.h + shelfWin.lift
                                z: propSlot.lifted ? 4 : 0

                                onLiftedChanged: {
                                    if (propSlot.lifted)
                                        shelfWin.hoverId = propSlot.it.id
                                    else if (shelfWin.hoverId === propSlot.it.id)
                                        shelfWin.hoverId = ""
                                }
                                Component.onDestruction: {
                                    if (shelfWin.hoverId === propSlot.it.id)
                                        shelfWin.hoverId = ""
                                }

                                HoverHandler {
                                    id: propHover
                                }

                                Item {
                                    id: book
                                    width: propSlot.modelData.w
                                    height: propSlot.modelData.h
                                    y: (propSlot.lifted ? 0 : shelfWin.lift) + (propClickMa.pressed ? 2 : 0)
                                    rotation: propSlot.lifted ? -2.5 : SM.restTilt(propSlot.kind, propSlot.seed)
                                    transformOrigin: Item.Bottom

                                    Behavior on y {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                    }
                                    Behavior on rotation {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                    }

                                    // ---- 7 Handcrafted Prop Appearances ----
                                    // 1. Folder
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "folder"
                                        readonly property real tabH: 10
                                        Rectangle { x: 3; y: 3 + parent.tabH; width: parent.width; height: parent.height - parent.tabH; radius: 6; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle { x: 3; y: 0; width: 20; height: parent.tabH + 8; radius: 5; color: Qt.darker(propSlot.tint, 1.12); border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true }
                                        Rectangle { y: parent.tabH; width: parent.width; height: parent.height - parent.tabH; radius: 6; color: Qt.darker(propSlot.tint, 1.12); border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: fFront
                                            x: 0; y: parent.tabH + 7; width: parent.width; height: parent.height - parent.tabH - 7; radius: 6
                                            color: propSlot.tint; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle { x: 4; y: 6; width: 2; height: Math.max(0, fFront.height - 20); radius: 1; color: "#FFFFFF"; opacity: 0.4 }
                                            Item {
                                                x: (fFront.width - width) / 2; y: 8; width: 24; height: 24
                                                opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                                Rectangle { anchors.fill: parent; radius: 7; color: "#FFFFFF"; border.width: 2; border.color: themeHub.darkInk; antialiasing: true }
                                                Image { anchors.centerIn: parent; width: 14; height: 14; smooth: true; source: "qrc:/qml/icons/folder-2-dark.svg" }
                                            }
                                            Item {
                                                id: fTitleBox
                                                x: (fFront.width - width) / 2; y: 38; width: 14; height: Math.max(0, fFront.height - 46)
                                                opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                                Text {
                                                    x: 0; y: fTitleBox.height; width: fTitleBox.height; height: fTitleBox.width; rotation: -90; transformOrigin: Item.TopLeft
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; maximumLineCount: 1
                                                    text: propSlot.it.name; color: "#1A1B2E"; font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black
                                                }
                                            }
                                        }
                                    }

                                    // 2. Polaroid Photo
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "image"
                                        readonly property real pMargin: 6
                                        readonly property real stripH: 26
                                        Rectangle { x: 3; y: 3; width: parent.width; height: parent.height; radius: 4; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: pCard; anchors.fill: parent; radius: 4; color: "#FFFFFF"; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle {
                                                x: parent.parent.pMargin; y: parent.parent.pMargin
                                                width: pCard.width - 2 * parent.parent.pMargin; height: pCard.height - parent.parent.pMargin - parent.parent.stripH
                                                color: Qt.darker(propSlot.tint, 1.4); border.width: 2; border.color: themeHub.darkInk; antialiasing: true; clip: true
                                                Image {
                                                    id: pPic; anchors.fill: parent; anchors.margins: 2; asynchronous: true; smooth: true; fillMode: Image.PreserveAspectCrop
                                                    sourceSize: Qt.size(160, 160)
                                                    source: (propSlot.kind === "image" && propSlot.isFile) ? SM.pathToFileUrl(propSlot.it.value || propSlot.it.path) : ""
                                                    visible: status === Image.Ready
                                                }
                                                Rectangle { anchors.fill: parent; anchors.margins: 2; visible: !pPic.visible; color: propSlot.tint }
                                                Image { anchors.centerIn: parent; visible: !pPic.visible; width: 18; height: 18; source: "qrc:/qml/icons/gallery-dark.svg" }
                                            }
                                            Text {
                                                x: parent.parent.pMargin; y: pCard.height - parent.parent.stripH
                                                width: pCard.width - 2 * parent.parent.pMargin; height: parent.parent.stripH - 4
                                                verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle; maximumLineCount: 1
                                                text: propSlot.it.name; color: "#1A1B2E"; font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Bold
                                                opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                            }
                                        }
                                        Rectangle { x: (parent.width - width) / 2; y: -5; width: 26; height: 11; radius: 2; rotation: 5; color: "#6EE7B7"; opacity: 0.85; antialiasing: true }
                                    }

                                    // 3. Vinyl Sleeve
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "audio"
                                        readonly property real sleeveTop: 16
                                        readonly property real discSz: Math.min(width - 10, 52)
                                        Rectangle {
                                            x: (parent.width - width) / 2; y: 0; width: parent.discSz; height: parent.discSz; radius: width / 2
                                            color: "#2B2D42"; border.width: 2; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle { anchors.centerIn: parent; width: parent.width - 14; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22); antialiasing: true }
                                            Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 8; color: propSlot.tint; antialiasing: true }
                                        }
                                        Rectangle { x: 3; y: parent.sleeveTop + 3; width: parent.width; height: parent.height - parent.sleeveTop; radius: 5; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: vSleeve; y: parent.sleeveTop; width: parent.width; height: parent.height - parent.sleeveTop; radius: 5
                                            color: propSlot.tint; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle {
                                                x: (vSleeve.width - width) / 2; y: 9; width: 28; height: 28; radius: 14
                                                color: Qt.rgba(1, 1, 1, 0.85); border.width: 2; border.color: themeHub.darkInk; antialiasing: true
                                                Image { anchors.centerIn: parent; width: 15; height: 15; smooth: true; source: "qrc:/qml/icons/music-note-dark.svg" }
                                            }
                                            Text {
                                                x: 5; y: vSleeve.height - height - 7; width: vSleeve.width - 10; horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideMiddle; maximumLineCount: 1; text: propSlot.it.name; color: "#1A1B2E"
                                                font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black; opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                            }
                                        }
                                    }

                                    // 4. VHS Tape
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "video"
                                        Rectangle { x: 3; y: 3; width: parent.width; height: parent.height; radius: 4; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: vhsShell; anchors.fill: parent; radius: 4; color: "#3A3D5C"; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Repeater {
                                                model: [4.5, vhsShell.height - 10.5]
                                                Rectangle { required property real modelData; x: 4.5; y: modelData; width: vhsShell.width - 9; height: 6; radius: 2; color: propSlot.tint }
                                            }
                                            Rectangle { x: 3; y: 16; width: 2; height: Math.max(0, vhsShell.height - 32); radius: 1; color: "#FFFFFF"; opacity: 0.25 }
                                            Text {
                                                x: (vhsShell.width - width) / 2; y: 15; text: "VHS"; color: "#FFFFFF"
                                                opacity: propSlot.lifted ? 0 : 0.85; font.family: "Consolas"; font.pixelSize: 9; font.weight: Font.Black
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                            }
                                            Rectangle {
                                                id: vhsLabel; x: (vhsShell.width - width) / 2; y: 30; width: 14; height: Math.max(0, vhsShell.height - 48)
                                                radius: 3; color: "#FFFFFF"; border.width: 1.5; border.color: themeHub.darkInk; antialiasing: true
                                                opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                                Text {
                                                    y: vhsLabel.height; width: vhsLabel.height; height: vhsLabel.width; rotation: -90; transformOrigin: Item.TopLeft
                                                    verticalAlignment: Text.AlignVCenter; leftPadding: 4; rightPadding: 4; elide: Text.ElideRight; maximumLineCount: 1
                                                    text: propSlot.it.name; color: "#1A1B2E"; font.family: "Segoe UI"; font.pixelSize: 9; font.weight: Font.Black
                                                }
                                            }
                                        }
                                    }

                                    // 5. Archive Box
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "archive"
                                        readonly property color kraft: "#E3BD8A"
                                        readonly property real lidH: 18
                                        Rectangle { x: 3; y: 3; width: parent.width; height: parent.height; radius: 5; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: boxBody; x: 3; y: parent.lidH - 4; width: parent.width - 6; height: parent.height - parent.lidH + 4
                                            radius: 5; color: parent.kraft; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle { x: (boxBody.width - width) / 2; y: 4; width: 12; height: boxBody.height - 6.5; color: Qt.rgba(1, 1, 1, 0.55) }
                                            Rectangle {
                                                x: (boxBody.width - width) / 2; y: boxBody.height - height - 8; width: boxBody.width - 14; height: 20
                                                radius: 4; color: "#FFFFFF"; border.width: 1.5; border.color: themeHub.darkInk; antialiasing: true
                                                Text {
                                                    anchors.fill: parent; anchors.margins: 2; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle; maximumLineCount: 1; text: propSlot.it.name; color: "#1A1B2E"
                                                    font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Bold; opacity: propSlot.lifted ? 0 : 1
                                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                                }
                                            }
                                            Image { x: (boxBody.width - width) / 2; y: 9; width: 18; height: 18; smooth: true; source: "qrc:/qml/icons/archive-dark.svg" }
                                        }
                                        Rectangle {
                                            x: 0; y: 0; width: parent.width; height: parent.lidH; radius: 5
                                            color: Qt.darker(parent.kraft, 1.08); border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle { x: 6; y: 5; width: parent.width - 12; height: 2; radius: 1; color: "#FFFFFF"; opacity: 0.45 }
                                        }
                                    }

                                    // 6. Sticky Note
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "note"
                                        Rectangle { x: 3; y: 3; width: parent.width; height: parent.height; radius: 3; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: nPaper; anchors.fill: parent; radius: 3; color: propSlot.tint; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Rectangle { x: 4.5; y: 3.5; width: nPaper.width - 9; height: 6; radius: 2; color: "#FFFFFF"; opacity: 0.4 }
                                            Text {
                                                x: 8; y: 15; width: nPaper.width - 16; height: nPaper.height - 36
                                                wrapMode: Text.Wrap; elide: Text.ElideRight; maximumLineCount: 4; lineHeight: 0.95
                                                text: String(propSlot.it.value || propSlot.it.name || "").trim(); color: "#1A1B2E"
                                                font.family: "Segoe UI"; font.pixelSize: 9; font.weight: Font.Bold
                                                opacity: propSlot.lifted ? 0.35 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                            }
                                            Rectangle {
                                                x: nPaper.width - width - 2.5; y: nPaper.height - height - 2.5; width: 11; height: 11; radius: 2
                                                color: Qt.darker(propSlot.tint, 1.18); border.width: 1.5; border.color: themeHub.darkInk; antialiasing: true
                                            }
                                        }
                                    }

                                    // 7. Book Spine
                                    Item {
                                        anchors.fill: parent
                                        visible: propSlot.kind === "book"
                                        Rectangle { x: 3; y: 3; width: parent.width; height: parent.height; radius: 6; color: themeHub.darkInk; antialiasing: true }
                                        Rectangle {
                                            id: bSpine; anchors.fill: parent; radius: 6; color: propSlot.tint; border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                                            Repeater {
                                                model: [8, 14, bSpine.height - 15]
                                                Rectangle { required property real modelData; x: 3; y: modelData; width: bSpine.width - 6; height: 3; radius: 1.5; color: "#FFFFFF"; opacity: 0.6 }
                                            }
                                            Rectangle { x: 3; y: 22; width: 2; height: Math.max(0, bSpine.height - 40); radius: 1; color: "#FFFFFF"; opacity: 0.35 }
                                            Item {
                                                x: (bSpine.width - width) / 2; y: 22; width: 24; height: 24
                                                opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                                Rectangle { anchors.fill: parent; radius: 7; color: "#FFFFFF"; border.width: 2; border.color: themeHub.darkInk; antialiasing: true }
                                                Image { anchors.centerIn: parent; width: 14; height: 14; smooth: true; source: SM.iconSvgOf(propSlot.it) }
                                            }
                                            Item {
                                                id: bTitleBox; x: (bSpine.width - width) / 2; y: 54; width: 14; height: Math.max(0, bSpine.height - 76)
                                                opacity: propSlot.lifted ? 0 : 1
                                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                                Text {
                                                    x: 0; y: bTitleBox.height; width: bTitleBox.height; height: bTitleBox.width; rotation: -90; transformOrigin: Item.TopLeft
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; maximumLineCount: 1
                                                    text: propSlot.it.name; color: "#1A1B2E"; font.family: "Segoe UI"; font.pixelSize: 10; font.weight: Font.Black
                                                }
                                            }
                                        }
                                    }

                                    // Prop Click Target
                                    MouseArea {
                                        id: propClickMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            DropShelfService.openItem(propSlot.origIdx)
                                            shelfWin.closeShelf()
                                        }
                                    }

                                    // Inline Hover Action Buttons (Copy / Folder / Remove)
                                    Grid {
                                        columns: propSlot.rowButtons ? 3 : 1
                                        spacing: propSlot.rowButtons ? 3 : 4
                                        x: (book.width - width) / 2
                                        y: propSlot.rowButtons ? (book.height - height - 7) : 14
                                        opacity: propSlot.lifted ? 1 : 0
                                        visible: opacity > 0.01

                                        Behavior on opacity { NumberAnimation { duration: 110 } }

                                        Repeater {
                                            model: propSlot.isFile ? ["copy", "folder", "x"] : ["copy", "x"]
                                            delegate: Rectangle {
                                                id: actBtn
                                                required property string modelData
                                                width: propSlot.btnS
                                                height: propSlot.btnS
                                                radius: propSlot.rowButtons ? 6 : 7
                                                color: "#FFFFFF"
                                                border.width: 2
                                                border.color: actMa.containsMouse ? (actBtn.modelData === "x" ? "#E0575B" : themeHub.accentB) : themeHub.darkInk
                                                antialiasing: true

                                                Image {
                                                    anchors.centerIn: parent
                                                    width: propSlot.rowButtons ? 11 : 13
                                                    height: propSlot.rowButtons ? 11 : 13
                                                    smooth: true
                                                    source: actBtn.modelData === "copy"
                                                        ? "qrc:/qml/icons/copy-dark.svg"
                                                        : (actBtn.modelData === "folder"
                                                            ? "qrc:/qml/icons/folder-open-dark.svg"
                                                            : "qrc:/qml/icons/close-circle-dark.svg")
                                                }

                                                MouseArea {
                                                    id: actMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (actBtn.modelData === "copy")
                                                            DropShelfService.copyItem(propSlot.origIdx)
                                                        else if (actBtn.modelData === "folder")
                                                            DropShelfService.revealItem(propSlot.origIdx)
                                                        else
                                                            DropShelfService.removeIndex(propSlot.origIdx)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Signature Springing Shelf Plank
                    Item {
                        id: ledge
                        readonly property real grow: 0.7 + 0.3 * Math.min(1.12, shelfWin.popK)
                        readonly property real fullW: shelfWin.listW + 16
                        width: fullW * grow
                        height: shelfWin.plankH + 4
                        x: shelfWin.vpMargin - 8 + (fullW - width) / 2
                        y: shelfWin.areaH + 14

                        Repeater {
                            model: 2
                            Rectangle {
                                required property int index
                                x: index === 0 ? 26 : ledge.width - 26 - 12
                                y: shelfWin.plankH - 5
                                width: 12; height: 12; radius: 3; rotation: 45
                                color: "#FFFFFF"; border.width: 2; border.color: themeHub.darkInk; antialiasing: true
                            }
                        }
                        Rectangle { y: 3; width: ledge.width; height: shelfWin.plankH; radius: 7; color: themeHub.darkInk; antialiasing: true }
                        Rectangle {
                            id: board
                            width: ledge.width; height: shelfWin.plankH; radius: 7
                            border.width: 2.5; border.color: themeHub.darkInk; antialiasing: true
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: themeHub.accentB }
                                GradientStop { position: 1.0; color: themeHub.accentA }
                            }
                            Rectangle { x: 22; y: 4; width: Math.max(0, board.width - 44); height: 2; radius: 1; color: "#FFFFFF"; opacity: 0.45 }
                            Repeater {
                                model: 2
                                Rectangle {
                                    required property int index
                                    x: (index === 0 ? 11 : board.width - 11) - width / 2
                                    y: (board.height - height) / 2
                                    width: 6; height: 6; radius: 1.5; rotation: 45
                                    color: "#FFFFFF"; border.width: 1.5; border.color: themeHub.darkInk; antialiasing: true
                                }
                            }
                        }
                    }
                }
            }

            // Thin shelf scroll bar on right
            Rectangle {
                visible: shelves.visible && shelfWin.shelfCount > 1
                x: shelfWin.pad + shelfWin.listW + 8
                y: shelves.y + (shelves.height - height) * (shelves.currentIndex / Math.max(1, shelfWin.shelfCount - 1))
                width: 5
                height: Math.max(26, shelves.height / Math.max(1, shelfWin.shelfCount))
                radius: 2.5
                color: "#CBD5E1"
            }

            // One wheel notch scrolls one shelf cleanly
            Item {
                id: wheelHost
                anchors.fill: shelves
                z: 50
                visible: shelves.visible && shelfWin.shelfCount > 1

                property real acc: 0
                property bool cooling: false
                Timer { id: coolDown; interval: 220; onTriggered: wheelHost.cooling = false }
                Timer { id: settle; interval: 300; onTriggered: wheelHost.acc = 0 }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const d = (Math.abs(event.pixelDelta.y) > 0) ? event.pixelDelta.y : event.angleDelta.y
                        if (d === 0 || wheelHost.cooling)
                            return
                        wheelHost.acc += d
                        settle.restart()
                        if (wheelHost.acc >= 60) {
                            shelves.currentIndex = Math.max(0, shelves.currentIndex - 1)
                        } else if (wheelHost.acc <= -60) {
                            shelves.currentIndex = Math.min(shelfWin.shelfCount - 1, shelves.currentIndex + 1)
                        } else {
                            return
                        }
                        wheelHost.acc = 0
                        wheelHost.cooling = true
                        coolDown.restart()
                    }
                }
            }
        }

        // Signature washi tapes holding the top of the card
        SekaiWashiTape {
            x: 30
            y: -9
            width: 84
            height: 22
            rotation: -5
            color: "#6EE7B7"
        }

        SekaiWashiTape {
            x: shelfWin.cardW - 30 - 84
            y: -9
            width: 84
            height: 22
            rotation: 4
            color: "#F9A8D4"
        }
    }
}
