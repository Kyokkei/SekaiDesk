#include "TrayService.h"

#ifdef Q_OS_WIN
#include "trayhook/TrayHookProtocol.h"
#endif

#include <QByteArray>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#ifdef Q_OS_WIN
#include <commctrl.h>
#include <psapi.h>
#include <shellapi.h>

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <vector>

#ifndef NIF_MESSAGE
#define NIF_MESSAGE 0x00000001
#endif
#ifndef NIF_ICON
#define NIF_ICON 0x00000002
#endif
#ifndef NIF_TIP
#define NIF_TIP 0x00000004
#endif
#ifndef NIF_STATE
#define NIF_STATE 0x00000008
#endif
#ifndef NIF_INFO
#define NIF_INFO 0x00000010
#endif
#ifndef NIF_GUID
#define NIF_GUID 0x00000020
#endif
#ifndef NIS_HIDDEN
#define NIS_HIDDEN 0x00000001
#endif
#ifndef NIM_ADD
#define NIM_ADD 0x00000000
#endif
#ifndef NIM_MODIFY
#define NIM_MODIFY 0x00000001
#endif
#ifndef NIM_DELETE
#define NIM_DELETE 0x00000002
#endif
#ifndef NIM_SETVERSION
#define NIM_SETVERSION 0x00000004
#endif
#ifndef NIN_SELECT
#define NIN_SELECT (WM_USER + 0)
#endif
#ifndef WM_CONTEXTMENU
#define WM_CONTEXTMENU 0x007B
#endif
#ifndef PROCESS_QUERY_LIMITED_INFORMATION
#define PROCESS_QUERY_LIMITED_INFORMATION 0x1000
#endif
#ifndef LIST_MODULES_ALL
#define LIST_MODULES_ALL 0x03
#endif

namespace {

constexpr qint64 kBroadcastCooldownMs = 8000;
constexpr size_t kMaxPipeMessageBytes = 1024U * 1024U;

static_assert(sizeof(SekaiPipeHeader) == 4, "SekaiPipeHeader wire size mismatch");
static_assert(sizeof(SekaiPipeCopyDataMsg) == 28, "SekaiPipeCopyDataMsg wire size mismatch");
static_assert(sizeof(SekaiNotifyIconData32) == 956, "SekaiNotifyIconData32 wire size mismatch");
static_assert(sizeof(SekaiShellTrayData) == 964, "SekaiShellTrayData wire size mismatch");
static_assert(offsetof(SekaiShellTrayData, nid) == 8, "SekaiShellTrayData nid offset mismatch");
static_assert(offsetof(SekaiNotifyIconData32, szTip) == 24, "SekaiNotifyIconData32 szTip offset mismatch");
static_assert(offsetof(SekaiNotifyIconData32, uVersion) == 800, "SekaiNotifyIconData32 uVersion offset mismatch");
static_assert(offsetof(SekaiNotifyIconData32, guidItem) == 936, "SekaiNotifyIconData32 guidItem offset mismatch");

struct TrayData64 {
    HWND hwnd;
    UINT uID;
    UINT uCallbackMessage;
    DWORD dwState;
    UINT uVersion;
    HICON hIcon;
};

struct TbButton64 {
    int iBitmap;
    int idCommand;
    BYTE fsState;
    BYTE fsStyle;
    BYTE bReserved[6];
    DWORD_PTR dwData;
    INT_PTR iString;
};

QString processExeFromPid(DWORD pid)
{
    if (pid == 0)
        return {};
    HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!hProc)
        return {};
    wchar_t buf[MAX_PATH * 2]{};
    DWORD len = MAX_PATH * 2;
    QString out;
    if (QueryFullProcessImageNameW(hProc, 0, buf, &len) && len > 0)
        out = QString::fromWCharArray(buf, static_cast<int>(len));
    CloseHandle(hProc);
    return out;
}

QString processExeFromHwnd(HWND hwnd)
{
    if (!hwnd || !IsWindow(hwnd))
        return {};
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    return processExeFromPid(pid);
}

HWND findRealExplorerTrayWnd() noexcept
{
    const DWORD selfPid = GetCurrentProcessId();
    HWND firstNonSelf = nullptr;
    HWND candidate = nullptr;

    while ((candidate = FindWindowExW(nullptr, candidate, L"Shell_TrayWnd", nullptr)) != nullptr) {
        DWORD pid = 0;
        GetWindowThreadProcessId(candidate, &pid);
        if (pid == 0 || pid == selfPid)
            continue;

        if (!firstNonSelf)
            firstNonSelf = candidate;

        const QString exe = processExeFromPid(pid);
        if (!exe.isEmpty() &&
            QFileInfo(exe).fileName().compare(QLatin1String("explorer.exe"), Qt::CaseInsensitive) == 0) {
            return candidate;
        }
    }
    return firstNonSelf;
}

