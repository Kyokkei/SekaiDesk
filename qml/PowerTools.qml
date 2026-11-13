import QtQuick
import Quickshell
import SekaiDesk

Item {
    id: powerToolsRoot
    visible: false

    required property var themeHub
    required property bool fullscreenActive

    Connections {
        target: SystemControl
        function onSpotlightToggleRequested() {
            if (!themeHub.spotlightOpen && (Date.now() - themeHub.spotlightClosedAt) < 200)
                return
            themeHub.clipboardOpen = false
            themeHub.settingsOpen = false
            themeHub.spotlightOpen = !themeHub.spotlightOpen
        }
        function onClipboardToggleRequested() {
            if (!themeHub.clipboardOpen && (Date.now() - themeHub.clipboardClosedAt) < 200)
                return
            themeHub.spotlightOpen = false
            themeHub.settingsOpen = false
            themeHub.clipboardOpen = !themeHub.clipboardOpen
        }
    }

    // =========================================================================
    // 1. SPOTLIGHT LAUNCHER (Alt + Space)
    // =========================================================================
    PanelWindow {
        id: spotlightWin
        visible: themeHub.spotlightOpen
        clickThrough: false
        color: "transparent"

        readonly property int cardW: 540
        readonly property int shadow: 5
        property string query: ""
        property int selectedIdx: 0
        property var appResults: []
        property string mathResult: ""
        property double openedAt: 0

        width: cardW + shadow
        height: spotCard.height + shadow
        x: Math.max(12, Math.round((themeHub.screenW - width) * 0.5))
        y: Math.max(54, Math.round(themeHub.screenH * 0.18))

        function evalMath(raw) {
            const s = (raw || "").trim()
            if (s === "")
                return ""
            let expr = s
            if (expr.startsWith("="))
                expr = expr.slice(1).trim()
            else if (!/[+\-*/%()]/.test(expr))
                return ""
            if (!/^[0-9.\s+\-*/%()]+$/.test(expr))
                return ""
            try {
                const fn = new Function("return (" + expr + ")")
                const val = fn()
                if (typeof val === "number" && isFinite(val)) {
                    const rounded = Math.round(val * 1000000) / 1000000
                    return String(rounded)
                }
            } catch (e) {}
            return ""
        }

        function refreshResults() {
            mathResult = evalMath(query)
            appResults = AppLauncher.searchApps(query)
            selectedIdx = 0
        }

        function activateCurrent() {
            if (mathResult !== "" && selectedIdx === 0) {
                ClipboardService.copyText(mathResult)
                themeHub.spotlightClosedAt = Date.now()
                themeHub.spotlightOpen = false
                return
            }
            const offset = (mathResult !== "" ? 1 : 0)
            const idx = selectedIdx - offset
            if (idx >= 0 && idx < appResults.length) {
                const item = appResults[idx]
                AppLauncher.launch(item.target, item.args || "")
                themeHub.spotlightClosedAt = Date.now()
                themeHub.spotlightOpen = false
            } else if (query.trim().startsWith(">")) {
                const cmd = query.trim().slice(1).trim()
                if (cmd !== "")
                    AppLauncher.launch("cmd.exe", "/c start \"\" " + cmd)
                themeHub.spotlightClosedAt = Date.now()
                themeHub.spotlightOpen = false
            }
        }

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                query = ""
                spotInput.text = ""
                refreshResults()
                focusActivate()
                spotFocusTimer.restart()
            }
        }

        Timer {
            id: spotFocusTimer
            interval: 35
            onTriggered: spotInput.forceActiveFocus()
        }

        onWindowDeactivated: {
            if (themeHub.spotlightOpen) {
                themeHub.spotlightClosedAt = Date.now()
                themeHub.spotlightOpen = false
            }
        }

        Timer {
            interval: 60
            repeat: true
            running: spotlightWin.visible
            onTriggered: {
                if ((Date.now() - spotlightWin.openedAt) > 250 && spotlightWin.isPointerOutsideAndPressed()) {
                    themeHub.spotlightClosedAt = Date.now()
                    themeHub.spotlightOpen = false
                }
            }
        }

        Rectangle {
            x: spotlightWin.shadow
            y: spotlightWin.shadow
            width: spotlightWin.cardW
            height: spotCard.height
            radius: 16
            color: themeHub.darkInk
        }

        Rectangle {
            id: spotCard
            x: 0
            y: 0
            width: spotlightWin.cardW
            height: spotCol.implicitHeight + 20
            radius: 16
            color: "#FFFFFF"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                id: spotCol
                x: 12
                y: 10
                width: spotlightWin.cardW - 24
                spacing: 8

                // Search Bar
                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 11
                    color: "#F1F5F9"
                    border.width: 2
                    border.color: themeHub.darkInk

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
                            source: "qrc:/qml/icons/magnifer-dark.svg"
                        }

                        TextInput {
                            id: spotInput
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 96
                            font.family: "Segoe UI"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: themeHub.darkInk
                            onTextChanged: {
                                spotlightWin.query = text
                                spotlightWin.refreshResults()
                            }
                            Keys.onPressed: event => {
                                const total = spotlightWin.appResults.length + (spotlightWin.mathResult !== "" ? 1 : 0)
                                if (event.key === Qt.Key_Escape) {
                                    themeHub.spotlightClosedAt = Date.now()
                                    themeHub.spotlightOpen = false
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Down) {
                                    if (total > 0)
                                        spotlightWin.selectedIdx = (spotlightWin.selectedIdx + 1) % total
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    if (total > 0)
                                        spotlightWin.selectedIdx = (spotlightWin.selectedIdx - 1 + total) % total
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    spotlightWin.activateCurrent()
                                    event.accepted = true
                                }
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: parent.text === ""
                                text: "Search apps, =math, or >command..."
                                font: parent.font
                                color: "#94A3B8"
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 58
                            height: 22
                            radius: 6
                            color: themeHub.accentA
                            border.width: 1.5
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: "ALT+SPC"
                                font.family: "Consolas"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                        }
                    }
                }

                // Instant Math Result Row
                Rectangle {
                    visible: spotlightWin.mathResult !== ""
                    width: parent.width
                    height: 44
                    radius: 10
                    color: spotlightWin.selectedIdx === 0 ? themeHub.accentA : themeHub.hoverTint
                    border.width: 2
                    border.color: themeHub.darkInk

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "= " + spotlightWin.mathResult
                            font.family: "Consolas"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        Item { width: 1; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Enter to copy"
                            font.family: "Segoe UI"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: "#475569"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ClipboardService.copyText(spotlightWin.mathResult)
                            themeHub.spotlightClosedAt = Date.now()
                            themeHub.spotlightOpen = false
                        }
                    }
                }

                // App Results List
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: spotlightWin.appResults.slice(0, 8)
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property int itemSlot: index + (spotlightWin.mathResult !== "" ? 1 : 0)
                            readonly property bool isSel: spotlightWin.selectedIdx === itemSlot

                            width: parent.width
                            height: 40
                            radius: 10
                            color: isSel ? themeHub.accentA : (resMa.containsMouse ? themeHub.hoverTint : "#F8FAFC")
                            border.width: isSel ? 2 : 1
                            border.color: isSel ? themeHub.darkInk : "#E2E8F0"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    height: 24
                                    sourceSize.width: 48
                                    sourceSize.height: 48
                                    smooth: true
                                    source: "image://winicon/" + encodeURIComponent(modelData.target)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 110
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    font.family: "Segoe UI"
                                    font.pixelSize: 13
                                    font.weight: isSel ? Font.Bold : Font.Medium
                                    color: themeHub.darkInk
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 60
                                    height: 20
                                    radius: 6
                                    color: isSel ? "#FFFFFF" : "#E2E8F0"
                                    border.width: 1
                                    border.color: themeHub.darkInk
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.category || "App"
                                        font.family: "Segoe UI"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: themeHub.darkInk
                                    }
                                }
                            }

                            MouseArea {
                                id: resMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: spotlightWin.selectedIdx = itemSlot
                                onClicked: {
                                    AppLauncher.launch(modelData.target, modelData.args || "")
                                    themeHub.spotlightClosedAt = Date.now()
                                    themeHub.spotlightOpen = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 2. CLIPBOARD HISTORY (Ctrl + Alt + V)
    // =========================================================================
    PanelWindow {
        id: clipWin
        visible: themeHub.clipboardOpen
        clickThrough: false
        color: "transparent"

        readonly property int cardW: 440
        readonly property int shadow: 5
        property string filterText: ""
        property double openedAt: 0

        width: cardW + shadow
        height: 470 + shadow
        x: Math.max(12, Math.round((themeHub.screenW - width) * 0.5))
        y: Math.max(44, Math.round(themeHub.screenH * 0.16))

        onVisibleChanged: {
            if (visible) {
                openedAt = Date.now()
                clipSearch.text = ""
                filterText = ""
                focusActivate()
            }
        }

        onWindowDeactivated: {
            if (themeHub.clipboardOpen && !clipSearch.activeFocus) {
                themeHub.clipboardClosedAt = Date.now()
                themeHub.clipboardOpen = false
            }
        }

        Timer {
            interval: 65
            repeat: true
            running: clipWin.visible
            onTriggered: {
                if ((Date.now() - clipWin.openedAt) > 250 && clipWin.isPointerOutsideAndPressed()) {
                    themeHub.clipboardClosedAt = Date.now()
                    themeHub.clipboardOpen = false
                }
            }
        }

        Rectangle {
            x: clipWin.shadow
            y: clipWin.shadow
            width: clipWin.cardW
            height: 470
            radius: 16
            color: themeHub.darkInk
        }

        Rectangle {
            x: 0
            y: 0
            width: clipWin.cardW
            height: 470
            radius: 16
            color: "#F8FAFC"
            border.width: 2.5
            border.color: themeHub.darkInk

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 8
                        color: themeHub.accentB
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            source: "qrc:/qml/icons/clipboard-text-dark.svg"
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 144
                        text: "Clipboard History (" + ClipboardService.count + ")"
                        font.family: "Segoe UI"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }

                    Rectangle {
                        width: 102
                        height: 24
                        radius: 7
                        color: clrClipMa.containsMouse ? "#FEE2E2" : "#FFFFFF"
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        Text {
                            anchors.centerIn: parent
                            text: "Clear Unpinned"
                            font.family: "Segoe UI"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#DC2626"
                        }
                        MouseArea {
                            id: clrClipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ClipboardService.clearUnpinned()
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: "#FFFFFF"
                    border.width: 1.5
                    border.color: themeHub.darkInk
                    TextInput {
                        id: clipSearch
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: themeHub.darkInk
                        onTextChanged: clipWin.filterText = text.trim().toLowerCase()
                        Keys.onEscapePressed: {
                            themeHub.clipboardClosedAt = Date.now()
                            themeHub.clipboardOpen = false
                        }
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: parent.text === ""
                            text: "Filter clipboard entries..."
                            font: parent.font
                            color: "#94A3B8"
                        }
                    }
                }

                ListView {
                    width: parent.width
                    height: parent.height - 82
                    clip: true
                    spacing: 6
                    model: {
                        const raw = ClipboardService.history || []
                        const f = clipWin.filterText
                        const out = []
                        for (let i = 0; i < raw.length; ++i) {
                            const item = raw[i]
                            if (f === "" || (item.text || "").toLowerCase().indexOf(f) !== -1) {
                                out.push({
                                    origIdx: i,
                                    text: item.text || "",
                                    preview: item.preview || "",
                                    time: item.time || "",
                                    chars: item.chars || 0,
                                    pinned: !!item.pinned
                                })
                            }
                        }
                        return out
                    }
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: Math.max(54, clipPrevTxt.implicitHeight + 26)
                        radius: 10
                        color: clipRowMa.containsMouse ? themeHub.hoverTint : "#FFFFFF"
                        border.width: modelData.pinned ? 2 : 1.5
                        border.color: modelData.pinned ? themeHub.bandBorder : "#CBD5E1"

                        Column {
                            anchors.left: parent.left
                            anchors.right: clipBtnsRow.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 3

                            Text {
                                id: clipPrevTxt
                                width: parent.width
                                text: modelData.preview
                                maximumLineCount: 3
                                wrapMode: Text.WrapAnywhere
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.family: "Segoe UI"
                                font.pixelSize: 11
                                color: themeHub.darkInk
                            }

                            Text {
                                text: (modelData.pinned ? "PINNED • " : "") + modelData.time + " • " + modelData.chars + " chars"
                                font.family: "Consolas"
                                font.pixelSize: 9
                                color: "#64748B"
                            }
                        }

                        MouseArea {
                            id: clipRowMa
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: clipBtnsRow.left
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ClipboardService.copyIndex(modelData.origIdx)
                                themeHub.clipboardClosedAt = Date.now()
                                themeHub.clipboardOpen = false
                            }
                        }

                        Row {
                            id: clipBtnsRow
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: modelData.pinned ? themeHub.accentA : "#F1F5F9"
                                border.width: 1
                                border.color: themeHub.darkInk
                                Image {
                                    anchors.centerIn: parent
                                    width: 12
                                    height: 12
                                    source: "qrc:/qml/icons/pin-dark.svg"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ClipboardService.togglePin(modelData.origIdx)
                                }
                            }

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: "#FEE2E2"
                                border.width: 1
                                border.color: themeHub.darkInk
                                Image {
                                    anchors.centerIn: parent
                                    width: 12
                                    height: 12
                                    source: "qrc:/qml/icons/trash-bin-trash-red.svg"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ClipboardService.removeIndex(modelData.origIdx)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. DESKTOP DROP SHELF (Drag & Drop Staging Tray)
    // =========================================================================
    PanelWindow {
        id: shelfWin
        visible: themeHub.dropShelfOpen && !fullscreenActive
        clickThrough: false
        color: "transparent"

        readonly property int cardW: 340
        readonly property int shadow: 5
        width: cardW + shadow
        height: 360 + shadow
        x: Math.max(12, themeHub.screenW - width - 16)
        y: 36

        Rectangle {
            x: shelfWin.shadow
            y: shelfWin.shadow
            width: shelfWin.cardW
            height: 360
            radius: 16
            color: themeHub.darkInk
        }

        Rectangle {
            id: shelfCard
            x: 0
            y: 0
            width: shelfWin.cardW
            height: 360
            radius: 16
            color: "#F8FAFC"
            border.width: 2.5
            border.color: themeHub.darkInk

            DropArea {
                id: shelfDropArea
                anchors.fill: parent
                onDropped: drop => {
                    if (drop.hasUrls) {
                        DropShelfService.addUrls(drop.urls)
                        drop.acceptProposedAction()
                    }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 6
                    Rectangle {
                        width: 24
                        height: 24
                        radius: 7
                        color: themeHub.accentA
                        border.width: 1.5
                        border.color: themeHub.darkInk
                        Image {
                            anchors.centerIn: parent
                            width: 13
                            height: 13
                            source: "qrc:/qml/icons/folder-with-files-dark.svg"
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 170
                        text: "Drop Shelf (" + DropShelfService.count + ")"
                        font.family: "Segoe UI"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }
                    Rectangle {
                        width: 66
                        height: 22
                        radius: 6
                        color: themeHub.accentB
                        border.width: 1
                        border.color: themeHub.darkInk
                        Text {
                            anchors.centerIn: parent
                            text: "Copy Paths"
                            font.family: "Segoe UI"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: themeHub.darkInk
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DropShelfService.copyAllPaths()
                        }
                    }
                    Rectangle {
                        width: 44
                        height: 22
                        radius: 6
                        color: "#FEE2E2"
                        border.width: 1
                        border.color: themeHub.darkInk
                        Text {
                            anchors.centerIn: parent
                            text: "Clear"
                            font.family: "Segoe UI"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: "#DC2626"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DropShelfService.clear()
                        }
                    }
                    Rectangle {
                        width: 22
                        height: 22
                        radius: 6
                        color: "#E2E8F0"
                        border.width: 1
                        border.color: themeHub.darkInk
                        Image {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            source: "qrc:/qml/icons/close-circle-dark.svg"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                themeHub.dropShelfClosedAt = Date.now()
                                themeHub.dropShelfOpen = false
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - 36
                    radius: 10
                    color: shelfDropArea.containsDrag ? themeHub.hoverTint : "#FFFFFF"
                    border.width: shelfDropArea.containsDrag ? 2 : 1.5
                    border.color: shelfDropArea.containsDrag ? themeHub.darkInk : "#CBD5E1"

                    Text {
                        anchors.centerIn: parent
                        visible: DropShelfService.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: "Drag & drop files or folders here\nto hold temporarily"
                        font.family: "Segoe UI"
                        font.pixelSize: 12
                        color: "#64748B"
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        spacing: 5
                        visible: DropShelfService.count > 0
                        model: DropShelfService.items
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 44
                            radius: 8
                            color: shelfRowMa.containsMouse ? themeHub.hoverTint : "#F8FAFC"
                            border.width: 1
                            border.color: "#CBD5E1"

                            Column {
                                anchors.left: parent.left
                                anchors.right: shelfItemBtns.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 1
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.name || ""
                                    font.family: "Segoe UI"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: themeHub.darkInk
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                    text: (modelData.isDir ? "Folder" : (modelData.ext || "File")) + " • " + (modelData.sizeText || "")
                                    font.family: "Consolas"
                                    font.pixelSize: 9
                                    color: "#64748B"
                                }
                            }

                            MouseArea {
                                id: shelfRowMa
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: shelfItemBtns.left
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DropShelfService.openItem(index)
                            }

                            Row {
                                id: shelfItemBtns
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Rectangle {
                                    width: 46
                                    height: 22
                                    radius: 6
                                    color: themeHub.accentB
                                    border.width: 1
                                    border.color: themeHub.darkInk
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Reveal"
                                        font.family: "Segoe UI"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: themeHub.darkInk
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DropShelfService.revealItem(index)
                                    }
                                }
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 6
                                    color: "#FEE2E2"
                                    border.width: 1
                                    border.color: themeHub.darkInk
                                    Image {
                                        anchors.centerIn: parent
                                        width: 11
                                        height: 11
                                        source: "qrc:/qml/icons/close-circle-dark.svg"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: DropShelfService.removeIndex(index)
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
