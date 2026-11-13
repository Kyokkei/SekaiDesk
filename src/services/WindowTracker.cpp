#include "WindowTracker.h"

#include <QFileInfo>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#include <psapi.h>
#endif

namespace {

QString normalizeExeKey(const QString& path)
{
    QString p = path.trimmed();
    p.replace(QLatin1Char('/'), QLatin1Char('\\'));
    return p.toLower();
}

QString friendlyNameFromExe(const QString& exePath)
{
    const QString base = QFileInfo(exePath).completeBaseName();
    if (base.isEmpty())
        return QStringLiteral("App");
    QString out = base;
    out[0] = out[0].toUpper();
    return out;
}

#ifdef Q_OS_WIN
struct EnumContext {
    DWORD selfPid = 0;
    HWND foreground = nullptr;
    QHash<QString, QPair<QString, QList<HWND>>> byExe;
    QHash<QString, QString> firstTitle;
};

static bool isAltTabCandidate(HWND hwnd, DWORD selfPid)
{
    if (!IsWindowVisible(hwnd))
        return false;

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0 || pid == selfPid)
        return false;

    if (GetWindowTextLengthW(hwnd) <= 0)
        return false;

    const LONG_PTR exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW))
        return false;

    if (GetWindow(hwnd, GW_OWNER) != nullptr && !(exStyle & WS_EX_APPWINDOW))
        return false;

    // Skip cloaked UWP / other-virtual-desktop windows.
    BOOL cloaked = FALSE;
    if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked)))
        && cloaked) {
        return false;
    }

    wchar_t cls[128] = {};
    if (GetClassNameW(hwnd, cls, 128) > 0) {
        const QString className = QString::fromWCharArray(cls);
        if (className == QStringLiteral("Progman")
            || className == QStringLiteral("WorkerW")
            || className == QStringLiteral("Shell_TrayWnd")
            || className == QStringLiteral("Windows.UI.Core.CoreWindow")) {
            return false;
        }
    }

    return true;
}

static QString queryProcessExe(HWND hwnd)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0)
        return {};

    HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!proc)
        return {};

    wchar_t buf[MAX_PATH * 2] = {};
    DWORD len = MAX_PATH * 2;
    QString result;
    if (QueryFullProcessImageNameW(proc, 0, buf, &len) && len > 0)
        result = QString::fromWCharArray(buf, static_cast<int>(len));
    CloseHandle(proc);
    return result;
}

static BOOL CALLBACK enumWindowsProc(HWND hwnd, LPARAM lParam)
{
    auto* ctx = reinterpret_cast<EnumContext*>(lParam);
    if (!isAltTabCandidate(hwnd, ctx->selfPid))
        return TRUE;

    const QString exe = queryProcessExe(hwnd);
    if (exe.isEmpty())
        return TRUE;

    const QString key = normalizeExeKey(exe);
    if (!ctx->byExe.contains(key)) {
        ctx->byExe.insert(key, { exe, { hwnd } });
        wchar_t title[256] = {};
        if (GetWindowTextW(hwnd, title, 256) > 0)
            ctx->firstTitle.insert(key, QString::fromWCharArray(title));
    } else {
        ctx->byExe[key].second.append(hwnd);
    }
    return TRUE;
}
#endif

} // namespace

WindowTracker::WindowTracker(QObject* parent)
    : QObject(parent)
{
    m_pollTimer.setInterval(350);
    connect(&m_pollTimer, &QTimer::timeout, this, &WindowTracker::refresh);
    m_pollTimer.start();

    m_edgeTimer.setInterval(80);
    connect(&m_edgeTimer, &QTimer::timeout, this, &WindowTracker::pollEdgeAndOverlap);
    m_edgeTimer.start();

    refresh();
    pollEdgeAndOverlap();
}