bool isDllLoaded(DWORD pid, const wchar_t* dllBaseName) noexcept
{
    if (pid == 0 || !dllBaseName)
        return false;

    HANDLE hProc = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!hProc)
        return false;

    using EnumModulesExFn = BOOL(WINAPI*)(HANDLE, HMODULE*, DWORD, LPDWORD, DWORD);
    static EnumModulesExFn enumExFn = []() -> EnumModulesExFn {
        HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
        if (k32) {
            if (auto fn = reinterpret_cast<EnumModulesExFn>(
                    GetProcAddress(k32, "K32EnumProcessModulesEx"))) {
                return fn;
            }
        }
        HMODULE ps = GetModuleHandleW(L"psapi.dll");
        return ps ? reinterpret_cast<EnumModulesExFn>(GetProcAddress(ps, "EnumProcessModulesEx"))
                  : nullptr;
    }();

    std::vector<HMODULE> modules(256);
    DWORD bytesNeeded = 0;
    BOOL ok = FALSE;
    if (enumExFn) {
        ok = enumExFn(hProc, modules.data(),
                      static_cast<DWORD>(modules.size() * sizeof(HMODULE)),
                      &bytesNeeded, LIST_MODULES_ALL);
    } else {
        ok = EnumProcessModules(hProc, modules.data(),
                                static_cast<DWORD>(modules.size() * sizeof(HMODULE)),
                                &bytesNeeded);
    }

    if (ok && bytesNeeded > modules.size() * sizeof(HMODULE)) {
        modules.resize(bytesNeeded / sizeof(HMODULE));
        if (enumExFn) {
            ok = enumExFn(hProc, modules.data(),
                          static_cast<DWORD>(modules.size() * sizeof(HMODULE)),
                          &bytesNeeded, LIST_MODULES_ALL);
        } else {
            ok = EnumProcessModules(hProc, modules.data(),
                                    static_cast<DWORD>(modules.size() * sizeof(HMODULE)),
                                    &bytesNeeded);
        }
    }

    bool found = false;
    if (ok) {
        const size_t count = bytesNeeded / sizeof(HMODULE);
        wchar_t baseName[MAX_PATH]{};
        for (size_t i = 0; i < count && i < modules.size(); ++i) {
            if (GetModuleBaseNameW(hProc, modules[i], baseName, MAX_PATH) > 0) {
                if (_wcsicmp(baseName, dllBaseName) == 0) {
                    found = true;
                    break;
                }
            }
        }
    }

    CloseHandle(hProc);
    return found;
}

bool isNonZeroGuid(const GUID& g) noexcept
{
    static const GUID kZeroGuid{};
    return std::memcmp(&g, &kZeroGuid, sizeof(GUID)) != 0;
}

QString guidToString(const GUID& g)
{
    return QString::asprintf(
        "{%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}",
        static_cast<unsigned int>(g.Data1),
        static_cast<unsigned int>(g.Data2),
        static_cast<unsigned int>(g.Data3),
        g.Data4[0], g.Data4[1], g.Data4[2], g.Data4[3],
        g.Data4[4], g.Data4[5], g.Data4[6], g.Data4[7]);
}

// Legacy ToolbarWindow32 HICON pixel extraction (Windows 10 initial seed).
QImage extractHiconToQImage(HICON hIcon)
{
    if (!hIcon)
        return {};

    ICONINFO ii{};
    if (!GetIconInfo(hIcon, &ii))
        return {};

    auto cleanupIcons = [&]() {
        if (ii.hbmColor) DeleteObject(ii.hbmColor);
        if (ii.hbmMask) DeleteObject(ii.hbmMask);
    };

    if (!ii.hbmColor) {
        cleanupIcons();
        return {};
    }

    BITMAP bm{};
    if (GetObjectW(ii.hbmColor, sizeof(bm), &bm) == 0) {
        cleanupIcons();
        return {};
    }

    const int w = bm.bmWidth;
    const int h = bm.bmHeight < 0 ? -bm.bmHeight : bm.bmHeight;
    if (w <= 0 || h <= 0 || w > 256 || h > 256) {
        cleanupIcons();
        return {};
    }

    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    const int pixelCount = w * h;
    QByteArray pixels(pixelCount * 4, Qt::Uninitialized);
    HDC hdc = CreateCompatibleDC(nullptr);
    if (!hdc) {
        cleanupIcons();
        return {};
    }

    const int copied = GetDIBits(hdc, ii.hbmColor, 0, static_cast<UINT>(h),
                                 pixels.data(), &bi, DIB_RGB_COLORS);
    if (copied != h) {
        DeleteDC(hdc);
        cleanupIcons();
        return {};
    }

    auto* px = reinterpret_cast<unsigned char*>(pixels.data());
    bool allAlphaZero = true;
    for (int i = 0; i < pixelCount; ++i) {
        if (px[i * 4 + 3] != 0) {
            allAlphaZero = false;
            break;
        }
    }

    QByteArray maskBytes;
    bool hasMask = false;
    if (allAlphaZero && ii.hbmMask) {
        maskBytes.resize(pixelCount * 4);
        hasMask = GetDIBits(hdc, ii.hbmMask, 0, static_cast<UINT>(h),
                            maskBytes.data(), &bi, DIB_RGB_COLORS) == h;
    }

    DeleteDC(hdc);
    cleanupIcons();

    const auto* mk = hasMask ? reinterpret_cast<const unsigned char*>(maskBytes.constData()) : nullptr;
    for (int i = 0; i < pixelCount; ++i) {
        const unsigned char b = px[i * 4 + 0];
        const unsigned char g = px[i * 4 + 1];
        const unsigned char r = px[i * 4 + 2];
        unsigned char a = px[i * 4 + 3];
        if (allAlphaZero) {
            a = mk ? (mk[i * 4] == 255 ? 0 : 255) : 255;
        }
        px[i * 4 + 0] = r;
        px[i * 4 + 1] = g;
        px[i * 4 + 2] = b;
        px[i * 4 + 3] = a;
    }

    QImage img(px, w, h, w * 4, QImage::Format_RGBA8888);
    return img.copy();
}

