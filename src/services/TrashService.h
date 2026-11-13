#pragma once
// TrashService — native Windows Recycle Bin status & actions
// (SHQueryRecycleBinW / SHEmptyRecycleBinW / ShellExecuteW).

#include <QObject>
#include <QTimer>

class TrashService : public QObject {
    Q_OBJECT
    Q_PROPERTY(qint64 itemCount READ itemCount NOTIFY stateChanged)
    Q_PROPERTY(bool isEmpty READ isEmpty NOTIFY stateChanged)

public:
    explicit TrashService(QObject* parent = nullptr);

    qint64 itemCount() const { return m_itemCount; }
    bool isEmpty() const { return m_itemCount == 0; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void openBin();
    Q_INVOKABLE void emptyBin();

signals:
    void stateChanged();

private:
    QTimer m_timer;
    qint64 m_itemCount = 0;
};
