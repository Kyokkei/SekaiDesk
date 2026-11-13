#include "AppLauncher.h"
#include "core/SettingsStore.h"

#include <QDirIterator>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QVariantMap>
#include <algorithm>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>
#endif

AppLauncher::AppLauncher(SettingsStore* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    reload();
    refreshInstalledApps();
}

void AppLauncher::reload()
{
    m_pinnedApps.clear();
    bool hasKey = false;
    if (m_settings) {
        hasKey = m_settings->has(QStringLiteral("dock.pinnedApps"));
        const QVariant raw = m_settings->get(QStringLiteral("dock.pinnedApps"));
        if (raw.canConvert<QVariantList>()) {
            for (const QVariant& v : raw.toList()) {
                if (v.toMap().value(QStringLiteral("kind")).toString() != QStringLiteral("separator"))
                    m_pinnedApps << v;
            }
        }
        m_usageCounts = m_settings->get(QStringLiteral("launcher.usage")).toMap();
    }
    if (!hasKey)
        seedDefaultsIfEmpty();
    emit pinnedAppsChanged();
}

void AppLauncher::seedDefaultsIfEmpty()
{
    if (!m_pinnedApps.isEmpty())
        return;

    auto makeEntry = [](const QString& name, const QString& target,
                        const QString& args = {}) {
        QVariantMap m;
        m.insert(QStringLiteral("name"), name);
        m.insert(QStringLiteral("target"), target);
        if (!args.isEmpty())
            m.insert(QStringLiteral("args"), args);
        return QVariant(m);
    };

    m_pinnedApps << makeEntry(QStringLiteral("Files"),
                              QStringLiteral("C:\\Windows\\explorer.exe"));

#ifdef Q_OS_WIN
    wchar_t wtPath[MAX_PATH] = {};
    if (SearchPathW(nullptr, L"wt.exe", nullptr, MAX_PATH, wtPath, nullptr) > 0) {
        m_pinnedApps << makeEntry(QStringLiteral("Terminal"),
                                  QString::fromWCharArray(wtPath));
    } else {
        m_pinnedApps << makeEntry(QStringLiteral("Terminal"),
                                  QStringLiteral("C:\\Windows\\System32\\cmd.exe"));
    }

    const QString edge32 = QStringLiteral("C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe");
    const QString edge64 = QStringLiteral("C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe");
    if (QFileInfo::exists(edge64))
        m_pinnedApps << makeEntry(QStringLiteral("Edge"), edge64);
    else if (QFileInfo::exists(edge32))
        m_pinnedApps << makeEntry(QStringLiteral("Edge"), edge32);
#else
    m_pinnedApps << makeEntry(QStringLiteral("Terminal"),
                              QStringLiteral("cmd.exe"));
#endif

    m_pinnedApps << makeEntry(QStringLiteral("Notepad"),
                              QStringLiteral("C:\\Windows\\System32\\notepad.exe"));
    m_pinnedApps << makeEntry(QStringLiteral("Calculator"),
                              QStringLiteral("C:\\Windows\\System32\\calc.exe"));
    m_pinnedApps << makeEntry(QStringLiteral("Settings"),
                              QStringLiteral("ms-settings:"));

    savePinnedApps();
}

void AppLauncher::savePinnedApps()
{
    if (m_settings)
        m_settings->set(QStringLiteral("dock.pinnedApps"), m_pinnedApps);
}

void AppLauncher::recordUsage(const QString& target)
{
    const QString key = target.trimmed().toLower();
    if (key.isEmpty())
        return;
    m_usageCounts.insert(key, m_usageCounts.value(key, 0).toInt() + 1);
    if (m_settings)
        m_settings->set(QStringLiteral("launcher.usage"), m_usageCounts);
}

bool AppLauncher::launch(const QString& target, const QString& args)
{
    if (target.trimmed().isEmpty())
        return false;

#ifdef Q_OS_WIN
    const HINSTANCE res = ShellExecuteW(
        nullptr,
        L"open",
        reinterpret_cast<const wchar_t*>(target.utf16()),
        args.isEmpty() ? nullptr : reinterpret_cast<const wchar_t*>(args.utf16()),
        nullptr,
        SW_SHOWNORMAL);

    const auto code = reinterpret_cast<INT_PTR>(res);
    if (code <= 32) {
        qWarning("AppLauncher: ShellExecuteW(%s) failed with code %lld",
                 qPrintable(target), static_cast<long long>(code));
        return false;
    }
    recordUsage(target);
    return true;
#else
    Q_UNUSED(args);
    return false;
#endif
}

