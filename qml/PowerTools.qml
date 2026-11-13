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
    // 1. SPOTLIGHT LAUNCHER (Alt + Space — Flow Launcher Parity)
    // =========================================================================
    PanelWindow {
        id: spotlightWin
        visible: themeHub.spotlightOpen
        clickThrough: false
        color: "transparent"

        readonly property int cardW: 580
        readonly property int shadow: 5
        property string query: ""
        property int selectedIdx: 0
        property var unifiedItems: []
        property double openedAt: 0

        width: cardW + shadow
        height: spotCard.height + shadow
        x: Math.max(12, Math.round((themeHub.screenW - width) * 0.5))
        y: Math.max(54, Math.round(themeHub.screenH * 0.16))

        function closeSpotlight() {
            themeHub.spotlightClosedAt = Date.now()
            themeHub.spotlightOpen = false
        }

        function evalMath(raw) {
            const s = (raw || "").trim()
            if (s === "")
                return ""
            let expr = s
            if (expr.startsWith("="))
                expr = expr.slice(1).trim()
            else if (!/[+\-*/%()]/.test(expr) && !/\b(sqrt|pow|sin|cos|tan|abs|round|floor|ceil|pi)\b/i.test(expr))
                return ""

            const expanded = expr
                .replace(/\bpi\b/gi, "Math.PI")
                .replace(/\bsqrt\b/gi, "Math.sqrt")
                .replace(/\bpow\b/gi, "Math.pow")
                .replace(/\bsin\b/gi, "Math.sin")
                .replace(/\bcos\b/gi, "Math.cos")
                .replace(/\btan\b/gi, "Math.tan")
                .replace(/\babs\b/gi, "Math.abs")
                .replace(/\bround\b/gi, "Math.round")
                .replace(/\bfloor\b/gi, "Math.floor")
                .replace(/\bceil\b/gi, "Math.ceil")
                .replace(/\^/g, "**")

            const cleanedCheck = expanded.replace(/Math\.(PI|sqrt|pow|sin|cos|tan|abs|round|floor|ceil)/g, "")
            if (!/^[0-9.\s+\-*/%(),xXa-fA-F]+$/.test(cleanedCheck))
                return ""
            try {
                const fn = new Function("return (" + expanded + ")")
                const val = fn()
                if (typeof val === "number" && isFinite(val)) {
                    const rounded = Math.round(val * 1000000) / 1000000
                    return String(rounded)
                }
            } catch (e) {}
            return ""
        }

        readonly property var systemCatalog: [
            { name: "Lock PC", sub: "Sys • Lock Windows workstation (Win+L)", keys: "lock workstation", badge: "SYS", act: "lock" },
            { name: "Sleep Computer", sub: "Sys • Suspend Windows to sleep", keys: "sleep suspend", badge: "SYS", act: "sleep" },
            { name: "Screenshot (Snip)", sub: "Sys • Open Windows Snipping overlay", keys: "screenshot snip capture", badge: "SYS", act: "screenshot" },
            { name: "Empty Recycle Bin", sub: "Sys • Clear all deleted files in Trash", keys: "empty recycle bin trash", badge: "SYS", act: "emptybin" },
            { name: "SekaiDesk Settings / Hub", sub: "Shell • Open Control Hub & Widget switches", keys: "settings control hub config", badge: "SHELL", act: "settings" },
            { name: "Clipboard History", sub: "Tool • View & paste copied items (Ctrl+Alt+V)", keys: "clipboard history paste", badge: "TOOL", act: "clipboard" },
            { name: "Drop Shelf", sub: "Tool • Stage files dragged from Explorer", keys: "drop shelf tray files", badge: "TOOL", act: "dropshelf" },
            { name: "Task Manager", sub: "Win • Inspect processes & CPU/RAM", keys: "taskmgr task manager processes", badge: "WIN", target: "taskmgr.exe" },
            { name: "Display Settings", sub: "WinSettings • Resolution, refresh & scaling", keys: "display monitor resolution", badge: "WIN", target: "ms-settings:display" },
            { name: "Sound Settings", sub: "WinSettings • Output & input audio devices", keys: "sound audio volume speaker", badge: "WIN", target: "ms-settings:sound" },
            { name: "Bluetooth & Devices", sub: "WinSettings • Pair wireless devices", keys: "bluetooth devices", badge: "WIN", target: "ms-settings:bluetooth" },
            { name: "Wi-Fi & Network", sub: "WinSettings • Connections & proxy", keys: "wifi network internet", badge: "WIN", target: "ms-settings:network-wifi" },
            { name: "Windows Update", sub: "WinSettings • Check OS updates", keys: "windows update", badge: "WIN", target: "ms-settings:windowsupdate" },
            { name: "Installed Apps", sub: "WinSettings • Uninstall or manage programs", keys: "installed apps programs uninstall", badge: "WIN", target: "ms-settings:appsfeatures" },
            { name: "Control Panel", sub: "Win • Classic Windows Control Panel", keys: "control panel", badge: "WIN", target: "control.exe" },
            { name: "Widget: Sticker Clock", sub: "Toggle floating SekaiPop clock widget", keys: "widget clock time", badge: "WIDGET", widgetKey: "clock" },
            { name: "Widget: Weather Card", sub: "Toggle live weather & forecast widget", keys: "widget weather forecast", badge: "WIDGET", widgetKey: "weather" },
            { name: "Widget: Profile Card", sub: "Toggle system stats & user utility card", keys: "widget profile card user stats", badge: "WIDGET", widgetKey: "profile" },
            { name: "Widget: Todo Checklist", sub: "Toggle desktop task checklist", keys: "widget todo tasks list", badge: "WIDGET", widgetKey: "todo" },
            { name: "Widget: Sticky Note", sub: "Toggle quick desktop scratchpad", keys: "widget note sticky scratchpad", badge: "WIDGET", widgetKey: "notes" },
            { name: "Widget: Live Lyrics", sub: "Toggle synced karaoke lyrics widget", keys: "widget lyrics karaoke music", badge: "WIDGET", widgetKey: "lyrics" }
        ]

        function refreshResults() {
            const raw = (query || "")
            const q = raw.trim()
            const qLower = q.toLowerCase()
            const out = []

            // 1. Math calculator
            const calc = evalMath(q)
            if (calc !== "") {
                out.push({
                    kind: "math",
                    name: "= " + calc,
                    sub: "Calculator • Enter to copy result",
                    badge: "CALC",
                    value: calc,
                    target: ""
                })
            }

            // 2. Explorer Path Navigator (C:\..., D:\..., ~/..., \\...)
            const isPath = /^[a-zA-Z]:[\\/]/.test(q) || q.startsWith("~") || q.startsWith("\\\\") || q.startsWith("%")
            if (isPath) {
                const paths = AppLauncher.listPathSuggestions(q)
                for (let i = 0; i < paths.length && out.length < 9; ++i) {
                    const p = paths[i]
                    out.push({
                        kind: "path",
                        name: p.name,
                        sub: p.path,
                        badge: p.isDir ? "DIR" : "FILE",
                        target: p.path,
                        completeText: p.path + (p.isDir && !p.path.endsWith("\\") ? "\\" : "")
                    })
                }
            }

            // 3. Shell / PowerShell commands (>cmd or >ps cmd)
            if (q.startsWith(">")) {
                const body = q.slice(1).trim()
                if (body.toLowerCase().startsWith("ps ")) {
                    const psCmd = body.slice(3).trim()
                    out.push({
                        kind: "shell",
                        name: "PowerShell: " + (psCmd || "..."),
                        sub: "Run in Windows PowerShell",
                        badge: "PS",
                        target: "powershell.exe",
                        args: psCmd !== "" ? "-NoExit -Command \"" + psCmd.replace(/\"/g, "\\\"") + "\"" : ""
                    })
                } else {
                    out.push({
                        kind: "shell",
                        name: "Run Command: " + (body || "..."),
                        sub: "Execute via cmd.exe",
                        badge: "CMD",
                        target: "cmd.exe",
                        args: body !== "" ? "/k " + body : ""
                    })
                }
            }

            // 4. Web & URL Action Keywords
            if (/^https?:\/\/\S+/i.test(q) || /^[a-zA-Z0-9-]+\.(com|org|net|io|dev|vn|jp|gg|ai|edu)(\/\S*)?$/i.test(q)) {
                const fullUrl = /^https?:\/\//i.test(q) ? q : ("https://" + q)
                out.push({
                    kind: "url",
                    name: "Open URL: " + fullUrl,
                    sub: "Launch directly in default browser",
                    badge: "URL",
                    target: fullUrl
                })
            } else if (/^(g|gg)\s+(.+)/i.test(q)) {
                const term = q.replace(/^(g|gg)\s+/i, "").trim()
                out.push({
                    kind: "url",
                    name: "Google Search: \"" + term + "\"",
                    sub: "https://www.google.com/search?q=...",
                    badge: "GOOGLE",
                    target: "https://www.google.com/search?q=" + encodeURIComponent(term)
                })
            } else if (/^yt\s+(.+)/i.test(q)) {
                const term = q.replace(/^yt\s+/i, "").trim()
                out.push({
                    kind: "url",
                    name: "YouTube Search: \"" + term + "\"",
                    sub: "https://www.youtube.com/results?search_query=...",
                    badge: "YOUTUBE",
                    target: "https://www.youtube.com/results?search_query=" + encodeURIComponent(term)
                })
            } else if (/^gh\s+(.+)/i.test(q)) {
                const term = q.replace(/^gh\s+/i, "").trim()
                out.push({
                    kind: "url",
                    name: "GitHub Search: \"" + term + "\"",
                    sub: "https://github.com/search?q=...",
                    badge: "GITHUB",
                    target: "https://github.com/search?q=" + encodeURIComponent(term)
                })
            } else if (/^wiki\s+(.+)/i.test(q)) {
                const term = q.replace(/^wiki\s+/i, "").trim()
                out.push({
                    kind: "url",
                    name: "Wikipedia: \"" + term + "\"",
                    sub: "https://en.wikipedia.org/wiki/Special:Search?search=...",
                    badge: "WIKI",
                    target: "https://en.wikipedia.org/wiki/Special:Search?search=" + encodeURIComponent(term)
                })
            } else if (/^tr\s+(.+)/i.test(q)) {
                const term = q.replace(/^tr\s+/i, "").trim()
                out.push({
                    kind: "url",
                    name: "Translate to Vietnamese: \"" + term + "\"",
                    sub: "translate.google.com",
                    badge: "TRANS",
                    target: "https://translate.google.com/?sl=auto&tl=vi&text=" + encodeURIComponent(term) + "&op=translate"
                })
            }

            // 5. Theme quick-switch (`theme ...` or matching band name)
            if (qLower.startsWith("theme")) {
                const tq = qLower.replace(/^theme\s*/, "").trim()
                for (let b = 0; b < themeHub.bands.length; ++b) {
                    const band = themeHub.bands[b]
                    if (tq === "" || band.name.toLowerCase().includes(tq) || band.id.includes(tq) || band.shortName.toLowerCase().includes(tq)) {
                        out.push({
                            kind: "theme",
                            name: "Theme: " + band.name,
                            sub: "Switch SekaiDesk Unit Palette (" + band.shortName + ")",
                            badge: "THEME",
                            bandId: band.id,
                            target: ""
                        })
                    }
                }
            }

            // 6. Fuzzy Apps (C++ fuzzy + acronym + usage-frequency ranking)
            if (!isPath && !q.startsWith(">")) {
                const apps = AppLauncher.searchApps(q)
                const maxApps = q === "" ? 6 : 7
                for (let i = 0; i < apps.length && i < maxApps && out.length < 9; ++i) {
                    const a = apps[i]
                    out.push({
                        kind: "app",
                        name: a.name,
                        sub: a.target,
                        badge: a.category || "APP",
                        target: a.target,
                        args: a.args || "",
                        completeText: a.name
                    })
                }
            }

            // 7. System / Windows Settings / Widget quick actions when query matches
            if (qLower !== "" && !isPath && !q.startsWith(">")) {
                for (let s = 0; s < systemCatalog.length && out.length < 10; ++s) {
                    const sc = systemCatalog[s]
                    if (sc.name.toLowerCase().includes(qLower) || sc.keys.includes(qLower)) {
                        out.push({
                            kind: sc.widgetKey ? "widget" : (sc.act ? "sys" : "win"),
                            name: sc.name,
                            sub: sc.sub,
                            badge: sc.badge,
                            act: sc.act || "",
                            widgetKey: sc.widgetKey || "",
                            target: sc.target || ""
                        })
                    }
                }
            }

            // 8. Fallback Google Search when user typed text
            if (q !== "" && !isPath && !q.startsWith(">") && !/^(g|gg|yt|gh|wiki|tr)\s+/i.test(q) && out.length < 9) {
                out.push({
                    kind: "url",
                    name: "Search Google for \"" + q + "\"",
                    sub: "Open web search in browser",
                    badge: "WEB",
                    target: "https://www.google.com/search?q=" + encodeURIComponent(q)
                })
            }

            unifiedItems = out.slice(0, 9)
            selectedIdx = 0
        }

        function executeItem(item, modifiers) {
            if (!item)
                return
            const mods = modifiers || 0
            const isCtrl = (mods & Qt.ControlModifier) !== 0
            const isShift = (mods & Qt.ShiftModifier) !== 0

            if (item.kind === "math") {
                ClipboardService.copyText(item.value)
                closeSpotlight()
                return
            }
            if (item.kind === "theme") {
                themeHub.setBand(item.bandId)
                closeSpotlight()
                return
            }
            if (item.kind === "widget") {
                const key = item.widgetKey
                const cur = (key === "clock") ? themeHub.wClockVisible
                          : (key === "weather") ? themeHub.wWeatherVisible
                          : (key === "profile") ? themeHub.wProfileVisible
                          : (key === "todo") ? themeHub.wTodoVisible
                          : (key === "notes") ? themeHub.wNotesVisible
                          : themeHub.wLyricsVisible
                themeHub.setWidgetVisible(key, !cur)
                closeSpotlight()
                return
            }
            if (item.kind === "sys") {
                closeSpotlight()
                if (item.act === "lock") WindowTracker.lockWorkstation()
                else if (item.act === "sleep") WindowTracker.sleepComputer()
                else if (item.act === "screenshot") WindowTracker.takeScreenshot()
                else if (item.act === "emptybin") TrashService.emptyTrash()
                else if (item.act === "settings") themeHub.settingsOpen = true
                else if (item.act === "clipboard") themeHub.clipboardOpen = true
                else if (item.act === "dropshelf") themeHub.dropShelfOpen = true
                return
            }

            if (isCtrl && item.target && !item.target.startsWith("http") && !item.target.startsWith("ms-settings:")) {
                AppLauncher.revealInExplorer(item.target)
                closeSpotlight()
                return
            }

            if (item.kind === "app") {
                AppLauncher.recordUsage(item.target)
                if (isShift) {
                    AppLauncher.runElevated(item.target, item.args || "")
                    closeSpotlight()
                    return
                }
            }

            if (item.target) {
                AppLauncher.launch(item.target, item.args || "")
            }
            closeSpotlight()
        }

        function activateCurrent(modifiers) {
            if (selectedIdx >= 0 && selectedIdx < unifiedItems.length) {
                executeItem(unifiedItems[selectedIdx], modifiers)
            }
        }

        function autocompleteCurrent() {
            if (selectedIdx >= 0 && selectedIdx < unifiedItems.length) {
                const it = unifiedItems[selectedIdx]
                if (it.completeText) {
                    spotInput.text = it.completeText
                    spotInput.cursorPosition = spotInput.text.length
                } else if (it.kind === "theme") {
                    spotInput.text = "theme " + it.bandId
                    spotInput.cursorPosition = spotInput.text.length
                }
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
            if (themeHub.spotlightOpen)
                closeSpotlight()
        }

        Timer {
            interval: 60
            repeat: true
            running: spotlightWin.visible
            onTriggered: {
                if ((Date.now() - spotlightWin.openedAt) > 250 && spotlightWin.isPointerOutsideAndPressed())
                    spotlightWin.closeSpotlight()
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
                spacing: 7

                // Search Bar
                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 11
                    color: "#F1F5F9"
                    border.width: 2
                    border.color: themeHub.darkInk

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
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
                            width: parent.width - 102
                            font.family: "Segoe UI"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: themeHub.darkInk
                            onTextChanged: {
                                spotlightWin.query = text
                                spotlightWin.refreshResults()
                            }
                            Keys.onPressed: event => {
                                const total = spotlightWin.unifiedItems.length
                                if (event.key === Qt.Key_Escape) {
                                    spotlightWin.closeSpotlight()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Down) {
                                    if (total > 0)
                                        spotlightWin.selectedIdx = (spotlightWin.selectedIdx + 1) % total
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Up) {
                                    if (total > 0)
                                        spotlightWin.selectedIdx = (spotlightWin.selectedIdx - 1 + total) % total
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Tab) {
                                    spotlightWin.autocompleteCurrent()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    spotlightWin.activateCurrent(event.modifiers)
                                    event.accepted = true
                                }
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: parent.text === ""
                                elide: Text.ElideRight
                                text: "Apps, =math, C:\\path, >cmd, g/yt/gh web, sys, theme..."
                                font.family: parent.font.family
                                font.pixelSize: 13
                                color: "#94A3B8"
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62
                            height: 22
                            radius: 6
                            color: themeHub.accentA
                            border.width: 1.5
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: "FLOW+ALT"
                                font.family: "Consolas"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                        }
                    }
                }

                // Unified Results List
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: spotlightWin.unifiedItems
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool isSel: spotlightWin.selectedIdx === index

                            width: parent.width
                            height: 44
                            radius: 10
                            color: isSel ? themeHub.accentA : (resMa.containsMouse ? themeHub.hoverTint : "#F8FAFC")
                            border.width: isSel ? 2 : 1
                            border.color: isSel ? themeHub.darkInk : "#E2E8F0"

                            Image {
                                id: spotRowIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                sourceSize.width: 48
                                sourceSize.height: 48
                                smooth: true
                                visible: modelData.kind === "app"
                                source: modelData.kind === "app" ? ("image://winicon/" + encodeURIComponent(modelData.target)) : ""
                            }

                            Rectangle {
                                id: spotGlyphBadge
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 7
                                visible: modelData.kind !== "app"
                                color: isSel ? "#FFFFFF" : themeHub.bandDeep
                                border.width: 1.5
                                border.color: themeHub.darkInk
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.kind === "math" ? "="
                                        : modelData.kind === "path" ? (modelData.badge === "DIR" ? "D" : "F")
                                        : modelData.kind === "shell" ? ">"
                                        : modelData.kind === "url" ? "W"
                                        : modelData.kind === "theme" ? "T"
                                        : "S"
                                    font.family: "Consolas"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: isSel ? themeHub.darkInk : themeHub.accentA
                                }
                            }

                            Column {
                                anchors.left: spotRowIcon.right
                                anchors.right: spotCatPill.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 1

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.name || ""
                                    font.family: "Segoe UI"
                                    font.pixelSize: 13
                                    font.weight: isSel ? Font.Bold : Font.Medium
                                    color: themeHub.darkInk
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                    text: modelData.sub || ""
                                    font.family: "Consolas"
                                    font.pixelSize: 10
                                    color: isSel ? "#1E293B" : "#64748B"
                                }
                            }

                            Rectangle {
                                id: spotCatPill
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(54, badgeTxt.implicitWidth + 14)
                                height: 20
                                radius: 6
                                color: isSel ? "#FFFFFF" : "#E2E8F0"
                                border.width: 1
                                border.color: themeHub.darkInk
                                Text {
                                    id: badgeTxt
                                    anchors.centerIn: parent
                                    text: modelData.badge || "APP"
                                    font.family: "Segoe UI"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: themeHub.darkInk
                                }
                            }

                            MouseArea {
                                id: resMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: spotlightWin.selectedIdx = index
                                onClicked: mouse => spotlightWin.executeItem(modelData, mouse.modifiers)
                            }
                        }
                    }
                }

                // Keyboard action hint footer
                Row {
                    width: parent.width
                    spacing: 10
                    Text {
                        text: "Enter: Run   •   Ctrl+Enter: Reveal Folder   •   Shift+Enter: Admin   •   Tab: Complete"
                        font.family: "Consolas"
                        font.pixelSize: 10
                        color: "#64748B"
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
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
        acceptFileDrops: true
        color: "transparent"

        onFilesDropped: paths => DropShelfService.addPaths(paths)

        readonly property int cardW: 360
        readonly property int shadow: 5
        width: cardW + shadow
        height: 360 + shadow
        x: Math.max(12, themeHub.screenW - width - 16)
        y: 52

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

                Item {
                    width: parent.width
                    height: 26

                    Rectangle {
                        id: shelfHdrIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
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
                        anchors.left: shelfHdrIcon.right
                        anchors.right: shelfHdrBtns.left
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: "Drop Shelf (" + DropShelfService.count + ")"
                        font.family: "Segoe UI"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: themeHub.darkInk
                    }

                    Row {
                        id: shelfHdrBtns
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Rectangle {
                            width: 68
                            height: 22
                            radius: 6
                            color: copyShelfMa.containsMouse ? themeHub.accentA : themeHub.accentB
                            border.width: 1.2
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: "Copy Paths"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: themeHub.darkInk
                            }
                            MouseArea {
                                id: copyShelfMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DropShelfService.copyAllPaths()
                            }
                        }

                        Rectangle {
                            width: 44
                            height: 22
                            radius: 6
                            color: clrShelfMa.containsMouse ? "#FECACA" : "#FEE2E2"
                            border.width: 1.2
                            border.color: themeHub.darkInk
                            Text {
                                anchors.centerIn: parent
                                text: "Clear"
                                font.family: "Segoe UI"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: "#DC2626"
                            }
                            MouseArea {
                                id: clrShelfMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DropShelfService.clear()
                            }
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 6
                            color: closeShelfMa.containsMouse ? "#CBD5E1" : "#E2E8F0"
                            border.width: 1.2
                            border.color: themeHub.darkInk
                            Image {
                                anchors.centerIn: parent
                                width: 12
                                height: 12
                                source: "qrc:/qml/icons/close-circle-dark.svg"
                            }
                            MouseArea {
                                id: closeShelfMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    themeHub.dropShelfClosedAt = Date.now()
                                    themeHub.dropShelfOpen = false
                                }
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
                        text: "Drag & drop files or folders here\nfrom Windows Explorer"
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