void WindowTracker::refresh()
{
    QHash<QString, AppGroup> nextGroups;
    QVariantList nextList;

#ifdef Q_OS_WIN
    EnumContext ctx;
    ctx.selfPid = GetCurrentProcessId();
    ctx.foreground = GetForegroundWindow();
    EnumWindows(enumWindowsProc, reinterpret_cast<LPARAM>(&ctx));

    // Preserve deterministic order by exePath
    QStringList keys = ctx.byExe.keys();
    keys.sort();

    for (const QString& key : keys) {
        const auto& pair = ctx.byExe.value(key);
        AppGroup g;
        g.exePath = pair.first;
        g.exeKey = key;
        g.name = friendlyNameFromExe(g.exePath);

        bool allMin = true;
        quintptr bestHwnd = 0;
        for (HWND h : pair.second) {
            const auto ptr = reinterpret_cast<quintptr>(h);
            g.hwnds.append(ptr);
            if (h == ctx.foreground) {
                g.active = true;
                bestHwnd = ptr;
            }
            if (!IsIconic(h)) {
                allMin = false;
                if (bestHwnd == 0)
                    bestHwnd = ptr;
            }
        }
        if (bestHwnd == 0 && !g.hwnds.isEmpty())
            bestHwnd = g.hwnds.first();
        g.primaryHwnd = bestHwnd;
        g.allMinimized = allMin;

        nextGroups.insert(key, g);

        QVariantMap item;
        item.insert(QStringLiteral("name"), g.name);
        item.insert(QStringLiteral("target"), g.exePath);
        item.insert(QStringLiteral("exeKey"), g.exeKey);
        item.insert(QStringLiteral("count"), g.hwnds.size());
        item.insert(QStringLiteral("active"), g.active);
        item.insert(QStringLiteral("minimized"), g.allMinimized);
        nextList.append(item);
    }
#endif

    m_groups = std::move(nextGroups);
    if (m_runningApps != nextList) {
        m_runningApps = std::move(nextList);
        emit runningAppsChanged();
    }

#ifdef Q_OS_WIN
    if (ctx.foreground && IsWindow(ctx.foreground) && IsWindowVisible(ctx.foreground) && !IsIconic(ctx.foreground)) {
        DWORD fgPid = 0;
        GetWindowThreadProcessId(ctx.foreground, &fgPid);
        if (fgPid != ctx.selfPid) {
            wchar_t cls[64] = {};
            GetClassNameW(ctx.foreground, cls, 64);
            const QString clsName = QString::fromWCharArray(cls);
            QString nextApp = m_activeAppName;
            QString nextTitle = m_activeWindowTitle;
            if (clsName == QStringLiteral("Progman") || clsName == QStringLiteral("WorkerW")) {
                nextApp = QStringLiteral("Desktop");
                nextTitle.clear();
            } else if (clsName != QStringLiteral("Shell_TrayWnd") && clsName != QStringLiteral("Shell_SecondaryTrayWnd")) {
                const QString exe = queryProcessExe(ctx.foreground);
                nextApp = exe.isEmpty() ? QStringLiteral("Window") : friendlyNameFromExe(exe);
                wchar_t tbuf[256] = {};
                GetWindowTextW(ctx.foreground, tbuf, 256);
                nextTitle = QString::fromWCharArray(tbuf).trimmed();
            }
            if (nextApp != m_activeAppName || nextTitle != m_activeWindowTitle) {
                m_activeAppName = nextApp;
                m_activeWindowTitle = nextTitle;
                emit activeWindowChanged();
            }
        }
    } else if (!ctx.foreground) {
        if (m_activeAppName != QStringLiteral("Desktop") || !m_activeWindowTitle.isEmpty()) {
            m_activeAppName = QStringLiteral("Desktop");
            m_activeWindowTitle.clear();
            emit activeWindowChanged();
        }
    }
    updateSystemStats();
#endif
}

