#include "TaskbarManager.h"

#include "core/SettingsStore.h"

#include <QDateTime>
#include <QMetaObject>
#include <QTimer>

#ifdef Q_OS_WIN
#include <dwmapi.h>
#include <shellapi.h>

#include <atomic>
#include <vector>

#ifndef ABS_AUTOHIDE
#define ABS_AUTOHIDE 0x00000001
#endif
#ifndef ABS_ALWAYSONTOP
#define ABS_ALWAYSONTOP 0x00000002
#endif
#ifndef ABM_GETSTATE
#define ABM_GETSTATE 0x00000004
#endif
#ifndef ABM_GETTASKBARPOS
#define ABM_GETTASKBARPOS 0x00000005
#endif
#ifndef ABM_SETSTATE
#define ABM_SETSTATE 0x0000000a
#endif
#ifndef ABE_BOTTOM
#define ABE_BOTTOM 3
#endif
#ifndef LWA_ALPHA
#define LWA_ALPHA 0x00000002
#endif
#ifndef WS_EX_LAYERED
#define WS_EX_LAYERED 0x00080000
#endif
#ifndef WS_EX_TOOLWINDOW
#define WS_EX_TOOLWINDOW 0x00000080
#endif
#ifndef WS_EX_TRANSPARENT
#define WS_EX_TRANSPARENT 0x00000020
#endif
#ifndef WS_EX_NOACTIVATE
#define WS_EX_NOACTIVATE 0x08000000L
#endif
#ifndef EVENT_OBJECT_SHOW
#define EVENT_OBJECT_SHOW 0x8002
#endif
#ifndef EVENT_OBJECT_UNCLOAKED
#define EVENT_OBJECT_UNCLOAKED 0x8018
#endif
#ifndef OBJID_WINDOW
#define OBJID_WINDOW 0
#endif
#ifndef CHILDID_SELF
#define CHILDID_SELF 0
#endif
#ifndef WINEVENT_OUTOFCONTEXT
#define WINEVENT_OUTOFCONTEXT 0x0000
#endif
#ifndef WINEVENT_SKIPOWNPROCESS
#define WINEVENT_SKIPOWNPROCESS 0x0002
#endif
#ifndef SPIF_SENDCHANGE
#define SPIF_SENDCHANGE 0x0002
#endif
#ifndef PROCESS_QUERY_LIMITED_INFORMATION
#define PROCESS_QUERY_LIMITED_INFORMATION 0x1000
#endif
#ifndef HSHELL_REDRAW
#define HSHELL_REDRAW 6
#endif
#ifndef HSHELL_FLASH
#define HSHELL_FLASH 0x8006
#endif

namespace {

constexpr LONG_PTR kManagedExBits =
    WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT;
constexpr UINT kWin11TaskbarStateMsg = 0x05CA;
constexpr wchar_t kWatcherClassName[] = L"SekaiDesk_TaskbarWatcher";
constexpr int kMaxAtomicSecondary = 16;

std::atomic<TaskbarManager*> g_activeInstance{nullptr};
std::atomic<bool> g_suppressedForCrash{false};
std::atomic<bool> g_bottomAppBarReserved{false};
std::atomic<bool> g_isWin11Build22400{false};
std::atomic<HWND> g_crashPrimaryTray{nullptr};
std::atomic<LONG_PTR> g_crashOrigPrimaryEx{0};
std::atomic<DWORD_PTR> g_crashOrigAbsState{ABS_ALWAYSONTOP};
std::atomic<int> g_crashSecCount{0};
std::atomic<HWND> g_crashSecTrays[kMaxAtomicSecondary]{};
std::atomic<LONG_PTR> g_crashSecOrigEx[kMaxAtomicSecondary]{};

int queryWindowsBuildNumber() noexcept
{
    using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (!ntdll)
        return 0;
    auto fn = reinterpret_cast<RtlGetVersionFn>(
        GetProcAddress(ntdll, "RtlGetVersion"));
    if (!fn)
        return 0;

    RTL_OSVERSIONINFOW info{};
    info.dwOSVersionInfoSize = sizeof(info);
    if (fn(&info) != 0)
        return 0;
    return static_cast<int>(info.dwBuildNumber);
}

bool tryGetLayeredAlpha(HWND hwnd, BYTE* outAlpha, DWORD* outFlags) noexcept
{
    using GetLayeredFn = BOOL(WINAPI*)(HWND, COLORREF*, BYTE*, DWORD*);
    static GetLayeredFn fn = []() -> GetLayeredFn {
        HMODULE u32 = GetModuleHandleW(L"user32.dll");
        return u32
            ? reinterpret_cast<GetLayeredFn>(
                  GetProcAddress(u32, "GetLayeredWindowAttributes"))
            : nullptr;
    }();
    if (!fn)
        return false;
    return fn(hwnd, nullptr, outAlpha, outFlags) != FALSE;
}

bool tryQueryProcessImageName(HANDLE hProc, wchar_t* buf, DWORD* size) noexcept
{
    using QueryFullNameFn = BOOL(WINAPI*)(HANDLE, DWORD, LPWSTR, PDWORD);
    static QueryFullNameFn fn = []() -> QueryFullNameFn {
        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        return k32
            ? reinterpret_cast<QueryFullNameFn>(
                  GetProcAddress(k32, "QueryFullProcessImageNameW"))
            : nullptr;
    }();
    if (!fn)
        return false;
    return fn(hProc, 0, buf, size) != FALSE;
}

bool equalsIgnoreCaseAscii(const wchar_t* a, const wchar_t* b) noexcept
{
    if (!a || !b)
        return false;
    return _wcsicmp(a, b) == 0;
}

void collectSecondaryTrays(std::vector<HWND>& out) noexcept
{
    out.clear();
    EnumWindows(
        [](HWND hwnd, LPARAM lParam) -> BOOL {
            wchar_t cls[64]{};
            if (GetClassNameW(hwnd, cls, 64) > 0 &&
                wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) {
                auto* vec = reinterpret_cast<std::vector<HWND>*>(lParam);
                vec->push_back(hwnd);
            }
            return TRUE;
        },
        reinterpret_cast<LPARAM>(&out));
}

void restoreHwndBasic(HWND hwnd, LONG_PTR origExStyle) noexcept
{
    if (!hwnd || !IsWindow(hwnd))
        return;

    const LONG_PTR curEx = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if ((curEx & WS_EX_LAYERED) != 0)
        SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    const LONG_PTR restoredEx =
        (curEx & ~kManagedExBits) | (origExStyle & kManagedExBits);
    if (restoredEx != curEx)
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, restoredEx);

