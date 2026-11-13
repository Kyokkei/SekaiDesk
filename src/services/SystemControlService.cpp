#include "SystemControlService.h"

#include <QCoreApplication>
#include <QHash>
#include <QHostAddress>
#include <QNetworkInterface>
#include <QProcess>
#include <QSettings>
#include <QTimer>
#include <QVariantMap>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#include <thread>

namespace {
constexpr int kQuickPanelHotkeyId = 0x534B;
constexpr int kSpotlightHotkeyId = 0x534C;
constexpr int kClipboardHotkeyId = 0x5343;

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
    if (QCoreApplication::instance())
        QCoreApplication::instance()->installNativeEventFilter(this);
    m_hotkeyRegistered = (RegisterHotKey(nullptr, kQuickPanelHotkeyId, MOD_CONTROL | MOD_ALT, 'A') != FALSE);
    m_spotlightHotkeyRegistered = (RegisterHotKey(nullptr, kSpotlightHotkeyId, MOD_ALT, VK_SPACE) != FALSE);
    m_clipboardHotkeyRegistered = (RegisterHotKey(nullptr, kClipboardHotkeyId, MOD_CONTROL | MOD_ALT, 'V') != FALSE);
    refresh();
#endif
}

SystemControlService::~SystemControlService()
{
#ifdef Q_OS_WIN
    if (m_hotkeyRegistered)
        UnregisterHotKey(nullptr, kQuickPanelHotkeyId);
    if (m_spotlightHotkeyRegistered)
        UnregisterHotKey(nullptr, kSpotlightHotkeyId);
    if (m_clipboardHotkeyRegistered)
        UnregisterHotKey(nullptr, kClipboardHotkeyId);
    if (QCoreApplication::instance())
        QCoreApplication::instance()->removeNativeEventFilter(this);
#endif
}

bool SystemControlService::nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result)
{
    Q_UNUSED(result);
#ifdef Q_OS_WIN
    if (eventType == "windows_generic_MSG" || eventType == "windows_dispatcher_MSG") {
        const MSG* msg = static_cast<const MSG*>(message);
        if (msg && msg->message == WM_HOTKEY) {
            const int id = static_cast<int>(msg->wParam);
            if (id == kQuickPanelHotkeyId) {
                emit quickPanelToggleRequested();
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
    emit stateChanged();
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
    QProcess::startDetached(QStringLiteral("rundll32.exe"),
                            { QStringLiteral("powrprof.dll,SetSuspendState"), QStringLiteral("0,1,0") });
#endif
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
