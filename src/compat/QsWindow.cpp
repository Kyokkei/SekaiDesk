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
            if (m_reserveTopBar)
                registerOrUpdateAppBar();
        } else {
            unregisterAppBar();
        }
    });
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

    if (m_hasAppliedMask && m_lastMask == next)
        return;
    m_lastMask = next;
    m_hasAppliedMask = true;
    setMask(next);
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

bool PanelWindow::nativeEvent(const QByteArray& eventType, void* message, qintptr* result)
{
#ifdef Q_OS_WIN
    if (eventType == "windows_generic_MSG" || eventType == "windows_dispatcher_MSG") {
        const MSG* msg = static_cast<const MSG*>(message);
        if (msg && msg->message == kAppBarCallbackMsg) {
            if (msg->wParam == ABN_POSCHANGED && m_reserveTopBar && isVisible()) {
                registerOrUpdateAppBar();
            } else if (msg->wParam == ABN_FULLSCREENAPP) {
                bool fs = (msg->lParam != 0);
                if (fs) {
                    HWND fg = GetForegroundWindow();
                    if (fg) {
                        wchar_t cls[64]{};
                        GetClassNameW(fg, cls, 64);
                        if (wcscmp(cls, L"Progman") == 0
                            || wcscmp(cls, L"WorkerW") == 0
                            || wcscmp(cls, L"Shell_TrayWnd") == 0
                            || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) {
                            fs = false;
                        }
                    }
                }
                if (m_fullscreenActive != fs) {
                    m_fullscreenActive = fs;
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
