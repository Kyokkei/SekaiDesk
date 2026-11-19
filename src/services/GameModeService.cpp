#include "GameModeService.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStandardPaths>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <tlhelp32.h>
#endif

namespace {

#ifdef Q_OS_WIN
struct SekaiPowerThrottlingState
{
    ULONG Version;
    ULONG ControlMask;
    ULONG StateMask;
};

constexpr ULONG kPowerThrottlingVersion = 1;
constexpr ULONG kExecSpeed = 0x1;
constexpr ULONG kIgnoreTimerRes = 0x4;
constexpr ULONG kProcessPowerThrottling = 4;
constexpr int kQunsRunningD3dFullScreen = 3;

void setEcoQosAndPriority(bool eco)
{
    HANDLE self = GetCurrentProcess();
    SetPriorityClass(self, eco ? IDLE_PRIORITY_CLASS : NORMAL_PRIORITY_CLASS);

    using SetProcessInfoFn = BOOL(WINAPI*)(HANDLE, PROCESS_INFORMATION_CLASS, LPVOID, DWORD);
    static auto fnSetProcessInfo = reinterpret_cast<SetProcessInfoFn>(
        GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "SetProcessInformation"));
    if (fnSetProcessInfo) {
        SekaiPowerThrottlingState state{};
        state.Version = kPowerThrottlingVersion;
        state.ControlMask = kExecSpeed | kIgnoreTimerRes;
        state.StateMask = eco ? (kExecSpeed | kIgnoreTimerRes) : 0;
        if (!fnSetProcessInfo(self,
                              static_cast<PROCESS_INFORMATION_CLASS>(kProcessPowerThrottling),
                              &state,
                              sizeof(state))) {
            // Fallback for older Windows 10 builds that reject IGNORE_TIMER_RESOLUTION.
            state.ControlMask = kExecSpeed;
            state.StateMask = eco ? kExecSpeed : 0;
            fnSetProcessInfo(self,
                             static_cast<PROCESS_INFORMATION_CLASS>(kProcessPowerThrottling),
                             &state,
                             sizeof(state));
        }
    }

    if (eco) {
        SetProcessWorkingSetSize(self, static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
    }
}

bool isD3dExclusiveFullscreenActive()
{
    using QueryStateFn = HRESULT(WINAPI*)(int*);
    static auto fnQueryState = reinterpret_cast<QueryStateFn>(
        GetProcAddress(GetModuleHandleW(L"shell32.dll"), "SHQueryUserNotificationState"));
    if (!fnQueryState)
        return false;
    int state = 0;
    return SUCCEEDED(fnQueryState(&state)) && state == kQunsRunningD3dFullScreen;
}

QString queryProcessExeNameWin(DWORD pid)
{
    if (pid == 0)
        return {};
    HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!proc)
        return {};
    wchar_t buf[MAX_PATH * 2]{};
    DWORD len = static_cast<DWORD>(std::size(buf));
    QString out;
    if (QueryFullProcessImageNameW(proc, 0, buf, &len) && len > 0) {
        out = QFileInfo(QString::fromWCharArray(buf, static_cast<int>(len))).fileName().toLower();
    }
    CloseHandle(proc);
    return out;
}

bool isWindowGenuineBorderlessFullscreen(HWND hwnd)
{
    if (!hwnd || !IsWindowVisible(hwnd) || IsIconic(hwnd))
        return false;

    DWORD cloaked = 0;
    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, 14 /*DWMWA_CLOAKED*/, &cloaked, sizeof(cloaked))) && cloaked != 0)
        return false;

    const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if ((style & WS_CHILD) || (style & WS_CAPTION) != 0)
        return false;

    RECT wr{};
    if (!GetWindowRect(hwnd, &wr))
        return false;

    HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    if (!mon || !GetMonitorInfoW(mon, &mi))
        return false;

    constexpr LONG kTol = 2;
    return wr.left <= mi.rcMonitor.left + kTol
        && wr.top <= mi.rcMonitor.top + kTol
        && wr.right >= mi.rcMonitor.right - kTol
        && wr.bottom >= mi.rcMonitor.bottom - kTol;
}