void WindowTracker::updateSystemStats()
{
#ifdef Q_OS_WIN
    int nextCpu = m_cpuUsage;
    FILETIME idleFt{}, kernelFt{}, userFt{};
    if (GetSystemTimes(&idleFt, &kernelFt, &userFt)) {
        const auto toU64 = [](const FILETIME& ft) -> quint64 {
            return (static_cast<quint64>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
        };
        const quint64 idle = toU64(idleFt);
        const quint64 kernel = toU64(kernelFt);
        const quint64 user = toU64(userFt);
        if (m_prevKernelTime != 0 || m_prevUserTime != 0) {
            const quint64 idleDiff = idle - m_prevIdleTime;
            const quint64 totalDiff = (kernel - m_prevKernelTime) + (user - m_prevUserTime);
            if (totalDiff > 0 && idleDiff <= totalDiff) {
                nextCpu = static_cast<int>(((totalDiff - idleDiff) * 100ULL) / totalDiff);
            }
        }
        m_prevIdleTime = idle;
        m_prevKernelTime = kernel;
        m_prevUserTime = user;
    }

    int nextRam = m_ramUsage;
    MEMORYSTATUSEX ms{};
    ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms)) {
        nextRam = static_cast<int>(ms.dwMemoryLoad);
    }

    if (nextCpu != m_cpuUsage || nextRam != m_ramUsage) {
        m_cpuUsage = nextCpu;
        m_ramUsage = nextRam;
        emit statsChanged();
    }
#endif
}

void WindowTracker::pollEdgeAndOverlap()
{
#ifdef Q_OS_WIN
    const HMONITOR mon = MonitorFromPoint(POINT{ 0, 0 }, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(mon, &mi))
        return;

    POINT pt{};
    bool nextBottomEdge = m_bottomEdgeHovered;
    bool nextTopEdge = m_topEdgeHovered;
    if (GetCursorPos(&pt)) {
        const bool inX = (pt.x >= mi.rcMonitor.left && pt.x <= mi.rcMonitor.right);
        const int botTriggerY = m_bottomEdgeHovered ? (mi.rcMonitor.bottom - 96) : (mi.rcMonitor.bottom - 4);
        nextBottomEdge = inX && (pt.y >= botTriggerY);
        const int topTriggerY = m_topEdgeHovered ? (mi.rcMonitor.top + 56) : (mi.rcMonitor.top + 3);
        const bool avoidWindowControls = !m_topEdgeHovered && (pt.x >= mi.rcMonitor.right - 150);
        nextTopEdge = inX && !avoidWindowControls && (pt.y <= topTriggerY);
    }
    if (nextBottomEdge != m_bottomEdgeHovered) {
        m_bottomEdgeHovered = nextBottomEdge;
        emit bottomEdgeHoveredChanged();
    }
    if (nextTopEdge != m_topEdgeHovered) {
        m_topEdgeHovered = nextTopEdge;
        emit topEdgeHoveredChanged();
    }

    bool nextDockOverlap = m_dockOverlap;
    bool nextTopOverlap = m_topOverlap;
    const HWND fg = GetForegroundWindow();
    if (!fg || !IsWindowVisible(fg) || IsIconic(fg)) {
        nextDockOverlap = false;
        nextTopOverlap = false;
    } else {
        DWORD fgPid = 0;
        GetWindowThreadProcessId(fg, &fgPid);
        if (fgPid != GetCurrentProcessId()) {
            wchar_t cls[64] = {};
            GetClassNameW(fg, cls, 64);
            const QString clsName = QString::fromWCharArray(cls);
            if (clsName == QStringLiteral("Progman")
                || clsName == QStringLiteral("WorkerW")
                || clsName == QStringLiteral("Shell_TrayWnd")
                || clsName == QStringLiteral("Shell_SecondaryTrayWnd")) {
                nextDockOverlap = false;
                nextTopOverlap = false;
            } else {
                RECT rc{};
                if (FAILED(DwmGetWindowAttribute(fg, DWMWA_EXTENDED_FRAME_BOUNDS, &rc, sizeof(rc))))
                    GetWindowRect(fg, &rc);
                const bool inScreenX = (rc.right > mi.rcMonitor.left) && (rc.left < mi.rcMonitor.right);
                nextDockOverlap = inScreenX && (rc.bottom >= mi.rcMonitor.bottom - 86);
                nextTopOverlap = inScreenX && (rc.top <= mi.rcMonitor.top + 52);
            }
        }
    }
    if (nextDockOverlap != m_dockOverlap) {
        m_dockOverlap = nextDockOverlap;
        emit dockOverlapChanged();
    }
    if (nextTopOverlap != m_topOverlap) {
        m_topOverlap = nextTopOverlap;
        emit topOverlapChanged();
    }
#endif
}

