#pragma once
// WinIconProvider — QQuickImageProvider("winicon") extracting native Windows
// icons (HICON -> QImage) for .exe / .lnk / shell targets.

#include <QQuickImageProvider>

class WinIconProvider : public QQuickImageProvider {
public:
    WinIconProvider();

    QImage requestImage(const QString& id, QSize* size,
                        const QSize& requestedSize) override;
};
