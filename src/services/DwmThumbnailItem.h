#pragma once
// DwmThumbnailItem — QQuickItem hosting a live 60fps Windows DWM thumbnail
// (DwmRegisterThumbnail + DwmUpdateThumbnailProperties) composited directly
// into the owning QQuickWindow HWND.

#include <QQuickItem>
#include <QRectF>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#endif

class DwmThumbnailItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(qulonglong sourceHwnd READ sourceHwnd WRITE setSourceHwnd NOTIFY sourceHwndChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QSize sourceSize READ sourceSize NOTIFY sourceSizeChanged)

public:
    explicit DwmThumbnailItem(QQuickItem* parent = nullptr);
    ~DwmThumbnailItem() override;

    qulonglong sourceHwnd() const { return m_sourceHwnd; }
    void setSourceHwnd(qulonglong hwnd);

    bool active() const { return m_active; }
    void setActive(bool active);

    QSize sourceSize() const { return m_sourceSize; }

signals:
    void sourceHwndChanged();
    void activeChanged();
    void sourceSizeChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData& value) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private slots:
    void syncThumbnail();

private:
    void registerThumb();
    void unregisterThumb();
    void updateProperties();

    qulonglong m_sourceHwnd = 0;
    bool m_active = true;
    QSize m_sourceSize;

#ifdef Q_OS_WIN
    HTHUMBNAIL m_thumbId = nullptr;
    HWND m_registeredDest = nullptr;
    HWND m_registeredSrc = nullptr;
#endif
};
