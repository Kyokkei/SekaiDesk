#pragma once
// NotificationService — Windows 10/11 Toast notification listener via persistent
// hidden PowerShell WinRT worker (UserNotificationListener).

#include <QObject>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class NotificationService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int count READ count NOTIFY notificationsChanged)
    Q_PROPERTY(bool accessGranted READ accessGranted NOTIFY accessGrantedChanged)

public:
    explicit NotificationService(QObject* parent = nullptr);
    ~NotificationService() override;

    QVariantList notifications() const { return m_notifications; }
    int count() const { return m_notifications.size(); }
    bool accessGranted() const { return m_accessGranted; }

    Q_INVOKABLE void dismiss(quint32 id);
    Q_INVOKABLE void clearAll();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void emitTestNotification();

signals:
    void notificationsChanged();
    void accessGrantedChanged();
    void newNotificationReceived(const QVariantMap& item);

private:
    void startWorker();
    void sendCommand(const QString& cmd);
    void onStdoutReady();
    void refreshTimeTexts();

    QVariantList m_notifications;
    bool m_accessGranted = false;
    bool m_initialPollDone = false;
    QSet<QString> m_seenToastKeys;
    QString m_cmdFile;
    QString m_iconDir;
    QProcess* m_proc = nullptr;
    QByteArray m_buf;
    QTimer m_ageTimer;
};