bool isProcessAliveBySnapshot(DWORD pid, const QString& lowerExe)
{
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE)
        return false;

    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);
    bool found = false;
    if (Process32FirstW(snap, &pe)) {
        do {
            if (pid != 0 && pe.th32ProcessID == pid) {
                found = true;
                break;
            }
            if (!lowerExe.isEmpty()
                && QString::fromWCharArray(pe.szExeFile).compare(lowerExe, Qt::CaseInsensitive) == 0) {
                found = true;
                break;
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}

DWORD findPidByExeName(const QString& lowerExe)
{
    if (lowerExe.isEmpty())
        return 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE)
        return 0;

    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);
    DWORD foundPid = 0;
    if (Process32FirstW(snap, &pe)) {
        do {
            if (QString::fromWCharArray(pe.szExeFile).compare(lowerExe, Qt::CaseInsensitive) == 0) {
                foundPid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return foundPid;
}

QString readRegistryString(HKEY root, const wchar_t* subKey, const wchar_t* valueName)
{
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, subKey, 0, KEY_READ, &key) != ERROR_SUCCESS)
        return {};
    wchar_t buf[MAX_PATH * 2]{};
    DWORD type = 0;
    DWORD bytes = sizeof(buf);
    QString result;
    if (RegQueryValueExW(key, valueName, nullptr, &type, reinterpret_cast<LPBYTE>(buf), &bytes) == ERROR_SUCCESS
        && (type == REG_SZ || type == REG_EXPAND_SZ) && bytes >= sizeof(wchar_t)) {
        result = QString::fromWCharArray(buf).trimmed();
    }
    RegCloseKey(key);
    return result;
}

QString discoverRtssInstallDir()
{
    const QStringList regCandidates = {
        readRegistryString(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WOW6432Node\\Unwinder\\RTSS", L"InstallDir"),
        readRegistryString(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Unwinder\\RTSS", L"InstallDir"),
        readRegistryString(HKEY_CURRENT_USER, L"Software\\Unwinder\\RTSS", L"InstallDir"),
    };
    const QStringList dirCandidates = regCandidates + QStringList{
        QStringLiteral("C:/Program Files (x86)/RivaTuner Statistics Server"),
        QStringLiteral("C:/Program Files/RivaTuner Statistics Server"),
        QStringLiteral("D:/Program Files (x86)/RivaTuner Statistics Server"),
    };
    for (const QString& raw : dirCandidates) {
        if (raw.isEmpty())
            continue;
        QString dir = QDir::cleanPath(raw);
        if (QFileInfo::exists(dir + QStringLiteral("/RTSS.exe"))
            || QDir(dir + QStringLiteral("/Profiles")).exists()) {
            return dir;
        }
    }
    return {};
}
#endif

} // namespace

GameModeService::GameModeService(QObject* parent)
    : QObject(parent)
{
    loadConfig();
    refreshRtssStatus();

    m_pollTimer.setInterval(800);
    m_pollTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_pollTimer, &QTimer::timeout, this, &GameModeService::pollForeground);
    if (m_autoDetect)
        m_pollTimer.start();
}

int GameModeService::runWaitGameWatchdog(unsigned long targetPid,
                                         const QString& waitExe,
                                         const QString& instanceTag)
{
#ifdef Q_OS_WIN
    setEcoQosAndPriority(true);

    const QString lowerExe = waitExe.trimmed().toLower();
    DWORD currentPid = static_cast<DWORD>(targetPid);

    Sleep(600);

    while (true) {
        if (currentPid != 0) {
            HANDLE hProc = OpenProcess(SYNCHRONIZE, FALSE, currentPid);
            if (hProc) {
                while (true) {
                    DWORD waitRes = WaitForSingleObject(hProc, 1500);
                    SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
                    if (waitRes != WAIT_TIMEOUT)
                        break;
                }
                CloseHandle(hProc);
                currentPid = 0;
            }
        }

        // Handle anti-cheat processes that deny SYNCHRONIZE, child relaunches of same exe,
        // or lingering exclusive Direct3D fullscreen sessions.
        Sleep(800);
        if (DWORD respawnPid = findPidByExeName(lowerExe); respawnPid != 0 && respawnPid != GetCurrentProcessId()) {
            currentPid = respawnPid;
            SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
            Sleep(700);
            continue;
        }
        if ((currentPid != 0 && isProcessAliveBySnapshot(currentPid, QString())) || isD3dExclusiveFullscreenActive()) {
            SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
            Sleep(700);
            continue;
        }
        break;
    }

    // Wait briefly until main instance's single-instance mutex has closed.
    const std::wstring mutexName = instanceTag.isEmpty()
        ? std::wstring(L"Local\\SekaiDesk_SingleInstance_v1")
        : (std::wstring(L"Local\\SekaiDesk_SingleInstance_") + instanceTag.toStdWString());
    for (int i = 0; i < 30; ++i) {
        HANDLE hMtx = OpenMutexW(SYNCHRONIZE, FALSE, mutexName.c_str());
        if (!hMtx)
            break;
        CloseHandle(hMtx);
        Sleep(150);
    }

    wchar_t exeBuf[MAX_PATH * 2]{};
    DWORD len = GetModuleFileNameW(nullptr, exeBuf, static_cast<DWORD>(std::size(exeBuf)));
    if (len > 0) {
        const QString exePath = QString::fromWCharArray(exeBuf, static_cast<int>(len));
        const QString workDir = QFileInfo(exePath).absolutePath();
        const std::wstring wExe = exePath.toStdWString();
        const std::wstring wDir = workDir.toStdWString();
        std::wstring cmdLine = L"\"" + wExe + L"\"";
        if (!instanceTag.isEmpty())
            cmdLine += L" --instance=\"" + instanceTag.toStdWString() + L"\"";

        STARTUPINFOW si{};
        si.cb = sizeof(si);
        PROCESS_INFORMATION pi{};
        if (CreateProcessW(wExe.c_str(), cmdLine.data(), nullptr, nullptr, FALSE,
                           DETACHED_PROCESS, nullptr, wDir.c_str(), &si, &pi)) {
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
        }
    }
    return 0;
#else
    Q_UNUSED(targetPid)
    Q_UNUSED(waitExe)
    Q_UNUSED(instanceTag)
    return 0;
#endif
}

QString GameModeService::normalizeExeName(const QString& exeOrPath)
{
    QString trimmed = exeOrPath.trimmed();
    if (trimmed.isEmpty())
        return {};
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.size() >= 2)
        trimmed = trimmed.mid(1, trimmed.size() - 2).trimmed();
    QString name = QFileInfo(trimmed).fileName().toLower();
    if (name.isEmpty())
        name = trimmed.toLower();
    if (!name.isEmpty() && !name.endsWith(QStringLiteral(".exe")))
        name += QStringLiteral(".exe");
    return name;
}