    ShowWindowAsync(hwnd, SW_SHOWNA);
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                 SWP_SHOWWINDOW | SWP_ASYNCWINDOWPOS);
}

void applyAbsState(HWND hPrimary, DWORD_PTR absState, int winBuild) noexcept
{
    if (!hPrimary || !IsWindow(hPrimary))
        return;

    APPBARDATA abd{};
    abd.cbSize = sizeof(abd);
    abd.hWnd = hPrimary;
    abd.lParam = static_cast<LPARAM>(absState);
    SHAppBarMessage(ABM_SETSTATE, &abd);

    if (winBuild >= 22400) {
        const LPARAM autoHideFlag = (absState & ABS_AUTOHIDE) ? 1 : 0;
        PostMessageW(hPrimary, kWin11TaskbarStateMsg, 4, autoHideFlag);
    }
}

bool trayNeedsRestoreOutsideSession(HWND hwnd) noexcept
{
    if (!hwnd || !IsWindow(hwnd))
        return false;
    if (!IsWindowVisible(hwnd))
        return true;

    const LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if ((ex & WS_EX_TRANSPARENT) != 0)
        return true;

    if ((ex & WS_EX_LAYERED) != 0) {
        BYTE alpha = 255;
        DWORD flags = 0;
        if (tryGetLayeredAlpha(hwnd, &alpha, &flags) &&
            (flags & LWA_ALPHA) != 0 && alpha == 0) {
            return true;
        }
    }
    return false;
}

} // namespace
#endif // Q_OS_WIN

TaskbarManager::TaskbarManager(SettingsStore* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    if (m_settings) {
        m_settings->ensureLoaded();
        m_hideMode = sanitizeHideMode(
            m_settings->stringValue(QStringLiteral("taskbar.hideMode"),
                                    QStringLiteral("primary")));
        m_win11StrictHide =
            m_settings->boolValue(QStringLiteral("taskbar.win11StrictHide"), true);
    }

    m_watchdogTimer = new QTimer(this);
    m_watchdogTimer->setInterval(500);
    connect(m_watchdogTimer, &QTimer::timeout, this, &TaskbarManager::onWatchdogTick);

    m_reclaimTimer = new QTimer(this);
    m_reclaimTimer->setSingleShot(true);
    m_reclaimTimer->setInterval(300);
    connect(m_reclaimTimer, &QTimer::timeout,
            this, &TaskbarManager::checkAndReclaimWorkArea);

    m_reapplyDebounceTimer = new QTimer(this);
    m_reapplyDebounceTimer->setSingleShot(true);
    m_reapplyDebounceTimer->setInterval(20);
    connect(m_reapplyDebounceTimer, &QTimer::timeout, this, [this]() {
        applySuppressionPass(false);
    });

#ifdef Q_OS_WIN
    detectWindowsVersion();
    g_activeInstance.store(this, std::memory_order_release);
    createWatcherWindow();

    if (m_settings && m_settings->boolValue(QStringLiteral("taskbar.wasSuppressed"), false)) {
        m_origAbsState = static_cast<DWORD_PTR>(
            m_settings->intValue(QStringLiteral("taskbar.origAbsState"), ABS_ALWAYSONTOP));
        m_origPrimaryExStyle = static_cast<LONG_PTR>(
            m_settings->intValue(QStringLiteral("taskbar.origExStyle"), 0));
    }

    if (m_hideMode == QStringLiteral("off")) {
        if (m_settings && m_settings->boolValue(QStringLiteral("taskbar.wasSuppressed"), false)) {
            restoreAllSuppressed(true);
        }
    } else {
        applySuppressionPass(true);
        m_watchdogTimer->start();
    }
#endif
}

