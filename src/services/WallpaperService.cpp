#include "WallpaperService.h"
#include "core/SettingsStore.h"

#include <QColor>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QUrl>
#include <QWindow>

#include <algorithm>
#include <cmath>
#include <vector>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <objbase.h>
#include <shobjidl.h>
#endif

namespace {
QString normalizeLocalPath(const QString& raw)
{
    QString s = raw.trimmed();
    if (s.startsWith(QStringLiteral("file://"), Qt::CaseInsensitive)) {
        const QUrl u(s);
        if (u.isLocalFile())
            s = u.toLocalFile();
    }
    return QDir::cleanPath(QDir::fromNativeSeparators(s));
}

QString formatFileSize(qint64 bytes)
{
    if (bytes < 1024)
        return QStringLiteral("%1 B").arg(bytes);
    if (bytes < 1024 * 1024)
        return QStringLiteral("%1 KB").arg(qMax<qint64>(1, bytes / 1024));
    return QStringLiteral("%1 MB").arg(QString::number(static_cast<double>(bytes) / (1024.0 * 1024.0), 'f', 1));
}

QString sanitizeSortBy(const QString& raw)
{
    const QString s = raw.trimmed().toLower();
    if (s == QStringLiteral("name") || s == QStringLiteral("oldest"))
        return s;
    return QStringLiteral("newest");
}

QString sanitizeTransitionStyle(const QString& raw)
{
    const QString s = raw.trimmed();
    if (s == QStringLiteral("sekaiRing")
        || s == QStringLiteral("star")
        || s == QStringLiteral("diagonalBlocks")
        || s == QStringLiteral("sekaiIris")
        || s == QStringLiteral("sekaiFlash")
        || s == QStringLiteral("fade")
        || s == QStringLiteral("random")
        || s == QStringLiteral("none")) {
        return s;
    }
    return QStringLiteral("sekaiRing");
}

#ifdef Q_OS_WIN
const CLSID kClsidFileOpenDialog = {
    0xDC1C5A9C, 0xE88A, 0x4DDE, {0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7}
};
const IID kIidIFileOpenDialog = {
    0xD57C7288, 0xD4AD, 0x4768, {0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60}
};
const IID kIidIShellItem = {
    0x43826D1E, 0xE718, 0x42EE, {0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE}
};

HWND resolveOwnerHwnd()
{
    if (QWindow* fw = QGuiApplication::focusWindow()) {
        HWND h = reinterpret_cast<HWND>(fw->winId());
        if (h && IsWindow(h))
            return h;
    }
    const auto wins = QGuiApplication::topLevelWindows();
    for (QWindow* w : wins) {
        if (!w || !w->isVisible())
            continue;
        HWND h = reinterpret_cast<HWND>(w->winId());
        if (h && IsWindow(h) && (GetWindowLongPtrW(h, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0)
            return h;
    }
    for (QWindow* w : wins) {
        if (!w || !w->isVisible())
            continue;
        HWND h = reinterpret_cast<HWND>(w->winId());
        if (h && IsWindow(h))
            return h;
    }
    return nullptr;
}
#endif
} // namespace

WallpaperService::WallpaperService(SettingsStore* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    m_watchDebounce.setSingleShot(true);
    m_watchDebounce.setInterval(250);
    connect(&m_watchDebounce, &QTimer::timeout, this, &WallpaperService::refresh);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        m_watchDebounce.start();
    });

    connect(&m_slideshowTimer, &QTimer::timeout, this, &WallpaperService::nextRandomWallpaper);

    if (m_settings) {
        m_customFolder = m_settings->boolValue(QStringLiteral("wallpaper.customFolder"), false);
        const QString savedDir = normalizeLocalPath(m_settings->stringValue(QStringLiteral("wallpaper.directory")));
        m_sortBy = sanitizeSortBy(m_settings->stringValue(QStringLiteral("wallpaper.sortBy"), QStringLiteral("newest")));
        m_slideshowEnabled = m_settings->boolValue(QStringLiteral("wallpaper.slideshowEnabled"), false);
        m_slideshowMinutes = qBound(1, m_settings->intValue(QStringLiteral("wallpaper.slideshowMinutes"), 15), 1440);
        m_transitionStyle = sanitizeTransitionStyle(m_settings->stringValue(QStringLiteral("wallpaper.transitionStyle"), QStringLiteral("sekaiRing")));
        m_currentWallpaper = normalizeLocalPath(m_settings->stringValue(QStringLiteral("wallpaper.currentPath")));

        if (m_customFolder && !savedDir.isEmpty() && QFileInfo::exists(savedDir)) {
            updateDirectory(savedDir, true, false);
        } else {
            m_customFolder = false;
            updateDirectory(defaultPicturesFolder(), false, false);
        }
    } else {
        updateDirectory(defaultPicturesFolder(), false, false);
    }

