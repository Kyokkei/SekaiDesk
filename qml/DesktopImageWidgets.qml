import QtQuick
import Quickshell
import SekaiDesk

// #6: SekaiPop ImageWidget — custom Polaroid & Washi-Tape desktop photo frames
Item {
    id: root
    visible: false

    required property var themeHub
    property bool fullscreenActive: false

    Instantiator {
        model: root.themeHub.imageFrames || []

        delegate: PanelWindow {
            id: imgWin
            required property var modelData
            required property int index

            readonly property string frameId: modelData.id || ""
            readonly property string rawPath: modelData.path || ""
            readonly property string resolvedUrl: {
                if (rawPath === "")
                    return ""
                if (rawPath.indexOf("file://") === 0 || rawPath.indexOf("qrc:/") === 0)
                    return rawPath
                return WallpaperService.toFileUrl(rawPath)
            }
            readonly property string captionText: {
                if (rawPath === "")
                    return "Drop image here"
                const parts = rawPath.replace(/\\/g, "/").split("/")
                return (parts[parts.length - 1] || "Photo").replace(/\.[^.]+$/, "")
            }
            readonly property int frameW: Math.max(140, Math.min(720, Number(modelData.w) || 260))
            readonly property int frameH: Math.max(140, Math.min(720, Number(modelData.h) || 300))
            readonly property string fitMode: modelData.fitMode === "fit" ? "fit" : "crop"
            readonly property bool showTape: modelData.showTape !== false
            readonly property bool showFrame: modelData.showFrame !== false
            readonly property bool isPinned: !!modelData.pinned
            readonly property real frameTilt: Number(modelData.tilt) || 0.0

            property int liveW: frameW
            property int liveH: frameH
            property bool nativeDragging: false
            property bool resizing: false
            property bool hovered: frameHover.hovered || resizeMa.containsMouse || resizeMa.pressed

            onFrameWChanged: if (!resizing) liveW = frameW
            onFrameHChanged: if (!resizing) liveH = frameH

            readonly property int padX: 22
            readonly property int padTop: 22
            readonly property int padBottom: 22
            readonly property int clampedX: root.themeHub.clampWidgetX(Number(modelData.x) || 200, 120)
            readonly property int clampedY: root.themeHub.clampWidgetY(clampedX, Number(modelData.y) || 140, 120)

            onClampedXChanged: if (!nativeDragging) x = clampedX
            onClampedYChanged: if (!nativeDragging) y = clampedY
            Component.onCompleted: {
                x = clampedX
                y = clampedY
            }

            width: liveW + padX * 2
            height: liveH + padTop + padBottom
            visible: !root.fullscreenActive
            desktopLayer: !(imgWin.isPinned && !root.themeHub.editMode)
            color: "transparent"
            acceptFileDrops: true
            clickThrough: !root.themeHub.editMode && root.themeHub.widgetsLocked && !(imgWin.isPinned && false)
            mask: (!root.themeHub.editMode && root.themeHub.widgetsLocked)
                ? []
                : [{ x: 4, y: 4, width: width - 8, height: height - 8 }]

            onFilesDropped: paths => {
                if (!paths || paths.length === 0)
                    return
                const re = /\.(png|jpe?g|webp|bmp|gif)$/i
                let usedFirst = false
                for (let i = 0; i < paths.length; ++i) {
                    const p = String(paths[i] || "")
                    if (!re.test(p))
                        continue
                    if (!usedFirst) {
                        usedFirst = true
                        root.themeHub.updateImageFrame(imgWin.frameId, { path: p })
                    } else {
                        root.themeHub.addImageFrame(p)
                    }
                }
            }

            Item {
                id: cardStage
                x: imgWin.padX
                y: imgWin.padTop
                width: imgWin.liveW
                height: imgWin.liveH
                rotation: imgWin.hovered || root.themeHub.editMode ? 0 : imgWin.frameTilt
                Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                HoverHandler {
                    id: frameHover
                }

                // Comic hard offset shadow
                Rectangle {
                    x: 5; y: 6
                    width: parent.width
                    height: parent.height
                    radius: imgWin.showFrame ? 14 : 18
                    color: root.themeHub.darkInk
                    opacity: 0.92
                }

                // Main Polaroid / Card frame
                Rectangle {
                    id: frameCard
                    anchors.fill: parent
                    radius: imgWin.showFrame ? 14 : 18
                    color: imgWin.showFrame ? "#FFFDF7" : "#1A1B2E"
                    border.width: imgWin.showFrame ? 3 : 3.5
                    border.color: root.themeHub.darkInk
                    clip: true

                    // Inner image area
                    Rectangle {
                        id: photoArea
                        x: imgWin.showFrame ? 10 : 0
                        y: imgWin.showFrame ? 10 : 0
                        width: parent.width - (imgWin.showFrame ? 20 : 0)
                        height: Math.max(40, parent.height - (imgWin.showFrame ? 44 : 0))
                        radius: imgWin.showFrame ? 8 : 16
                        color: "#E8EEF8"
                        border.width: imgWin.showFrame ? 2 : 0
                        border.color: root.themeHub.darkInk
                        clip: true

                        Image {
                            id: photoImg
                            anchors.fill: parent
                            source: imgWin.resolvedUrl
                            fillMode: imgWin.fitMode === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            cache: true
                            visible: status === Image.Ready
                        }

                        // Empty dropzone / Loading state
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            visible: photoImg.status !== Image.Ready
                            width: parent.width - 24

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 30; height: 30
                                sourceSize.width: 60; sourceSize.height: 60
                                source: "qrc:/qml/icons/gallery-dark.svg"
                                opacity: 0.55
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: imgWin.rawPath === ""
                                    ? "Drop photo here\nor click to choose"
                                    : (photoImg.status === Image.Error ? "Could not load image" : "Loading...")
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#475569"
                            }
                        }
                    }

                    // Polaroid bottom caption strip
                    Row {
                        visible: imgWin.showFrame
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 28
                        anchors.bottomMargin: 8
                        spacing: 6
                        height: 22

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; rotation: 45; radius: 1
                            color: imgWin.isPinned ? root.themeHub.accentB : root.themeHub.accentA
                            border.width: 1; border.color: root.themeHub.darkInk
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 14
                            elide: Text.ElideRight
                            text: imgWin.captionText
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: Font.Black
                            color: root.themeHub.darkInk
                        }
                    }

                    // Drag / Click Surface
                    MouseArea {
                        id: dragMa
                        anchors.fill: parent
                        z: 1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: (root.themeHub.widgetsLocked && !root.themeHub.editMode)
                            ? (imgWin.rawPath === "" ? Qt.PointingHandCursor : Qt.ArrowCursor)
                            : (imgWin.nativeDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

                        property bool didMove: false
                        property real pressX: 0
                        property real pressY: 0

                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                root.themeHub.setEditMode(true)
                                return
                            }
                            if (root.themeHub.widgetsLocked && !root.themeHub.editMode)
                                return
                            didMove = false
                            pressX = mouse.x
                            pressY = mouse.y
                            const minX = root.themeHub.virtMinX + 8
                            const minY = root.themeHub.virtMinY + 8
                            const maxW = Math.max(minX + 100, root.themeHub.virtMaxX - 80)
                            const maxH = Math.max(minY + 100, root.themeHub.virtMaxY - 60)
                            imgWin.nativeDragging = true
                            imgWin.beginNativeDrag(minX, minY, maxW, maxH)
                        }
                        onPositionChanged: mouse => {
                            if (!imgWin.nativeDragging)
                                return
                            if (Math.abs(mouse.x - pressX) > 4 || Math.abs(mouse.y - pressY) > 4)
                                didMove = true
                            imgWin.stepNativeDrag()
                        }
                        onReleased: {
                            if (imgWin.nativeDragging) {
                                imgWin.nativeDragging = false
                                imgWin.endNativeDrag()
                                if (didMove) {
                                    root.themeHub.updateImageFrame(imgWin.frameId, { x: imgWin.x, y: imgWin.y })
                                } else if (imgWin.rawPath === "") {
                                    const picked = SystemControl.pickImageFile("Choose Polaroid Image")
                                    if (picked !== "")
                                        root.themeHub.updateImageFrame(imgWin.frameId, { path: picked })
                                }
                            }
                        }
                        onCanceled: {
                            if (imgWin.nativeDragging) {
                                imgWin.nativeDragging = false
                                imgWin.endNativeDrag()
                            }
                        }
                    }
                }

                // Decorative SekaiPop Washi Tape Strips overlapping top corners
                SekaiWashiTape {
                    visible: imgWin.showTape
                    x: -10; y: -10
                    width: 68; height: 20
                    rotation: -14
                    color: root.themeHub.accentB
                    z: 20
                }
                SekaiWashiTape {
                    visible: imgWin.showTape
                    x: parent.width - 58; y: -10
                    width: 68; height: 20
                    rotation: 12
                    color: root.themeHub.accentA
                    z: 20
                }

                // Floating Action Pill Toolbar (visible on hover or in Edit Mode)
                Rectangle {
                    id: actionPill
                    visible: imgWin.hovered || root.themeHub.editMode
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -14
                    z: 40
                    width: actRow.implicitWidth + 12
                    height: 26
                    radius: 13
                    color: "#FFFFFF"
                    border.width: 2
                    border.color: root.themeHub.darkInk

                    Row {
                        id: actRow
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: [
                                { k: "pick",  t: "IMG",                        bg: "#E0F2FE" },
                                { k: "fit",   t: imgWin.fitMode.toUpperCase(), bg: "#F1F5F9" },
                                { k: "tape",  t: imgWin.showTape ? "TAPE" : "NO TAPE", bg: imgWin.showTape ? root.themeHub.accentB : "#F1F5F9" },
                                { k: "frame", t: imgWin.showFrame ? "CARD" : "BARE",   bg: imgWin.showFrame ? root.themeHub.accentA : "#F1F5F9" },
                                { k: "pin",   t: imgWin.isPinned ? "TOP" : "DESK",     bg: imgWin.isPinned ? "#FFD166" : "#F1F5F9" },
                                { k: "del",   t: "×",                          bg: "#FFE4E6" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: chipTxt.implicitWidth + 10
                                height: 20
                                radius: 10
                                color: chipMa.containsMouse ? root.themeHub.hoverTint : modelData.bg
                                border.width: 1.5
                                border.color: root.themeHub.darkInk

                                Text {
                                    id: chipTxt
                                    anchors.centerIn: parent
                                    text: modelData.t
                                    font.family: "Segoe UI"
                                    font.pixelSize: modelData.k === "del" ? 12 : 9
                                    font.weight: Font.Black
                                    color: modelData.k === "del" ? "#D92652" : root.themeHub.darkInk
                                }
                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const k = modelData.k
                                        if (k === "pick") {
                                            const p = SystemControl.pickImageFile("Choose Polaroid Image")
                                            if (p !== "")
                                                root.themeHub.updateImageFrame(imgWin.frameId, { path: p })
                                        } else if (k === "fit") {
                                            root.themeHub.updateImageFrame(imgWin.frameId, { fitMode: imgWin.fitMode === "fit" ? "crop" : "fit" })
                                        } else if (k === "tape") {
                                            root.themeHub.updateImageFrame(imgWin.frameId, { showTape: !imgWin.showTape })
                                        } else if (k === "frame") {
                                            root.themeHub.updateImageFrame(imgWin.frameId, { showFrame: !imgWin.showFrame })
                                        } else if (k === "pin") {
                                            root.themeHub.updateImageFrame(imgWin.frameId, { pinned: !imgWin.isPinned })
                                        } else if (k === "del") {
                                            root.themeHub.removeImageFrame(imgWin.frameId)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom-Right Resize Grip (visible on hover or Edit Mode)
                Rectangle {
                    id: resizeGrip
                    visible: imgWin.hovered || root.themeHub.editMode
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -5
                    width: 20
                    height: 20
                    radius: 10
                    z: 45
                    color: resizeMa.containsMouse || resizeMa.pressed ? root.themeHub.accentB : root.themeHub.accentA
                    border.width: 2
                    border.color: root.themeHub.darkInk

                    Text {
                        anchors.centerIn: parent
                        text: "↘"
                        font.pixelSize: 11
                        font.weight: Font.Black
                        color: root.themeHub.darkInk
                    }

                    MouseArea {
                        id: resizeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.SizeFDiagCursor
                        property real startX: 0
                        property real startY: 0
                        property int startW: 260
                        property int startH: 300

                        onPressed: mouse => {
                            imgWin.resizing = true
                            startX = mouse.x
                            startY = mouse.y
                            startW = imgWin.liveW
                            startH = imgWin.liveH
                        }
                        onPositionChanged: mouse => {
                            if (!imgWin.resizing)
                                return
                            imgWin.liveW = Math.max(140, Math.min(720, Math.round(imgWin.liveW + (mouse.x - startX))))
                            imgWin.liveH = Math.max(140, Math.min(720, Math.round(imgWin.liveH + (mouse.y - startY))))
                        }
                        onReleased: {
                            if (!imgWin.resizing)
                                return
                            imgWin.resizing = false
                            root.themeHub.updateImageFrame(imgWin.frameId, { w: imgWin.liveW, h: imgWin.liveH })
                        }
                        onCanceled: imgWin.resizing = false
                    }
                }
            }
        }
    }
}