TaskbarManager::~TaskbarManager()
{
    prepareForExit();
#ifdef Q_OS_WIN
    removeWinEventHooks();
    destroyWatcherWindow();
    if (g_activeInstance.load(std::memory_order_acquire) == this)
        g_activeInstance.store(nullptr, std::memory_order_release);
#endif
}

QString TaskbarManager::sanitizeHideMode(const QString& raw)
{
    const QString low = raw.trimmed().toLower();
    if (low == QStringLiteral("all"))
        return QStringLiteral("all");
    if (low == QStringLiteral("off") || low == QStringLiteral("none") ||
        low == QStringLiteral("false") || low == QStringLiteral("show")) {
        return QStringLiteral("off");
    }
    // "primary", legacy alias "dock", or empty -> "primary"
    return QStringLiteral("primary");
}

bool TaskbarManager::isActive() const
{
    return m_hideMode != QStringLiteral("off") && !m_temporarilyShown;
}

QString TaskbarManager::statusText() const
{
    if (m_hideMode == QStringLiteral("off"))
        return QStringLiteral("Native taskbar visible");
    if (m_temporarilyShown)
        return QStringLiteral("Paused temporarily (Ctrl+Alt+T)");
    if (m_hideMode == QStringLiteral("all"))
        return QStringLiteral("Hidden on all displays");
    return QStringLiteral("Hidden on primary display");
}

void TaskbarManager::setHideMode(const QString& mode)
{
    const QString sanitized = sanitizeHideMode(mode);
    const bool wasActive = isActive();
    const bool modeChanged = (m_hideMode != sanitized);
    const bool tempChanged = m_temporarilyShown;

    m_hideMode = sanitized;
    m_temporarilyShown = false;

    if (m_settings) {
        m_settings->set(QStringLiteral("taskbar.hideMode"), m_hideMode);
    }

#ifdef Q_OS_WIN
    if (m_hideMode == QStringLiteral("off")) {
        m_watchdogTimer->stop();
        m_reclaimTimer->stop();
        m_reapplyDebounceTimer->stop();
        restoreAllSuppressed(true);
    } else {
        applySuppressionPass(true);
        if (!m_watchdogTimer->isActive())
            m_watchdogTimer->start();
    }
#endif

    if (modeChanged)
        emit hideModeChanged();
    if (tempChanged)
        emit temporarilyShownChanged();
    if (wasActive != isActive())
        emit activeChanged();
    emit statusTextChanged();
}

void TaskbarManager::setWin11StrictHide(bool on)
{
    if (m_win11StrictHide == on)
        return;
    m_win11StrictHide = on;
    if (m_settings)
        m_settings->set(QStringLiteral("taskbar.win11StrictHide"), m_win11StrictHide);
#ifdef Q_OS_WIN
    if (isActive())
        applySuppressionPass(true);
#endif
    emit win11StrictHideChanged();
}

void TaskbarManager::toggleTemporary()
{
    if (m_hideMode == QStringLiteral("off")) {
        // Already off; switch back to primary hidden cleanly when toggled via hotkey.
        setHideMode(QStringLiteral("primary"));
        return;
    }

    const bool wasActive = isActive();
    m_temporarilyShown = !m_temporarilyShown;

#ifdef Q_OS_WIN
    if (m_temporarilyShown) {
        m_watchdogTimer->stop();
        m_reclaimTimer->stop();
        m_reapplyDebounceTimer->stop();
        restoreAllSuppressed(true);
    } else {
        applySuppressionPass(true);
        if (!m_watchdogTimer->isActive())
            m_watchdogTimer->start();
    }
#endif

    emit temporarilyShownChanged();
    if (wasActive != isActive())
        emit activeChanged();
    emit statusTextChanged();
}