void sendTrayCallback(HWND hwnd, uint32_t callbackMsg, uint32_t uID,
                      uint32_t version, UINT mouseMsg, const POINT& pt) noexcept
{
    WPARAM wParam = 0;
    LPARAM lParam = 0;
    if (version >= 4) {
        wParam = static_cast<WPARAM>(
            MAKELPARAM(static_cast<uint16_t>(static_cast<int16_t>(pt.x)),
                       static_cast<uint16_t>(static_cast<int16_t>(pt.y))));
        lParam = static_cast<LPARAM>(
            MAKELPARAM(static_cast<uint16_t>(mouseMsg),
                       static_cast<uint16_t>(uID & 0xFFFFu)));
    } else {
        wParam = static_cast<WPARAM>(uID);
        lParam = static_cast<LPARAM>(mouseMsg);
    }
    SendNotifyMessageW(hwnd, callbackMsg, wParam, lParam);
}

} // namespace
#endif // Q_OS_WIN

TrayService::TrayService(QObject* parent)
    : QObject(parent)
{
    m_iconDir = QDir::tempPath()
        + QStringLiteral("/sekaidesk_tray_%1").arg(QCoreApplication::applicationPid());
    QDir().mkpath(m_iconDir);

#ifdef Q_OS_WIN
    // Start capture cleanly after TaskbarManager finishes its initial Explorer pass.
    QTimer::singleShot(350, this, &TrayService::beginCapture);
#endif
}

TrayService::~TrayService()
{
    stop();
    if (!m_iconDir.isEmpty())
        QDir(m_iconDir).removeRecursively();
}

void TrayService::setPaused(bool paused)
{
#ifdef Q_OS_WIN
    const bool prev = m_paused.exchange(paused, std::memory_order_acq_rel);
    if (prev == paused)
        return;

    if (!paused)
        QTimer::singleShot(150, this, &TrayService::refresh);
#else
    Q_UNUSED(paused);
#endif
}

void TrayService::stop()
{
#ifdef Q_OS_WIN
    m_stopping.store(true, std::memory_order_release);
    m_hookReady.store(false, std::memory_order_release);

    if (m_hStopEvent)
        SetEvent(m_hStopEvent);

    // Releasing the watchdog mutex signals SekaiTrayHook.dll inside Explorer
    // to restore Shell_TrayWnd's WndProc and cleanly FreeLibraryAndExitThread.
    if (m_hWatchdogMutex) {
        ReleaseMutex(m_hWatchdogMutex);
        CloseHandle(m_hWatchdogMutex);
        m_hWatchdogMutex = nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(m_ioMutex);
        if (m_activeHook) {
            UnhookWindowsHookEx(m_activeHook);
            m_activeHook = nullptr;
        }
        if (m_activeHookDll) {
            FreeLibrary(m_activeHookDll);
            m_activeHookDll = nullptr;
        }
        if (m_hPipe != INVALID_HANDLE_VALUE) {
            CancelIoEx(m_hPipe, nullptr);
        }
    }

    if (m_pipeThread.joinable())
        m_pipeThread.join();

    {
        std::lock_guard<std::mutex> lock(m_ioMutex);
        if (m_hPipe != INVALID_HANDLE_VALUE) {
            CloseHandle(m_hPipe);
            m_hPipe = INVALID_HANDLE_VALUE;
        }
    }

    if (m_hStopEvent) {
        CloseHandle(m_hStopEvent);
        m_hStopEvent = nullptr;
    }
#endif
}

#ifdef Q_OS_WIN
void TrayService::beginCapture()
{
    if (m_stopping.load(std::memory_order_acquire) || m_pipeThread.joinable())
        return;

    m_taskbarCreatedMsg.store(RegisterWindowMessageW(L"TaskbarCreated"), std::memory_order_release);
    m_hookDllPath = QDir::toNativeSeparators(
        QCoreApplication::applicationDirPath() + QStringLiteral("/SekaiTrayHook.dll"));

    m_hStopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!m_hStopEvent) {
        qWarning("TrayService: failed to create stop event (err=%lu)", GetLastError());
        return;
    }

    m_hWatchdogMutex = CreateMutexW(nullptr, TRUE, SEKAI_TRAY_WATCHDOG_MUTEX);
    if (m_hWatchdogMutex && GetLastError() == ERROR_ALREADY_EXISTS) {
        WaitForSingleObject(m_hWatchdogMutex, 3000);
    } else if (!m_hWatchdogMutex) {
        qWarning("TrayService: failed to create watchdog mutex (err=%lu)", GetLastError());
    }

    scanExplorerToolbars();
    rebuildVisibleItems();

    m_pipeThread = std::thread(&TrayService::pipeThreadMain, this);
}

