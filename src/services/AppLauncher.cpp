#include "AppLauncher.h"
#include "core/SettingsStore.h"

#include <QDirIterator>
#include <QFileInfo>
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
    return true;
#else
    Q_UNUSED(args);
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

QVariantList AppLauncher::searchApps(const QString& query) const
{
    const QString q = query.trimmed().toLower();
    if (q.isEmpty()) {
        QVariantList top;
        for (int i = 0; i < m_pinnedApps.size() && top.size() < 8; ++i) {
            QVariantMap pm = m_pinnedApps.at(i).toMap();
            if (pm.value(QStringLiteral("kind")).toString() == QStringLiteral("separator"))
                continue;
            pm.insert(QStringLiteral("category"), QStringLiteral("Pinned"));
            top.append(pm);
        }
        return top;
    }

    QVariantList startsWith;
    QVariantList contains;
    for (const QVariant& v : m_installedApps) {
        const QVariantMap m = v.toMap();
        const QString name = m.value(QStringLiteral("name")).toString().toLower();
        if (name.startsWith(q))
            startsWith.append(m);
        else if (name.contains(q))
            contains.append(m);
    }

    QVariantList res = startsWith;
    res.append(contains);
    if (res.size() > 14)
        res = res.mid(0, 14);
    return res;
}
