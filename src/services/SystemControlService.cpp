#include "SystemControlService.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QGuiApplication>
#include <QHash>
#include <QHostAddress>
#include <QNetworkInterface>
#include <QProcess>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QWindow>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#if !defined(_WIN32_WINNT) || (_WIN32_WINNT < 0x0600)
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include <winsock2.h>
#include <ws2ipdef.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <commdlg.h>
#include <shellapi.h>
#include <thread>

#ifndef MOD_NOREPEAT
#define MOD_NOREPEAT 0x4000
#endif

#ifndef EVENT_OBJECT_UNCLOAKED
#define EVENT_OBJECT_UNCLOAKED 0x8018
#endif

namespace {
constexpr int kQuickPanelHotkeyId = 0x534B;
constexpr int kSpotlightHotkeyId = 0x534C;
constexpr int kClipboardHotkeyId = 0x5343;
constexpr UINT kLlAltSpaceMsg = WM_APP + 0x51;
constexpr UINT kLlQuickPanelMsg = WM_APP + 0x52;
constexpr UINT kLlVolMuteMsg = WM_APP + 0x53;
constexpr UINT kLlVolDownMsg = WM_APP + 0x54;
constexpr UINT kLlVolUpMsg = WM_APP + 0x56;

HWND s_hotkeyMsgHwnd = nullptr;
bool s_altSpaceDown = false;
bool s_ctrlAltADown = false;
bool s_volMuteDown = false;
bool s_volDownDown = false;
bool s_volUpDown = false;
HWINEVENTHOOK s_osdWinEventHook = nullptr;
HWINEVENTHOOK s_osdUncloakHook = nullptr;
bool s_suppressStockOsd = false;

bool isWin10StockOsdWindow(HWND hwnd)
{
    if (!hwnd || !IsWindow(hwnd))
        return false;

    wchar_t cls[64]{};
    if (GetClassNameW(hwnd, cls, 64) == 0 || wcscmp(cls, L"NativeHWNDHost") != 0)
        return false;

    if (GetWindowTextLengthW(hwnd) != 0)
        return false;

    const LONG_PTR exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if ((exStyle & WS_EX_TOOLWINDOW) == 0)
        return false;

    if (!FindWindowExW(hwnd, nullptr, L"DirectUIHWND", nullptr))
        return false;

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0 || pid == GetCurrentProcessId())
        return false;

    HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProc)
        return false;

    wchar_t exePath[MAX_PATH]{};
    DWORD sz = MAX_PATH;
    bool isShellHost = false;
    if (QueryFullProcessImageNameW(hProc, 0, exePath, &sz)) {
        const wchar_t* base = wcsrchr(exePath, L'\\');
        const wchar_t* name = base ? base + 1 : exePath;
        isShellHost = (_wcsicmp(name, L"explorer.exe") == 0
                       || _wcsicmp(name, L"ShellExperienceHost.exe") == 0);
    }
    CloseHandle(hProc);
    return isShellHost;
}

void hideStockOsdTree(HWND hwnd)
{
    if (!hwnd || !IsWindow(hwnd))
        return;
    if (HWND child = FindWindowExW(hwnd, nullptr, L"DirectUIHWND", nullptr))
        ShowWindowAsync(child, SW_HIDE);
    ShowWindowAsync(hwnd, SW_HIDE);
}

BOOL CALLBACK hideExistingStockOsdProc(HWND hwnd, LPARAM)
{
    if (IsWindowVisible(hwnd) && isWin10StockOsdWindow(hwnd))
        hideStockOsdTree(hwnd);
    return TRUE;
}

void CALLBACK osdWinEventProc(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG idObject,
                              LONG idChild, DWORD, DWORD)
{
    if (!s_suppressStockOsd
        || (event != EVENT_OBJECT_SHOW && event != EVENT_OBJECT_UNCLOAKED)) {
        return;
    }
    if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || !hwnd || !IsWindow(hwnd))
        return;

    HWND target = hwnd;
    wchar_t cls[64]{};
    if (GetClassNameW(hwnd, cls, 64) > 0 && wcscmp(cls, L"DirectUIHWND") == 0) {
        HWND parent = GetParent(hwnd);
        if (parent)
            target = parent;
    }
    if (isWin10StockOsdWindow(target))
        hideStockOsdTree(target);
}

LRESULT CALLBACK lowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode == HC_ACTION && lParam) {
        const auto* kb = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lParam);
        if ((kb->flags & LLKHF_INJECTED) == 0) {
            const bool isDown = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
            const bool isUp = (wParam == WM_KEYUP || wParam == WM_SYSKEYUP);
            const bool altDown = ((kb->flags & LLKHF_ALTDOWN) != 0)
                                 || ((GetAsyncKeyState(VK_MENU) & 0x8000) != 0);
            const bool ctrlDown = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
            const bool shiftDown = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
            const bool winDown = ((GetAsyncKeyState(VK_LWIN) & 0x8000) != 0)
                                || ((GetAsyncKeyState(VK_RWIN) & 0x8000) != 0);

            if (kb->vkCode == VK_SPACE) {
                if (isUp && s_altSpaceDown) {
                    s_altSpaceDown = false;
                    return 1;
                }
                if (isDown && altDown && !ctrlDown && !shiftDown && !winDown) {
                    if (!s_altSpaceDown) {
                        s_altSpaceDown = true;
                        // Cancel pending Alt menu activation (SC_KEYMENU) on Alt release.
                        INPUT in{};
                        in.type = INPUT_KEYBOARD;
                        in.ki.wVk = 0xFF;
                        in.ki.dwFlags = KEYEVENTF_KEYUP;
                        SendInput(1, &in, sizeof(INPUT));
                        if (s_hotkeyMsgHwnd)
                            PostMessageW(s_hotkeyMsgHwnd, kLlAltSpaceMsg, 0, 0);
                    }
                    return 1;
                }
            } else if (kb->vkCode == 'A') {
                if (isUp && s_ctrlAltADown) {
                    s_ctrlAltADown = false;
                    return 1;
                }
                if (isDown && ctrlDown && altDown && !shiftDown && !winDown) {
                    if (!s_ctrlAltADown) {
                        s_ctrlAltADown = true;
                        if (s_hotkeyMsgHwnd)
                            PostMessageW(s_hotkeyMsgHwnd, kLlQuickPanelMsg, 0, 0);
                    }
                    return 1;
                }
            } else if (kb->vkCode == VK_VOLUME_UP) {
                if (isUp && s_volUpDown) {
                    s_volUpDown = false;
                    return 1;
                }
                if (isDown && s_suppressStockOsd && s_hotkeyMsgHwnd) {
                    s_volUpDown = true;
                    PostMessageW(s_hotkeyMsgHwnd, kLlVolUpMsg, 0, 0);
                    return 1;
                }
            } else if (kb->vkCode == VK_VOLUME_DOWN) {
                if (isUp && s_volDownDown) {
                    s_volDownDown = false;
                    return 1;
                }
                if (isDown && s_suppressStockOsd && s_hotkeyMsgHwnd) {
                    s_volDownDown = true;
                    PostMessageW(s_hotkeyMsgHwnd, kLlVolDownMsg, 0, 0);
                    return 1;
                }
            } else if (kb->vkCode == VK_VOLUME_MUTE) {
                if (isUp && s_volMuteDown) {
                    s_volMuteDown = false;
                    return 1;
                }
                if (isDown && s_suppressStockOsd && s_hotkeyMsgHwnd) {
                    if (!s_volMuteDown) {
                        s_volMuteDown = true;
                        PostMessageW(s_hotkeyMsgHwnd, kLlVolMuteMsg, 0, 0);
                    }
                    return 1;
                }
            }
        }
    }
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

bool enableShutdownPrivilege()
{
    HANDLE hToken = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken))
        return false;
    LUID luid{};
    bool ok = false;
    if (LookupPrivilegeValueW(nullptr, SE_SHUTDOWN_NAME, &luid)) {
        TOKEN_PRIVILEGES tp{};
        tp.PrivilegeCount = 1;
        tp.Privileges[0].Luid = luid;
        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        ok = (AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(tp), nullptr, nullptr) != FALSE)
             && (GetLastError() == ERROR_SUCCESS);
    }
    CloseHandle(hToken);
    return ok;
}