QStringList GameModeService::defaultGameList()
{
    return {
        QStringLiteral("cs2.exe"),
        QStringLiteral("csgo.exe"),
        QStringLiteral("valorant.exe"),
        QStringLiteral("valorant-win64-shipping.exe"),
        QStringLiteral("league of legends.exe"),
        QStringLiteral("genshinimpact.exe"),
        QStringLiteral("starrail.exe"),
        QStringLiteral("zenlesszonezero.exe"),
        QStringLiteral("wuthering waves.exe"),
        QStringLiteral("client-win64-shipping.exe"),
        QStringLiteral("eldenring.exe"),
        QStringLiteral("darksoulsiii.exe"),
        QStringLiteral("sekiro.exe"),
        QStringLiteral("cyberpunk2077.exe"),
        QStringLiteral("witcher3.exe"),
        QStringLiteral("r5apex.exe"),
        QStringLiteral("overwatch.exe"),
        QStringLiteral("dota2.exe"),
        QStringLiteral("tslgame.exe"),
        QStringLiteral("fortniteclient-win64-shipping.exe"),
        QStringLiteral("gta5.exe"),
        QStringLiteral("rdr2.exe"),
        QStringLiteral("javaw.exe"),
        QStringLiteral("osu!.exe"),
        QStringLiteral("holocure.exe"),
        QStringLiteral("cinebench.exe"),
        QStringLiteral("cinebench windows 64 bit.exe"),
        QStringLiteral("furmark.exe"),
        QStringLiteral("furmark_win64.exe"),
        QStringLiteral("furmark_gui.exe"),
        QStringLiteral("3dmark.exe"),
        QStringLiteral("superposition.exe"),
    };
}