    syncSystemWallpaper();
    m_sysWallTimer.setInterval(3000);
    connect(&m_sysWallTimer, &QTimer::timeout, this, &WallpaperService::syncSystemWallpaper);
    m_sysWallTimer.start();

    refresh();
    syncSlideshowTimer();
}

WallpaperService::~WallpaperService() = default;

QString WallpaperService::defaultPicturesFolder() const
{
    QString pics = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (pics.isEmpty())
        pics = QDir::homePath() + QStringLiteral("/Pictures");
    pics = normalizeLocalPath(pics);
    const QString wpSub = QDir(pics).absoluteFilePath(QStringLiteral("Wallpapers"));
    if (QFileInfo::exists(wpSub) && QFileInfo(wpSub).isDir())
        return normalizeLocalPath(wpSub);
    return pics;
}

void WallpaperService::updateDirectory(const QString& dirPath, bool isCustom, bool persist)
{
    const QString clean = normalizeLocalPath(dirPath);
    const bool changed = (m_directory != clean) || (m_customFolder != isCustom);
    m_directory = clean;
    m_customFolder = isCustom;
    updateDirectoryShort();
    syncWatcher();

    if (persist && m_settings) {
        m_settings->set(QStringLiteral("wallpaper.directory"), m_directory);
        m_settings->set(QStringLiteral("wallpaper.customFolder"), m_customFolder);
    }
    if (changed)
        emit directoryChanged();
}

void WallpaperService::updateDirectoryShort()
{
    if (m_directory.isEmpty()) {
        m_directoryShort = QStringLiteral("Wallpapers");
        return;
    }
    const QFileInfo fi(m_directory);
    QString name = fi.fileName();
    if (name.isEmpty())
        name = m_directory;
    m_directoryShort = name;
}

void WallpaperService::syncWatcher()
{
    const QStringList existing = m_watcher.directories();
    if (!existing.isEmpty())
        m_watcher.removePaths(existing);
    if (!m_directory.isEmpty() && QFileInfo::exists(m_directory))
        m_watcher.addPath(m_directory);
}

void WallpaperService::syncSlideshowTimer()
{
    if (m_slideshowEnabled) {
        m_slideshowTimer.setInterval(qBound(1, m_slideshowMinutes, 1440) * 60000);
        if (!m_slideshowTimer.isActive())
            m_slideshowTimer.start();
    } else {
        m_slideshowTimer.stop();
    }
}

void WallpaperService::querySystemWallpaperState(QString& outPath, qint64& outMtime) const
{
    outPath.clear();
    outMtime = 0;
#ifdef Q_OS_WIN
    wchar_t buf[MAX_PATH * 2]{};
    if (SystemParametersInfoW(SPI_GETDESKWALLPAPER, MAX_PATH * 2, buf, 0)) {
        const QString sysPath = normalizeLocalPath(QString::fromWCharArray(buf));
        if (!sysPath.isEmpty() && QFileInfo::exists(sysPath)) {
            outPath = sysPath;
            outMtime = QFileInfo(sysPath).lastModified().toMSecsSinceEpoch();
        }
    }
#endif
}

QString WallpaperService::syncSystemWallpaper()
{
    QString sysPath;
    qint64 sysMtime = 0;
    querySystemWallpaperState(sysPath, sysMtime);
    if (sysPath.isEmpty())
        return m_currentWallpaper;

    const bool sysStateChanged = (sysPath != m_lastSysWallPath) || (sysMtime != m_lastSysWallMtime);
    if (!sysStateChanged && !m_currentWallpaper.isEmpty() && QFileInfo::exists(m_currentWallpaper))
        return m_currentWallpaper;

    m_lastSysWallPath = sysPath;
    m_lastSysWallMtime = sysMtime;

    const bool pathChanged = (m_currentWallpaper != sysPath);
    m_currentWallpaper = sysPath;
    if (m_settings)
        m_settings->set(QStringLiteral("wallpaper.currentPath"), m_currentWallpaper);
    if (pathChanged || sysStateChanged)
        emit currentWallpaperChanged();
    return m_currentWallpaper;
}

QVariantMap WallpaperService::extractCurrentPalette()
{
    syncSystemWallpaper();
    return extractPalette(m_currentWallpaper);
}