struct PhysicalMonitor {
    HANDLE hPhysicalMonitor;
    WCHAR szPhysicalMonitorDescription[128];
};

using FnGetNumPhys = BOOL(WINAPI*)(HMONITOR, LPDWORD);
using FnGetPhys = BOOL(WINAPI*)(HMONITOR, DWORD, PhysicalMonitor*);
using FnDestroyPhys = BOOL(WINAPI*)(DWORD, PhysicalMonitor*);
using FnGetBright = BOOL(WINAPI*)(HANDLE, LPDWORD, LPDWORD, LPDWORD);
using FnSetBright = BOOL(WINAPI*)(HANDLE, DWORD);

struct Dxva2Api {
    HMODULE mod = nullptr;
    FnGetNumPhys getNum = nullptr;
    FnGetPhys getPhys = nullptr;
    FnDestroyPhys destroyPhys = nullptr;
    FnGetBright getBright = nullptr;
    FnSetBright setBright = nullptr;

    static const Dxva2Api& instance()
    {
        static Dxva2Api api = []() {
            Dxva2Api a;
            a.mod = LoadLibraryW(L"dxva2.dll");
            if (a.mod) {
                a.getNum = reinterpret_cast<FnGetNumPhys>(
                    GetProcAddress(a.mod, "GetNumberOfPhysicalMonitorsFromHMONITOR"));
                a.getPhys = reinterpret_cast<FnGetPhys>(
                    GetProcAddress(a.mod, "GetPhysicalMonitorsFromHMONITOR"));
                a.destroyPhys = reinterpret_cast<FnDestroyPhys>(
                    GetProcAddress(a.mod, "DestroyPhysicalMonitors"));
                a.getBright = reinterpret_cast<FnGetBright>(
                    GetProcAddress(a.mod, "GetMonitorBrightness"));
                a.setBright = reinterpret_cast<FnSetBright>(
                    GetProcAddress(a.mod, "SetMonitorBrightness"));
            }
            return a;
        }();
        return api;
    }

    bool valid() const
    {
        return getNum && getPhys && destroyPhys && getBright && setBright;
    }
};
} // namespace
#endif

SystemControlService::SystemControlService(QObject* parent)
    : QObject(parent)
{
#ifdef Q_OS_WIN
    m_startupTimer.start();
    if (QCoreApplication::instance())
        QCoreApplication::instance()->installNativeEventFilter(this);

    HWND msgHwnd = CreateWindowExW(0, L"STATIC", L"SekaiDeskHotkeyMsg", 0,
                                   0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                   GetModuleHandleW(nullptr), nullptr);
    m_hotkeyMsgHwnd = msgHwnd;
    s_hotkeyMsgHwnd = msgHwnd;

    HHOOK kbdHook = SetWindowsHookExW(WH_KEYBOARD_LL, lowLevelKeyboardProc,
                                      GetModuleHandleW(nullptr), 0);
    m_kbdHook = kbdHook;
    qInfo("SystemControlService: WH_KEYBOARD_LL hook (Alt+Space, Ctrl+Alt+A) %s",
          kbdHook ? "installed" : "failed");

    m_hotkeyRetryTimer.setInterval(5000);
    connect(&m_hotkeyRetryTimer, &QTimer::timeout, this, &SystemControlService::registerHotkeys);
    registerHotkeys();

    m_netSpeedTimer.setInterval(1000);
    connect(&m_netSpeedTimer, &QTimer::timeout, this, &SystemControlService::sampleNetSpeed);

    refresh();
#endif
}

SystemControlService::~SystemControlService()
{
#ifdef Q_OS_WIN
    applyStockOsdSuppression(false);
    m_suppressStockOsd = false;
    m_netSpeedTimer.stop();
    if (m_keepAwake) {
        SetThreadExecutionState(ES_CONTINUOUS);
        m_keepAwake = false;
    }
    m_hotkeyRetryTimer.stop();
    if (m_kbdHook) {
        UnhookWindowsHookEx(static_cast<HHOOK>(m_kbdHook));
        m_kbdHook = nullptr;
    }
    s_hotkeyMsgHwnd = nullptr;
    s_altSpaceDown = false;
    s_ctrlAltADown = false;
    s_volMuteDown = false;
    s_volDownDown = false;
    s_volUpDown = false;
    HWND msgHwnd = static_cast<HWND>(m_hotkeyMsgHwnd);
    if (m_hotkeyRegistered)
        UnregisterHotKey(msgHwnd, kQuickPanelHotkeyId);
    if (m_spotlightHotkeyRegistered)
        UnregisterHotKey(msgHwnd, kSpotlightHotkeyId);
    if (m_clipboardHotkeyRegistered)
        UnregisterHotKey(msgHwnd, kClipboardHotkeyId);
    if (msgHwnd) {
        DestroyWindow(msgHwnd);
        m_hotkeyMsgHwnd = nullptr;
    }
    if (QCoreApplication::instance())
        QCoreApplication::instance()->removeNativeEventFilter(this);
#endif
}

void SystemControlService::registerHotkeys()
{
#ifdef Q_OS_WIN
    HWND msgHwnd = static_cast<HWND>(m_hotkeyMsgHwnd);
    if (!m_hotkeyRegistered) {
        m_hotkeyRegistered = (RegisterHotKey(msgHwnd, kQuickPanelHotkeyId,
                                             MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'A') != FALSE);
        qInfo("SystemControlService: RegisterHotKey Ctrl+Alt+A %s",
              m_hotkeyRegistered ? "ok" : "pending");
    }
    if (!m_clipboardHotkeyRegistered) {
        m_clipboardHotkeyRegistered = (RegisterHotKey(msgHwnd, kClipboardHotkeyId,
                                                      MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'V') != FALSE);
        qInfo("SystemControlService: RegisterHotKey Ctrl+Alt+V %s",
              m_clipboardHotkeyRegistered ? "ok" : "pending");
    }
    if (!m_kbdHook && !m_spotlightHotkeyRegistered) {
        m_spotlightHotkeyRegistered = (RegisterHotKey(msgHwnd, kSpotlightHotkeyId,
                                                      MOD_ALT | MOD_NOREPEAT, VK_SPACE) != FALSE);
    }

    const bool needRetry = !m_hotkeyRegistered || !m_clipboardHotkeyRegistered
                           || (!m_kbdHook && !m_spotlightHotkeyRegistered);
    if (needRetry && !m_hotkeyRetryTimer.isActive())
        m_hotkeyRetryTimer.start();
    else if (!needRetry && m_hotkeyRetryTimer.isActive())
        m_hotkeyRetryTimer.stop();
#endif
}

void SystemControlService::triggerQuickPanelToggle()
{
    if (m_quickPanelToggleTimer.isValid() && m_quickPanelToggleTimer.elapsed() < 150)
        return;
    m_quickPanelToggleTimer.start();
    emit quickPanelToggleRequested();
}

bool SystemControlService::nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result)
{
    Q_UNUSED(result);
#ifdef Q_OS_WIN
    if (eventType == "windows_generic_MSG" || eventType == "windows_dispatcher_MSG") {
        const MSG* msg = static_cast<const MSG*>(message);
        if (msg && msg->hwnd == static_cast<HWND>(m_hotkeyMsgHwnd)) {
            if (msg->message == kLlAltSpaceMsg) {
                emit spotlightToggleRequested();
                return true;
            }
            if (msg->message == kLlQuickPanelMsg) {
                triggerQuickPanelToggle();
                return true;
            }
            if (msg->message == kLlVolUpMsg) {
                emit volumeStepRequested(2);
                return true;
            }
            if (msg->message == kLlVolDownMsg) {
                emit volumeStepRequested(-2);
                return true;
            }
            if (msg->message == kLlVolMuteMsg) {
                emit volumeMuteToggleRequested();
                return true;
            }
        }
        if (msg && msg->message == WM_HOTKEY) {
            const int id = static_cast<int>(msg->wParam);
            if (id == kQuickPanelHotkeyId) {
                triggerQuickPanelToggle();
                return true;
            }
            if (id == kSpotlightHotkeyId) {
                emit spotlightToggleRequested();
                return true;
            }
            if (id == kClipboardHotkeyId) {
                emit clipboardToggleRequested();
                return true;
            }
        }
    }
#else
    Q_UNUSED(eventType);
    Q_UNUSED(message);
#endif
    return false;
}