void TaskbarManager::restoreNow()
{
    if (m_hideMode == QStringLiteral("off")) {
#ifdef Q_OS_WIN
        // Allow manual recovery of externally stuck taskbar state even when already "off".
        m_watchdogTimer->stop();
        m_reclaimTimer->stop();
        m_reapplyDebounceTimer->stop();
        restoreAllSuppressed(true);
#endif
        if (m_temporarilyShown) {
            m_temporarilyShown = false;
            emit temporarilyShownChanged();
        }
        emit statusTextChanged();
        return;
    }
    setHideMode(QStringLiteral("off"));
}

void TaskbarManager::prepareForExit()
{
#ifdef Q_OS_WIN
    if (m_watchdogTimer)
        m_watchdogTimer->stop();
    if (m_reclaimTimer)
        m_reclaimTimer->stop();
    if (m_reapplyDebounceTimer)
        m_reapplyDebounceTimer->stop();

    const bool suppressedInSettings =
        m_settings && m_settings->boolValue(QStringLiteral("taskbar.wasSuppressed"), false);
    if (g_suppressedForCrash.load(std::memory_order_acquire) || suppressedInSettings ||
        !m_suppressedSecondaryStyles.isEmpty()) {
        restoreAllSuppressed(true);
        if (m_settings)
            m_settings->flush();
    }
#endif
}

void TaskbarManager::emergencyRestoreAll(SettingsStore* settings)
{
#ifdef Q_OS_WIN
    const int winBuild = queryWindowsBuildNumber();
    const bool wasSuppressed =
        settings && settings->boolValue(QStringLiteral("taskbar.wasSuppressed"), false);
    const bool hasOrigAbs =
        settings && settings->has(QStringLiteral("taskbar.origAbsState"));
    const DWORD_PTR origAbs = hasOrigAbs
        ? static_cast<DWORD_PTR>(
              settings->intValue(QStringLiteral("taskbar.origAbsState"), ABS_ALWAYSONTOP))
        : static_cast<DWORD_PTR>(ABS_ALWAYSONTOP);
    const LONG_PTR origPrimaryEx = settings
        ? static_cast<LONG_PTR>(settings->intValue(QStringLiteral("taskbar.origExStyle"), 0))
        : 0;

    std::vector<HWND> secondaryTrays;
    collectSecondaryTrays(secondaryTrays);
    for (HWND hSec : secondaryTrays) {
        if (wasSuppressed || trayNeedsRestoreOutsideSession(hSec))
            restoreHwndBasic(hSec, 0);
    }

    HWND hPrimary = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (hPrimary && (wasSuppressed || trayNeedsRestoreOutsideSession(hPrimary))) {
        restoreHwndBasic(hPrimary, origPrimaryEx);
        if (wasSuppressed || hasOrigAbs)
            applyAbsState(hPrimary, origAbs, winBuild);
    }

    g_suppressedForCrash.store(false, std::memory_order_release);

    if (settings) {
        settings->set(QStringLiteral("taskbar.wasSuppressed"), false);
        settings->flush();
    }
#else
    Q_UNUSED(settings);
#endif
}

void TaskbarManager::emergencyRestoreAllNoAlloc() noexcept
{
#ifdef Q_OS_WIN
    if (!g_suppressedForCrash.exchange(false, std::memory_order_acq_rel))
        return;

    const int secCount = qBound(0, g_crashSecCount.load(std::memory_order_acquire),
                                kMaxAtomicSecondary);
    for (int i = 0; i < secCount; ++i) {
        HWND hSec = g_crashSecTrays[i].load(std::memory_order_acquire);
        LONG_PTR ex = g_crashSecOrigEx[i].load(std::memory_order_acquire);
        restoreHwndBasic(hSec, ex);
    }

    HWND hPrimary = g_crashPrimaryTray.load(std::memory_order_acquire);
    if (hPrimary && IsWindow(hPrimary)) {
        restoreHwndBasic(hPrimary, g_crashOrigPrimaryEx.load(std::memory_order_acquire));
        const DWORD_PTR origAbs = g_crashOrigAbsState.load(std::memory_order_acquire);
        const int fakeBuild = g_isWin11Build22400.load(std::memory_order_acquire) ? 22400 : 0;
        applyAbsState(hPrimary, origAbs, fakeBuild);
    }
#endif
}

void TaskbarManager::setBottomAppBarReserved(bool reserved) noexcept
{
#ifdef Q_OS_WIN
    g_bottomAppBarReserved.store(reserved, std::memory_order_release);
#else
    Q_UNUSED(reserved);
#endif
}

bool TaskbarManager::isBottomAppBarReserved() noexcept
{
#ifdef Q_OS_WIN
    return g_bottomAppBarReserved.load(std::memory_order_acquire);
#else
    return false;
#endif
}

#ifdef Q_OS_WIN
void TaskbarManager::detectWindowsVersion()
{
    m_winBuild = queryWindowsBuildNumber();
    m_isWin11 = (m_winBuild >= 22000);
    g_isWin11Build22400.store(m_winBuild >= 22400, std::memory_order_release);
}

