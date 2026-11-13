#pragma once
// ClipboardService — Win32 AddClipboardFormatListener history tracker.

#include <QObject>
#include <QVariantList>

class ClipboardService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int count READ count NOTIFY historyChanged)

public:
    explicit ClipboardService(QObject* parent = nullptr);
    ~ClipboardService() override;

    QVariantList history() const { return m_history; }
    int count() const { return m_history.size(); }

    Q_INVOKABLE void copyIndex(int index);
    Q_INVOKABLE void copyText(const QString& text);
    Q_INVOKABLE void togglePin(int index);
    Q_INVOKABLE void removeIndex(int index);
    Q_INVOKABLE void clearUnpinned();

    void handleClipboardUpdate();

signals:
    void historyChanged();

private:
    void captureClipboard(bool initial = false);

    QVariantList m_history;
    QString m_suppressText;
#ifdef Q_OS_WIN
    void* m_hwnd = nullptr;
#endif
};
