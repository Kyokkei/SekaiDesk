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
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <objbase.h>

namespace {
QString expandEnvVars(const QString& raw)
{
    if (raw.isEmpty())
        return {};
    wchar_t expanded[MAX_PATH * 4] = {};
    const DWORD n = ExpandEnvironmentStringsW(
        reinterpret_cast<const wchar_t*>(raw.utf16()),
        expanded, MAX_PATH * 4);
    if (n > 0 && n < MAX_PATH * 4)
        return QString::fromWCharArray(expanded);
    return raw;
}

bool isUriOrShellTarget(const QString& target)
{
    if (target.startsWith(QStringLiteral("ms-settings:"), Qt::CaseInsensitive)
        || target.startsWith(QStringLiteral("shell:"), Qt::CaseInsensitive)) {
        return true;
    }
    return target.contains(QStringLiteral("://"));
}

struct ResolvedTarget {
    QString inputPath;
    QString resolvedPath;
    QString shortcutArgs;
    QString workingDir;
    bool isUriOrShell = false;
    bool isShortcut = false;
    bool inputExists = false;
    bool inputIsDir = false;
    bool targetExists = false;
    bool targetIsDir = false;
};

ResolvedTarget resolveTargetDetails(const QString& rawTarget)
{
    ResolvedTarget out;
    QString clean = rawTarget.trimmed();
    if (clean.size() >= 2 && clean.startsWith(QLatin1Char('"')) && clean.endsWith(QLatin1Char('"')))
        clean = clean.mid(1, clean.size() - 2).trimmed();
    if (clean.isEmpty())
        return out;

    if (isUriOrShellTarget(clean)) {
        out.isUriOrShell = true;
        out.inputPath = clean;
        out.resolvedPath = clean;
        return out;
    }

    clean = QDir::toNativeSeparators(expandEnvVars(clean).trimmed());
    if (!clean.contains(QLatin1Char('\\')) && !clean.contains(QLatin1Char('/'))
        && !clean.contains(QLatin1Char(':'))) {
        wchar_t found[MAX_PATH * 2] = {};
        if (SearchPathW(nullptr,
                        reinterpret_cast<const wchar_t*>(clean.utf16()),
                        nullptr, MAX_PATH * 2, found, nullptr) > 0) {
            clean = QDir::toNativeSeparators(QString::fromWCharArray(found));
        }
    }

    out.inputPath = clean;
    out.resolvedPath = clean;

    const QFileInfo inputFi(out.inputPath);
    out.inputExists = inputFi.exists();
    out.inputIsDir = inputFi.isDir();

    if (out.inputExists && !out.inputIsDir
        && inputFi.suffix().compare(QStringLiteral("lnk"), Qt::CaseInsensitive) == 0) {
        out.isShortcut = true;
        out.resolvedPath.clear();

        static const CLSID kCLSID_ShellLink = {
            0x00021401, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
        };
        static const IID kIID_IShellLinkW = {
            0x000214F9, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
        };
        static const IID kIID_IPersistFile = {
            0x0000010B, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
        };

        const HRESULT hrCom = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        IShellLinkW* psl = nullptr;
        if (SUCCEEDED(CoCreateInstance(kCLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                       kIID_IShellLinkW, reinterpret_cast<void**>(&psl))) && psl) {
            IPersistFile* ppf = nullptr;
            if (SUCCEEDED(psl->QueryInterface(kIID_IPersistFile, reinterpret_cast<void**>(&ppf))) && ppf) {
                if (SUCCEEDED(ppf->Load(reinterpret_cast<const wchar_t*>(out.inputPath.utf16()), STGM_READ))) {
                    wchar_t targetBuf[MAX_PATH * 4] = {};
                    HRESULT hrPath = psl->GetPath(targetBuf, MAX_PATH * 4, nullptr, 0);
                    if (FAILED(hrPath) || targetBuf[0] == L'\0') {
                        targetBuf[0] = L'\0';
                        hrPath = psl->GetPath(targetBuf, MAX_PATH * 4, nullptr, SLGP_RAWPATH);
                    }
                    if (SUCCEEDED(hrPath) && targetBuf[0] != L'\0') {
                        const QString expanded = expandEnvVars(QString::fromWCharArray(targetBuf)).trimmed();
                        if (!expanded.isEmpty())
                            out.resolvedPath = QDir::toNativeSeparators(expanded);
                    }

                    wchar_t argBuf[2048] = {};
                    if (SUCCEEDED(psl->GetArguments(argBuf, 2048)) && argBuf[0] != L'\0')
                        out.shortcutArgs = QString::fromWCharArray(argBuf).trimmed();

                    wchar_t dirBuf[MAX_PATH * 4] = {};
                    if (SUCCEEDED(psl->GetWorkingDirectory(dirBuf, MAX_PATH * 4)) && dirBuf[0] != L'\0') {
                        out.workingDir = QDir::toNativeSeparators(
                            expandEnvVars(QString::fromWCharArray(dirBuf)).trimmed());
                    }
                }
                ppf->Release();
            }
            psl->Release();
        }
        if (SUCCEEDED(hrCom))
            CoUninitialize();
    }

    if (!out.resolvedPath.isEmpty()) {
        const QFileInfo targetFi(out.resolvedPath);
        out.targetExists = targetFi.exists();
        out.targetIsDir = targetFi.isDir();
        if (out.workingDir.isEmpty() && out.targetExists) {
            out.workingDir = out.targetIsDir
                ? out.resolvedPath
                : QDir::toNativeSeparators(targetFi.absolutePath());
        }
    }

    return out;
}

bool shellExecuteVerb(const wchar_t* verb, const QString& file,
                      const QString& args, const QString& workDir)
{
    if (file.isEmpty())
        return false;
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof(sei);
    sei.fMask = 0;
    sei.lpVerb = verb;
    sei.lpFile = reinterpret_cast<const wchar_t*>(file.utf16());
    sei.lpParameters = args.isEmpty() ? nullptr : reinterpret_cast<const wchar_t*>(args.utf16());
    sei.lpDirectory = workDir.isEmpty() ? nullptr : reinterpret_cast<const wchar_t*>(workDir.utf16());
    sei.nShow = SW_SHOWNORMAL;
    return ShellExecuteExW(&sei) != FALSE;
}

QString combineArgs(const QString& shortcutArgs, const QString& extraArgs)
{
    const QString a = shortcutArgs.trimmed();
    const QString b = extraArgs.trimmed();
    if (a.isEmpty())
        return b;
    if (b.isEmpty())
        return a;
    return a + QLatin1Char(' ') + b;
}
} // namespace
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
        m_hiddenApps = m_settings->get(QStringLiteral("launcher.hiddenApps")).toMap();
    }
    if (!hasKey)
        seedDefaultsIfEmpty();
    emit pinnedAppsChanged();
    emit hiddenAppsChanged();
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