void TrayService::pipeThreadMain()
{
    HANDLE pipe = CreateNamedPipeW(
        SEKAI_TRAY_PIPE_NAME,
        PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
        1,
        SEKAI_TRAY_PIPE_BUFFER_SIZE,
        SEKAI_TRAY_PIPE_BUFFER_SIZE,
        0,
        nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
        qWarning("TrayService: CreateNamedPipeW failed (err=%lu)", GetLastError());
        return;
    }

    {
        std::lock_guard<std::mutex> lock(m_ioMutex);
        m_hPipe = pipe;
    }

    HANDLE hIoEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!hIoEvent) {
        qWarning("TrayService: failed to create pipe I/O event (err=%lu)", GetLastError());
        std::lock_guard<std::mutex> lock(m_ioMutex);
        CloseHandle(pipe);
        m_hPipe = INVALID_HANDLE_VALUE;
        return;
    }

    auto waitStop = [&](DWORD ms) {
        if (m_hStopEvent)
            WaitForSingleObject(m_hStopEvent, ms);
    };

    auto waitForIo = [&](OVERLAPPED& ov, DWORD timeoutMs) -> bool {
        HANDLE handles[2] = { m_hStopEvent, hIoEvent };
        const DWORD res = WaitForMultipleObjects(2, handles, FALSE, timeoutMs);
        if (res == WAIT_OBJECT_0 + 1)
            return true;
        CancelIoEx(pipe, &ov);
        DWORD unused = 0;
        GetOverlappedResult(pipe, &ov, &unused, TRUE);
        return false;
    };

    auto releaseInjectionHook = [&]() {
        std::lock_guard<std::mutex> lock(m_ioMutex);
        if (m_activeHook) {
            UnhookWindowsHookEx(m_activeHook);
            m_activeHook = nullptr;
        }
        if (m_activeHookDll) {
            FreeLibrary(m_activeHookDll);
            m_activeHookDll = nullptr;
        }
    };

    bool missingDllWarned = false;
    QByteArray chunk(static_cast<int>(SEKAI_TRAY_PIPE_BUFFER_SIZE), Qt::Uninitialized);
    QByteArray packet;

    while (!m_stopping.load(std::memory_order_acquire)) {
        HWND trayHwnd = findRealExplorerTrayWnd();
        DWORD explorerPid = 0;
        const DWORD explorerTid = trayHwnd ? GetWindowThreadProcessId(trayHwnd, &explorerPid) : 0;
        if (!trayHwnd || explorerPid == 0 || explorerTid == 0) {
            waitStop(1000);
            continue;
        }

        const auto* dllPathW = reinterpret_cast<const wchar_t*>(m_hookDllPath.utf16());
        if (m_hookDllPath.isEmpty() || GetFileAttributesW(dllPathW) == INVALID_FILE_ATTRIBUTES) {
            if (!missingDllWarned) {
                qWarning("TrayService: SekaiTrayHook.dll not found at %s (falling back to ToolbarWindow32)",
                         qPrintable(m_hookDllPath));
                missingDllWarned = true;
            }
            break;
        }

        // If a previous instance's hook DLL is still detaching from Explorer, wait up to 2s.
        bool alreadyLoaded = isDllLoaded(explorerPid, L"SekaiTrayHook.dll");
        for (int waitIdx = 0;
             alreadyLoaded && waitIdx < 20 && !m_stopping.load(std::memory_order_acquire);
             ++waitIdx) {
            waitStop(100);
            alreadyLoaded = isDllLoaded(explorerPid, L"SekaiTrayHook.dll");
        }
        if (m_stopping.load(std::memory_order_acquire))
            break;

        if (!alreadyLoaded) {
            HMODULE hDll = LoadLibraryW(dllPathW);
            if (!hDll) {
                qWarning("TrayService: LoadLibraryW(SekaiTrayHook.dll) failed (err=%lu)", GetLastError());
                waitStop(2000);
                continue;
            }
            auto hookProc = reinterpret_cast<HOOKPROC>(GetProcAddress(hDll, "GetMsgProc"));
            if (!hookProc) {
                qWarning("TrayService: GetMsgProc export missing in SekaiTrayHook.dll");
                FreeLibrary(hDll);
                break;
            }

            HHOOK hHook = SetWindowsHookExW(WH_GETMESSAGE, hookProc, hDll, explorerTid);
            if (!hHook) {
                qWarning("TrayService: SetWindowsHookExW failed (err=%lu)", GetLastError());
                FreeLibrary(hDll);
                waitStop(2000);
                continue;
            }

            {
                std::lock_guard<std::mutex> lock(m_ioMutex);
                if (m_stopping.load(std::memory_order_acquire)) {
                    UnhookWindowsHookEx(hHook);
                    FreeLibrary(hDll);
                    break;
                }
                m_activeHook = hHook;
                m_activeHookDll = hDll;
            }

            // Wake Explorer's UI thread message loop so WH_GETMESSAGE loads SekaiTrayHook.dll.
            PostThreadMessageW(explorerTid, WM_NULL, 0, 0);
        }

        bool connected = false;
        OVERLAPPED ovConn{};
        ResetEvent(hIoEvent);
        ovConn.hEvent = hIoEvent;
        if (ConnectNamedPipe(pipe, &ovConn)) {
            connected = true;
        } else {
            const DWORD err = GetLastError();
            if (err == ERROR_PIPE_CONNECTED) {
                connected = true;
            } else if (err == ERROR_IO_PENDING) {
                if (waitForIo(ovConn, 5000)) {
                    DWORD unused = 0;
                    if (GetOverlappedResult(pipe, &ovConn, &unused, FALSE))
                        connected = true;
                }
            }
        }

        releaseInjectionHook();

        if (!connected) {
            DisconnectNamedPipe(pipe);
            if (m_stopping.load(std::memory_order_acquire))
                break;
            waitStop(1000);
            continue;
        }

        while (!m_stopping.load(std::memory_order_acquire)) {
            packet.clear();
            bool msgOk = false;
            bool pipeBroken = false;

            while (!m_stopping.load(std::memory_order_acquire)) {
                OVERLAPPED ovRead{};
                ResetEvent(hIoEvent);
                ovRead.hEvent = hIoEvent;
                DWORD nRead = 0;
                BOOL ok = ReadFile(pipe, chunk.data(), static_cast<DWORD>(chunk.size()), &nRead, &ovRead);
                DWORD err = ok ? ERROR_SUCCESS : GetLastError();

                if (err == ERROR_IO_PENDING) {
                    if (!waitForIo(ovRead, INFINITE)) {
                        pipeBroken = true;
                        break;
                    }
                    ok = GetOverlappedResult(pipe, &ovRead, &nRead, FALSE);
                    err = ok ? ERROR_SUCCESS : GetLastError();
                }

                if (err == ERROR_SUCCESS || err == ERROR_MORE_DATA) {
                    if (nRead > 0) {
                        if (static_cast<size_t>(packet.size()) + nRead > kMaxPipeMessageBytes) {
                            pipeBroken = true;
                            break;
                        }
                        packet.append(chunk.constData(), static_cast<int>(nRead));
                    }
                    if (err == ERROR_SUCCESS) {
                        msgOk = !packet.isEmpty();
                        break;
                    }
                } else {
                    pipeBroken = true;
                    break;
                }
            }

            if (pipeBroken || !msgOk)
                break;

            handlePipePacket(packet);
        }

        m_hookReady.store(false, std::memory_order_release);
        DisconnectNamedPipe(pipe);

        if (!m_stopping.load(std::memory_order_acquire)) {
            QMetaObject::invokeMethod(this, [this]() {
                if (m_stopping.load(std::memory_order_acquire))
                    return;
                pruneDeadItems();
                rebuildVisibleItems();
            }, Qt::QueuedConnection);
            waitStop(1500);
        }
    }

    releaseInjectionHook();
    CloseHandle(hIoEvent);

    {
        std::lock_guard<std::mutex> lock(m_ioMutex);
        if (m_hPipe != INVALID_HANDLE_VALUE) {
            CloseHandle(m_hPipe);
            m_hPipe = INVALID_HANDLE_VALUE;
        }
    }
}

