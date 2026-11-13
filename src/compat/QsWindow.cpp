#include "QsWindow.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQuickItem>

#ifdef Q_OS_WIN
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>

static constexpr UINT kAppBarCallbackMsg = WM_APP + 0x55;
#endif

// ---------------------------------------------------------------------------
// MarginGroup / WindowAnchors
// ---------------------------------------------------------------------------

MarginGroup::MarginGroup(QObject* parent)
    : QObject(parent)
{
}

WindowAnchors::WindowAnchors(QObject* parent)
    : QObject(parent)
    , m_margins(new MarginGroup(this))
{
    connect(m_margins, &MarginGroup::changed, this, &WindowAnchors::changed);
}

// ---------------------------------------------------------------------------
// QsRegion
// ---------------------------------------------------------------------------

QsRegion::QsRegion(QObject* parent)
    : QObject(parent)
{
}

void QsRegion::setItem(QQuickItem* item)
{
    if (m_item == item)
        return;

    if (m_item)
        m_item->disconnect(this);

    m_item = item;
    handleItemChanged();
    emit itemChanged();
}

void QsRegion::setRegions(const QVariantList& regions)
{
    if (m_regions == regions)
        return;
    m_regions = regions;
    emit regionsChanged();
}

void QsRegion::handleItemChanged()
{
    if (!m_item)
        return;
    connect(m_item, &QQuickItem::xChanged, this, &QsRegion::regionsChanged, Qt::UniqueConnection);
    connect(m_item, &QQuickItem::yChanged, this, &QsRegion::regionsChanged, Qt::UniqueConnection);
    connect(m_item, &QQuickItem::widthChanged, this, &QsRegion::regionsChanged, Qt::UniqueConnection);
    connect(m_item, &QQuickItem::heightChanged, this, &QsRegion::regionsChanged, Qt::UniqueConnection);
}

QRegion QsRegion::regionRelativeTo(const QQuickWindow* win) const
{
    QRegion out;

    QPointF origin(0, 0);
    if (m_item) {
        const QRectF sceneRect = m_item->mapRectToScene(
            QRectF(0, 0, m_item->width(), m_item->height()));
        origin = sceneRect.topLeft();
        out += sceneRect.toAlignedRect();
    }

    for (const QVariant& v : m_regions) {
        const QVariantMap r = v.toMap();
        const QRectF rect(r.value(QStringLiteral("x")).toReal(),
                          r.value(QStringLiteral("y")).toReal(),
                          r.value(QStringLiteral("width")).toReal(),
                          r.value(QStringLiteral("height")).toReal());
        out += rect.translated(origin).toAlignedRect();
    }

    // Clamp to the window rect so SetWindowRgn never exceeds the window.
    if (win) {
        const QRect winRect(0, 0, win->width(), win->height());
        out = out.intersected(winRect);
    }
    return out;
}

// ---------------------------------------------------------------------------
// PanelWindow
// ---------------------------------------------------------------------------

