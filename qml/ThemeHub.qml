import QtQuick
import SekaiDesk

Item {
    id: hub
    visible: false

    // Reference screen dimensions passed from Shell.qml
    property int screenW: 1920
    property int screenH: 1080

    readonly property var bands: [
        {
            id: "vs",
            name: "Virtual Singer",
            shortName: "VS",
            border: "#555473",
            A: "#04feee",
            B: "#00ffcb",
            deep: "#232235",
            hoverTint: "#d9fff6"
        },
        {
            id: "leoneed",
            name: "Leo/need",
            shortName: "L/n",
            border: "#2d3775",
            A: "#8ea3ff",
            B: "#9fd8ff",
            deep: "#181e3f",
            hoverTint: "#f1f9ff"
        },
        {
            id: "mmj",
            name: "MORE MORE JUMP!",
            shortName: "MMJ",
            border: "#39662d",
            A: "#a4ee55",
            B: "#7fe9a8",
            deep: "#223c1b",
            hoverTint: "#ecfcf2"
        },
        {
            id: "vbs",
            name: "Vivid BAD SQUAD",
            shortName: "VBS",
            border: "#561938",
            A: "#ff5c9a",
            B: "#ff96c0",
            deep: "#43142c",
            hoverTint: "#ffeff6"
        },
        {
            id: "wxs",
            name: "Wonderlands×Showtime",
            shortName: "WxS",
            border: "#6a3c11",
            A: "#ffa51f",
            B: "#ffd54a",
            deep: "#4b2a0c",
            hoverTint: "#fff9e4"
        },
        {
            id: "nightcord",
            name: "Nightcord at 25:00",
            shortName: "25ji",
            border: "#43285f",
            A: "#c08cf2",
            B: "#e2b5ff",
            deep: "#2b1a3d",
            hoverTint: "#fbf4ff"
        },
        {
            id: "mono",
            name: "Monochrome",
            shortName: "MONO",
            border: "#444444",
            A: "#f4f4f4",
            B: "#bdbdbd",
            deep: "#1a1a1a",
            hoverTint: "#e9e9e9"
        }
    ]

    property string bandId: ConfigStore.stringValue("theme.band", "vs")
    readonly property var currentBand: {
        for (let i = 0; i < bands.length; ++i) {
            if (bands[i].id === bandId)
                return bands[i]
        }
        return bands[0]
    }

    readonly property color accentA: currentBand.A
    readonly property color accentB: currentBand.B
    readonly property color bandBorder: currentBand.border
    readonly property color bandDeep: currentBand.deep
    readonly property color hoverTint: currentBand.hoverTint
    readonly property color darkInk: "#1A1B2E"
    readonly property string bandName: currentBand.name
    readonly property string bandShort: currentBand.shortName

    function setBand(id) {
        bandId = id
        ConfigStore.set("theme.band", id)
    }

    // Shell / UI toggles
    property bool screenRoundEnabled: ConfigStore.boolValue("ui.screenRound", true)
    property bool dockAutoHide: ConfigStore.boolValue("dock.autoHide", true)

    function setScreenRound(v) {
        screenRoundEnabled = !!v
        ConfigStore.set("ui.screenRound", screenRoundEnabled)
    }

    function setDockAutoHide(v) {
        dockAutoHide = !!v
        ConfigStore.set("dock.autoHide", dockAutoHide)
    }

    // Modal & tool windows
    property bool settingsOpen: false
    property double settingsClosedAt: 0
    property bool spotlightOpen: false
    property double spotlightClosedAt: 0
    property bool clipboardOpen: false
    property double clipboardClosedAt: 0
    property bool dropShelfOpen: false
    property double dropShelfClosedAt: 0

    function closeAllTools() {
        settingsOpen = false
        spotlightOpen = false
        clipboardOpen = false
        dropShelfOpen = false
    }

    // Desktop widgets visibility (persisted)
    property bool wClockVisible: ConfigStore.boolValue("widgets.clock.visible", false)
    property bool wWeatherVisible: ConfigStore.boolValue("widgets.weather.visible", false)
    property bool wTodoVisible: ConfigStore.boolValue("widgets.todo.visible", false)
    property bool wNotesVisible: ConfigStore.boolValue("widgets.notes.visible", false)
    property bool wLyricsVisible: ConfigStore.boolValue("widgets.lyrics.visible", false)
    property bool wProfileVisible: ConfigStore.boolValue("widgets.profile.visible", false)

    // Desktop widgets coordinates
    property int wClockX: ConfigStore.intValue("widgets.clock.x", 28)
    property int wClockY: ConfigStore.intValue("widgets.clock.y", 48)
    property int wWeatherX: ConfigStore.intValue("widgets.weather.x", 28)
    property int wWeatherY: ConfigStore.intValue("widgets.weather.y", 184)
    property int wProfileX: ConfigStore.intValue("widgets.profile.x", 28)
    property int wProfileY: ConfigStore.intValue("widgets.profile.y", 352)
    property int wTodoX: ConfigStore.intValue("widgets.todo.x", Math.max(320, screenW - 295))
    property int wTodoY: ConfigStore.intValue("widgets.todo.y", 48)
    property int wNotesX: ConfigStore.intValue("widgets.notes.x", Math.max(320, screenW - 295))
    property int wNotesY: ConfigStore.intValue("widgets.notes.y", 332)
    property int wLyricsX: ConfigStore.intValue("widgets.lyrics.x", Math.max(320, screenW - 340))
    property int wLyricsY: ConfigStore.intValue("widgets.lyrics.y", 568)

    function setWidgetVisible(key, vis) {
        const v = !!vis
        ConfigStore.set("widgets." + key + ".visible", v)
        if (key === "clock") wClockVisible = v
        else if (key === "weather") wWeatherVisible = v
        else if (key === "todo") wTodoVisible = v
        else if (key === "notes") wNotesVisible = v
        else if (key === "lyrics") wLyricsVisible = v
        else if (key === "profile") wProfileVisible = v
    }

    function saveWidgetPos(key, nx, ny) {
        const cx = Math.max(0, Math.round(nx))
        const cy = Math.max(28, Math.round(ny))
        ConfigStore.set("widgets." + key + ".x", cx)
        ConfigStore.set("widgets." + key + ".y", cy)
        if (key === "clock") { wClockX = cx; wClockY = cy }
        else if (key === "weather") { wWeatherX = cx; wWeatherY = cy }
        else if (key === "todo") { wTodoX = cx; wTodoY = cy }
        else if (key === "notes") { wNotesX = cx; wNotesY = cy }
        else if (key === "lyrics") { wLyricsX = cx; wLyricsY = cy }
        else if (key === "profile") { wProfileX = cx; wProfileY = cy }
    }

    function resetWidgetPositions() {
        saveWidgetPos("clock", 28, 48)
        saveWidgetPos("weather", 28, 184)
        saveWidgetPos("profile", 28, 352)
        saveWidgetPos("todo", Math.max(320, screenW - 295), 48)
        saveWidgetPos("notes", Math.max(320, screenW - 295), 332)
        saveWidgetPos("lyrics", Math.max(320, screenW - 340), 568)
    }

    // Todo data
    property var todoItems: {
        const raw = ConfigStore.get("widgets.todo.items", null)
        if (Array.isArray(raw))
            return raw
        return [
            { text: "Check SekaiDesk Band Themes", done: false },
            { text: "Try Alt+Space Spotlight", done: false }
        ]
    }

    function saveTodoItems(arr) {
        todoItems = arr
        ConfigStore.set("widgets.todo.items", arr)
    }

    function addTodo(text) {
        const clean = (text || "").trim()
        if (clean === "")
            return
        const next = todoItems.slice()
        next.unshift({ text: clean, done: false })
        saveTodoItems(next)
    }

    function toggleTodo(idx) {
        if (idx < 0 || idx >= todoItems.length)
            return
        const next = todoItems.slice()
        next[idx] = { text: next[idx].text, done: !next[idx].done }
        saveTodoItems(next)
    }

    function removeTodo(idx) {
        if (idx < 0 || idx >= todoItems.length)
            return
        const next = todoItems.slice()
        next.splice(idx, 1)
        saveTodoItems(next)
    }

    // Notes & Profile persisted text
    property string noteText: ConfigStore.stringValue("widgets.notes.text", "Quick note...\n• Alt+Space: Spotlight\n• Ctrl+Alt+V: Clipboard")
    function saveNoteText(t) {
        noteText = t
        ConfigStore.set("widgets.notes.text", t)
    }

    property string profileName: ConfigStore.stringValue("widgets.profile.name", "Yozora")
    property string profileStatus: ConfigStore.stringValue("widgets.profile.status", "Wonderhoy Desktop Shell")
    function saveProfile(name, status) {
        profileName = name.trim() !== "" ? name.trim() : "Yozora"
        profileStatus = status.trim() !== "" ? status.trim() : "SekaiDesk"
        ConfigStore.set("widgets.profile.name", profileName)
        ConfigStore.set("widgets.profile.status", profileStatus)
    }
}