void TaskbarManager::createWatcherWindow()
{
    if (m_watcherHwnd)
        return;

    m_taskbarCreatedMsg = RegisterWindowMessageW(L"TaskbarCreated");
    m_shellHookMsg = RegisterWindowMessageW(L"SHELLHOOK");

    HINSTANCE hInst = GetModuleHandleW(nullptr);
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &TaskbarManager::watcherWndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = kWatcherClassName;
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        qWarning("TaskbarManager: RegisterClassExW failed (%lu)", GetLastError());
        return;
    }

    // Must be a hidden top-level WS_POPUP (never HWND_MESSAGE) to receive TaskbarCreated / WM_DISPLAYCHANGE.
    m_watcherHwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kWatcherClassName,
        L"SekaiDeskTaskbarWatcher",
        WS_POPUP,
        -32000, -32000, 0, 0,
        nullptr, nullptr, hInst, this);

    if (m_watcherHwnd) {
        m_shellHookRegistered = (RegisterShellHookWindow(m_watcherHwnd) != FALSE);
    } else {
        qWarning("TaskbarManager: CreateWindowExW watcher failed (%lu)", GetLastError());
    }
}

void TaskbarManager::destroyWatcherWindow()
{
    if (!m_watcherHwnd)
        return;
    if (m_shellHookRegistered) {
        DeregisterShellHookWindow(m_watcherHwnd);
        m_shellHookRegistered = false;
    }
    DestroyWindow(m_watcherHwnd);
    m_watcherHwnd = nullptr;
}

void TaskbarManager::installWinEventHooks(DWORD explorerPid)
{
    if (explorerPid == 0)
        return;
    if (m_hookedExplorerPid == explorerPid && m_showHook && m_uncloakHook)
        return;

    removeWinEventHooks();
    m_hookedExplorerPid = explorerPid;

    m_showHook = SetWinEventHook(
        EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW,
        nullptr, &TaskbarManager::winEventProc,
        explorerPid, 0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);

    m_uncloakHook = SetWinEventHook(
        EVENT_OBJECT_UNCLOAKED, EVENT_OBJECT_UNCLOAKED,
        nullptr, &TaskbarManager::winEventProc,
        explorerPid, 0,
        WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
}

void TaskbarManager::removeWinEventHooks()
{
    if (m_showHook) {
        UnhookWinEvent(m_showHook);
        m_showHook = nullptr;
    }
    if (m_uncloakHook) {
        UnhookWinEvent(m_uncloakHook);
        m_uncloakHook = nullptr;
    }
    m_hookedExplorerPid = 0;
}

bool TaskbarManager::isStartMenuOrSearchForeground()
{
    HWND fg = GetForegroundWindow();
    if (!fg)
        return false;

    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (pid == 0)
        return false;

    HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProc)
        return false;

    wchar_t fullPath[MAX_PATH]{};
    DWORD len = MAX_PATH;
    const bool ok = tryQueryProcessImageName(hProc, fullPath, &len);
    CloseHandle(hProc);
    if (!ok || len == 0)
        return false;

    const wchar_t* base = wcsrchr(fullPath, L'\\');
    base = base ? (base + 1) : fullPath;

    return equalsIgnoreCaseAscii(base, L"StartMenuExperienceHost.exe") ||
           equalsIgnoreCaseAscii(base, L"SearchHost.exe") ||
           equalsIgnoreCaseAscii(base, L"SearchApp.exe") ||
           equalsIgnoreCaseAscii(base, L"ShellExperienceHost.exe");
}

