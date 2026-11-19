.pragma library

// Bookshelf prop classifier and packing layout (ported from SekaiPop ShelfMath.js).

const IMAGE = /\.(png|jpe?g|gif|webp|bmp|svg)$/i
const VIDEO = /\.(mp4|m4v|mkv|webm|mov|avi|flv|wmv|mpe?g|ogv|3gp|ts|vob)$/i
const AUDIO = /\.(mp3|flac|wav|ogg|oga|opus|m4a|aac|wma|aiff?|mid|midi|ape)$/i
const ARCHIVE = /\.(zip|tar|gz|tgz|bz2|xz|zst|7z|rar|lz4|cab)$/i
const CODE = /\.(js|ts|jsx|tsx|py|rs|go|c|h|cpp|hpp|java|kt|qml|sh|ps1|bat|lua|rb|php|css|html|json|ya?ml|toml|nix)$/i
const PDF = /\.pdf$/i

const SPEC = {
    book:    { w: 36, hMax: 120, step: 8, buttons: "column", lean: 0 },
    folder:  { w: 46, hMax: 112, step: 6, buttons: "column", lean: 0 },
    video:   { w: 30, hMax: 112, step: 0, buttons: "column", lean: 0 },
    image:   { w: 64, hMax: 88,  step: 0, buttons: "row",    lean: 2 },
    audio:   { w: 62, hMax: 84,  step: 0, buttons: "row",    lean: 0 },
    archive: { w: 62, hMax: 78,  step: 0, buttons: "row",    lean: 0 },
    note:    { w: 56, hMax: 84,  step: 0, buttons: "row",    lean: 2 }
}

const PROP_TINTS = ["#60A5FA", "#F472B6", "#34D399", "#FBBF24", "#A78BFA"]

function pathToFileUrl(raw) {
    if (!raw)
        return ""
    let s = String(raw).trim()
    if (!s)
        return ""
    if (s.startsWith("file://") || s.startsWith("qrc:/") || s.startsWith("http://") || s.startsWith("https://"))
        return s
    s = s.replace(/\\/g, "/")
    if (s.startsWith("/"))
        s = s.slice(1)
    return "file:///" + encodeURI(s).replace(/#/g, "%23")
}

function seedOf(id) {
    let h = 7
    const t = String(id || "")
    for (let i = 0; i < t.length; i++)
        h = (h * 31 + t.charCodeAt(i)) % 1000003
    return h
}

function isImage(path) {
    return IMAGE.test(String(path || ""))
}

function kindOf(item) {
    if (!item)
        return "book"
    if (item.kind === "text")
        return "note"
    if (item.dir === true || item.isDir === true)
        return "folder"
    const p = String(item.value || item.path || "")
    if (IMAGE.test(p)) return "image"
    if (VIDEO.test(p)) return "video"
    if (AUDIO.test(p)) return "audio"
    if (ARCHIVE.test(p)) return "archive"
    return "book"
}

function iconSvgOf(item) {
    switch (kindOf(item)) {
    case "folder":  return "qrc:/qml/icons/folder-2-dark.svg"
    case "video":   return "qrc:/qml/icons/clapperboard-play-dark.svg"
    case "audio":   return "qrc:/qml/icons/music-note-dark.svg"
    case "archive": return "qrc:/qml/icons/archive-dark.svg"
    case "image":   return "qrc:/qml/icons/gallery-dark.svg"
    case "note":    return "qrc:/qml/icons/notes-dark.svg"
    }
    const p = String((item && (item.value || item.path)) || "")
    if (CODE.test(p))
        return "qrc:/qml/icons/code-file-dark.svg"
    return "qrc:/qml/icons/document-text-dark.svg"
}

function specOf(kind) {
    return SPEC[kind] || SPEC.book
}

function heightOf(kind, seed) {
    const s = specOf(kind)
    return s.step === 0 ? s.hMax : s.hMax - (seed % 4) * s.step
}

function restTilt(kind, seed) {
    return specOf(kind).lean * ((seed % 3) - 1)
}

function tintOf(seed) {
    return PROP_TINTS[Math.floor(seed / 4) % PROP_TINTS.length]
}

function pack(items, listW, gap) {
    const shelves = []
    if (!items || items.length === 0)
        return shelves
    let row = []
    let x = 0
    for (let idx = 0; idx < items.length; idx++) {
        const item = items[idx]
        const kind = kindOf(item)
        const idStr = item.id || item.value || item.path || String(idx)
        const seed = seedOf(idStr)
        const w = specOf(kind).w
        if (row.length > 0 && x + w > listW) {
            shelves.push(row)
            row = []
            x = 0
        }
        row.push({
            origIdx: idx,
            item: item,
            kind: kind,
            seed: seed,
            x: x,
            w: w,
            h: heightOf(kind, seed)
        })
        x += w + gap
    }
    if (row.length > 0)
        shelves.push(row)
    return shelves
}