void SystemControlService::refresh()
{
    readBrightness();
    readDarkMode();
    readNetwork();
    emit stateChanged();
}

void SystemControlService::readNetwork()
{
    QString bestIp;
    QString bestType = QStringLiteral("Offline");
    const auto ifaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface& iface : ifaces) {
        const auto flags = iface.flags();
        if (!flags.testFlag(QNetworkInterface::IsUp)
            || !flags.testFlag(QNetworkInterface::IsRunning)
            || flags.testFlag(QNetworkInterface::IsLoopBack)) {
            continue;
        }
        const QString lname = iface.humanReadableName().toLower();
        if (lname.contains(QStringLiteral("vmware"))
            || lname.contains(QStringLiteral("virtualbox"))
            || lname.contains(QStringLiteral("vethernet"))
            || lname.contains(QStringLiteral("hyper-v"))
            || lname.contains(QStringLiteral("tailscale"))
            || lname.contains(QStringLiteral("radmin"))
            || lname.contains(QStringLiteral("zerotier"))
            || lname.contains(QStringLiteral("hamachi"))
            || lname.contains(QStringLiteral("wireguard"))
            || lname.contains(QStringLiteral("openvpn"))
            || lname.contains(QStringLiteral("wintun"))
            || lname.contains(QStringLiteral("loopback"))) {
            continue;
        }
        for (const QNetworkAddressEntry& entry : iface.addressEntries()) {
            const QHostAddress ip = entry.ip();
            if (ip.protocol() != QAbstractSocket::IPv4Protocol)
                continue;
            const QString ipStr = ip.toString();
            if (ipStr.startsWith(QStringLiteral("169.254.")))
                continue;
            bestIp = ipStr;
            bestType = (iface.type() == QNetworkInterface::Wifi)
                ? QStringLiteral("Wi-Fi")
                : QStringLiteral("Ethernet");
            break;
        }
        if (!bestIp.isEmpty() && bestType == QStringLiteral("Ethernet"))
            break;
    }
    m_localIp = bestIp;
    m_networkType = bestType;
}

void SystemControlService::readDarkMode()
{
#ifdef Q_OS_WIN
    QSettings reg(QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
                  QSettings::NativeFormat);
    m_darkMode = (reg.value(QStringLiteral("AppsUseLightTheme"), 0).toInt() == 0);
#endif
}

void SystemControlService::toggleDarkMode()
{
#ifdef Q_OS_WIN
    const int nextVal = m_darkMode ? 1 : 0;
    QSettings reg(QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
                  QSettings::NativeFormat);
    reg.setValue(QStringLiteral("AppsUseLightTheme"), nextVal);
    reg.setValue(QStringLiteral("SystemUsesLightTheme"), nextVal);
    reg.sync();
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                        reinterpret_cast<LPARAM>(L"ImmersiveColorSet"),
                        SMTO_ABORTIFHUNG, 500, nullptr);
    m_darkMode = (nextVal == 0);
    emit stateChanged();
    emit darkModeOsdRequested(m_darkMode);
#endif
}

#ifdef Q_OS_WIN
namespace {
QHash<QString, QString> friendlyNamesByGdiDevice()
{
    QHash<QString, QString> map;
    UINT32 numPaths = 0, numModes = 0;
    if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &numPaths, &numModes) != ERROR_SUCCESS
        || numPaths == 0) {
        return map;
    }
    QVector<DISPLAYCONFIG_PATH_INFO> paths(numPaths);
    QVector<DISPLAYCONFIG_MODE_INFO> modes(numModes);
    if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &numPaths, paths.data(), &numModes, modes.data(), nullptr) != ERROR_SUCCESS)
        return map;

    for (UINT32 i = 0; i < numPaths; ++i) {
        DISPLAYCONFIG_SOURCE_DEVICE_NAME srcName{};
        srcName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
        srcName.header.size = sizeof(srcName);
        srcName.header.adapterId = paths[i].sourceInfo.adapterId;
        srcName.header.id = paths[i].sourceInfo.id;
        if (DisplayConfigGetDeviceInfo(&srcName.header) != ERROR_SUCCESS)
            continue;

        DISPLAYCONFIG_TARGET_DEVICE_NAME tgtName{};
        tgtName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
        tgtName.header.size = sizeof(tgtName);
        tgtName.header.adapterId = paths[i].targetInfo.adapterId;
        tgtName.header.id = paths[i].targetInfo.id;
        if (DisplayConfigGetDeviceInfo(&tgtName.header) != ERROR_SUCCESS)
            continue;

        const QString gdi = QString::fromWCharArray(srcName.viewGdiDeviceName).trimmed();
        const QString friendly = QString::fromWCharArray(tgtName.monitorFriendlyDeviceName).trimmed();
        if (!gdi.isEmpty() && !friendly.isEmpty())
            map.insert(gdi.toUpper(), friendly);
    }
    return map;
}

BOOL CALLBACK collectMonitorsProc(HMONITOR hMon, HDC, LPRECT, LPARAM lParam)
{
    auto* list = reinterpret_cast<QVector<HMONITOR>*>(lParam);
    list->append(hMon);
    return TRUE;
}
} // namespace
#endif

void SystemControlService::readBrightness()
{
#ifdef Q_OS_WIN
    const bool wasInitialized = m_brightnessInitialized;
    const bool prevSupported = m_brightnessSupported;
    const int prevBrightness = m_brightness;

    m_brightnessSupported = false;
    m_monitorName.clear();
    m_monitors.clear();

    const auto& api = Dxva2Api::instance();
    if (!api.valid())
        return;

    QVector<HMONITOR> hmons;
    EnumDisplayMonitors(nullptr, nullptr, collectMonitorsProc, reinterpret_cast<LPARAM>(&hmons));
    const QHash<QString, QString> friendlyMap = friendlyNamesByGdiDevice();

    int idx = 0;
    for (HMONITOR hMon : hmons) {
        MONITORINFOEXW mi{};
        mi.cbSize = sizeof(mi);
        QString gdiName;
        if (GetMonitorInfoW(hMon, &mi))
            gdiName = QString::fromWCharArray(mi.szDevice).trimmed().toUpper();

        DWORD count = 0;
        if (!api.getNum(hMon, &count) || count == 0)
            continue;

        QVector<PhysicalMonitor> mons(static_cast<int>(count));
        if (!api.getPhys(hMon, count, mons.data()))
            continue;

        for (DWORD i = 0; i < count; ++i) {
            DWORD minB = 0, curB = 0, maxB = 100;
            if (api.getBright(mons[i].hPhysicalMonitor, &minB, &curB, &maxB) && maxB > minB) {
                const int pct = qBound(0, qRound((static_cast<double>(curB - minB) / (maxB - minB)) * 100.0), 100);
                QString name = friendlyMap.value(gdiName);
                if (name.isEmpty())
                    name = QString::fromWCharArray(mons[i].szPhysicalMonitorDescription).trimmed();
                if (name.isEmpty())
                    name = QStringLiteral("Display %1").arg(idx + 1);

                QVariantMap m;
                m.insert(QStringLiteral("index"), idx);
                m.insert(QStringLiteral("name"), name);
                m.insert(QStringLiteral("brightness"), pct);
                m_monitors.append(m);

                if (!m_brightnessSupported) {
                    m_brightnessSupported = true;
                    m_brightness = pct;
                    m_monitorName = name;
                }
                ++idx;
            }
        }
        api.destroyPhys(count, mons.data());
    }

    m_brightnessInitialized = true;
    if (wasInitialized && prevSupported && m_brightnessSupported && m_brightness != prevBrightness) {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        if ((!m_startupTimer.isValid() || m_startupTimer.elapsed() >= 800)
            && now - m_lastSelfBrightnessMs > 500) {
            emit brightnessOsdRequested(m_brightness);
        }
    }
#endif
}

