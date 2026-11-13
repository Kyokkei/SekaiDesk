#include "DwmThumbnailItem.h"

#include <QQuickWindow>

DwmThumbnailItem::DwmThumbnailItem(QQuickItem* parent)
    : QQuickItem(parent)
{
    connect(this, &QQuickItem::visibleChanged, this, &DwmThumbnailItem::syncThumbnail);
    connect(this, &QQuickItem::xChanged, this, &DwmThumbnailItem::syncThumbnail);
    connect(this, &QQuickItem::yChanged, this, &DwmThumbnailItem::syncThumbnail);
}

DwmThumbnailItem::~DwmThumbnailItem()
{
    unregisterThumb();
}

void DwmThumbnailItem::setSourceHwnd(qulonglong hwnd)
{
    if (m_sourceHwnd == hwnd)
        return;
    m_sourceHwnd = hwnd;
    emit sourceHwndChanged();
    registerThumb();
}

void DwmThumbnailItem::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
    syncThumbnail();
}

void DwmThumbnailItem::itemChange(ItemChange change, const ItemChangeData& value)
{
    QQuickItem::itemChange(change, value);
    if (change == ItemSceneChange || change == ItemVisibleHasChanged) {
        if (change == ItemSceneChange && value.window) {
            connect(value.window, &QWindow::visibleChanged,
                    this, &DwmThumbnailItem::syncThumbnail, Qt::UniqueConnection);
            connect(value.window, &QQuickWindow::afterSynchronizing,
                    this, &DwmThumbnailItem::updateProperties, Qt::UniqueConnection);
        }
        registerThumb();
    }
}

void DwmThumbnailItem::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    updateProperties();
}

void DwmThumbnailItem::syncThumbnail()
{
    if (!m_active || !isVisible() || !window() || !window()->isVisible() || m_sourceHwnd == 0) {
        unregisterThumb();
        return;
    }
    registerThumb();
}

void DwmThumbnailItem::registerThumb()
{
#ifdef Q_OS_WIN
    if (!m_active || !isVisible() || !window() || !window()->isVisible() || m_sourceHwnd == 0) {
        unregisterThumb();
        return;
    }

    HWND dest = reinterpret_cast<HWND>(window()->winId());
    HWND src = reinterpret_cast<HWND>(static_cast<quintptr>(m_sourceHwnd));
    if (!dest || !src || !IsWindow(src)) {
        unregisterThumb();
        return;
    }

    if (m_thumbId && m_registeredDest == dest && m_registeredSrc == src) {
        updateProperties();
        return;
    }

    unregisterThumb();

    HTHUMBNAIL thumb = nullptr;
    if (SUCCEEDED(DwmRegisterThumbnail(dest, src, &thumb)) && thumb) {
        m_thumbId = thumb;
        m_registeredDest = dest;
        m_registeredSrc = src;

        SIZE sz = {};
        if (SUCCEEDED(DwmQueryThumbnailSourceSize(m_thumbId, &sz))) {
            const QSize nextSz(sz.cx, sz.cy);
            if (m_sourceSize != nextSz) {
                m_sourceSize = nextSz;
                emit sourceSizeChanged();
            }
        }
        updateProperties();
    }
#endif
}

void DwmThumbnailItem::unregisterThumb()
{
#ifdef Q_OS_WIN
    if (m_thumbId) {
        DwmUnregisterThumbnail(m_thumbId);
        m_thumbId = nullptr;
        m_registeredDest = nullptr;
        m_registeredSrc = nullptr;
    }
#endif
}

void DwmThumbnailItem::updateProperties()
{
#ifdef Q_OS_WIN
    if (!m_thumbId || !window())
        return;

    const QRectF sceneRect = mapRectToScene(QRectF(0, 0, width(), height()));
    if (sceneRect.width() < 2 || sceneRect.height() < 2)
        return;

    const qreal dpr = window()->effectiveDevicePixelRatio();
    RECT destRect;
    destRect.left = qRound(sceneRect.left() * dpr);
    destRect.top = qRound(sceneRect.top() * dpr);
    destRect.right = qRound(sceneRect.right() * dpr);
    destRect.bottom = qRound(sceneRect.bottom() * dpr);

    // Preserve source aspect ratio centered inside destRect.
    if (m_sourceSize.width() > 0 && m_sourceSize.height() > 0) {
        const qreal boxW = destRect.right - destRect.left;
        const qreal boxH = destRect.bottom - destRect.top;
        const qreal scale = qMin(boxW / m_sourceSize.width(), boxH / m_sourceSize.height());
        const int fitW = qMax(1, qRound(m_sourceSize.width() * scale));
        const int fitH = qMax(1, qRound(m_sourceSize.height() * scale));
        const int offX = qRound((boxW - fitW) * 0.5);
        const int offY = qRound((boxH - fitH) * 0.5);
        destRect.left += offX;
        destRect.top += offY;
        destRect.right = destRect.left + fitW;
        destRect.bottom = destRect.top + fitH;
    }

    DWM_THUMBNAIL_PROPERTIES props = {};
    props.dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY | DWM_TNP_SOURCECLIENTAREAONLY;
    props.rcDestination = destRect;
    props.fVisible = (m_active && isVisible()) ? TRUE : FALSE;
    props.opacity = 255;
    props.fSourceClientAreaOnly = FALSE;

    DwmUpdateThumbnailProperties(m_thumbId, &props);
#endif
}