QStringList GameModeService::defaultExcludeList()
{
    return {
        QStringLiteral("chrome.exe"),
        QStringLiteral("msedge.exe"),
        QStringLiteral("firefox.exe"),
        QStringLiteral("brave.exe"),
        QStringLiteral("opera.exe"),
        QStringLiteral("vivaldi.exe"),
        QStringLiteral("vlc.exe"),
        QStringLiteral("mpv.exe"),
        QStringLiteral("mpc-hc64.exe"),
        QStringLiteral("mpc-be64.exe"),
        QStringLiteral("potplayermini64.exe"),
        QStringLiteral("explorer.exe"),
        QStringLiteral("dwm.exe"),
        QStringLiteral("searchhost.exe"),
        QStringLiteral("shellexperiencehost.exe"),
        QStringLiteral("startmenuexperiencehost.exe"),
        QStringLiteral("applicationframehost.exe"),
        QStringLiteral("lockapp.exe"),
        QStringLiteral("sekaidesk.exe"),
        QStringLiteral("obs64.exe"),
        QStringLiteral("discord.exe"),
        QStringLiteral("spotify.exe"),
        QStringLiteral("code.exe"),
        QStringLiteral("windowsterminal.exe"),
    };
}

QString GameModeService::configFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/game_mode.json");
}