void SystemControlService::setBrightness(int percent)
{
    setMonitorBrightness(0, percent);
}

void SystemControlService::setMonitorBrightness(int index, int percent)
{
#ifdef Q_OS_WIN
    const int clamped = qBound(0, percent, 100);
    const auto& api = Dxva2Api::instance();
    if (!api.valid())
        return;

    QVector<HMONITOR> hmons;
    EnumDisplayMonitors(nullptr, nullptr, collectMonitorsProc, reinterpret_cast<LPARAM>(&hmons));

    int curIdx = 0;
    for (HMONITOR hMon : hmons) {
        DWORD count = 0;
        if (!api.getNum(hMon, &count) || count == 0)
            continue;
        QVector<PhysicalMonitor> mons(static_cast<int>(count));
        if (!api.getPhys(hMon, count, mons.data()))
            continue;
        for (DWORD i = 0; i < count; ++i) {
            DWORD minB = 0, curB = 0, maxB = 100;
            if (api.getBright(mons[i].hPhysicalMonitor, &minB, &curB, &maxB) && maxB > minB) {
                if (curIdx == index) {
                    const DWORD target = minB + static_cast<DWORD>(qRound((clamped / 100.0) * (maxB - minB)));
                    api.setBright(mons[i].hPhysicalMonitor, target);
                    if (index < m_monitors.size()) {
                        QVariantMap m = m_monitors[index].toMap();
                        m.insert(QStringLiteral("brightness"), clamped);
                        m_monitors[index] = m;
                    }
                    if (index == 0)
                        m_brightness = clamped;
                }
                ++curIdx;
            }
        }
        api.destroyPhys(count, mons.data());
    }
    m_lastSelfBrightnessMs = QDateTime::currentMSecsSinceEpoch();
    emit stateChanged();
    if (index == 0)
        emit brightnessOsdRequested(clamped);
#else
    Q_UNUSED(index);
    Q_UNUSED(percent);
#endif
}

void SystemControlService::setDisplayMode(const QString& mode)
{
#ifdef Q_OS_WIN
    QString arg;
    if (mode == QStringLiteral("internal")) arg = QStringLiteral("/internal");
    else if (mode == QStringLiteral("clone")) arg = QStringLiteral("/clone");
    else if (mode == QStringLiteral("extend")) arg = QStringLiteral("/extend");
    else if (mode == QStringLiteral("external")) arg = QStringLiteral("/external");
    if (!arg.isEmpty())
        QProcess::startDetached(QStringLiteral("DisplaySwitch.exe"), { arg });
#else
    Q_UNUSED(mode);
#endif
}