QVariantMap WindowTracker::stateForTarget(const QString& target) const
{
    const QString key = normalizeExeKey(target);
    QVariantMap m;
    if (!m_groups.contains(key)) {
        m.insert(QStringLiteral("running"), false);
        m.insert(QStringLiteral("count"), 0);
        m.insert(QStringLiteral("active"), false);
        m.insert(QStringLiteral("minimized"), false);
        return m;
    }
    const AppGroup& g = m_groups.value(key);
    m.insert(QStringLiteral("running"), true);
    m.insert(QStringLiteral("count"), g.hwnds.size());
    m.insert(QStringLiteral("active"), g.active);
    m.insert(QStringLiteral("minimized"), g.allMinimized);
    return m;
}

bool WindowTracker::activateOrToggle(const QString& target)
{
#ifdef Q_OS_WIN
    const QString key = normalizeExeKey(target);
    if (!m_groups.contains(key))
        return false;

    const AppGroup& g = m_groups.value(key);
    HWND hwnd = reinterpret_cast<HWND>(g.primaryHwnd);
    if (!hwnd || !IsWindow(hwnd))
        return false;

    if (g.active && !IsIconic(hwnd)) {
        ShowWindow(hwnd, SW_MINIMIZE);
    } else {
        if (IsIconic(hwnd))
            ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
    }
    refresh();
    return true;
#else
    Q_UNUSED(target);
    return false;
#endif
}

QVariantList WindowTracker::windowsForTarget(const QString& target) const
{
    QVariantList out;
#ifdef Q_OS_WIN
    const QString key = normalizeExeKey(target);
    if (!m_groups.contains(key))
        return out;

    const HWND fg = GetForegroundWindow();
    const AppGroup& g = m_groups.value(key);
    for (quintptr raw : g.hwnds) {
        HWND h = reinterpret_cast<HWND>(raw);
        if (!IsWindow(h))
            continue;
        wchar_t titleBuf[256] = {};
        GetWindowTextW(h, titleBuf, 256);
        QVariantMap m;
        m.insert(QStringLiteral("hwnd"), static_cast<qulonglong>(raw));
        m.insert(QStringLiteral("title"), QString::fromWCharArray(titleBuf));
        m.insert(QStringLiteral("active"), h == fg);
        m.insert(QStringLiteral("minimized"), static_cast<bool>(IsIconic(h)));
        out.append(m);
    }
#else
    Q_UNUSED(target);
#endif
    return out;
}

bool WindowTracker::activateHwnd(qulonglong hwnd)
{
#ifdef Q_OS_WIN
    HWND h = reinterpret_cast<HWND>(static_cast<quintptr>(hwnd));
    if (!h || !IsWindow(h))
        return false;
    if (IsIconic(h))
        ShowWindow(h, SW_RESTORE);
    SetForegroundWindow(h);
    refresh();
    return true;
#else
    Q_UNUSED(hwnd);
    return false;
#endif
}

bool WindowTracker::minimizeHwnd(qulonglong hwnd)
{
#ifdef Q_OS_WIN
    HWND h = reinterpret_cast<HWND>(static_cast<quintptr>(hwnd));
    if (!h || !IsWindow(h))
        return false;
    ShowWindow(h, SW_MINIMIZE);
    refresh();
    return true;
#else
    Q_UNUSED(hwnd);
    return false;
#endif
}

bool WindowTracker::closeHwnd(qulonglong hwnd)
{
#ifdef Q_OS_WIN
    HWND h = reinterpret_cast<HWND>(static_cast<quintptr>(hwnd));
    if (!h || !IsWindow(h))
        return false;
    PostMessageW(h, WM_CLOSE, 0, 0);
    QTimer::singleShot(150, this, &WindowTracker::refresh);
    return true;
#else
    Q_UNUSED(hwnd);
    return false;
#endif
}