void WallpaperService::setSortBy(const QString& sortBy)
{
    const QString next = sanitizeSortBy(sortBy);
    if (m_sortBy == next)
        return;
    m_sortBy = next;
    if (m_settings)
        m_settings->set(QStringLiteral("wallpaper.sortBy"), m_sortBy);
    emit sortByChanged();
    refresh();
}

void WallpaperService::setSlideshowEnabled(bool enabled)
{
    if (m_slideshowEnabled == enabled)
        return;
    m_slideshowEnabled = enabled;
    if (m_settings)
        m_settings->set(QStringLiteral("wallpaper.slideshowEnabled"), m_slideshowEnabled);
    syncSlideshowTimer();
    emit slideshowChanged();
}

void WallpaperService::setSlideshowMinutes(int minutes)
{
    const int clamped = qBound(1, minutes, 1440);
    if (m_slideshowMinutes == clamped)
        return;
    m_slideshowMinutes = clamped;
    if (m_settings)
        m_settings->set(QStringLiteral("wallpaper.slideshowMinutes"), m_slideshowMinutes);
    syncSlideshowTimer();
    emit slideshowChanged();
}

void WallpaperService::setTransitionStyle(const QString& style)
{
    const QString next = sanitizeTransitionStyle(style);
    if (m_transitionStyle == next)
        return;
    m_transitionStyle = next;
    if (m_settings)
        m_settings->set(QStringLiteral("wallpaper.transitionStyle"), m_transitionStyle);
    emit transitionStyleChanged();
}

QString WallpaperService::toFileUrl(const QString& filePath) const
{
    const QString clean = normalizeLocalPath(filePath);
    if (clean.isEmpty())
        return {};
    return QUrl::fromLocalFile(clean).toString();
}

void WallpaperService::requestWallpaperChange(const QString& filePath)
{
    const QString clean = normalizeLocalPath(filePath);
    if (clean.isEmpty() || !QFileInfo::exists(clean))
        return;
    if (clean.compare(m_currentWallpaper, Qt::CaseInsensitive) == 0)
        return;

    if (m_transitionStyle == QStringLiteral("none")
        || m_currentWallpaper.isEmpty()
        || !QFileInfo::exists(m_currentWallpaper)) {
        applyWallpaper(clean);
        return;
    }

    QString chosen = m_transitionStyle;
    if (chosen == QStringLiteral("random")) {
        static const QStringList kPool = {
            QStringLiteral("sekaiRing"),
            QStringLiteral("star"),
            QStringLiteral("diagonalBlocks"),
            QStringLiteral("sekaiIris"),
            QStringLiteral("sekaiFlash")
        };
        QStringList filtered;
        for (const QString& s : kPool) {
            if (s != m_lastRolledStyle)
                filtered.append(s);
        }
        const QStringList& src = filtered.isEmpty() ? kPool : filtered;
        chosen = src.at(static_cast<int>(QRandomGenerator::global()->bounded(static_cast<quint32>(src.size()))));
        m_lastRolledStyle = chosen;
    }

    emit transitionRequested(m_currentWallpaper, clean, chosen);
}

void WallpaperService::refresh()
{
    QVariantList nextList;
    if (!m_directory.isEmpty() && QFileInfo::exists(m_directory)) {
        const QDir dir(m_directory);
        const QStringList filters = {
            QStringLiteral("*.png"),
            QStringLiteral("*.jpg"),
            QStringLiteral("*.jpeg"),
            QStringLiteral("*.webp"),
            QStringLiteral("*.bmp")
        };
        QFileInfoList entries = dir.entryInfoList(filters, QDir::Files | QDir::Readable, QDir::NoSort);

        std::sort(entries.begin(), entries.end(), [this](const QFileInfo& a, const QFileInfo& b) {
            if (m_sortBy == QStringLiteral("name"))
                return a.fileName().compare(b.fileName(), Qt::CaseInsensitive) < 0;
            const qint64 ta = a.lastModified().toMSecsSinceEpoch();
            const qint64 tb = b.lastModified().toMSecsSinceEpoch();
            if (m_sortBy == QStringLiteral("oldest")) {
                if (ta != tb)
                    return ta < tb;
                return a.fileName().compare(b.fileName(), Qt::CaseInsensitive) < 0;
            }
            if (ta != tb)
                return ta > tb;
            return a.fileName().compare(b.fileName(), Qt::CaseInsensitive) < 0;
        });

        nextList.reserve(entries.size());
        for (const QFileInfo& fi : entries) {
            const QString cleanPath = normalizeLocalPath(fi.absoluteFilePath());
            QVariantMap item;
            item.insert(QStringLiteral("path"), cleanPath);
            item.insert(QStringLiteral("fileUrl"), QUrl::fromLocalFile(cleanPath).toString());
            item.insert(QStringLiteral("name"), fi.completeBaseName());
            item.insert(QStringLiteral("modifiedMs"), fi.lastModified().toMSecsSinceEpoch());
            item.insert(QStringLiteral("sizeText"), formatFileSize(fi.size()));
            nextList.append(item);
        }
    }

    if (m_wallpapers != nextList) {
        m_wallpapers = std::move(nextList);
        emit wallpapersChanged();
    }
}

