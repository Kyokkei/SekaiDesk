#include "AppLauncher.h"
#include "core/SettingsStore.h"

#include <QFileInfo>
#include <QVariantMap>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shellapi.h>
#endif

AppLauncher::AppLauncher(SettingsStore* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    reload();
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