void AppLauncher::saveHiddenApps()
{
    if (m_settings)
        m_settings->set(QStringLiteral("launcher.hiddenApps"), m_hiddenApps);
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

bool AppLauncher::runAsDifferentUser(const QString& target, const QString& args)
{
#ifdef Q_OS_WIN
    if (target.trimmed().isEmpty())
        return false;
    const ResolvedTarget details = resolveTargetDetails(target);
    if (details.isUriOrShell || details.resolvedPath.isEmpty()
        || !details.targetExists || details.targetIsDir) {
        return false;
    }
    const QString combinedArgs = combineArgs(details.shortcutArgs, args);
    if (!shellExecuteVerb(L"runasuser", details.resolvedPath, combinedArgs, details.workingDir))
        return false;
    recordUsage(target);
    return true;
#else
    Q_UNUSED(target);
    Q_UNUSED(args);
    return false;
#endif
}

bool AppLauncher::runElevated(const QString& target, const QString& args)
{
#ifdef Q_OS_WIN
    const QString raw = target.trimmed();
    if (raw.isEmpty())
        return false;
    const ResolvedTarget details = resolveTargetDetails(raw);
    const bool useResolved = !details.isUriOrShell && !details.resolvedPath.isEmpty()
                             && details.targetExists && !details.targetIsDir;
    const QString execFile = useResolved ? details.resolvedPath : raw;
    const QString combinedArgs = useResolved
        ? combineArgs(details.shortcutArgs, args)
        : args.trimmed();
    if (!shellExecuteVerb(L"runas", execFile, combinedArgs, details.workingDir))
        return false;
    recordUsage(target);
    return true;
#else
    Q_UNUSED(target);
    Q_UNUSED(args);
    return false;
#endif
}

bool AppLauncher::openContainingFolder(const QString& target)
{
#ifdef Q_OS_WIN
    const ResolvedTarget details = resolveTargetDetails(target);
    if (details.isUriOrShell || details.inputPath.isEmpty() || !details.inputExists)
        return false;
    const QString arg = QStringLiteral("/select,\"%1\"").arg(details.inputPath);
    const HINSTANCE res = ShellExecuteW(
        nullptr, L"open", L"explorer.exe",
        reinterpret_cast<const wchar_t*>(arg.utf16()),
        nullptr, SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(res) > 32;
#else
    Q_UNUSED(target);
    return false;
#endif
}

bool AppLauncher::openTargetFolder(const QString& target)
{
#ifdef Q_OS_WIN
    const ResolvedTarget details = resolveTargetDetails(target);
    if (details.isUriOrShell || details.resolvedPath.isEmpty() || !details.targetExists)
        return false;
    if (details.targetIsDir) {
        const HINSTANCE res = ShellExecuteW(
            nullptr, L"open",
            reinterpret_cast<const wchar_t*>(details.resolvedPath.utf16()),
            nullptr, nullptr, SW_SHOWNORMAL);
        return reinterpret_cast<INT_PTR>(res) > 32;
    }
    const QString arg = QStringLiteral("/select,\"%1\"").arg(details.resolvedPath);
    const HINSTANCE res = ShellExecuteW(
        nullptr, L"open", L"explorer.exe",
        reinterpret_cast<const wchar_t*>(arg.utf16()),
        nullptr, SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(res) > 32;
#else
    Q_UNUSED(target);
    return false;
#endif
}

bool AppLauncher::revealInExplorer(const QString& target)
{
    return openContainingFolder(target);
}

void AppLauncher::hideApp(const QString& target, const QString& name)
{
    const QString key = target.trimmed().toLower();
    if (key.isEmpty())
        return;
    QString displayName = name.trimmed();
    if (displayName.isEmpty()) {
        const QString base = QFileInfo(target.trimmed()).completeBaseName();
        displayName = base.isEmpty() ? target.trimmed() : base;
    }
    m_hiddenApps.insert(key, displayName);
    saveHiddenApps();
    emit hiddenAppsChanged();
}

void AppLauncher::unhideApp(const QString& target)
{
    const QString key = target.trimmed().toLower();
    if (key.isEmpty() || !m_hiddenApps.contains(key))
        return;
    m_hiddenApps.remove(key);
    saveHiddenApps();
    emit hiddenAppsChanged();
}

void AppLauncher::clearHiddenApps()
{
    if (m_hiddenApps.isEmpty())
        return;
    m_hiddenApps.clear();
    saveHiddenApps();
    emit hiddenAppsChanged();
}

bool AppLauncher::isHidden(const QString& target) const
{
    const QString key = target.trimmed().toLower();
    return !key.isEmpty() && m_hiddenApps.contains(key);
}

QVariantList AppLauncher::hiddenApps() const
{
    QVariantList out;
    out.reserve(m_hiddenApps.size());
    for (auto it = m_hiddenApps.constBegin(); it != m_hiddenApps.constEnd(); ++it) {
        QVariantMap m;
        m.insert(QStringLiteral("name"), it.value().toString());
        m.insert(QStringLiteral("target"), it.key());
        out.append(m);
    }
    std::sort(out.begin(), out.end(), [](const QVariant& a, const QVariant& b) {
        const QString na = a.toMap().value(QStringLiteral("name")).toString().toLower();
        const QString nb = b.toMap().value(QStringLiteral("name")).toString().toLower();
        if (na != nb)
            return na < nb;
        return a.toMap().value(QStringLiteral("target")).toString()
             < b.toMap().value(QStringLiteral("target")).toString();
    });
    return out;
}

QVariantMap AppLauncher::inspectTarget(const QString& target) const
{
    QVariantMap caps;
#ifdef Q_OS_WIN
    const ResolvedTarget details = resolveTargetDetails(target);
    const bool isLocal = !details.isUriOrShell && (details.inputExists || details.targetExists);
    const bool isDir = details.isShortcut ? details.targetIsDir : details.inputIsDir;
    const QString suffix = details.resolvedPath.isEmpty()
        ? QString()
        : QFileInfo(details.resolvedPath).suffix().toLower();
    const bool canRunAsUser = !details.isUriOrShell && details.targetExists
                              && !details.targetIsDir && suffix == QStringLiteral("exe");
    const bool canElevate = !details.isUriOrShell && details.targetExists
                            && !details.targetIsDir
                            && (suffix == QStringLiteral("exe")
                                || suffix == QStringLiteral("bat")
                                || suffix == QStringLiteral("cmd")
                                || suffix == QStringLiteral("msc")
                                || suffix == QStringLiteral("msi"));
    const bool canOpenContaining = !details.isUriOrShell && details.inputExists;
    const bool canOpenTarget = !details.isUriOrShell && details.targetExists;

    caps.insert(QStringLiteral("isLocal"), isLocal);
    caps.insert(QStringLiteral("isShortcut"), details.isShortcut);
    caps.insert(QStringLiteral("isDir"), isDir);
    caps.insert(QStringLiteral("canRunAsUser"), canRunAsUser);
    caps.insert(QStringLiteral("canElevate"), canElevate);
    caps.insert(QStringLiteral("canOpenContaining"), canOpenContaining);
    caps.insert(QStringLiteral("canOpenTarget"), canOpenTarget);
#else
    Q_UNUSED(target);
    caps.insert(QStringLiteral("isLocal"), false);
    caps.insert(QStringLiteral("isShortcut"), false);
    caps.insert(QStringLiteral("isDir"), false);
    caps.insert(QStringLiteral("canRunAsUser"), false);
    caps.insert(QStringLiteral("canElevate"), false);
    caps.insert(QStringLiteral("canOpenContaining"), false);
    caps.insert(QStringLiteral("canOpenTarget"), false);
#endif
    return caps;
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
            const QString filePath = QDir::toNativeSeparators(it.next());
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
        QVariantList ranked;
        ranked.reserve(m_installedApps.size());
        for (const QVariant& v : m_installedApps) {
            if (!isHidden(v.toMap().value(QStringLiteral("target")).toString()))
                ranked.append(v);
        }
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
        if (isHidden(m.value(QStringLiteral("target")).toString()))
            continue;
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