PanelWindow::PanelWindow(QWindow* parent)
    : QQuickWindow(parent)
    , m_anchors(new WindowAnchors(this))
{
    setFlags(flags() | Qt::Tool | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    setColor(Qt::transparent);

    // Request an alpha channel so per-pixel translucency actually works.
    QSurfaceFormat fmt = format();
    fmt.setAlphaBufferSize(8);
    setFormat(fmt);

    connect(m_anchors, &WindowAnchors::changed, this, &PanelWindow::recomputeGeometry);
    connect(this, &QWindow::activeChanged, this, [this]() {
        if (!isActive())
            emit windowDeactivated();
    });
    // Content-driven sizing (QML sets height after anchors): keep the edge
    // placement honest whenever the window size changes.
    connect(this, &QWindow::widthChanged, this, &PanelWindow::recompute);
    connect(this, &QWindow::heightChanged, this, &PanelWindow::recompute);
    connect(this, &QWindow::visibleChanged, this, [this](bool vis) {
        if (vis) {
            recomputeGeometry();
            applyClickThrough();
            updateMask();
            applyBlurBehind();
            applyFileDrops();
            if (m_reserveTopBar)
                registerOrUpdateAppBar();
        } else {
            unregisterAppBar();
        }
    });
    m_fsGuardTimer.setInterval(300);
    connect(&m_fsGuardTimer, &QTimer::timeout, this, &PanelWindow::verifyFullscreenState);
    connect(this, &QWindow::screenChanged, this, [this](QScreen*) {
        recomputeGeometry();
        updateMask();
        if (m_reserveTopBar && isVisible())
            registerOrUpdateAppBar();
    });
    if (auto* app = QCoreApplication::instance()) {
        connect(app, &QCoreApplication::aboutToQuit, this, &PanelWindow::unregisterAppBar);
    }
}

PanelWindow::~PanelWindow()
{
    unregisterAppBar();
}

void PanelWindow::recompute()
{
    recomputeGeometry();
    updateMask();
    if (m_blurBehind && isVisible())
        applyBlurBehind();
}

void PanelWindow::recomputeGeometry()
{
    QScreen* scr = screen();
    if (!scr)
        scr = QGuiApplication::primaryScreen();
    if (!scr)
        return;

    const QRect geo = scr->geometry();
    const MarginGroup* mg = m_anchors->margins();
    const int mL = mg->left();
    const int mT = mg->top();
    const int mR = mg->right();
    const int mB = mg->bottom();

    // Horizontal placement. If both edges anchored, we own the width.
    if (m_anchors->left() && m_anchors->right()) {
        const int w = qMax(1, geo.width() - mL - mR);
        setX(geo.left() + mL);
        setWidth(w);
        m_geometryOwned = true;
    } else if (m_anchors->left()) {
        setX(geo.left() + mL);
        m_geometryOwned = true;
    } else if (m_anchors->right()) {
        setX(geo.right() + 1 - mR - width());
        m_geometryOwned = true;
    } else if (m_geometryOwned) {
        setX(geo.center().x() - width() / 2);
    }

    // Vertical placement.
    if (m_anchors->top() && m_anchors->bottom()) {
        const int h = qMax(1, geo.height() - mT - mB);
        setY(geo.top() + mT);
        setHeight(h);
        m_geometryOwned = true;
    } else if (m_anchors->top()) {
        setY(geo.top() + mT);
        m_geometryOwned = true;
    } else if (m_anchors->bottom()) {
        setY(geo.bottom() + 1 - mB - height());
        m_geometryOwned = true;
    } else if (m_geometryOwned) {
        setY(geo.center().y() - height() / 2);
    }
}

void PanelWindow::setClickThrough(bool on)
{
    if (m_clickThrough == on)
        return;
    m_clickThrough = on;
    applyClickThrough();
    emit clickThroughChanged();
}

void PanelWindow::applyClickThrough()
{
#ifdef Q_OS_WIN
    if (!isVisible())
        return;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    LONG_PTR exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (m_clickThrough)
        exStyle |= WS_EX_TRANSPARENT | WS_EX_LAYERED;
    else
        exStyle &= ~WS_EX_TRANSPARENT;
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, exStyle);
#endif
}

void PanelWindow::setMaskProperty(const QVariant& mask)
{
    if (m_mask == mask)
        return;

    m_mask = mask;

    // Track dynamic region sources (item-anchored masks move on layout).
    if (QObject* obj = m_mask.value<QObject*>()) {
        connect(obj, &QObject::destroyed, this, &PanelWindow::updateMask,
                Qt::UniqueConnection);
        if (auto* reg = qobject_cast<QsRegion*>(obj))
            connect(reg, &QsRegion::regionsChanged, this, &PanelWindow::updateMask,
                    Qt::UniqueConnection);
    }

    emit maskChanged();
    updateMask();
}

void PanelWindow::updateMask()
{
    if (!isVisible())
        return;

    QRegion next;
    if (QObject* obj = m_mask.value<QObject*>()) {
        if (auto* region = qobject_cast<QsRegion*>(obj)) {
            next = region->regionRelativeTo(this);
        }
    } else if (m_mask.canConvert<QVariantList>()) {
        const QVariantList rects = m_mask.toList();
        for (const QVariant& v : rects) {
            const QVariantMap r = v.toMap();
            next += QRect(r.value(QStringLiteral("x")).toInt(),
                          r.value(QStringLiteral("y")).toInt(),
                          r.value(QStringLiteral("width")).toInt(),
                          r.value(QStringLiteral("height")).toInt());
        }
    }

    if (m_blurBehind && next.isEmpty()) {
        applyBlurBehind();
        return;
    }

    if (m_hasAppliedMask && m_lastMask == next)
        return;
    m_lastMask = next;
    m_hasAppliedMask = true;
    setMask(next);
}