void TrayService::handlePipePacket(const QByteArray& packet)
{
    if (m_stopping.load(std::memory_order_acquire))
        return;
    if (packet.size() < static_cast<int>(sizeof(SekaiPipeHeader)))
        return;

    SekaiPipeHeader hdr{};
    std::memcpy(&hdr, packet.constData(), sizeof(hdr));

    if (hdr.type == SEKAI_TRAY_MSG_TEXT)
        return;

    if (hdr.type == SEKAI_TRAY_MSG_READY) {
        m_hookReady.store(true, std::memory_order_release);
        const UINT taskbarCreated = m_taskbarCreatedMsg.load(std::memory_order_acquire);
        if (taskbarCreated != 0 && !m_stopping.load(std::memory_order_acquire)) {
            QMetaObject::invokeMethod(this, [this, taskbarCreated]() {
                if (m_stopping.load(std::memory_order_acquire) ||
                    m_paused.load(std::memory_order_acquire))
                    return;
                m_lastBroadcastMs = QDateTime::currentMSecsSinceEpoch();
                SendNotifyMessageW(HWND_BROADCAST, taskbarCreated, 0, 0);
            }, Qt::QueuedConnection);
        }
        return;
    }

    if (hdr.type != SEKAI_TRAY_MSG_COPYDATA)
        return;
    if (packet.size() < static_cast<int>(sizeof(SekaiPipeCopyDataMsg)))
        return;

    SekaiPipeCopyDataMsg msg{};
    std::memcpy(&msg, packet.constData(), sizeof(msg));

    const size_t headerSize = sizeof(SekaiPipeCopyDataMsg);
    if (msg.cbData < 32U ||
        static_cast<size_t>(packet.size()) < headerSize + msg.cbData + msg.iconDataSize) {
        return;
    }

    const char* payloadPtr = packet.constData() + headerSize;
    SekaiShellTrayData st{};
    std::memcpy(&st, payloadPtr, std::min<size_t>(msg.cbData, sizeof(st)));

    const HWND iconHwnd = reinterpret_cast<HWND>(
        static_cast<intptr_t>(static_cast<int32_t>(st.nid.hWnd)));
    DWORD ownerPid = 0;
    if (iconHwnd && IsWindow(iconHwnd))
        GetWindowThreadProcessId(iconHwnd, &ownerPid);

    if (ownerPid == GetCurrentProcessId())
        return;
    if (iconHwnd == nullptr && !isNonZeroGuid(st.nid.guidItem))
        return;

    const uint32_t msgType = st.dwMessage;
    const bool hasGuid = ((st.nid.uFlags & NIF_GUID) != 0) && isNonZeroGuid(st.nid.guidItem);
    const QString guidStr = hasGuid ? guidToString(st.nid.guidItem) : QString{};
    const quintptr hwndVal = reinterpret_cast<quintptr>(iconHwnd);

    if (msgType == NIM_DELETE) {
        QMetaObject::invokeMethod(this, [this, hwndVal, uID = st.nid.uID, hasGuid, guidStr]() {
            if (m_stopping.load(std::memory_order_acquire))
                return;
            applyIconRemove(hwndVal, uID, hasGuid, guidStr);
        }, Qt::QueuedConnection);
        return;
    }

    if (msgType == NIM_ADD || msgType == NIM_MODIFY || msgType == NIM_SETVERSION) {
        CapturedIconUpdate upd;
        upd.hwnd = hwndVal;
        upd.uID = st.nid.uID;
        upd.uFlags = st.nid.uFlags;
        if (st.nid.uFlags & NIF_MESSAGE)
            upd.uCallbackMessage = st.nid.uCallbackMessage;
        if (msgType == NIM_SETVERSION || (st.nid.uVersion > 0 && st.nid.uVersion <= 4))
            upd.uVersion = st.nid.uVersion;
        if ((st.nid.uFlags & NIF_STATE) && (st.nid.dwStateMask & NIS_HIDDEN)) {
            upd.hasHiddenFlag = true;
            upd.hidden = (st.nid.dwState & NIS_HIDDEN) != 0;
        }
        upd.hasGuid = hasGuid;
        upd.guid = guidStr;
        if (st.nid.uFlags & NIF_TIP) {
            upd.hasTip = true;
            wchar_t tipBuf[129]{};
            std::memcpy(tipBuf, st.nid.szTip, sizeof(st.nid.szTip));
            upd.tip = QString::fromWCharArray(tipBuf).trimmed();
        }

        if (msg.iconDataSize > 0 && msg.iconWidth > 0 && msg.iconHeight > 0 &&
            msg.iconWidth <= 256 && msg.iconHeight <= 256) {
            const uint64_t expectedBytes =
                static_cast<uint64_t>(msg.iconWidth) * static_cast<uint64_t>(msg.iconHeight) * 4ULL;
            if (expectedBytes == msg.iconDataSize) {
                const auto* rgbaPtr = reinterpret_cast<const uchar*>(payloadPtr + msg.cbData);
                QImage img(rgbaPtr,
                           static_cast<int>(msg.iconWidth),
                           static_cast<int>(msg.iconHeight),
                           static_cast<int>(msg.iconWidth) * 4,
                           QImage::Format_RGBA8888);
                upd.iconImage = img.copy();
            }
        }

        QMetaObject::invokeMethod(this, [this, upd]() {
            if (m_stopping.load(std::memory_order_acquire))
                return;
            applyIconUpdate(upd);
        }, Qt::QueuedConnection);
    }
}