bool WallpaperService::applyWallpaper(const QString& filePath)
{
    const QString clean = normalizeLocalPath(filePath);
    if (clean.isEmpty() || !QFileInfo::exists(clean))
        return false;

#ifdef Q_OS_WIN
    const QString nativePath = QDir::toNativeSeparators(clean);
    std::wstring wpath = nativePath.toStdWString();
    const BOOL ok = SystemParametersInfoW(
        SPI_SETDESKWALLPAPER,
        0,
        wpath.data(),
        SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    if (!ok)
        return false;
    querySystemWallpaperState(m_lastSysWallPath, m_lastSysWallMtime);
#endif

    if (m_currentWallpaper != clean) {
        m_currentWallpaper = clean;
        emit currentWallpaperChanged();
    }
    if (m_settings)
        m_settings->set(QStringLiteral("wallpaper.currentPath"), clean);
    return true;
}

QVariantMap WallpaperService::extractPalette(const QString& filePath) const
{
    QVariantMap fallback;
    fallback.insert(QStringLiteral("accentA"), QStringLiteral("#33AAEE"));
    fallback.insert(QStringLiteral("accentB"), QStringLiteral("#FF66AA"));
    fallback.insert(QStringLiteral("border"), QStringLiteral("#1A1B2E"));
    fallback.insert(QStringLiteral("deep"), QStringLiteral("#1A1B2E"));
    fallback.insert(QStringLiteral("isDark"), true);

    const QString clean = normalizeLocalPath(filePath);
    if (clean.isEmpty() || !QFileInfo::exists(clean))
        return fallback;

    // Detect image format from file bytes so extensionless Windows TranscodedWallpaper decodes reliably.
    QImageReader reader(clean);
    reader.setDecideFormatFromContent(true);
    QImage img = reader.read();
    if (img.isNull())
        return fallback;

    img = img.scaled(48, 48, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
             .convertToFormat(QImage::Format_RGBA8888);

    struct Bucket {
        double sumR = 0.0;
        double sumG = 0.0;
        double sumB = 0.0;
        int count = 0;
        double score = 0.0;
    };

    QHash<int, Bucket> buckets;
    double lumaSum = 0.0;
    int pixelCount = 0;

    for (int y = 0; y < img.height(); ++y) {
        const uchar* row = img.constScanLine(y);
        for (int x = 0; x < img.width(); ++x) {
            const int r = row[x * 4 + 0];
            const int g = row[x * 4 + 1];
            const int b = row[x * 4 + 2];
            const int a = row[x * 4 + 3];
            if (a < 16)
                continue;

            const double luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            lumaSum += luma;
            ++pixelCount;

            const int key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
            Bucket& bk = buckets[key];
            bk.sumR += r;
            bk.sumG += g;
            bk.sumB += b;
            bk.count += 1;
        }
    }

    if (pixelCount == 0 || buckets.isEmpty())
        return fallback;

    const bool isDark = (lumaSum / static_cast<double>(pixelCount)) < 0.52;

    struct Candidate {
        QColor color;
        double score;
    };
    std::vector<Candidate> candidates;
    candidates.reserve(static_cast<size_t>(buckets.size()));

    for (auto it = buckets.begin(); it != buckets.end(); ++it) {
        const Bucket& bk = it.value();
        const int avgR = qBound(0, qRound(bk.sumR / bk.count), 255);
        const int avgG = qBound(0, qRound(bk.sumG / bk.count), 255);
        const int avgB = qBound(0, qRound(bk.sumB / bk.count), 255);
        const QColor c(avgR, avgG, avgB);

        float h = 0.0f, s = 0.0f, l = 0.0f;
        c.getHslF(&h, &s, &l);

        // Favor saturated, mid-luminance colors over washed-out whites or murky blacks.
        const double lumaPenalty = (l < 0.14 || l > 0.88) ? 0.22 : 1.0;
        const double satWeight = 0.25 + 2.2 * static_cast<double>(s);
        const double score = static_cast<double>(bk.count) * satWeight * lumaPenalty;
        candidates.push_back({ c, score });
    }

    std::sort(candidates.begin(), candidates.end(), [](const Candidate& a, const Candidate& b) {
        return a.score > b.score;
    });

    auto tuneAccent = [](QColor c) {
        float h = 0.0f, s = 0.0f, l = 0.0f;
        c.getHslF(&h, &s, &l);
        if (h < 0.0f)
            h = 0.58f;
        s = qBound(0.45f, s, 0.92f);
        l = qBound(0.44f, l, 0.66f);
        return QColor::fromHslF(h, s, l);
    };

    const QColor rawPrimary = candidates.front().color;
    const QColor accentA = tuneAccent(rawPrimary);

    QColor accentB;
    bool foundSecondary = false;
    for (size_t i = 1; i < candidates.size(); ++i) {
        const QColor& cand = candidates[i].color;
        const int dr = cand.red() - rawPrimary.red();
        const int dg = cand.green() - rawPrimary.green();
        const int db = cand.blue() - rawPrimary.blue();
        const double dist = std::sqrt(static_cast<double>(dr * dr + dg * dg + db * db));
        if (dist >= 68.0 && cand.hslSaturationF() >= 0.22f) {
            accentB = tuneAccent(cand);
            foundSecondary = true;
            break;
        }
    }
    if (!foundSecondary) {
        float h = 0.0f, s = 0.0f, l = 0.0f;
        accentA.getHslF(&h, &s, &l);
        const float h2 = std::fmod(h + 0.14f, 1.0f);
        accentB = QColor::fromHslF(h2, qBound(0.50f, s, 0.90f), qBound(0.48f, l + 0.06f, 0.68f));
    }

    float hA = 0.0f, sA = 0.0f, lA = 0.0f;
    accentA.getHslF(&hA, &sA, &lA);
    const QColor deep = QColor::fromHslF(hA < 0.0f ? 0.65f : hA, qMin(0.45f, sA), 0.13f);
    const QColor border(QStringLiteral("#1A1B2E"));

    QVariantMap out;
    out.insert(QStringLiteral("accentA"), accentA.name());
    out.insert(QStringLiteral("accentB"), accentB.name());
    out.insert(QStringLiteral("border"), border.name());
    out.insert(QStringLiteral("deep"), deep.name());
    out.insert(QStringLiteral("isDark"), isDark);
    return out;
}

void WallpaperService::pickFolder()
{
#ifdef Q_OS_WIN
    const HRESULT hrCom = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    IFileOpenDialog* pDialog = nullptr;
    if (SUCCEEDED(CoCreateInstance(kClsidFileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                   kIidIFileOpenDialog, reinterpret_cast<void**>(&pDialog))) && pDialog) {
        DWORD opts = 0;
        if (SUCCEEDED(pDialog->GetOptions(&opts))) {
            pDialog->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
        }
        pDialog->SetTitle(L"Select Wallpaper Folder");
        const HWND owner = resolveOwnerHwnd();
        if (SUCCEEDED(pDialog->Show(owner))) {
            IShellItem* pItem = nullptr;
            if (SUCCEEDED(pDialog->GetResult(&pItem)) && pItem) {
                LPWSTR pszPath = nullptr;
                if (SUCCEEDED(pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszPath)) && pszPath) {
                    const QString picked = QString::fromWCharArray(pszPath);
                    CoTaskMemFree(pszPath);
                    if (!picked.isEmpty()) {
                        updateDirectory(picked, true, true);
                        refresh();
                    }
                }
                pItem->Release();
            }
        }
        pDialog->Release();
    }
    if (SUCCEEDED(hrCom))
        CoUninitialize();
#endif
}

void WallpaperService::resetFolder()
{
    updateDirectory(defaultPicturesFolder(), false, true);
    refresh();
}

void WallpaperService::nextRandomWallpaper()
{
    if (m_wallpapers.isEmpty())
        return;
    if (m_wallpapers.size() == 1) {
        requestWallpaperChange(m_wallpapers.first().toMap().value(QStringLiteral("path")).toString());
        return;
    }

    std::vector<QString> candidates;
    candidates.reserve(static_cast<size_t>(m_wallpapers.size()));
    for (const QVariant& v : m_wallpapers) {
        const QString p = v.toMap().value(QStringLiteral("path")).toString();
        if (!p.isEmpty() && p.compare(m_currentWallpaper, Qt::CaseInsensitive) != 0)
            candidates.push_back(p);
    }
    if (candidates.empty())
        return;

    const quint32 idx = QRandomGenerator::global()->bounded(static_cast<quint32>(candidates.size()));
    requestWallpaperChange(candidates[idx]);
}