void TaskbarManager::applySuppressionPass(bool allowWorkAreaTimer)
{
    if (m_hideMode == QStringLiteral("off") || m_temporarilyShown)
        return;

    HWND hPrimary = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!hPrimary || !IsWindow(hPrimary))
        return;

    DWORD explorerPid = 0;
    GetWindowThreadProcessId(hPrimary, &explorerPid);
    installWinEventHooks(explorerPid);

    const bool wasAlreadySuppressed =
        (m_settings && m_settings->boolValue(QStringLiteral("taskbar.wasSuppressed"), false)) ||
        g_suppressedForCrash.load(std::memory_order_acquire);

    if (!wasAlreadySuppressed) {
        APPBARDATA getAbd{};
        getAbd.cbSize = sizeof(getAbd);
        getAbd.hWnd = hPrimary;
        m_origAbsState = static_cast<DWORD_PTR>(SHAppBarMessage(ABM_GETSTATE, &getAbd));

        const LONG_PTR ex = GetWindowLongPtrW(hPrimary, GWL_EXSTYLE);
        m_origPrimaryExStyle = (ex & kManagedExBits);

        if (m_settings) {
            m_settings->set(QStringLiteral("taskbar.origAbsState"),
                            static_cast<int>(m_origAbsState));
            m_settings->set(QStringLiteral("taskbar.origExStyle"),
                            static_cast<int>(m_origPrimaryExStyle));
            m_settings->set(QStringLiteral("taskbar.wasSuppressed"), true);
        }
    }

    // 1) Set system taskbar AppBar state to ABS_AUTOHIDE so Explorer releases edge work area.
    APPBARDATA currentAbd{};
    currentAbd.cbSize = sizeof(currentAbd);
    currentAbd.hWnd = hPrimary;
    const DWORD_PTR curAbs = static_cast<DWORD_PTR>(SHAppBarMessage(ABM_GETSTATE, &currentAbd));
    if ((curAbs & ABS_AUTOHIDE) == 0) {
        applyAbsState(hPrimary, ABS_AUTOHIDE, m_winBuild);
    } else if (m_winBuild >= 22400) {
        PostMessageW(hPrimary, kWin11TaskbarStateMsg, 4, 1);
    }

    // 2) Suppress primary taskbar out-of-process (no DLL injection).
    const bool strictHide = m_isWin11 ? m_win11StrictHide : true;
    suppressSingleTray(hPrimary, true, strictHide);

    // 3) Handle secondary monitors strictly according to hideMode ("primary" vs "all").
    std::vector<HWND> secondaryTrays;
    collectSecondaryTrays(secondaryTrays);

    if (m_hideMode == QStringLiteral("all")) {
        for (HWND hSec : secondaryTrays) {
            if (!hSec || !IsWindow(hSec))
                continue;
            const qulonglong key = reinterpret_cast<qulonglong>(hSec);
            if (!m_suppressedSecondaryStyles.contains(key)) {
                m_suppressedSecondaryStyles.insert(
                    key, GetWindowLongPtrW(hSec, GWL_EXSTYLE) & kManagedExBits);
            }
            if (m_winBuild >= 22400)
                PostMessageW(hSec, kWin11TaskbarStateMsg, 4, 1);
            suppressSingleTray(hSec, false, strictHide);
        }
    } else {
        // Switching back from "all" -> "primary": restore secondary trays only.
        for (auto it = m_suppressedSecondaryStyles.cbegin();
             it != m_suppressedSecondaryStyles.cend(); ++it) {
            HWND hSec = reinterpret_cast<HWND>(it.key());
            restoreSingleTray(hSec, it.value(), false);
        }
        m_suppressedSecondaryStyles.clear();
    }

    syncAtomicCrashState();

    if (allowWorkAreaTimer)
        m_reclaimTimer->start();
}

void TaskbarManager::suppressSingleTray(HWND hwnd, bool isPrimary, bool strictHide)
{
    Q_UNUSED(isPrimary);
    if (!hwnd || !IsWindow(hwnd))
        return;

    const LONG_PTR curEx = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    const bool needStyle = (curEx & kManagedExBits) != kManagedExBits;
    if (needStyle)
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, curEx | kManagedExBits);

    BYTE alpha = 255;
    DWORD flags = 0;
    const bool hasAlphaInfo = tryGetLayeredAlpha(hwnd, &alpha, &flags);
    if (needStyle || !hasAlphaInfo || (flags & LWA_ALPHA) == 0 || alpha != 0)
        SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);

    if (needStyle || (curEx & WS_EX_TOPMOST) != 0) {
        SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
    }

    if (strictHide && !isStartMenuOrSearchForeground() && IsWindowVisible(hwnd))
        ShowWindowAsync(hwnd, SW_HIDE);
}

void TaskbarManager::restoreSingleTray(HWND hwnd, LONG_PTR origExStyle, bool isPrimary)
{
    restoreHwndBasic(hwnd, origExStyle);
    if (!isPrimary && m_winBuild >= 22400 && hwnd && IsWindow(hwnd)) {
        const LPARAM autoHideFlag = (m_origAbsState & ABS_AUTOHIDE) ? 1 : 0;
        PostMessageW(hwnd, kWin11TaskbarStateMsg, 4, autoHideFlag);
    }
}

