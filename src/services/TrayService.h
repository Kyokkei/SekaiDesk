#pragma once
// TrayService — Reads live Windows System Tray icons (Shell_TrayWnd +
// NotifyIconOverflowWindow) and forwards left/right click messages.

#include <QObject>
#include <QVariantList>

class TrayService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)

public:
    explicit TrayService(QObject* parent = nullptr);
    ~TrayService() override;

    QVariantList items() const { return m_items; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void activateItem(int index, bool rightClick);

signals:
    void itemsChanged();

private:
    struct InternalItem {
        quintptr hwnd = 0;
        uint uID = 0;
        uint uCallbackMessage = 0;
        QString tip;
        QString iconUrl;
    };

    QVector<InternalItem> m_raw;
    QVariantList m_items;
    QString m_iconDir;
};