int TrayService::findTrackedIndex(quintptr hwnd, uint32_t uID, bool hasGuid, const QString& guid) const
{
    if (hasGuid && !guid.isEmpty()) {
        for (int i = 0; i < m_tracked.size(); ++i) {
            if (m_tracked.at(i).hasGuid && m_tracked.at(i).guid == guid)
                return i;
        }
    }
    if (hwnd != 0) {
        for (int i = 0; i < m_tracked.size(); ++i) {
            if (m_tracked.at(i).hwnd == hwnd && m_tracked.at(i).uID == uID)
                return i;
        }
    }
    return -1;
}

QString TrayService::writeTempIconPng(const QImage& img)
{
    if (img.isNull() || m_iconDir.isEmpty())
        return {};
    const QString path = m_iconDir + QStringLiteral("/tray_%1.png").arg(++m_iconSeq);
    if (img.save(path, "PNG"))
        return path;
    return {};
}

void TrayService::removeTempIconFile(InternalItem& item)
{
    if (!item.iconFilePath.isEmpty()) {
        QFile::remove(item.iconFilePath);
        item.iconFilePath.clear();
    }
}

void TrayService::applyIconUpdate(const CapturedIconUpdate& upd)
{
    const int idx = findTrackedIndex(upd.hwnd, upd.uID, upd.hasGuid, upd.guid);
    InternalItem* target = nullptr;
    if (idx >= 0) {
        target = &m_tracked[idx];
    } else {
        m_tracked.append(InternalItem{});
        target = &m_tracked.last();
    }

    target->fromLegacyToolbar = false;
    if (upd.hwnd != 0)
        target->hwnd = upd.hwnd;
    if (upd.uID != 0 || idx < 0)
        target->uID = upd.uID;
    if (upd.hasGuid) {
        target->hasGuid = true;
        target->guid = upd.guid;
    }
    if (upd.uFlags & NIF_MESSAGE)
        target->uCallbackMessage = upd.uCallbackMessage;
    if (upd.uVersion > 0 && upd.uVersion <= 4)
        target->uVersion = upd.uVersion;
    if (upd.hasHiddenFlag)
        target->hidden = upd.hidden;
    if (upd.hasTip)
        target->tip = upd.tip;

    if (target->exePath.isEmpty() && target->hwnd != 0) {
        target->exePath = processExeFromHwnd(reinterpret_cast<HWND>(target->hwnd));
    }

    if (!upd.iconImage.isNull()) {
        const QString file = writeTempIconPng(upd.iconImage);
        if (!file.isEmpty()) {
            removeTempIconFile(*target);
            target->iconFilePath = file;
            target->iconUrl = QUrl::fromLocalFile(file).toString();
        }
    }

    if (target->iconUrl.isEmpty() && !target->exePath.isEmpty()) {
        target->iconUrl = QStringLiteral("image://winicon/exe/")
            + QString::fromLatin1(QUrl::toPercentEncoding(target->exePath));
    }

    rebuildVisibleItems();
}