void GameModeService::loadConfig()
{
    m_gameList = defaultGameList();
    m_excludeList = defaultExcludeList();

    QFile f(configFilePath());
    if (!f.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    if (obj.contains(QStringLiteral("autoDetect")))
        m_autoDetect = obj.value(QStringLiteral("autoDetect")).toBool(true);
    const QString m = obj.value(QStringLiteral("mode")).toString(QStringLiteral("hibernate")).toLower();
    if (m == QStringLiteral("hibernate") || m == QStringLiteral("zero"))
        m_mode = m;
    if (obj.contains(QStringLiteral("restoreTaskbarInZero")))
        m_restoreTaskbarInZero = obj.value(QStringLiteral("restoreTaskbarInZero")).toBool(true);

    auto readStringArray = [](const QJsonObject& o, const QString& key, QStringList& dst) {
        if (!o.contains(key) || !o.value(key).isArray())
            return;
        QStringList parsed;
        QSet<QString> seen;
        for (const QJsonValue& v : o.value(key).toArray()) {
            const QString norm = normalizeExeName(v.toString());
            if (!norm.isEmpty() && !seen.contains(norm)) {
                seen.insert(norm);
                parsed.append(norm);
            }
        }
        dst = parsed;
    };

    readStringArray(obj, QStringLiteral("gameList"), m_gameList);
    readStringArray(obj, QStringLiteral("excludeList"), m_excludeList);
}

void GameModeService::saveConfig() const
{
    QJsonObject obj;
    obj.insert(QStringLiteral("autoDetect"), m_autoDetect);
    obj.insert(QStringLiteral("mode"), m_mode);
    obj.insert(QStringLiteral("restoreTaskbarInZero"), m_restoreTaskbarInZero);

    QJsonArray games;
    for (const QString& g : m_gameList)
        games.append(g);
    obj.insert(QStringLiteral("gameList"), games);

    QJsonArray excludes;
    for (const QString& e : m_excludeList)
        excludes.append(e);
    obj.insert(QStringLiteral("excludeList"), excludes);

    QFile f(configFilePath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    }
}

void GameModeService::setAutoDetect(bool on)
{
    if (m_autoDetect == on)
        return;
    m_autoDetect = on;
    saveConfig();
    if (on) {
        m_pollTimer.start();
    } else {
        m_pollTimer.stop();
        m_pendingHits = 0;
        m_clearMisses = 0;
        if (m_autoActive) {
            m_autoActive = false;
            applyEffectiveState(QStringLiteral("Auto-Detect Disabled"));
            emit activeChanged();
        }
    }
    setStatus(on ? QStringLiteral("Auto Game Mode enabled (%1)").arg(m_mode)
                 : QStringLiteral("Auto Game Mode disabled"));
    emit autoDetectChanged();
}

void GameModeService::setMode(const QString& mode)
{
    const QString normalized = (mode.trimmed().toLower() == QStringLiteral("zero"))
        ? QStringLiteral("zero")
        : QStringLiteral("hibernate");
    if (m_mode == normalized)
        return;
    m_mode = normalized;
    saveConfig();
    emit modeChanged();
}

void GameModeService::setRestoreTaskbarInZero(bool on)
{
    if (m_restoreTaskbarInZero == on)
        return;
    m_restoreTaskbarInZero = on;
    saveConfig();
    emit restoreTaskbarInZeroChanged();
}

void GameModeService::toggleManual()
{
    setManualActive(!m_manualActive);
}

void GameModeService::setManualActive(bool on)
{
    if (m_manualActive == on)
        return;
    m_manualActive = on;
    if (on) {
        m_activeGameExe = QStringLiteral("Manual");
        m_activeGameTitle = QStringLiteral("Manual Game Mode");
        m_activeReason = QStringLiteral("Ctrl+Alt+G / Manual Toggle");
    } else if (!m_autoActive) {
        m_activeGameExe.clear();
        m_activeGameTitle.clear();
        m_activeReason.clear();
    }
    applyEffectiveState(on ? QStringLiteral("Manual") : QStringLiteral("Manual Off"));
    emit activeChanged();
}

void GameModeService::addGameExe(const QString& exeOrPath)
{
    const QString norm = normalizeExeName(exeOrPath);
    if (norm.isEmpty())
        return;
    if (m_excludeList.removeAll(norm) > 0)
        emit excludeListChanged();
    if (!m_gameList.contains(norm)) {
        m_gameList.prepend(norm);
        saveConfig();
        emit gameListChanged();
        setStatus(QStringLiteral("Added %1 to Game List").arg(norm));
    }
}

void GameModeService::removeGameExe(const QString& exe)
{
    const QString norm = normalizeExeName(exe);
    if (m_gameList.removeAll(norm) > 0) {
        saveConfig();
        emit gameListChanged();
    }
}

void GameModeService::addExcludeExe(const QString& exeOrPath)
{
    const QString norm = normalizeExeName(exeOrPath);
    if (norm.isEmpty())
        return;
    if (m_gameList.removeAll(norm) > 0)
        emit gameListChanged();
    if (!m_excludeList.contains(norm)) {
        m_excludeList.prepend(norm);
        saveConfig();
        emit excludeListChanged();
        setStatus(QStringLiteral("Excluded %1 from Auto Game Mode").arg(norm));
    }
}

void GameModeService::removeExcludeExe(const QString& exe)
{
    const QString norm = normalizeExeName(exe);
    if (m_excludeList.removeAll(norm) > 0) {
        saveConfig();
        emit excludeListChanged();
    }
}

void GameModeService::resetDefaultLists()
{
    m_gameList = defaultGameList();
    m_excludeList = defaultExcludeList();
    saveConfig();
    emit gameListChanged();
    emit excludeListChanged();
    setStatus(QStringLiteral("Reset Game & Exclude lists to defaults"));
}

void GameModeService::refreshRtssStatus()
{
#ifdef Q_OS_WIN
    const QString dir = discoverRtssInstallDir();
    const bool detected = !dir.isEmpty();
    bool excluded = false;
    if (detected) {
        const QString cfgPath = dir + QStringLiteral("/Profiles/SekaiDesk.exe.cfg");
        QFile f(cfgPath);
        if (f.open(QIODevice::ReadOnly)) {
            const QString content = QString::fromUtf8(f.readAll());
            excluded = content.contains(QStringLiteral("EnableHooking=0"), Qt::CaseInsensitive);
        }
    }
    if (m_rtssDetected != detected || m_rtssExcluded != excluded || m_rtssInstallDir != dir) {
        m_rtssDetected = detected;
        m_rtssExcluded = excluded;
        m_rtssInstallDir = dir;
        emit rtssStatusChanged();
    }
#endif
}

bool GameModeService::applyRtssExclusion()
{
#ifdef Q_OS_WIN
    refreshRtssStatus();
    if (!m_rtssDetected || m_rtssInstallDir.isEmpty()) {
        setStatus(QStringLiteral("RTSS not found on system"));
        return false;
    }

    const QByteArray profileBytes =
        "[Hooking]\r\n"
        "EnableHooking=0\r\n"
        "\r\n"
        "[RendererDirect3D8]\r\n"
        "HookDirect3D8=0\r\n"
        "\r\n"
        "[RendererDirect3D9]\r\n"
        "HookDirect3D9=0\r\n"
        "\r\n"
        "[RendererDirect3D10]\r\n"
        "HookDXGI=0\r\n"
        "\r\n"
        "[RendererDirect3D11]\r\n"
        "HookDXGI=0\r\n"
        "\r\n"
        "[RendererDirect3D12]\r\n"
        "HookDirect3D12=0\r\n"
        "HookDXGI=0\r\n"
        "\r\n"
        "[RendererOpenGL]\r\n"
        "HookOpenGL=0\r\n"
        "\r\n"
        "[RendererVulkan]\r\n"
        "HookVulkan=0\r\n";

    const QString profilesDir = m_rtssInstallDir + QStringLiteral("/Profiles");
    QDir().mkpath(profilesDir);
    const QString destPath = QDir::toNativeSeparators(profilesDir + QStringLiteral("/SekaiDesk.exe.cfg"));

    QFile destFile(destPath);
    if (destFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        destFile.write(profileBytes);
        destFile.close();
        refreshRtssStatus();
        setStatus(QStringLiteral("RTSS profile created: %1").arg(destPath));
        return m_rtssExcluded;
    }

    // Program Files (x86) requires UAC elevation: stage in %TEMP% and copy with runas.
    const QString tempPath = QDir::toNativeSeparators(
        QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/SekaiDesk_rtss.cfg"));
    QFile tmp(tempPath);
    if (!tmp.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        setStatus(QStringLiteral("Failed to stage temporary RTSS profile"));
        return false;
    }
    tmp.write(profileBytes);
    tmp.close();

    const QString cmdArgs = QStringLiteral("/c if not exist \"%1\" mkdir \"%1\" & copy /y \"%2\" \"%3\"")
                                .arg(QDir::toNativeSeparators(profilesDir), tempPath, destPath);
    const std::wstring wArgs = cmdArgs.toStdWString();

    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpVerb = L"runas";
    sei.lpFile = L"cmd.exe";
    sei.lpParameters = wArgs.c_str();
    sei.nShow = SW_HIDE;

    if (ShellExecuteExW(&sei)) {
        if (sei.hProcess) {
            WaitForSingleObject(sei.hProcess, 8000);
            CloseHandle(sei.hProcess);
        }
        QFile::remove(tempPath);
        refreshRtssStatus();
        if (m_rtssExcluded) {
            setStatus(QStringLiteral("RTSS exclusion applied via UAC"));
            return true;
        }
    } else {
        QFile::remove(tempPath);
    }

    setStatus(QStringLiteral("Could not write RTSS profile (UAC declined or denied)"));
    return false;
#else
    return false;
#endif
}

void GameModeService::setStatus(const QString& msg)
{
    if (m_lastStatus == msg)
        return;
    m_lastStatus = msg;
    emit lastStatusChanged();
}

void GameModeService::applyProcessPowerState(bool eco)
{
#ifdef Q_OS_WIN
    setEcoQosAndPriority(eco);
#else
    Q_UNUSED(eco)
#endif
}

void GameModeService::applyEffectiveState(const QString& reason)
{
    const bool wantHibernated = m_manualActive || (m_autoActive && m_mode == QStringLiteral("hibernate"));
    if (wantHibernated == m_hibernatedState)
        return;

    m_hibernatedState = wantHibernated;
    qInfo("GameModeService: %s (%s)", wantHibernated ? "ENTER HIBERNATE" : "EXIT HIBERNATE", qPrintable(reason));
    emit hibernateChanged(wantHibernated, reason);
    applyProcessPowerState(wantHibernated);
}

void GameModeService::setSpotlightOverride(bool open)
{
    if (m_spotlightOverride == open)
        return;
    m_spotlightOverride = open;
    if (m_hibernatedState) {
        if (open) {
            applyProcessPowerState(false);
        } else {
            applyProcessPowerState(true);
            emit spotlightHiddenWhileHibernated();
        }
    }
}

bool GameModeService::launchWaitGameAndExit(unsigned long targetPid, const QString& exeName)
{
#ifdef Q_OS_WIN
    if (m_zeroLaunching)
        return false;
    m_zeroLaunching = true;

    const QString exePath = QCoreApplication::applicationFilePath();
    const QString workDir = QCoreApplication::applicationDirPath();
    const QString cleanExe = exeName.trimmed().toLower();
    QString cmdLine = QStringLiteral("\"%1\" --wait-game=%2 --wait-exe=\"%3\"")
                          .arg(QDir::toNativeSeparators(exePath))
                          .arg(targetPid)
                          .arg(cleanExe);
    if (!m_instanceTag.isEmpty())
        cmdLine += QStringLiteral(" --instance=\"%1\"").arg(m_instanceTag);

    std::wstring wExe = QDir::toNativeSeparators(exePath).toStdWString();
    std::wstring wDir = QDir::toNativeSeparators(workDir).toStdWString();
    std::wstring wCmd = cmdLine.toStdWString();

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    if (!CreateProcessW(wExe.c_str(), wCmd.data(), nullptr, nullptr, FALSE,
                        DETACHED_PROCESS, nullptr, wDir.c_str(), &si, &pi)) {
        qWarning("GameModeService: CreateProcessW watchdog failed (err=%lu)", GetLastError());
        m_zeroLaunching = false;
        return false;
    }

    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);

    qInfo("GameModeService: Zero-Footprint handoff -> watchdog waiting for %s (pid=%lu)",
          qPrintable(cleanExe), targetPid);
    emit zeroFootprintRequested();
    return true;
#else
    Q_UNUSED(targetPid)
    Q_UNUSED(exeName)
    return false;
#endif
}

void GameModeService::pollForeground()
{
#ifdef Q_OS_WIN
    if (!m_autoDetect || m_zeroLaunching)
        return;
    if (m_spotlightOverride)
        return;

    HWND hwnd = GetForegroundWindow();
    DWORD pid = 0;
    QString exe;
    QString title;
    QString triggerReason;
    bool matched = false;

    if (hwnd) {
        GetWindowThreadProcessId(hwnd, &pid);
        if (pid != 0 && pid != GetCurrentProcessId()) {
            exe = queryProcessExeNameWin(pid);
            const bool isExcluded = (!exe.isEmpty() && m_excludeList.contains(exe));
            if (!isExcluded) {
                wchar_t classBuf[64]{};
                GetClassNameW(hwnd, classBuf, static_cast<int>(std::size(classBuf)));
                const QString cls = QString::fromWCharArray(classBuf);
                const bool isDesktopShell = (cls == QStringLiteral("Progman")
                    || cls == QStringLiteral("WorkerW")
                    || cls == QStringLiteral("Shell_TrayWnd"));

                if (!isDesktopShell) {
                    const QString displayExe = exe.isEmpty()
                        ? QStringLiteral("protected-game")
                        : exe;
                    if (!exe.isEmpty() && m_gameList.contains(exe)
                        && IsWindowVisible(hwnd) && !IsIconic(hwnd)) {
                        matched = true;
                        triggerReason = QStringLiteral("Game List (%1)").arg(displayExe);
                    } else if (isD3dExclusiveFullscreenActive()) {
                        matched = true;
                        triggerReason = QStringLiteral("D3D Fullscreen (%1)").arg(displayExe);
                    } else if (isWindowGenuineBorderlessFullscreen(hwnd)) {
                        matched = true;
                        triggerReason = QStringLiteral("Borderless Fullscreen (%1)").arg(displayExe);
                    }
                }
            }
        }
    }

    const QString displayExe = exe.isEmpty() ? QStringLiteral("protected-game") : exe;

    if (matched) {
        wchar_t titleBuf[256]{};
        int len = GetWindowTextW(hwnd, titleBuf, static_cast<int>(std::size(titleBuf)));
        title = (len > 0) ? QString::fromWCharArray(titleBuf, len).trimmed() : displayExe;

        m_clearMisses = 0;
        if (m_pendingPid == pid && m_pendingExe == displayExe) {
            ++m_pendingHits;
        } else {
            m_pendingPid = pid;
            m_pendingExe = displayExe;
            m_pendingTitle = title;
            m_pendingReason = triggerReason;
            m_pendingHits = 1;
        }

        // Require 2 consecutive ticks (~1.6s) before committing Game Mode.
        if (m_pendingHits >= 2) {
            if (m_mode == QStringLiteral("zero") && !m_manualActive) {
                if (launchWaitGameAndExit(pid, exe))
                    return;
            }
            if (!m_autoActive || m_activeGameExe != displayExe) {
                m_autoActive = true;
                m_activeGameExe = displayExe;
                m_activeGameTitle = title;
                m_activeReason = triggerReason;
                applyEffectiveState(triggerReason);
                emit activeChanged();
            }
        }
        return;
    }

    // No active game in foreground: keep checking if exclusive D3D fullscreen still holds.
    m_pendingHits = 0;
    if (m_autoActive) {
        if (isD3dExclusiveFullscreenActive()) {
            m_clearMisses = 0;
            return;
        }
        ++m_clearMisses;
        if (m_clearMisses >= 2) {
            m_autoActive = false;
            if (!m_manualActive) {
                m_activeGameExe.clear();
                m_activeGameTitle.clear();
                m_activeReason.clear();
            }
            applyEffectiveState(QStringLiteral("Game Inactive"));
            emit activeChanged();
        }
    }
#endif
}