void TaskbarManager::restoreAllSuppressed(bool updateConfigFlag)
{
    const bool shouldRestoreAbsState =
        g_suppressedForCrash.load(std::memory_order_acquire) ||
        (m_settings &&
         (m_settings->boolValue(QStringLiteral("taskbar.wasSuppressed"), false) ||
          m_settings->has(QStringLiteral("taskbar.origAbsState"))));

    for (auto it = m_suppressedSecondaryStyles.cbegin();
         it != m_suppressedSecondaryStyles.cend(); ++it) {
        HWND hSec = reinterpret_cast<HWND>(it.key());
        restoreSingleTray(hSec, it.value(), false);
    }
    m_suppressedSecondaryStyles.clear();

    // Also recover any Shell_SecondaryTrayWnd left suppressed from an earlier crash.
    std::vector<HWND> secondaryTrays;
    collectSecondaryTrays(secondaryTrays);
    for (HWND hSec : secondaryTrays) {
        if (trayNeedsRestoreOutsideSession(hSec))
            restoreSingleTray(hSec, 0, false);
    }

    HWND hPrimary = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (hPrimary && IsWindow(hPrimary)) {
        restoreSingleTray(hPrimary, m_origPrimaryExStyle, true);
        if (shouldRestoreAbsState)
            applyAbsState(hPrimary, m_origAbsState, m_winBuild);
    }

    g_suppressedForCrash.store(false, std::memory_order_release);
    g_crashPrimaryTray.store(nullptr, std::memory_order_release);
    g_crashSecCount.store(0, std::memory_order_release);

    if (updateConfigFlag && m_settings)
        m_settings->set(QStringLiteral("taskbar.wasSuppressed"), false);
}

void TaskbarManager::syncAtomicCrashState()
{
    HWND hPrimary = FindWindowW(L"Shell_TrayWnd", nullptr);
    g_crashPrimaryTray.store(hPrimary, std::memory_order_release);
    g_crashOrigPrimaryEx.store(m_origPrimaryExStyle, std::memory_order_release);
    g_crashOrigAbsState.store(m_origAbsState, std::memory_order_release);

    int idx = 0;
    for (auto it = m_suppressedSecondaryStyles.cbegin();
         it != m_suppressedSecondaryStyles.cend() && idx < kMaxAtomicSecondary; ++it) {
        g_crashSecTrays[idx].store(reinterpret_cast<HWND>(it.key()),
                                   std::memory_order_release);
        g_crashSecOrigEx[idx].store(it.value(), std::memory_order_release);
        ++idx;
    }
    g_crashSecCount.store(idx, std::memory_order_release);
    g_suppressedForCrash.store(true, std::memory_order_release);
}

void TaskbarManager::checkAndReclaimWorkArea()
{
    if (!isActive())
        return;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastWorkAreaReclaimMs < 1500)
        return;

    HWND hPrimary = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!hPrimary || !IsWindow(hPrimary))
        return;

    APPBARDATA pos{};
    pos.cbSize = sizeof(pos);
    pos.hWnd = hPrimary;
    const UINT_PTR posOk = SHAppBarMessage(ABM_GETTASKBARPOS, &pos);
    if (!posOk || pos.uEdge != ABE_BOTTOM)
        return;

    auto reclaimBottomForHwnd = [this](HWND tray) -> bool {
        HMONITOR hMon = MonitorFromWindow(tray, MONITOR_DEFAULTTONEAREST);
        if (!hMon)
            return false;
        MONITORINFO mi{};
        mi.cbSize = sizeof(mi);
        if (!GetMonitorInfoW(hMon, &mi))
            return false;

        const LONG bottomGap = mi.rcMonitor.bottom - mi.rcWork.bottom;
        if (bottomGap > 0 && bottomGap <= 140) {
            RECT rcNew = mi.rcWork;
            // Extend ONLY the bottom edge so TopBar's top AppBar zone (rcWork.top) stays intact.
            rcNew.bottom = mi.rcMonitor.bottom;
            m_applyingWorkArea = true;
            const BOOL changed =
                SystemParametersInfoW(SPI_SETWORKAREA, 0, &rcNew, SPIF_SENDCHANGE);
            m_applyingWorkArea = false;
            return changed != FALSE;
        }
        return false;
    };

    bool anyChanged = false;
    // Skip primary bottom reclaim while SekaiDesk's own Bar AppBar is docked at bottom.
    if (!g_bottomAppBarReserved.load(std::memory_order_acquire))
        anyChanged = reclaimBottomForHwnd(hPrimary);
    if (m_hideMode == QStringLiteral("all")) {
        HMONITOR primaryMon = MonitorFromWindow(hPrimary, MONITOR_DEFAULTTOPRIMARY);
        for (auto it = m_suppressedSecondaryStyles.cbegin();
             it != m_suppressedSecondaryStyles.cend(); ++it) {
            HWND hSec = reinterpret_cast<HWND>(it.key());
            if (g_bottomAppBarReserved.load(std::memory_order_acquire)
                && MonitorFromWindow(hSec, MONITOR_DEFAULTTONEAREST) == primaryMon) {
                continue;
            }
            if (reclaimBottomForHwnd(hSec))
                anyChanged = true;
        }
    }

    if (anyChanged)
        m_lastWorkAreaReclaimMs = now;
}