void TrayService::applyIconRemove(quintptr hwnd, uint32_t uID, bool hasGuid, const QString& guid)
{
    const int idx = findTrackedIndex(hwnd, uID, hasGuid, guid);
    if (idx < 0)
        return;
    removeTempIconFile(m_tracked[idx]);
    m_tracked.removeAt(idx);
    rebuildVisibleItems();
}

void TrayService::pruneDeadItems()
{
    for (int i = m_tracked.size() - 1; i >= 0; --i) {
        const HWND h = reinterpret_cast<HWND>(m_tracked.at(i).hwnd);
        if (h != nullptr && !IsWindow(h)) {
            removeTempIconFile(m_tracked[i]);
            m_tracked.removeAt(i);
        }
    }
}

void TrayService::scanExplorerToolbars()
{
    // Legacy Win10 seed pass: Explorer hosts ToolbarWindow32 inside Shell_TrayWnd and
    // NotifyIconOverflowWindow. On Win11 22H2+, these return nullptr cleanly.
    HWND realTray = findRealExplorerTrayWnd();
    HWND notify = realTray ? FindWindowExW(realTray, nullptr, L"TrayNotifyWnd", nullptr) : nullptr;
    HWND pager = notify ? FindWindowExW(notify, nullptr, L"SysPager", nullptr) : nullptr;
    HWND tb1 = pager ? FindWindowExW(pager, nullptr, L"ToolbarWindow32", nullptr) : nullptr;

    HWND ov = FindWindowW(L"NotifyIconOverflowWindow", nullptr);
    HWND tb2 = ov ? FindWindowExW(ov, nullptr, L"ToolbarWindow32", nullptr) : nullptr;

    auto scanToolbar = [this](HWND tb) {
        if (!tb || !IsWindow(tb))
            return;
        DWORD pid = 0;
        GetWindowThreadProcessId(tb, &pid);
        if (pid == 0 || pid == GetCurrentProcessId())
            return;
        HANDLE hProc = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ, FALSE, pid);
        if (!hProc)
            return;

        const int count = static_cast<int>(SendMessageW(tb, TB_BUTTONCOUNT, 0, 0));
        void* remoteBtn = VirtualAllocEx(hProc, nullptr, 4096, MEM_COMMIT, PAGE_READWRITE);
        if (remoteBtn && count > 0 && count < 256) {
            for (int i = 0; i < count; ++i) {
                TbButton64 btn{};
                if (!SendMessageW(tb, TB_GETBUTTON, static_cast<WPARAM>(i),
                                  reinterpret_cast<LPARAM>(remoteBtn)))
                    continue;
                SIZE_T bytesRead = 0;
                if (!ReadProcessMemory(hProc, remoteBtn, &btn, sizeof(btn), &bytesRead))
                    continue;
                if ((btn.fsState & TBSTATE_HIDDEN) || btn.dwData == 0)
                    continue;

                TrayData64 td{};
                if (!ReadProcessMemory(hProc, reinterpret_cast<LPCVOID>(btn.dwData),
                                       &td, sizeof(td), &bytesRead))
                    continue;
                if (!td.hwnd || !IsWindow(td.hwnd))
                    continue;

                DWORD itemPid = 0;
                GetWindowThreadProcessId(td.hwnd, &itemPid);
                if (itemPid == GetCurrentProcessId())
                    continue;

                const quintptr hwndVal = reinterpret_cast<quintptr>(td.hwnd);
                const int existing = findTrackedIndex(hwndVal, td.uID, false, {});
                if (existing >= 0 && !m_tracked.at(existing).fromLegacyToolbar)
                    continue; // Live hook data is fresher than static ToolbarWindow32 seed.

                QString tip;
                const int textLen = static_cast<int>(
                    SendMessageW(tb, TB_GETBUTTONTEXTW, static_cast<WPARAM>(btn.idCommand),
                                 reinterpret_cast<LPARAM>(remoteBtn)));
                if (textLen > 0 && textLen < 512) {
                    QVector<wchar_t> wbuf(textLen + 1, 0);
                    if (ReadProcessMemory(hProc, remoteBtn, wbuf.data(),
                                          static_cast<SIZE_T>(textLen) * sizeof(wchar_t), &bytesRead)) {
                        tip = QString::fromWCharArray(wbuf.data(), textLen).trimmed();
                    }
                }

                const QString exePath = processExeFromHwnd(td.hwnd);

                InternalItem* target = nullptr;
                if (existing >= 0) {
                    target = &m_tracked[existing];
                } else {
                    m_tracked.append(InternalItem{});
                    target = &m_tracked.last();
                }

                target->hwnd = hwndVal;
                target->uID = td.uID;
                target->uCallbackMessage = td.uCallbackMessage;
                target->uVersion = td.uVersion;
                target->fromLegacyToolbar = true;
                target->hidden = false;
                if (!tip.isEmpty())
                    target->tip = tip;
                if (!exePath.isEmpty())
                    target->exePath = exePath;

                if (td.hIcon) {
                    const QImage img = extractHiconToQImage(td.hIcon);
                    if (!img.isNull()) {
                        const QString file = writeTempIconPng(img);
                        if (!file.isEmpty()) {
                            removeTempIconFile(*target);
                            target->iconFilePath = file;
                            target->iconUrl = QUrl::fromLocalFile(file).toString();
                        }
                    }
                }
                if (target->iconUrl.isEmpty() && !exePath.isEmpty()) {
                    target->iconUrl = QStringLiteral("image://winicon/exe/")
                        + QString::fromLatin1(QUrl::toPercentEncoding(exePath));
                }
            }
        }
        if (remoteBtn)
            VirtualFreeEx(hProc, remoteBtn, 0, MEM_RELEASE);
        CloseHandle(hProc);
    };

    scanToolbar(tb1);
    scanToolbar(tb2);
}