void PanelWindow::setBlurBehind(bool on)
{
    if (m_blurBehind == on)
        return;
    m_blurBehind = on;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::setBlurRadius(int r)
{
    if (m_blurRadius == r)
        return;
    m_blurRadius = r;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::setBlurInsetX(int v)
{
    if (m_blurInsetX == v)
        return;
    m_blurInsetX = v;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::setBlurInsetY(int v)
{
    if (m_blurInsetY == v)
        return;
    m_blurInsetY = v;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::setBlurInsetRight(int v)
{
    if (m_blurInsetRight == v)
        return;
    m_blurInsetRight = v;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::setBlurInsetBottom(int v)
{
    if (m_blurInsetBottom == v)
        return;
    m_blurInsetBottom = v;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::setBlurTint(const QColor& c)
{
    if (m_blurTint == c)
        return;
    m_blurTint = c;
    emit blurChanged();
    applyBlurBehind();
}

void PanelWindow::applyBlurBehind()
{
#ifdef Q_OS_WIN
    if (!isVisible())
        return;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (!hwnd || !IsWindow(hwnd))
        return;

    struct AccentPolicy {
        int AccentState;
        int AccentFlags;
        DWORD GradientColor;
        int AnimationId;
    };
    struct WindowCompositionAttribData {
        int Attrib;
        PVOID pvData;
        SIZE_T cbData;
    };
    using FnSetWindowCompositionAttribute = BOOL(WINAPI*)(HWND, WindowCompositionAttribData*);
    static auto fnSetWCA = reinterpret_cast<FnSetWindowCompositionAttribute>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute"));

    if (m_blurBehind) {
        if (fnSetWCA) {
            const DWORD a = static_cast<DWORD>(qBound(0, m_blurTint.alpha(), 255));
            const DWORD r = static_cast<DWORD>(m_blurTint.red());
            const DWORD g = static_cast<DWORD>(m_blurTint.green());
            const DWORD b = static_cast<DWORD>(m_blurTint.blue());
            AccentPolicy policy{};
            policy.AccentState = 4; // ACCENT_ENABLE_ACRYLICBLURBEHIND
            policy.AccentFlags = 2;
            policy.GradientColor = (a << 24) | (b << 16) | (g << 8) | r;
            WindowCompositionAttribData data{ 19 /*WCA_ACCENT_POLICY*/, &policy, sizeof(policy) };
            fnSetWCA(hwnd, &data);
        }

        const qreal dpr = devicePixelRatio();
        const int x1 = qRound(m_blurInsetX * dpr);
        const int y1 = qRound(m_blurInsetY * dpr);
        const int x2 = qMax(x1 + 2, qRound((width() - m_blurInsetRight) * dpr));
        const int y2 = qMax(y1 + 2, qRound((height() - m_blurInsetBottom) * dpr));
        const int rad = qMax(0, qRound(m_blurRadius * 2 * dpr));
        HRGN rgn = (rad > 0) ? CreateRoundRectRgn(x1, y1, x2 + 1, y2 + 1, rad, rad)
                             : CreateRectRgn(x1, y1, x2, y2);
        if (rgn)
            SetWindowRgn(hwnd, rgn, TRUE);
    } else if (fnSetWCA) {
        AccentPolicy policy{};
        policy.AccentState = 0; // ACCENT_DISABLED
        WindowCompositionAttribData data{ 19, &policy, sizeof(policy) };
        fnSetWCA(hwnd, &data);
    }
#endif
}

void PanelWindow::setReserveTopBar(bool on)
{
    if (m_reserveTopBar == on)
        return;
    m_reserveTopBar = on;
    emit reserveTopBarChanged();
    if (m_reserveTopBar && isVisible())
        registerOrUpdateAppBar();
    else if (!m_reserveTopBar)
        unregisterAppBar();
}

void PanelWindow::setReserveHeight(int h)
{
    if (m_reserveHeight == h)
        return;
    m_reserveHeight = h;
    emit reserveHeightChanged();
    if (m_reserveTopBar && isVisible())
        registerOrUpdateAppBar();
}

void PanelWindow::registerOrUpdateAppBar()
{
#ifdef Q_OS_WIN
    if (!m_reserveTopBar || !isVisible())
        return;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (!hwnd || !IsWindow(hwnd))
        return;

    const HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(mon, &mi))
        return;

    const int physH = qMax(24, qRound(m_reserveHeight * devicePixelRatio()));
    APPBARDATA abd{};
    abd.cbSize = sizeof(abd);
    abd.hWnd = hwnd;
    abd.uCallbackMessage = kAppBarCallbackMsg;
    abd.uEdge = ABE_TOP;
    abd.rc = mi.rcMonitor;
    abd.rc.bottom = abd.rc.top + physH;

    if (!m_appBarRegistered) {
        SHAppBarMessage(ABM_NEW, &abd);
        m_appBarRegistered = true;
    }
    SHAppBarMessage(ABM_QUERYPOS, &abd);
    abd.rc.bottom = abd.rc.top + physH;
    SHAppBarMessage(ABM_SETPOS, &abd);
#endif
}

void PanelWindow::unregisterAppBar()
{
#ifdef Q_OS_WIN
    if (!m_appBarRegistered)
        return;
    m_appBarRegistered = false;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (!hwnd)
        return;
    APPBARDATA abd{};
    abd.cbSize = sizeof(abd);
    abd.hWnd = hwnd;
    SHAppBarMessage(ABM_REMOVE, &abd);
#endif
}

#ifdef Q_OS_WIN
static bool isGenuineFullscreenForeground()
{
    HWND fg = GetForegroundWindow();
    if (!fg || !IsWindow(fg) || !IsWindowVisible(fg) || IsIconic(fg))
        return false;

    wchar_t cls[64]{};
    GetClassNameW(fg, cls, 64);
    if (wcscmp(cls, L"Progman") == 0
        || wcscmp(cls, L"WorkerW") == 0
        || wcscmp(cls, L"Shell_TrayWnd") == 0
        || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0
        || wcscmp(cls, L"NotifyIconOverflowWindow") == 0) {
        return false;
    }

    DWORD fgPid = 0;
    GetWindowThreadProcessId(fg, &fgPid);
    if (fgPid == GetCurrentProcessId())
        return false;
    if (fgPid != 0) {
        HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, fgPid);
        if (hProc) {
            wchar_t exePath[MAX_PATH]{};
            DWORD sz = MAX_PATH;
            if (QueryFullProcessImageNameW(hProc, 0, exePath, &sz)) {
                const wchar_t* base = wcsrchr(exePath, L'\\');
                const wchar_t* name = base ? base + 1 : exePath;
                if (_wcsicmp(name, L"wallpaper64.exe") == 0
                    || _wcsicmp(name, L"wallpaper32.exe") == 0
                    || _wcsicmp(name, L"explorer.exe") == 0) {
                    CloseHandle(hProc);
                    return false;
                }
            }
            CloseHandle(hProc);
        }
    }

    const HMONITOR mon = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(mon, &mi))
        return false;

    RECT rc{};
    if (!GetWindowRect(fg, &rc))
        return false;

    // Normal maximized app with titlebar respects TopBar work area or sits above taskbar: not exclusive fullscreen
    const LONG_PTR style = GetWindowLongPtrW(fg, GWL_STYLE);
    if ((style & WS_CAPTION) == WS_CAPTION)
        return false;

    return rc.left <= mi.rcMonitor.left
        && rc.top <= mi.rcMonitor.top
        && rc.right >= mi.rcMonitor.right
        && rc.bottom >= mi.rcMonitor.bottom;
}
#endif

void PanelWindow::verifyFullscreenState()
{
#ifdef Q_OS_WIN
    if (m_fullscreenActive && !isGenuineFullscreenForeground()) {
        m_fullscreenActive = false;
        m_fsGuardTimer.stop();
        emit fullscreenActiveChanged();
        if (!m_desktopLayer && isVisible()) {
            HWND hwnd = reinterpret_cast<HWND>(winId());
            if (hwnd) {
                SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }
    }
#endif
}

bool PanelWindow::nativeEvent(const QByteArray& eventType, void* message, qintptr* result)
{
#ifdef Q_OS_WIN
    if (eventType == "windows_generic_MSG" || eventType == "windows_dispatcher_MSG") {
        const MSG* msg = static_cast<const MSG*>(message);
        if (msg && msg->message == WM_DROPFILES && m_acceptFileDrops) {
            HDROP hDrop = reinterpret_cast<HDROP>(msg->wParam);
            const UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
            QStringList dropped;
            for (UINT i = 0; i < count; ++i) {
                const UINT len = DragQueryFileW(hDrop, i, nullptr, 0);
                if (len == 0)
                    continue;
                QString path(static_cast<int>(len), Qt::Uninitialized);
                DragQueryFileW(hDrop, i, reinterpret_cast<wchar_t*>(path.data()), len + 1);
                dropped << path;
            }
            DragFinish(hDrop);
            if (!dropped.isEmpty())
                emit filesDropped(dropped);
            if (result)
                *result = 0;
            return true;
        }
        if (msg && msg->message == kAppBarCallbackMsg) {
            if (msg->wParam == ABN_POSCHANGED && m_reserveTopBar && isVisible()) {
                registerOrUpdateAppBar();
                if (!m_fullscreenActive && !m_desktopLayer) {
                    HWND hwnd = reinterpret_cast<HWND>(winId());
                    if (hwnd)
                        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                }
            } else if (msg->wParam == ABN_FULLSCREENAPP) {
                bool fs = (msg->lParam != 0) && isGenuineFullscreenForeground();
                if (m_fullscreenActive != fs) {
                    m_fullscreenActive = fs;
                    if (fs)
                        m_fsGuardTimer.start();
                    else
                        m_fsGuardTimer.stop();
                    emit fullscreenActiveChanged();
                }
            }
        }
    }
#else
    Q_UNUSED(eventType);
    Q_UNUSED(message);
    Q_UNUSED(result);
#endif
    return QQuickWindow::nativeEvent(eventType, message, result);
}

bool PanelWindow::isPointerOutsideAndPressed() const
{
#ifdef Q_OS_WIN
    const bool down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0
                   || (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;
    if (!down)
        return false;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (!hwnd)
        return false;
    RECT rc{};
    if (!GetWindowRect(hwnd, &rc))
        return false;
    POINT pt{};
    if (!GetCursorPos(&pt))
        return false;
    const bool inside = (pt.x >= rc.left && pt.x <= rc.right && pt.y >= rc.top && pt.y <= rc.bottom);
    return !inside;
#else
    return false;
#endif
}

void PanelWindow::setDesktopLayer(bool on)
{
    if (m_desktopLayer == on)
        return;
    m_desktopLayer = on;
    if (on) {
        setFlags(flags() & ~Qt::WindowStaysOnTopHint);
    } else {
        setFlags(flags() | Qt::WindowStaysOnTopHint);
    }
#ifdef Q_OS_WIN
    if (isVisible()) {
        HWND hwnd = reinterpret_cast<HWND>(winId());
        if (hwnd) {
            SetWindowPos(hwnd, on ? HWND_NOTOPMOST : HWND_TOPMOST,
                         0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }
#endif
    emit desktopLayerChanged();
}

void PanelWindow::raiseOnDesktop()
{
#ifdef Q_OS_WIN
    if (!m_desktopLayer || !isVisible())
        return;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (!hwnd)
        return;
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
#endif
}

void PanelWindow::setAcceptFileDrops(bool on)
{
    if (m_acceptFileDrops == on)
        return;
    m_acceptFileDrops = on;
    applyFileDrops();
    emit acceptFileDropsChanged();
}

void PanelWindow::applyFileDrops()
{
#ifdef Q_OS_WIN
    if (!isVisible())
        return;
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (!hwnd)
        return;
    DragAcceptFiles(hwnd, m_acceptFileDrops ? TRUE : FALSE);
    if (m_acceptFileDrops) {
        using FnFilterEx = BOOL(WINAPI*)(HWND, UINT, DWORD, void*);
        static auto fnFilter = reinterpret_cast<FnFilterEx>(
            GetProcAddress(GetModuleHandleW(L"user32.dll"), "ChangeWindowMessageFilterEx"));
        if (fnFilter) {
            // Allow drag-drop from medium-integrity Explorer even if SekaiDesk runs elevated
            fnFilter(hwnd, WM_DROPFILES, 1 /*MSGFLT_ALLOW*/, nullptr);
            fnFilter(hwnd, WM_COPYDATA, 1 /*MSGFLT_ALLOW*/, nullptr);
            fnFilter(hwnd, 0x0049 /*WM_COPYGLOBALDATA*/, 1 /*MSGFLT_ALLOW*/, nullptr);
        }
    }
#endif
}

void PanelWindow::focusActivate()
{
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(winId());
    if (hwnd) {
        SetForegroundWindow(hwnd);
        BringWindowToTop(hwnd);
    }
#endif
    requestActivate();
}
