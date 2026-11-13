#include "TrayService.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QUrl>
#include <QVariantMap>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commctrl.h>

namespace {
struct TrayData64 {
    HWND hwnd;
    UINT uID;
    UINT uCallbackMessage;
    DWORD reserved[2];
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

QString processExeFromHwnd(HWND hwnd)
{
    if (!hwnd || !IsWindow(hwnd))
        return {};
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
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
} // namespace
#endif

TrayService::TrayService(QObject* parent)
    : QObject(parent)
{
    m_iconDir = QDir::tempPath()
        + QStringLiteral("/sekaidesk_tray_%1").arg(QCoreApplication::applicationPid());
    QDir().mkpath(m_iconDir);
}

TrayService::~TrayService()
{
    if (!m_iconDir.isEmpty())
        QDir(m_iconDir).removeRecursively();
}

void TrayService::refresh()
{
#ifdef Q_OS_WIN
    QVector<InternalItem> collected;
    QVariantList nextItems;

    auto scanToolbar = [&](HWND tb) {
        if (!tb || !IsWindow(tb))
            return;
        DWORD pid = 0;
        GetWindowThreadProcessId(tb, &pid);
        if (pid == 0)
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
                if (btn.fsState & TBSTATE_HIDDEN)
                    continue;
                if (btn.dwData == 0)
                    continue;

                TrayData64 td{};
                if (!ReadProcessMemory(hProc, reinterpret_cast<LPCVOID>(btn.dwData),
                                       &td, sizeof(td), &bytesRead))
                    continue;
                if (!td.hwnd || !IsWindow(td.hwnd))
                    continue;

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
                if (tip.isEmpty() && !exePath.isEmpty())
                    tip = QFileInfo(exePath).completeBaseName();
                if (tip.isEmpty())
                    tip = QStringLiteral("Tray App");

                QString iconUrl;
                if (td.hIcon) {
                    ICONINFO ii{};
                    if (GetIconInfo(td.hIcon, &ii)) {
                        if (ii.hbmColor) DeleteObject(ii.hbmColor);
                        if (ii.hbmMask) DeleteObject(ii.hbmMask);
                        const QImage img = QImage::fromHICON(td.hIcon);
                        if (!img.isNull()) {
                            const QString p = m_iconDir + QStringLiteral("/tray_%1_%2.png")
                                .arg(reinterpret_cast<quintptr>(td.hwnd), 0, 16)
                                .arg(td.uID);
                            if (img.save(p, "PNG"))
                                iconUrl = QUrl::fromLocalFile(p).toString();
                        }
                    }
                }
                if (iconUrl.isEmpty() && !exePath.isEmpty()) {
                    iconUrl = QStringLiteral("image://winicon/exe/")
                        + QString::fromLatin1(QUrl::toPercentEncoding(exePath));
                }

                InternalItem item;
                item.hwnd = reinterpret_cast<quintptr>(td.hwnd);
                item.uID = td.uID;
                item.uCallbackMessage = td.uCallbackMessage;
                item.tip = tip;
                item.iconUrl = iconUrl;
                collected.append(item);

                QVariantMap vm;
                vm.insert(QStringLiteral("index"), collected.size() - 1);
                vm.insert(QStringLiteral("tip"), tip);
                vm.insert(QStringLiteral("iconUrl"), iconUrl);
                nextItems.append(vm);
            }
        }
        if (remoteBtn)
            VirtualFreeEx(hProc, remoteBtn, 0, MEM_RELEASE);
        CloseHandle(hProc);
    };

    HWND tray = FindWindowW(L"Shell_TrayWnd", nullptr);
    HWND notify = tray ? FindWindowExW(tray, nullptr, L"TrayNotifyWnd", nullptr) : nullptr;
    HWND pager = notify ? FindWindowExW(notify, nullptr, L"SysPager", nullptr) : nullptr;
    HWND tb1 = pager ? FindWindowExW(pager, nullptr, L"ToolbarWindow32", nullptr) : nullptr;
    scanToolbar(tb1);

    HWND ov = FindWindowW(L"NotifyIconOverflowWindow", nullptr);
    HWND tb2 = ov ? FindWindowExW(ov, nullptr, L"ToolbarWindow32", nullptr) : nullptr;
    scanToolbar(tb2);

    m_raw = collected;
    if (m_items != nextItems) {
        m_items = nextItems;
        emit itemsChanged();
    }
#endif
}

void TrayService::activateItem(int index, bool rightClick)
{
#ifdef Q_OS_WIN
    if (index < 0 || index >= m_raw.size())
        return;
    const auto& it = m_raw.at(index);
    HWND hwnd = reinterpret_cast<HWND>(it.hwnd);
    if (!hwnd || !IsWindow(hwnd))
        return;
    SetForegroundWindow(hwnd);
    if (rightClick) {
        PostMessageW(hwnd, it.uCallbackMessage, it.uID, WM_RBUTTONDOWN);
        PostMessageW(hwnd, it.uCallbackMessage, it.uID, WM_RBUTTONUP);
        PostMessageW(hwnd, it.uCallbackMessage, it.uID, WM_CONTEXTMENU);
    } else {
        PostMessageW(hwnd, it.uCallbackMessage, it.uID, WM_LBUTTONDOWN);
        PostMessageW(hwnd, it.uCallbackMessage, it.uID, WM_LBUTTONUP);
    }
#else
    Q_UNUSED(index);
    Q_UNUSED(rightClick);
#endif
}