bool AppLauncher::runElevated(const QString& target, const QString& args)
{
#ifdef Q_OS_WIN
    if (target.trimmed().isEmpty())
        return false;
    const HINSTANCE res = ShellExecuteW(
        nullptr,
        L"runas",
        reinterpret_cast<const wchar_t*>(target.utf16()),
        args.isEmpty() ? nullptr : reinterpret_cast<const wchar_t*>(args.utf16()),
        nullptr,
        SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(res) > 32;
#else
    Q_UNUSED(target);
    Q_UNUSED(args);
    return false;
#endif
}

bool AppLauncher::revealInExplorer(const QString& target)
{
#ifdef Q_OS_WIN
    const QString clean = QDir::toNativeSeparators(target.trimmed());
    if (clean.isEmpty() || !QFileInfo::exists(clean))
        return false;
    const QString arg = QStringLiteral("/select,\"%1\"").arg(clean);
    ShellExecuteW(nullptr, L"open", L"explorer.exe",
                  reinterpret_cast<const wchar_t*>(arg.utf16()),
                  nullptr, SW_SHOWNORMAL);
    return true;
#else
    Q_UNUSED(target);
    return false;
#endif
}

void AppLauncher::addPinnedApp(const QString& name, const QString& target,
                               const QString& args)
{
    const QString norm = target.trimmed().toLower();
    for (const QVariant& v : m_pinnedApps) {
        if (v.toMap().value(QStringLiteral("target")).toString().trimmed().toLower() == norm)
            return;
    }
    QVariantMap m;
    m.insert(QStringLiteral("name"), name);
    m.insert(QStringLiteral("target"), target);
    if (!args.isEmpty())
        m.insert(QStringLiteral("args"), args);
    m_pinnedApps << m;
    savePinnedApps();
    emit pinnedAppsChanged();
}

void AppLauncher::removePinnedApp(int index)
{
    if (index < 0 || index >= m_pinnedApps.size())
        return;
    m_pinnedApps.removeAt(index);
    savePinnedApps();
    emit pinnedAppsChanged();
}

void AppLauncher::removePinnedByTarget(const QString& target)
{
    const QString norm = target.trimmed().toLower();
    for (int i = m_pinnedApps.size() - 1; i >= 0; --i) {
        const QString t = m_pinnedApps.at(i).toMap().value(QStringLiteral("target")).toString().trimmed().toLower();
        if (t == norm) {
            m_pinnedApps.removeAt(i);
            savePinnedApps();
            emit pinnedAppsChanged();
            return;
        }
    }
}

void AppLauncher::movePinnedApp(int fromIndex, int toIndex)
{
    const int n = m_pinnedApps.size();
    if (fromIndex < 0 || fromIndex >= n || toIndex < 0 || toIndex >= n || fromIndex == toIndex)
        return;
    m_pinnedApps.move(fromIndex, toIndex);
    savePinnedApps();
    emit pinnedAppsChanged();
}

void AppLauncher::insertSeparatorAt(int index)
{
    const int clamped = qBound(0, index, m_pinnedApps.size());
    QVariantMap sep;
    sep.insert(QStringLiteral("kind"), QStringLiteral("separator"));
    m_pinnedApps.insert(clamped, sep);
    savePinnedApps();
    emit pinnedAppsChanged();
}

void AppLauncher::pinAppAt(const QString& name, const QString& target,
                           const QString& args, int index)
{
    const QString norm = target.trimmed().toLower();
    for (int i = 0; i < m_pinnedApps.size(); ++i) {
        if (m_pinnedApps.at(i).toMap().value(QStringLiteral("target")).toString().trimmed().toLower() == norm) {
            movePinnedApp(i, qBound(0, index, m_pinnedApps.size() - 1));
            return;
        }
    }
    QVariantMap m;
    m.insert(QStringLiteral("name"), name);
    m.insert(QStringLiteral("target"), target);
    if (!args.isEmpty())
        m.insert(QStringLiteral("args"), args);
    const int clamped = qBound(0, index, m_pinnedApps.size());
    m_pinnedApps.insert(clamped, m);
    savePinnedApps();
    emit pinnedAppsChanged();
}

void AppLauncher::reorderDock(const QVariantList& currentAppItems,
                              int fromIndex, int toIndex)
{
    const int n = currentAppItems.size();
    if (fromIndex < 0 || fromIndex >= n || toIndex < 0 || toIndex >= n || fromIndex == toIndex)
        return;

    QVariantList reordered = currentAppItems;
    reordered.move(fromIndex, toIndex);

    int cutoff = toIndex;
    for (int i = n - 1; i >= 0; --i) {
        if (reordered.at(i).toMap().value(QStringLiteral("pinned")).toBool()) {
            cutoff = qMax(cutoff, i);
            break;
        }
    }

    QVariantList nextPinned;
    QSet<QString> seen;
    for (int i = 0; i <= cutoff; ++i) {
        const QVariantMap src = reordered.at(i).toMap();
        const QString target = src.value(QStringLiteral("target")).toString().trimmed();
        const QString key = target.toLower();
        if (target.isEmpty() || seen.contains(key))
            continue;
        seen.insert(key);

        QVariantMap entry;
        entry.insert(QStringLiteral("name"), src.value(QStringLiteral("name")).toString());
        entry.insert(QStringLiteral("target"), target);
        const QString args = src.value(QStringLiteral("args")).toString();
        if (!args.isEmpty())
            entry.insert(QStringLiteral("args"), args);
        nextPinned.append(entry);
    }

    m_pinnedApps = nextPinned;
    savePinnedApps();
    emit pinnedAppsChanged();
}

void AppLauncher::refreshInstalledApps()
{
    QVariantList out;
    QSet<QString> seenNames;

    auto addItem = [&](const QString& name, const QString& target,
                       const QString& category, const QString& args = {}) {
        const QString clean = name.trimmed();
        if (clean.isEmpty())
            return;
        const QString key = clean.toLower();
        if (seenNames.contains(key))
            return;
        seenNames.insert(key);
        QVariantMap m;
        m.insert(QStringLiteral("name"), clean);
        m.insert(QStringLiteral("target"), target);
        m.insert(QStringLiteral("args"), args);
        m.insert(QStringLiteral("category"), category);
        out.append(m);
    };

    for (const QVariant& v : m_pinnedApps) {
        const QVariantMap pm = v.toMap();
        if (pm.value(QStringLiteral("kind")).toString() == QStringLiteral("separator"))
            continue;
        addItem(pm.value(QStringLiteral("name")).toString(),
                pm.value(QStringLiteral("target")).toString(),
                QStringLiteral("Pinned"),
                pm.value(QStringLiteral("args")).toString());
    }

#ifdef Q_OS_WIN
    addItem(QStringLiteral("Task Manager"), QStringLiteral("taskmgr.exe"), QStringLiteral("System"));
    addItem(QStringLiteral("Control Panel"), QStringLiteral("control.exe"), QStringLiteral("System"));
    addItem(QStringLiteral("Display Settings"), QStringLiteral("ms-settings:display"), QStringLiteral("System"));
    addItem(QStringLiteral("Sound Settings"), QStringLiteral("ms-settings:sound"), QStringLiteral("System"));
    addItem(QStringLiteral("Windows Settings"), QStringLiteral("ms-settings:"), QStringLiteral("System"));
    addItem(QStringLiteral("Device Manager"), QStringLiteral("devmgmt.msc"), QStringLiteral("System"));
    addItem(QStringLiteral("Registry Editor"), QStringLiteral("regedit.exe"), QStringLiteral("System"));

    const QString progData = qEnvironmentVariable("ProgramData");
    const QString appData = qEnvironmentVariable("AppData");
    QStringList roots;
    if (!progData.isEmpty())
        roots << (progData + QStringLiteral("\\Microsoft\\Windows\\Start Menu\\Programs"));
    if (!appData.isEmpty())
        roots << (appData + QStringLiteral("\\Microsoft\\Windows\\Start Menu\\Programs"));

    for (const QString& root : roots) {
        QDirIterator it(root, QStringList() << QStringLiteral("*.lnk"),
                        QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString filePath = it.next();
            const QFileInfo fi(filePath);
            const QString base = fi.completeBaseName();
            const QString low = base.toLower();
            if (low.contains(QStringLiteral("uninstall"))
                || low.contains(QStringLiteral("readme"))
                || low.contains(QStringLiteral("help"))
                || low.contains(QStringLiteral("manual"))
                || low.contains(QStringLiteral("website"))) {
                continue;
            }
            addItem(base, filePath, QStringLiteral("App"));
        }
    }
#endif

    std::sort(out.begin(), out.end(), [](const QVariant& a, const QVariant& b) {
        const QString na = a.toMap().value(QStringLiteral("name")).toString().toLower();
        const QString nb = b.toMap().value(QStringLiteral("name")).toString().toLower();
        return na < nb;
    });

    m_installedApps = std::move(out);
    emit installedAppsChanged();
}

static int fuzzyMatchScore(const QString& nameRaw, const QString& query)
{
    const QString name = nameRaw.toLower();
    if (name == query)
        return 1000;
    if (name.startsWith(query))
        return 850 - qMin(100, name.size() - query.size());

    // Word-boundary or CamelCase acronym matching ("vsc" -> "Visual Studio Code")
    QString initials;
    QStringList words = name.split(QRegularExpression(QStringLiteral("[\\s\\-_\\.]+")), Qt::SkipEmptyParts);
    for (const QString& w : words)
        initials.append(w.at(0));
    if (initials.startsWith(query))
        return 760;

    const int subIdx = name.indexOf(query);
    if (subIdx >= 0) {
        const bool atWordStart = (subIdx == 0 || !name.at(subIdx - 1).isLetterOrNumber());
        return (atWordStart ? 680 : 540) - qMin(80, subIdx);
    }

    // Tight subsequence fuzzy match
    int qi = 0;
    int lastMatch = -1;
    int gapSum = 0;
    for (int ni = 0; ni < name.size() && qi < query.size(); ++ni) {
        if (name.at(ni) == query.at(qi)) {
            if (lastMatch >= 0)
                gapSum += (ni - lastMatch - 1);
            lastMatch = ni;
            ++qi;
        }
    }
    if (qi == query.size() && gapSum <= name.size())
        return qMax(120, 420 - gapSum * 8);

    return 0;
}

QVariantList AppLauncher::searchApps(const QString& query) const
{
    const QString q = query.trimmed().toLower();
    if (q.isEmpty()) {
        QVariantList ranked = m_installedApps;
        std::stable_sort(ranked.begin(), ranked.end(), [this](const QVariant& a, const QVariant& b) {
            const QVariantMap ma = a.toMap();
            const QVariantMap mb = b.toMap();
            const int ua = m_usageCounts.value(ma.value(QStringLiteral("target")).toString().toLower(), 0).toInt();
            const int ub = m_usageCounts.value(mb.value(QStringLiteral("target")).toString().toLower(), 0).toInt();
            if (ua != ub)
                return ua > ub;
            const bool pa = ma.value(QStringLiteral("category")).toString() == QStringLiteral("Pinned");
            const bool pb = mb.value(QStringLiteral("category")).toString() == QStringLiteral("Pinned");
            return pa && !pb;
        });
        return ranked.size() > 8 ? ranked.mid(0, 8) : ranked;
    }

    struct Scored {
        int score;
        QVariantMap item;
    };
    QList<Scored> matches;
    for (const QVariant& v : m_installedApps) {
        QVariantMap m = v.toMap();
        const int base = fuzzyMatchScore(m.value(QStringLiteral("name")).toString(), q);
        if (base <= 0)
            continue;
        const int usage = m_usageCounts.value(m.value(QStringLiteral("target")).toString().toLower(), 0).toInt();
        const int bonus = qMin(180, usage * 25) + (m.value(QStringLiteral("category")).toString() == QStringLiteral("Pinned") ? 30 : 0);
        m.insert(QStringLiteral("score"), base + bonus);
        matches.append({ base + bonus, m });
    }

    std::sort(matches.begin(), matches.end(), [](const Scored& a, const Scored& b) {
        if (a.score != b.score)
            return a.score > b.score;
        return a.item.value(QStringLiteral("name")).toString() < b.item.value(QStringLiteral("name")).toString();
    });

    QVariantList res;
    for (int i = 0; i < matches.size() && i < 12; ++i)
        res.append(matches.at(i).item);
    return res;
}

QVariantList AppLauncher::listPathSuggestions(const QString& rawPath) const
{
    QVariantList out;
    QString p = rawPath.trimmed();
    if (p.startsWith(QLatin1Char('~')))
        p = qEnvironmentVariable("USERPROFILE") + p.mid(1);
    p.replace(QLatin1Char('/'), QLatin1Char('\\'));

    QFileInfo direct(p);
    QString dirPath;
    QString prefix;
    if (direct.exists() && direct.isDir()) {
        dirPath = direct.absoluteFilePath();
    } else {
        const int slash = p.lastIndexOf(QLatin1Char('\\'));
        if (slash < 0)
            return out;
        dirPath = p.left(slash + 1);
        prefix = p.mid(slash + 1).toLower();
    }

    QDir dir(dirPath);
    if (!dir.exists())
        return out;

    const QFileInfoList entries = dir.entryInfoList(
        QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
        QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo& fi : entries) {
        if (!prefix.isEmpty() && !fi.fileName().toLower().contains(prefix))
            continue;
        QVariantMap m;
        m.insert(QStringLiteral("name"), fi.fileName());
        m.insert(QStringLiteral("target"), QDir::toNativeSeparators(fi.absoluteFilePath()));
        m.insert(QStringLiteral("args"), QString());
        m.insert(QStringLiteral("category"), fi.isDir() ? QStringLiteral("Folder") : QStringLiteral("File"));
        m.insert(QStringLiteral("isPath"), true);
        out.append(m);
        if (out.size() >= 10)
            break;
    }
    return out;
}