void SystemControlService::openSettings(const QString& uri)
{
#ifdef Q_OS_WIN
    const std::wstring wUri = uri.toStdWString();
    ShellExecuteW(nullptr, L"open", wUri.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
#else
    Q_UNUSED(uri);
#endif
}

void SystemControlService::lockScreen()
{
#ifdef Q_OS_WIN
    LockWorkStation();
#endif
}

void SystemControlService::sleepPc()
{
#ifdef Q_OS_WIN
    using FnSetSuspendState = BOOLEAN(WINAPI*)(BOOLEAN, BOOLEAN, BOOLEAN);
    HMODULE powr = LoadLibraryW(L"powrprof.dll");
    auto pSuspend = powr ? reinterpret_cast<FnSetSuspendState>(GetProcAddress(powr, "SetSuspendState")) : nullptr;
    if (!pSuspend || !pSuspend(FALSE, FALSE, FALSE)) {
        QProcess::startDetached(QStringLiteral("rundll32.exe"),
                                { QStringLiteral("powrprof.dll,SetSuspendState"), QStringLiteral("0,1,0") });
    }
#endif
}

void SystemControlService::shutdownPc()
{
#ifdef Q_OS_WIN
    enableShutdownPrivilege();
    if (!ExitWindowsEx(EWX_POWEROFF | EWX_FORCEIFHUNG,
                       SHTDN_REASON_MAJOR_OTHER | SHTDN_REASON_MINOR_OTHER | SHTDN_REASON_FLAG_PLANNED)) {
        QProcess::startDetached(QStringLiteral("shutdown.exe"),
                                { QStringLiteral("/s"), QStringLiteral("/t"), QStringLiteral("0") });
    }
#endif
}

void SystemControlService::restartPc()
{
#ifdef Q_OS_WIN
    enableShutdownPrivilege();
    if (!ExitWindowsEx(EWX_REBOOT | EWX_FORCEIFHUNG,
                       SHTDN_REASON_MAJOR_OTHER | SHTDN_REASON_MINOR_OTHER | SHTDN_REASON_FLAG_PLANNED)) {
        QProcess::startDetached(QStringLiteral("shutdown.exe"),
                                { QStringLiteral("/r"), QStringLiteral("/t"), QStringLiteral("0") });
    }
#endif
}

void SystemControlService::hibernatePc()
{
#ifdef Q_OS_WIN
    enableShutdownPrivilege();
    using FnSetSuspendState = BOOLEAN(WINAPI*)(BOOLEAN, BOOLEAN, BOOLEAN);
    HMODULE powr = LoadLibraryW(L"powrprof.dll");
    auto pSuspend = powr ? reinterpret_cast<FnSetSuspendState>(GetProcAddress(powr, "SetSuspendState")) : nullptr;
    if (!pSuspend || !pSuspend(TRUE, FALSE, FALSE)) {
        QProcess::startDetached(QStringLiteral("shutdown.exe"), { QStringLiteral("/h") });
    }
#endif
}

void SystemControlService::signOut()
{
#ifdef Q_OS_WIN
    if (!ExitWindowsEx(EWX_LOGOFF | EWX_FORCEIFHUNG, 0)) {
        QProcess::startDetached(QStringLiteral("shutdown.exe"), { QStringLiteral("/l") });
    }
#endif
}

QString SystemControlService::pickImageFile(const QString& title)
{
#ifdef Q_OS_WIN
    using FnGetOpenFileNameW = BOOL(WINAPI*)(LPOPENFILENAMEW);
    HMODULE comdlg = LoadLibraryW(L"comdlg32.dll");
    auto pGetOpen = comdlg ? reinterpret_cast<FnGetOpenFileNameW>(GetProcAddress(comdlg, "GetOpenFileNameW")) : nullptr;
    if (!pGetOpen)
        return {};

    HWND ownerHwnd = nullptr;
    if (QWindow* fw = QGuiApplication::focusWindow()) {
        HWND h = reinterpret_cast<HWND>(fw->winId());
        if (h && IsWindow(h))
            ownerHwnd = h;
    }
    if (!ownerHwnd) {
        const auto wins = QGuiApplication::topLevelWindows();
        for (QWindow* w : wins) {
            if (!w || !w->isVisible())
                continue;
            HWND h = reinterpret_cast<HWND>(w->winId());
            if (h && IsWindow(h) && (GetWindowLongPtrW(h, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0) {
                ownerHwnd = h;
                break;
            }
        }
        if (!ownerHwnd) {
            for (QWindow* w : wins) {
                if (!w || !w->isVisible())
                    continue;
                HWND h = reinterpret_cast<HWND>(w->winId());
                if (h && IsWindow(h)) {
                    ownerHwnd = h;
                    break;
                }
            }
        }
    }
    HWND tempOwner = nullptr;
    if (!ownerHwnd) {
        tempOwner = CreateWindowExW(0, L"STATIC", L"SekaiDesk", WS_POPUP,
                                    0, 0, 0, 0, nullptr, nullptr,
                                    GetModuleHandleW(nullptr), nullptr);
        ownerHwnd = tempOwner;
    }

    wchar_t fileBuf[MAX_PATH * 4]{};
    const std::wstring wTitle = title.isEmpty() ? std::wstring(L"Select Image") : title.toStdWString();
    OPENFILENAMEW ofn{};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = ownerHwnd;
    ofn.lpstrFilter = L"Image Files (*.png;*.jpg;*.jpeg;*.webp)\0*.png;*.jpg;*.jpeg;*.webp\0All Files (*.*)\0*.*\0\0";
    ofn.lpstrFile = fileBuf;
    ofn.nMaxFile = static_cast<DWORD>(sizeof(fileBuf) / sizeof(wchar_t));
    ofn.lpstrTitle = wTitle.c_str();
    ofn.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    const BOOL ok = pGetOpen(&ofn);
    if (tempOwner)
        DestroyWindow(tempOwner);
    if (ok) {
        return QUrl::fromLocalFile(QString::fromWCharArray(fileBuf)).toString();
    }
#else
    Q_UNUSED(title);
#endif
    return {};
}

#ifdef Q_OS_WIN
namespace {
struct WlanIfaceInfo {
    GUID InterfaceGuid;
    WCHAR strInterfaceDescription[256];
    int isState;
};
struct WlanIfaceInfoList {
    DWORD dwNumberOfItems;
    DWORD dwIndex;
    WlanIfaceInfo InterfaceInfo[1];
};
struct WlanSsid {
    ULONG uSSIDLength;
    UCHAR ucSSID[32];
};
struct WlanAvailNet {
    WCHAR strProfileName[256];
    WlanSsid dot11Ssid;
    int dot11BssType;
    ULONG uNumberOfBssids;
    BOOL bNetworkConnectable;
    DWORD wlanNotConnectableReason;
    ULONG uNumberOfPhyTypes;
    int dot11PhyTypes[8];
    BOOL bMorePhyTypes;
    ULONG wlanSignalQuality;
    BOOL bSecurityEnabled;
    int dot11DefaultAuthAlgorithm;
    int dot11DefaultCipherAlgorithm;
    DWORD dwFlags;
    DWORD dwReserved;
};
struct WlanAvailNetList {
    DWORD dwNumberOfItems;
    DWORD dwIndex;
    WlanAvailNet Network[1];
};
struct WlanPhyRadioState {
    DWORD dwPhyIndex;
    int dot11SoftwareRadioState;
    int dot11HardwareRadioState;
};
struct WlanRadioState {
    DWORD dwNumberOfPhys;
    WlanPhyRadioState PhyRadioState[64];
};
struct WlanConnParams {
    int wlanConnectionMode;
    LPCWSTR strProfile;
    WlanSsid* pDot11Ssid;
    void* pDesiredBssidList;
    int dot11BssType;
    DWORD dwFlags;
};

struct BthRadioParams { DWORD dwSize; };
struct BthDeviceSearchParams {
    DWORD dwSize;
    BOOL fReturnAuthenticated;
    BOOL fReturnRemembered;
    BOOL fReturnUnknown;
    BOOL fReturnConnected;
    BOOL fIssueInquiry;
    UCHAR cTimeoutMultiplier;
    HANDLE hRadio;
};
struct BthDeviceInfo {
    DWORD dwSize;
    ULONGLONG Address;
    ULONG ulClassofDevice;
    BOOL fConnected;
    BOOL fRemembered;
    BOOL fAuthenticated;
    SYSTEMTIME stLastSeen;
    SYSTEMTIME stLastUsed;
    WCHAR szName[248];
};

// Lightweight WinRT Windows.Devices.Radios.Radio COM helper (no C++/WinRT headers needed)
namespace WinRtRadio {
inline void** vtbl(void* obj) { return *reinterpret_cast<void***>(obj); }
inline HRESULT qi(void* obj, const GUID& iid, void** out) {
    return reinterpret_cast<HRESULT(WINAPI*)(void*, const GUID*, void**)>(vtbl(obj)[0])(obj, &iid, out);
}
inline ULONG release(void* obj) {
    return obj ? reinterpret_cast<ULONG(WINAPI*)(void*)>(vtbl(obj)[2])(obj) : 0;
}

bool waitAsync(void* asyncOp, int timeoutMs = 2500) {
    static const GUID kIIDAsyncInfo = {0x00000036, 0x0000, 0x0000, {0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46}};
    void* info = nullptr;
    if (FAILED(qi(asyncOp, kIIDAsyncInfo, &info)) || !info)
        return false;
    auto pStatus = reinterpret_cast<HRESULT(WINAPI*)(void*, int*)>(vtbl(info)[7]);
    int status = 0;
    const DWORD start = GetTickCount();
    while (SUCCEEDED(pStatus(info, &status)) && status == 0) {
        if (static_cast<int>(GetTickCount() - start) >= timeoutMs)
            break;
        Sleep(10);
    }
    release(info);
    return status == 1; // AsyncStatus::Completed
}

template <typename Fn>
bool withRadios(Fn&& fn) {
    bool ok = false;
    std::thread worker([&]() {
        HMODULE combase = LoadLibraryW(L"combase.dll");
        if (!combase) return;
        using FnRoInit = HRESULT(WINAPI*)(int);
        using FnRoUninit = void(WINAPI*)();
        using FnRoFactory = HRESULT(WINAPI*)(void*, const GUID&, void**);
        using FnWinStrRef = HRESULT(WINAPI*)(PCWSTR, UINT32, void*, void**);

        auto pRoInit = reinterpret_cast<FnRoInit>(GetProcAddress(combase, "RoInitialize"));
        auto pRoUninit = reinterpret_cast<FnRoUninit>(GetProcAddress(combase, "RoUninitialize"));
        auto pRoFactory = reinterpret_cast<FnRoFactory>(GetProcAddress(combase, "RoGetActivationFactory"));
        auto pWinStrRef = reinterpret_cast<FnWinStrRef>(GetProcAddress(combase, "WindowsCreateStringReference"));
        if (!pRoInit || !pRoFactory || !pWinStrRef) return;

        const HRESULT hrInit = pRoInit(1 /*RO_INIT_MULTITHREADED*/);
        const bool didInit = SUCCEEDED(hrInit);

        static const GUID kIIDRadioStatics = {0x5FB6A12E, 0x67CB, 0x46AE, {0xAA,0xE9,0x65,0x91,0x9F,0x86,0xEF,0xF4}};
        alignas(8) unsigned char strHdr[32]{};
        void* hClass = nullptr;
        const wchar_t* cls = L"Windows.Devices.Radios.Radio";
        if (SUCCEEDED(pWinStrRef(cls, 28, strHdr, &hClass)) && hClass) {
            void* statics = nullptr;
            if (SUCCEEDED(pRoFactory(hClass, kIIDRadioStatics, &statics)) && statics) {
                void* op = nullptr;
                auto pGetRadios = reinterpret_cast<HRESULT(WINAPI*)(void*, void**)>(vtbl(statics)[6]);
                if (SUCCEEDED(pGetRadios(statics, &op)) && op) {
                    if (waitAsync(op)) {
                        void* list = nullptr;
                        auto pGetResults = reinterpret_cast<HRESULT(WINAPI*)(void*, void**)>(vtbl(op)[8]);
                        if (SUCCEEDED(pGetResults(op, &list)) && list) {
                            UINT32 count = 0;
                            auto pSize = reinterpret_cast<HRESULT(WINAPI*)(void*, UINT32*)>(vtbl(list)[7]);
                            auto pGetAt = reinterpret_cast<HRESULT(WINAPI*)(void*, UINT32, void**)>(vtbl(list)[6]);
                            if (SUCCEEDED(pSize(list, &count))) {
                                ok = true;
                                for (UINT32 i = 0; i < count; ++i) {
                                    void* radio = nullptr;
                                    if (SUCCEEDED(pGetAt(list, i, &radio)) && radio) {
                                        int kind = 0, state = 0;
                                        auto pGetKind = reinterpret_cast<HRESULT(WINAPI*)(void*, int*)>(vtbl(radio)[11]);
                                        auto pGetState = reinterpret_cast<HRESULT(WINAPI*)(void*, int*)>(vtbl(radio)[9]);
                                        if (SUCCEEDED(pGetKind(radio, &kind)) && SUCCEEDED(pGetState(radio, &state))) {
                                            fn(radio, kind, state);
                                        }
                                        release(radio);
                                    }
                                }
                            }
                            release(list);
                        }
                    }
                    release(op);
                }
                release(statics);
            }
        }
        if (didInit && pRoUninit) pRoUninit();
    });
    worker.join();
    return ok;
}

bool queryRadio(int targetKind, bool& supported, bool& enabled) {
    supported = false;
    enabled = false;
    return withRadios([&](void* /*radio*/, int kind, int state) {
        if (kind == targetKind) {
            supported = true;
            if (state == 1 /*RadioState::On*/)
                enabled = true;
        }
    });
}

bool setRadioState(int targetKind, int nextState) {
    bool changed = false;
    withRadios([&](void* radio, int kind, int /*state*/) {
        if (kind == targetKind) {
            void* setOp = nullptr;
            auto pSetState = reinterpret_cast<HRESULT(WINAPI*)(void*, int, void**)>(vtbl(radio)[6]);
            if (SUCCEEDED(pSetState(radio, nextState, &setOp)) && setOp) {
                if (waitAsync(setOp, 3000)) {
                    int accessStatus = 0;
                    auto pRes = reinterpret_cast<HRESULT(WINAPI*)(void*, int*)>(vtbl(setOp)[8]);
                    if (SUCCEEDED(pRes(setOp, &accessStatus)) && accessStatus == 1 /*Allowed*/)
                        changed = true;
                }
                release(setOp);
            }
        }
    });
    return changed;
}
} // namespace WinRtRadio
} // namespace
#endif

void SystemControlService::refreshWifi()
{
#ifdef Q_OS_WIN
    m_wifiSupported = false;
    m_wifiEnabled = false;
    m_wifiNetworks.clear();

    bool rtSupported = false;
    bool rtEnabled = false;
    if (WinRtRadio::queryRadio(1 /*WiFi*/, rtSupported, rtEnabled) && rtSupported) {
        m_wifiSupported = true;
        m_wifiEnabled = rtEnabled;
    }

    HMODULE mod = LoadLibraryW(L"wlanapi.dll");
    if (!mod) {
        emit wifiChanged();
        return;
    }
    using FnOpen = DWORD(WINAPI*)(DWORD, PVOID, PDWORD, PHANDLE);
    using FnClose = DWORD(WINAPI*)(HANDLE, PVOID);
    using FnEnum = DWORD(WINAPI*)(HANDLE, PVOID, WlanIfaceInfoList**);
    using FnFree = void(WINAPI*)(PVOID);
    using FnQuery = DWORD(WINAPI*)(HANDLE, const GUID*, int, PVOID, PDWORD, PVOID*, PVOID);
    using FnScan = DWORD(WINAPI*)(HANDLE, const GUID*, const WlanSsid*, PVOID, PVOID);
    using FnAvail = DWORD(WINAPI*)(HANDLE, const GUID*, DWORD, PVOID, WlanAvailNetList**);

    auto pOpen = reinterpret_cast<FnOpen>(GetProcAddress(mod, "WlanOpenHandle"));
    auto pClose = reinterpret_cast<FnClose>(GetProcAddress(mod, "WlanCloseHandle"));
    auto pEnum = reinterpret_cast<FnEnum>(GetProcAddress(mod, "WlanEnumInterfaces"));
    auto pFree = reinterpret_cast<FnFree>(GetProcAddress(mod, "WlanFreeMemory"));
    auto pQuery = reinterpret_cast<FnQuery>(GetProcAddress(mod, "WlanQueryInterface"));
    auto pScan = reinterpret_cast<FnScan>(GetProcAddress(mod, "WlanScan"));
    auto pAvail = reinterpret_cast<FnAvail>(GetProcAddress(mod, "WlanGetAvailableNetworkList"));
    if (!pOpen || !pClose || !pEnum || !pFree || !pAvail) {
        emit wifiChanged();
        return;
    }

    DWORD negVer = 0;
    HANDLE hClient = nullptr;
    if (pOpen(2, nullptr, &negVer, &hClient) != ERROR_SUCCESS || !hClient) {
        emit wifiChanged();
        return;
    }

    WlanIfaceInfoList* ifList = nullptr;
    if (pEnum(hClient, nullptr, &ifList) == ERROR_SUCCESS && ifList && ifList->dwNumberOfItems > 0) {
        m_wifiSupported = true;
        const GUID guid = ifList->InterfaceInfo[0].InterfaceGuid;
        if (!rtSupported && pQuery) {
            DWORD sz = 0;
            WlanRadioState* rs = nullptr;
            if (pQuery(hClient, &guid, 7 /*wlan_intf_opcode_radio_state*/, nullptr, &sz,
                       reinterpret_cast<PVOID*>(&rs), nullptr) == ERROR_SUCCESS && rs) {
                if (rs->dwNumberOfPhys > 0)
                    m_wifiEnabled = (rs->PhyRadioState[0].dot11SoftwareRadioState == 1);
                pFree(rs);
            }
        }

        if (m_wifiEnabled) {
            if (pScan)
                pScan(hClient, &guid, nullptr, nullptr, nullptr);
            WlanAvailNetList* nets = nullptr;
            if (pAvail(hClient, &guid, 0, nullptr, &nets) == ERROR_SUCCESS && nets) {
                QHash<QString, int> seenIdx;
                for (DWORD i = 0; i < nets->dwNumberOfItems; ++i) {
                    const WlanAvailNet& n = nets->Network[i];
                    if (n.dot11Ssid.uSSIDLength == 0)
                        continue;
                    const QString ssid = QString::fromUtf8(
                        reinterpret_cast<const char*>(n.dot11Ssid.ucSSID),
                        static_cast<int>(qMin<ULONG>(n.dot11Ssid.uSSIDLength, 32)));
                    const bool connected = (n.dwFlags & 0x1) != 0;
                    const QString profile = QString::fromWCharArray(n.strProfileName);
                    const int sig = static_cast<int>(n.wlanSignalQuality);
                    if (seenIdx.contains(ssid)) {
                        const int idx = seenIdx.value(ssid);
                        QVariantMap old = m_wifiNetworks[idx].toMap();
                        if (connected || sig > old.value(QStringLiteral("signal")).toInt()) {
                            old.insert(QStringLiteral("signal"), sig);
                            old.insert(QStringLiteral("connected"), connected || old.value(QStringLiteral("connected")).toBool());
                            if (!profile.isEmpty())
                                old.insert(QStringLiteral("profile"), profile);
                            m_wifiNetworks[idx] = old;
                        }
                        continue;
                    }
                    QVariantMap m;
                    m.insert(QStringLiteral("ssid"), ssid);
                    m.insert(QStringLiteral("profile"), profile);
                    m.insert(QStringLiteral("signal"), sig);
                    m.insert(QStringLiteral("secured"), n.bSecurityEnabled != FALSE);
                    m.insert(QStringLiteral("connected"), connected);
                    seenIdx.insert(ssid, m_wifiNetworks.size());
                    m_wifiNetworks.append(m);
                }
                pFree(nets);
            }
        }
        pFree(ifList);
    }
    pClose(hClient, nullptr);
    emit wifiChanged();
#endif
}

void SystemControlService::toggleWifi()
{
#ifdef Q_OS_WIN
    const int nextState = m_wifiEnabled ? 2 /*Off*/ : 1 /*On*/;
    if (!WinRtRadio::setRadioState(1 /*WiFi*/, nextState)) {
        HMODULE mod = LoadLibraryW(L"wlanapi.dll");
        if (mod) {
            using FnOpen = DWORD(WINAPI*)(DWORD, PVOID, PDWORD, PHANDLE);
            using FnClose = DWORD(WINAPI*)(HANDLE, PVOID);
            using FnEnum = DWORD(WINAPI*)(HANDLE, PVOID, WlanIfaceInfoList**);
            using FnFree = void(WINAPI*)(PVOID);
            using FnSet = DWORD(WINAPI*)(HANDLE, const GUID*, int, DWORD, PVOID, PVOID);

            auto pOpen = reinterpret_cast<FnOpen>(GetProcAddress(mod, "WlanOpenHandle"));
            auto pClose = reinterpret_cast<FnClose>(GetProcAddress(mod, "WlanCloseHandle"));
            auto pEnum = reinterpret_cast<FnEnum>(GetProcAddress(mod, "WlanEnumInterfaces"));
            auto pFree = reinterpret_cast<FnFree>(GetProcAddress(mod, "WlanFreeMemory"));
            auto pSet = reinterpret_cast<FnSet>(GetProcAddress(mod, "WlanSetInterface"));
            if (pOpen && pClose && pEnum && pFree && pSet) {
                DWORD negVer = 0;
                HANDLE hClient = nullptr;
                if (pOpen(2, nullptr, &negVer, &hClient) == ERROR_SUCCESS && hClient) {
                    WlanIfaceInfoList* ifList = nullptr;
                    if (pEnum(hClient, nullptr, &ifList) == ERROR_SUCCESS && ifList && ifList->dwNumberOfItems > 0) {
                        const GUID guid = ifList->InterfaceInfo[0].InterfaceGuid;
                        WlanPhyRadioState prs{};
                        prs.dwPhyIndex = 0;
                        prs.dot11SoftwareRadioState = static_cast<DWORD>(nextState);
                        pSet(hClient, &guid, 7 /*wlan_intf_opcode_radio_state*/, sizeof(prs), &prs, nullptr);
                        pFree(ifList);
                    }
                    pClose(hClient, nullptr);
                }
            }
        }
    }
    refreshWifi();
    if (nextState == 1)
        QTimer::singleShot(700, this, &SystemControlService::refreshWifi);
#endif
}

void SystemControlService::connectWifi(const QString& ssid)
{
#ifdef Q_OS_WIN
    if (ssid.isEmpty())
        return;
    HMODULE mod = LoadLibraryW(L"wlanapi.dll");
    if (!mod)
        return;
    using FnOpen = DWORD(WINAPI*)(DWORD, PVOID, PDWORD, PHANDLE);
    using FnClose = DWORD(WINAPI*)(HANDLE, PVOID);
    using FnEnum = DWORD(WINAPI*)(HANDLE, PVOID, WlanIfaceInfoList**);
    using FnFree = void(WINAPI*)(PVOID);
    using FnConnect = DWORD(WINAPI*)(HANDLE, const GUID*, const WlanConnParams*, PVOID);

    auto pOpen = reinterpret_cast<FnOpen>(GetProcAddress(mod, "WlanOpenHandle"));
    auto pClose = reinterpret_cast<FnClose>(GetProcAddress(mod, "WlanCloseHandle"));
    auto pEnum = reinterpret_cast<FnEnum>(GetProcAddress(mod, "WlanEnumInterfaces"));
    auto pFree = reinterpret_cast<FnFree>(GetProcAddress(mod, "WlanFreeMemory"));
    auto pConn = reinterpret_cast<FnConnect>(GetProcAddress(mod, "WlanConnect"));
    if (!pOpen || !pClose || !pEnum || !pFree || !pConn)
        return;

    DWORD negVer = 0;
    HANDLE hClient = nullptr;
    if (pOpen(2, nullptr, &negVer, &hClient) != ERROR_SUCCESS || !hClient)
        return;
    WlanIfaceInfoList* ifList = nullptr;
    if (pEnum(hClient, nullptr, &ifList) == ERROR_SUCCESS && ifList && ifList->dwNumberOfItems > 0) {
        const GUID guid = ifList->InterfaceInfo[0].InterfaceGuid;
        const std::wstring wProfile = ssid.toStdWString();
        WlanConnParams cp{};
        cp.wlanConnectionMode = 0; // wlan_connection_mode_profile
        cp.strProfile = wProfile.c_str();
        cp.dot11BssType = 1; // dot11_BSS_type_infrastructure
        pConn(hClient, &guid, &cp, nullptr);
        pFree(ifList);
    }
    pClose(hClient, nullptr);
    refreshWifi();
#else
    Q_UNUSED(ssid);
#endif
}

void SystemControlService::refreshBluetooth()
{
#ifdef Q_OS_WIN
    m_bluetoothSupported = false;
    m_bluetoothEnabled = false;
    m_bluetoothDevices.clear();

    bool rtSupported = false;
    bool rtEnabled = false;
    if (WinRtRadio::queryRadio(3 /*Bluetooth*/, rtSupported, rtEnabled) && rtSupported) {
        m_bluetoothSupported = true;
        m_bluetoothEnabled = rtEnabled;
    }

    HMODULE mod = LoadLibraryW(L"bthprops.cpl");
    if (!mod)
        mod = LoadLibraryW(L"BluetoothAPIs.dll");
    if (!mod) {
        emit bluetoothChanged();
        return;
    }

    using FnFindFirstRadio = HANDLE(WINAPI*)(const BthRadioParams*, HANDLE*);
    using FnFindRadioClose = BOOL(WINAPI*)(HANDLE);
    using FnIsConn = BOOL(WINAPI*)(HANDLE);
    using FnFindFirstDev = HANDLE(WINAPI*)(const BthDeviceSearchParams*, BthDeviceInfo*);
    using FnFindNextDev = BOOL(WINAPI*)(HANDLE, BthDeviceInfo*);
    using FnFindDevClose = BOOL(WINAPI*)(HANDLE);

    auto pFirstRadio = reinterpret_cast<FnFindFirstRadio>(GetProcAddress(mod, "BluetoothFindFirstRadio"));
    auto pCloseRadio = reinterpret_cast<FnFindRadioClose>(GetProcAddress(mod, "BluetoothFindRadioClose"));
    auto pIsConn = reinterpret_cast<FnIsConn>(GetProcAddress(mod, "BluetoothIsConnectable"));
    auto pFirstDev = reinterpret_cast<FnFindFirstDev>(GetProcAddress(mod, "BluetoothFindFirstDevice"));
    auto pNextDev = reinterpret_cast<FnFindNextDev>(GetProcAddress(mod, "BluetoothFindNextDevice"));
    auto pCloseDev = reinterpret_cast<FnFindDevClose>(GetProcAddress(mod, "BluetoothFindDeviceClose"));

    if (!rtSupported && pFirstRadio && pCloseRadio) {
        BthRadioParams rp{ sizeof(BthRadioParams) };
        HANDLE hRadio = nullptr;
        HANDLE hFind = pFirstRadio(&rp, &hRadio);
        if (hFind) {
            m_bluetoothSupported = true;
            if (hRadio) {
                m_bluetoothEnabled = pIsConn ? (pIsConn(hRadio) != FALSE) : true;
                CloseHandle(hRadio);
            }
            pCloseRadio(hFind);
        }
    }

    if (m_bluetoothSupported && m_bluetoothEnabled && pFirstDev && pNextDev && pCloseDev) {
        BthDeviceSearchParams sp{};
        sp.dwSize = sizeof(sp);
        sp.fReturnAuthenticated = TRUE;
        sp.fReturnRemembered = TRUE;
        sp.fReturnConnected = TRUE;
        sp.fReturnUnknown = FALSE;
        sp.fIssueInquiry = FALSE;
        BthDeviceInfo di{};
        di.dwSize = sizeof(di);
        HANDLE hDev = pFirstDev(&sp, &di);
        if (hDev) {
            do {
                const QString name = QString::fromWCharArray(di.szName).trimmed();
                if (!name.isEmpty()) {
                    QVariantMap m;
                    m.insert(QStringLiteral("name"), name);
                    m.insert(QStringLiteral("connected"), di.fConnected != FALSE);
                    m_bluetoothDevices.append(m);
                }
                di.dwSize = sizeof(di);
            } while (pNextDev(hDev, &di));
            pCloseDev(hDev);
        }
    }
    emit bluetoothChanged();
#endif
}

void SystemControlService::toggleBluetooth()
{
#ifdef Q_OS_WIN
    const int nextState = m_bluetoothEnabled ? 2 /*Off*/ : 1 /*On*/;
    if (!WinRtRadio::setRadioState(3 /*Bluetooth*/, nextState)) {
        HMODULE mod = LoadLibraryW(L"bthprops.cpl");
        if (!mod)
            mod = LoadLibraryW(L"BluetoothAPIs.dll");
        if (mod) {
            using FnFindFirstRadio = HANDLE(WINAPI*)(const BthRadioParams*, HANDLE*);
            using FnFindRadioClose = BOOL(WINAPI*)(HANDLE);
            using FnEnIn = BOOL(WINAPI*)(HANDLE, BOOL);
            using FnEnDisc = BOOL(WINAPI*)(HANDLE, BOOL);
            auto pFirstRadio = reinterpret_cast<FnFindFirstRadio>(GetProcAddress(mod, "BluetoothFindFirstRadio"));
            auto pCloseRadio = reinterpret_cast<FnFindRadioClose>(GetProcAddress(mod, "BluetoothFindRadioClose"));
            auto pEnIn = reinterpret_cast<FnEnIn>(GetProcAddress(mod, "BluetoothEnableIncomingConnections"));
            auto pEnDisc = reinterpret_cast<FnEnDisc>(GetProcAddress(mod, "BluetoothEnableDiscovery"));
            if (pFirstRadio && pCloseRadio) {
                BthRadioParams rp{ sizeof(BthRadioParams) };
                HANDLE hRadio = nullptr;
                HANDLE hFind = pFirstRadio(&rp, &hRadio);
                if (hFind) {
                    if (hRadio) {
                        const BOOL nextOn = (nextState == 1) ? TRUE : FALSE;
                        if (pEnDisc) pEnDisc(hRadio, nextOn);
                        if (pEnIn) pEnIn(hRadio, nextOn);
                        CloseHandle(hRadio);
                    }
                    pCloseRadio(hFind);
                }
            }
        }
    }
    refreshBluetooth();
    if (nextState == 1)
        QTimer::singleShot(450, this, &SystemControlService::refreshBluetooth);
#endif
}

void SystemControlService::setNetSpeedActive(bool active)
{
#ifdef Q_OS_WIN
    if (m_netSpeedActive == active)
        return;
    m_netSpeedActive = active;
    if (active) {
        m_hasNetBaseline = false;
        sampleNetSpeed();
        m_netSpeedTimer.start();
    } else {
        m_netSpeedTimer.stop();
        m_hasNetBaseline = false;
        if (!qFuzzyIsNull(m_downloadBps) || !qFuzzyIsNull(m_uploadBps)) {
            m_downloadBps = 0.0;
            m_uploadBps = 0.0;
            emit netSpeedChanged();
        }
    }
#else
    Q_UNUSED(active);
#endif
}

void SystemControlService::sampleNetSpeed()
{
#ifdef Q_OS_WIN
    PMIB_IF_TABLE2 table = nullptr;
    if (GetIfTable2(&table) != NO_ERROR || !table)
        return;

    quint64 totalRx = 0;
    quint64 totalTx = 0;
    for (ULONG i = 0; i < table->NumEntries; ++i) {
        const MIB_IF_ROW2& row = table->Table[i];
        if (row.Type == IF_TYPE_SOFTWARE_LOOPBACK)
            continue;
        if (row.Type != IF_TYPE_ETHERNET_CSMACD && row.Type != IF_TYPE_IEEE80211)
            continue;
        if (row.MediaConnectState != MediaConnectStateConnected || row.OperStatus != IfOperStatusUp)
            continue;
        if (row.InterfaceAndOperStatusFlags.FilterInterface)
            continue;

        const QString desc = QString::fromWCharArray(row.Description).toLower();
        if (desc.contains(QStringLiteral("vmware"))
            || desc.contains(QStringLiteral("virtualbox"))
            || desc.contains(QStringLiteral("vethernet"))
            || desc.contains(QStringLiteral("hyper-v"))
            || desc.contains(QStringLiteral("tailscale"))
            || desc.contains(QStringLiteral("radmin"))
            || desc.contains(QStringLiteral("zerotier"))
            || desc.contains(QStringLiteral("hamachi"))
            || desc.contains(QStringLiteral("wireguard"))
            || desc.contains(QStringLiteral("openvpn"))
            || desc.contains(QStringLiteral("wintun"))
            || desc.contains(QStringLiteral("loopback"))
            || desc.contains(QStringLiteral("qos"))
            || desc.contains(QStringLiteral("lightweight filter"))
            || desc.contains(QStringLiteral("wfp"))
            || desc.contains(QStringLiteral("npcap"))) {
            continue;
        }
        totalRx += static_cast<quint64>(row.InOctets);
        totalTx += static_cast<quint64>(row.OutOctets);
    }
    FreeMibTable(table);

    if (!m_hasNetBaseline) {
        m_prevRxBytes = totalRx;
        m_prevTxBytes = totalTx;
        m_netElapsed.restart();
        m_hasNetBaseline = true;
        return;
    }

    const qint64 elapsedMs = m_netElapsed.restart();
    if (elapsedMs <= 0)
        return;

    const double sec = static_cast<double>(elapsedMs) / 1000.0;
    const qreal nextDl = (totalRx >= m_prevRxBytes) ? static_cast<qreal>(totalRx - m_prevRxBytes) / sec : 0.0;
    const qreal nextUl = (totalTx >= m_prevTxBytes) ? static_cast<qreal>(totalTx - m_prevTxBytes) / sec : 0.0;
    m_prevRxBytes = totalRx;
    m_prevTxBytes = totalTx;

    if (!qFuzzyCompare(nextDl + 1.0, m_downloadBps + 1.0)
        || !qFuzzyCompare(nextUl + 1.0, m_uploadBps + 1.0)) {
        m_downloadBps = nextDl;
        m_uploadBps = nextUl;
        emit netSpeedChanged();
    }
#endif
}

void SystemControlService::toggleKeepAwake()
{
#ifdef Q_OS_WIN
    const bool next = !m_keepAwake;
    const EXECUTION_STATE flags = next
        ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED)
        : ES_CONTINUOUS;
    if (SetThreadExecutionState(flags) != 0) {
        m_keepAwake = next;
        emit keepAwakeChanged();
    }
#endif
}

void SystemControlService::applyStockOsdSuppression(bool on)
{
#ifdef Q_OS_WIN
    s_suppressStockOsd = on;
    if (on) {
        if (!s_osdWinEventHook) {
            s_osdWinEventHook = SetWinEventHook(
                EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW,
                nullptr, osdWinEventProc, 0, 0,
                WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        }
        if (!s_osdUncloakHook) {
            s_osdUncloakHook = SetWinEventHook(
                EVENT_OBJECT_UNCLOAKED, EVENT_OBJECT_UNCLOAKED,
                nullptr, osdWinEventProc, 0, 0,
                WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        }
        EnumWindows(hideExistingStockOsdProc, 0);
    } else {
        if (s_osdWinEventHook) {
            UnhookWinEvent(s_osdWinEventHook);
            s_osdWinEventHook = nullptr;
        }
        if (s_osdUncloakHook) {
            UnhookWinEvent(s_osdUncloakHook);
            s_osdUncloakHook = nullptr;
        }
    }
#else
    Q_UNUSED(on);
#endif
}

void SystemControlService::setSuppressStockOsd(bool on)
{
    if (m_suppressStockOsd == on)
        return;
    m_suppressStockOsd = on;
    applyStockOsdSuppression(on);
    emit suppressStockOsdChanged();
}

void SystemControlService::hideStockOsdIfActive()
{
#ifdef Q_OS_WIN
    if (m_suppressStockOsd)
        EnumWindows(hideExistingStockOsdProc, 0);
#endif
}
