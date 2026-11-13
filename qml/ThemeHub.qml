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
    property bool wCalendarVisible: ConfigStore.boolValue("widgets.calendar.visible", false)

    // Clock widget style (0=KEYS, 1=TOWER, 2=STICKER, 3=STACK) and format
    readonly property var clockDesignNames: ["KEYS", "TOWER", "STICKER", "STACK"]
    property int clockStyle: {
        const raw = ConfigStore.get("widgets.clock.style", 3)
        if (typeof raw === "number")
            return Math.max(0, Math.min(3, Math.round(raw)))
        const s = String(raw || "").toLowerCase()
        if (s === "keys" || s === "0") return 0
        if (s === "tower" || s === "1") return 1
        if (s === "sticker" || s === "2") return 2
        return 3
    }
    property bool clockUse24h: ConfigStore.boolValue("widgets.clock.use24h", false)
    readonly property bool clock24h: clockUse24h

    function setClockStyle(st) {
        let idx = 3
        if (typeof st === "number") {
            idx = Math.max(0, Math.min(3, Math.round(st)))
        } else {
            const s = String(st || "").toLowerCase()
            if (s === "keys" || s === "0") idx = 0
            else if (s === "tower" || s === "1") idx = 1
            else if (s === "sticker" || s === "2") idx = 2
            else idx = 3
        }
        clockStyle = idx
        ConfigStore.set("widgets.clock.style", idx)
    }

    function cycleClockStyle() {
        setClockStyle((clockStyle + 1) % 4)
    }

    function setClockUse24h(v) {
        clockUse24h = !!v
        ConfigStore.set("widgets.clock.use24h", clockUse24h)
    }

    // Weather widget preferences
    property bool weatherMinimal: ConfigStore.boolValue("widgets.weather.minimal", false)
    property string weatherView: {
        const v = ConfigStore.stringValue("widgets.weather.view", "hourly")
        return v === "days" ? "days" : "hourly"
    }

    function setWeatherMinimal(v) {
        weatherMinimal = !!v
        ConfigStore.set("widgets.weather.minimal", weatherMinimal)
    }

    function setWeatherView(v) {
        weatherView = (v === "days") ? "days" : "hourly"
        ConfigStore.set("widgets.weather.view", weatherView)
    }

    // Todo widget compact toggle
    property bool todoSmall: ConfigStore.boolValue("widgets.todo.small", false)
    function setTodoSmall(v) {
        todoSmall = !!v
        ConfigStore.set("widgets.todo.small", todoSmall)
    }

    // Desktop widgets coordinates (clamped so nothing spawns trapped under TopBar)
    property int wClockX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.clock.x", Math.max(320, screenW - 350))))
    property int wClockY: Math.max(54, ConfigStore.intValue("widgets.clock.y", 64))
    property int wWeatherX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.weather.x", 28)))
    property int wWeatherY: Math.max(54, ConfigStore.intValue("widgets.weather.y", 346))
    property int wProfileX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.profile.x", 28)))
    property int wProfileY: Math.max(54, ConfigStore.intValue("widgets.profile.y", 56))
    property int wTodoX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.todo.x", Math.max(320, screenW - 350))))
    property int wTodoY: Math.max(54, ConfigStore.intValue("widgets.todo.y", 356))
    property int wNotesX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.notes.x", Math.max(320, screenW - 350))))
    property int wNotesY: Math.max(54, ConfigStore.intValue("widgets.notes.y", 644))
    property int wLyricsX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.lyrics.x", Math.max(240, Math.round((screenW - 600) * 0.5)))))
    property int wLyricsY: Math.max(54, ConfigStore.intValue("widgets.lyrics.y", Math.max(400, screenH - 250)))
    property int wCalendarX: Math.max(12, Math.min(screenW - 140, ConfigStore.intValue("widgets.calendar.x", 364)))
    property int wCalendarY: Math.max(54, ConfigStore.intValue("widgets.calendar.y", 56))

    function setWidgetVisible(key, vis) {
        const v = !!vis
        ConfigStore.set("widgets." + key + ".visible", v)
        if (key === "clock") wClockVisible = v
        else if (key === "weather") wWeatherVisible = v
        else if (key === "todo") wTodoVisible = v
        else if (key === "notes") wNotesVisible = v
        else if (key === "lyrics") wLyricsVisible = v
        else if (key === "profile") wProfileVisible = v
        else if (key === "calendar") wCalendarVisible = v
    }

    function saveWidgetPos(key, nx, ny) {
        const cx = Math.max(8, Math.min(screenW - 100, Math.round(nx)))
        const cy = Math.max(52, Math.min(screenH - 80, Math.round(ny)))
        ConfigStore.set("widgets." + key + ".x", cx)
        ConfigStore.set("widgets." + key + ".y", cy)
        if (key === "clock") { wClockX = cx; wClockY = cy }
        else if (key === "weather") { wWeatherX = cx; wWeatherY = cy }
        else if (key === "todo") { wTodoX = cx; wTodoY = cy }
        else if (key === "notes") { wNotesX = cx; wNotesY = cy }
        else if (key === "lyrics") { wLyricsX = cx; wLyricsY = cy }
        else if (key === "profile") { wProfileX = cx; wProfileY = cy }
        else if (key === "calendar") { wCalendarX = cx; wCalendarY = cy }
    }

    function resetWidgetPositions() {
        saveWidgetPos("profile", 28, 56)
        saveWidgetPos("weather", 28, 346)
        saveWidgetPos("calendar", 364, 56)
        saveWidgetPos("clock", Math.max(320, screenW - 350), 64)
        saveWidgetPos("todo", Math.max(320, screenW - 350), 356)
        saveWidgetPos("notes", Math.max(320, screenW - 350), 644)
        saveWidgetPos("lyrics", Math.max(240, Math.round((screenW - 600) * 0.5)), Math.max(400, screenH - 250))
    }

    Component.onDestruction: ConfigStore.flush()

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

    function renameTodo(idx, newText) {
        const clean = (newText || "").trim()
        if (idx < 0 || idx >= todoItems.length || clean === "")
            return
        const next = todoItems.slice()
        next[idx] = { text: clean, done: !!next[idx].done }
        saveTodoItems(next)
    }

    function removeTodo(idx) {
        if (idx < 0 || idx >= todoItems.length)
            return
        const next = todoItems.slice()
        next.splice(idx, 1)
        saveTodoItems(next)
    }

    function clearDoneTodos() {
        const next = todoItems.filter(it => !it.done)
        saveTodoItems(next)
    }

    // Notes persisted text & SekaiPop paper tint
    property string noteText: ConfigStore.stringValue("widgets.notes.text", "Quick note...\n• Alt+Space: Spotlight\n• Ctrl+Alt+V: Clipboard")
    property string noteTint: ConfigStore.stringValue("widgets.notes.tint", "butter")
    function saveNoteText(t) {
        noteText = t
        ConfigStore.set("widgets.notes.text", t)
    }
    function setNoteTint(t) {
        noteTint = t || "butter"
        ConfigStore.set("widgets.notes.tint", noteTint)
    }

    // Profile persisted text & customizable images
    property string profileName: ConfigStore.stringValue("widgets.profile.name", "Yozora")
    property string profileStatus: ConfigStore.stringValue("widgets.profile.status", "Wonderhoy Desktop Shell")
    property string profileAvatarUrl: ConfigStore.stringValue("widgets.profile.avatar", "")
    property string profileBannerUrl: ConfigStore.stringValue("widgets.profile.banner", "")

    function saveProfile(name, status) {
        profileName = name.trim() !== "" ? name.trim() : "Yozora"
        profileStatus = status.trim() !== "" ? status.trim() : "SekaiDesk"
        ConfigStore.set("widgets.profile.name", profileName)
        ConfigStore.set("widgets.profile.status", profileStatus)
    }

    function setProfileAvatar(url) {
        profileAvatarUrl = String(url || "")
        ConfigStore.set("widgets.profile.avatar", profileAvatarUrl)
    }

    function setProfileBanner(url) {
        profileBannerUrl = String(url || "")
        ConfigStore.set("widgets.profile.banner", profileBannerUrl)
    }

    // Calendar Events & Deadlines persisted in ConfigStore
    property var calendarEvents: {
        const raw = ConfigStore.get("widgets.calendar.events", null)
        if (Array.isArray(raw))
            return raw
        const rawJson = ConfigStore.stringValue("widgets.calendar.eventsJson", "")
        if (rawJson !== "") {
            try {
                const parsed = JSON.parse(rawJson)
                if (Array.isArray(parsed))
                    return parsed
            } catch (e) {}
        }
        return []
    }

    function saveCalendarEvents(arr) {
        const clean = Array.isArray(arr) ? arr : []
        calendarEvents = clean
        ConfigStore.set("widgets.calendar.events", clean)
        ConfigStore.set("widgets.calendar.eventsJson", JSON.stringify(clean))
    }

    function nextCalendarEventId(list) {
        const used = {}
        for (let i = 0; i < list.length; ++i)
            used[list[i].id] = true
        let n = list.length + 1
        while (used["e" + n])
            n++
        return "e" + n
    }

    function upsertCalendarEvent(ev) {
        if (!ev || !ev.title || !ev.date)
            return
        const next = calendarEvents.slice()
        const entry = {
            id: ev.id && ev.id !== "" ? ev.id : nextCalendarEventId(next),
            title: String(ev.title).trim().slice(0, 80),
            date: String(ev.date),
            time: String(ev.time || ""),
            note: String(ev.note || "").trim().slice(0, 240),
            color: Math.max(0, Math.min(4, parseInt(ev.color, 10) || 0)),
            kind: ev.kind === "deadline" ? "deadline" : "event",
            done: ev.kind === "deadline" && ev.done === true
        }
        let replaced = false
        for (let i = 0; i < next.length; ++i) {
            if (next[i].id === entry.id) {
                next[i] = entry
                replaced = true
                break
            }
        }
        if (!replaced)
            next.push(entry)
        saveCalendarEvents(next)
    }

    function toggleCalendarDone(id) {
        const next = calendarEvents.slice()
        for (let i = 0; i < next.length; ++i) {
            if (next[i].id === id) {
                const cur = next[i]
                next[i] = {
                    id: cur.id, title: cur.title, date: cur.date, time: cur.time,
                    note: cur.note, color: cur.color, kind: cur.kind, done: !cur.done
                }
                saveCalendarEvents(next)
                return
            }
        }
    }

    function deleteCalendarEvent(id) {
        saveCalendarEvents(calendarEvents.filter(e => e.id !== id))
    }
}