void TrayService::rebuildVisibleItems()
{
    if (m_paused.load(std::memory_order_acquire))
        return;

    QVariantList nextItems;
    QVector<int> nextIndices;
    nextItems.reserve(m_tracked.size());
    nextIndices.reserve(m_tracked.size());

    for (int i = 0; i < m_tracked.size(); ++i) {
        const auto& it = m_tracked.at(i);
        if (it.hidden || it.hwnd == 0)
            continue;
        if (!IsWindow(reinterpret_cast<HWND>(it.hwnd)))
            continue;

        QString displayTip = it.tip;
        if (displayTip.isEmpty() && !it.exePath.isEmpty())
            displayTip = QFileInfo(it.exePath).completeBaseName();
        if (displayTip.isEmpty())
            displayTip = QStringLiteral("Tray App");

        QVariantMap vm;
        vm.insert(QStringLiteral("index"), nextItems.size());
        vm.insert(QStringLiteral("tip"), displayTip);
        vm.insert(QStringLiteral("iconUrl"), it.iconUrl);
        nextItems.append(vm);
        nextIndices.append(i);
    }

    m_visibleIndices = nextIndices;
    if (m_items != nextItems) {
        m_items = nextItems;
        emit itemsChanged();
    }
}
#endif // Q_OS_WIN

void TrayService::refresh()
{
#ifdef Q_OS_WIN
    if (m_stopping.load(std::memory_order_acquire))
        return;

    pruneDeadItems();
    scanExplorerToolbars();
    rebuildVisibleItems();

    if (m_items.isEmpty() &&
        m_hookReady.load(std::memory_order_acquire) &&
        !m_paused.load(std::memory_order_acquire)) {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        const UINT taskbarCreated = m_taskbarCreatedMsg.load(std::memory_order_acquire);
        if (taskbarCreated != 0 && (now - m_lastBroadcastMs) >= kBroadcastCooldownMs) {
            m_lastBroadcastMs = now;
            SendNotifyMessageW(HWND_BROADCAST, taskbarCreated, 0, 0);
        }
    }
#endif
}

void TrayService::activateItem(int index, bool rightClick)
{
#ifdef Q_OS_WIN
    if (index < 0 || index >= m_visibleIndices.size())
        return;
    const int rawIdx = m_visibleIndices.at(index);
    if (rawIdx < 0 || rawIdx >= m_tracked.size())
        return;

    const auto& it = m_tracked.at(rawIdx);
    HWND hwnd = reinterpret_cast<HWND>(it.hwnd);
    if (!hwnd || !IsWindow(hwnd) || it.uCallbackMessage == 0)
        return;

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != 0)
        AllowSetForegroundWindow(pid);
    SetForegroundWindow(hwnd);

    POINT pt{};
    GetCursorPos(&pt);

    if (rightClick) {
        sendTrayCallback(hwnd, it.uCallbackMessage, it.uID, it.uVersion, WM_RBUTTONDOWN, pt);
        sendTrayCallback(hwnd, it.uCallbackMessage, it.uID, it.uVersion, WM_RBUTTONUP, pt);
        sendTrayCallback(hwnd, it.uCallbackMessage, it.uID, it.uVersion, WM_CONTEXTMENU, pt);
    } else {
        sendTrayCallback(hwnd, it.uCallbackMessage, it.uID, it.uVersion, WM_LBUTTONDOWN, pt);
        sendTrayCallback(hwnd, it.uCallbackMessage, it.uID, it.uVersion, WM_LBUTTONUP, pt);
        if (it.uVersion >= 3)
            sendTrayCallback(hwnd, it.uCallbackMessage, it.uID, it.uVersion, NIN_SELECT, pt);
    }
#else
    Q_UNUSED(index);
    Q_UNUSED(rightClick);
#endif
}