void TaskbarManager::onWatchdogTick()
{
    if (!isActive())
        return;

    HWND hPrimary = FindWindowW(L"Shell_TrayWnd", nullptr);
    if (!hPrimary || !IsWindow(hPrimary))
        return;

    bool driftDetected = false;
    const LONG_PTR curEx = GetWindowLongPtrW(hPrimary, GWL_EXSTYLE);
    if ((curEx & kManagedExBits) != kManagedExBits)
        driftDetected = true;

    if (!driftDetected) {
        BYTE alpha = 255;
        DWORD flags = 0;
        if (!tryGetLayeredAlpha(hPrimary, &alpha, &flags) ||
            (flags & LWA_ALPHA) == 0 || alpha != 0) {
            driftDetected = true;
        }
    }

    const bool strictHide = m_isWin11 ? m_win11StrictHide : true;
    if (!driftDetected && strictHide && !isStartMenuOrSearchForeground() &&
        IsWindowVisible(hPrimary)) {
        driftDetected = true;
    }

    if (!driftDetected && m_hideMode == QStringLiteral("all")) {
        std::vector<HWND> secondaryTrays;
        collectSecondaryTrays(secondaryTrays);
        if (static_cast<int>(secondaryTrays.size()) != m_suppressedSecondaryStyles.size()) {
            driftDetected = true;
        } else {
            for (HWND hSec : secondaryTrays) {
                if ((GetWindowLongPtrW(hSec, GWL_EXSTYLE) & kManagedExBits) != kManagedExBits ||
                    (strictHide && !isStartMenuOrSearchForeground() && IsWindowVisible(hSec))) {
                    driftDetected = true;
                    break;
                }
            }
        }
    }

    if (driftDetected)
        applySuppressionPass(false);
}

LRESULT CALLBACK TaskbarManager::watcherWndProc(HWND hwnd, UINT msg,
                                                WPARAM wParam, LPARAM lParam)
{
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
        return TRUE;
    }

    auto* self = reinterpret_cast<TaskbarManager*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (!self)
        return DefWindowProcW(hwnd, msg, wParam, lParam);

    if (self->m_taskbarCreatedMsg != 0 && msg == self->m_taskbarCreatedMsg) {
        self->m_suppressedSecondaryStyles.clear();
        self->removeWinEventHooks();
        if (self->isActive()) {
            self->applySuppressionPass(true);
            QTimer::singleShot(250, self, [self]() {
                if (self->isActive())
                    self->applySuppressionPass(true);
            });
        }
        return 0;
    }

    if (self->m_shellHookMsg != 0 && msg == self->m_shellHookMsg) {
        if ((wParam == HSHELL_FLASH || wParam == HSHELL_REDRAW) && self->isActive() &&
            self->m_reapplyDebounceTimer && !self->m_reapplyDebounceTimer->isActive()) {
            self->m_reapplyDebounceTimer->start();
        }
        return 0;
    }

    switch (msg) {
    case WM_DISPLAYCHANGE:
        if (self->isActive()) {
            QTimer::singleShot(150, self, [self]() {
                if (self->isActive())
                    self->applySuppressionPass(true);
            });
        }
        return 0;

    case WM_SETTINGCHANGE:
        if (wParam == SPI_SETWORKAREA && !self->m_applyingWorkArea && self->isActive()) {
            self->m_reclaimTimer->start();
        }
        return 0;

    case WM_QUERYENDSESSION:
        return TRUE;

    case WM_ENDSESSION:
        if (wParam != FALSE)
            self->prepareForExit();
        return 0;

    default:
        break;
    }

    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void CALLBACK TaskbarManager::winEventProc(HWINEVENTHOOK /*hook*/, DWORD /*event*/,
                                           HWND hwnd, LONG idObject, LONG idChild,
                                           DWORD /*dwEventThread*/, DWORD /*dwmsEventTime*/)
{
    if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || !hwnd)
        return;

    TaskbarManager* self = g_activeInstance.load(std::memory_order_acquire);
    if (!self || !self->isActive())
        return;

    wchar_t cls[64]{};
    if (GetClassNameW(hwnd, cls, 64) <= 0)
        return;

    const bool isPrimaryTray = (wcscmp(cls, L"Shell_TrayWnd") == 0);
    const bool isSecondaryTray =
        !isPrimaryTray && (wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0);

    if (!isPrimaryTray && !(isSecondaryTray && self->m_hideMode == QStringLiteral("all")))
        return;

    // Immediately clamp alpha & style so zero frames flash before queued Qt re-apply runs.
    const LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if ((ex & kManagedExBits) != kManagedExBits)
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex | kManagedExBits);
    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);

    QMetaObject::invokeMethod(self, [self]() {
        if (self->isActive() && self->m_reapplyDebounceTimer &&
            !self->m_reapplyDebounceTimer->isActive()) {
            self->m_reapplyDebounceTimer->start();
        }
    }, Qt::QueuedConnection);
}
#endif // Q_OS_WIN
