#pragma once
// WindowTracker — enumerates active top-level Windows applications for the Dock
// (running dots, unpinned running apps, click-to-focus / minimize toggle).

#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class WindowTracker : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList runningApps READ runningApps NOTIFY runningAppsChanged)
    Q_PROPERTY(bool dockOverlap READ dockOverlap NOTIFY dockOverlapChanged)
    Q_PROPERTY(bool bottomEdgeHovered READ bottomEdgeHovered NOTIFY bottomEdgeHoveredChanged)
    Q_PROPERTY(bool topOverlap READ topOverlap NOTIFY topOverlapChanged)
    Q_PROPERTY(bool topEdgeHovered READ topEdgeHovered NOTIFY topEdgeHoveredChanged)
    Q_PROPERTY(QString activeAppName READ activeAppName NOTIFY activeWindowChanged)
    Q_PROPERTY(QString activeWindowTitle READ activeWindowTitle NOTIFY activeWindowChanged)
    Q_PROPERTY(int cpuUsage READ cpuUsage NOTIFY statsChanged)
    Q_PROPERTY(int ramUsage READ ramUsage NOTIFY statsChanged)
    Q_PROPERTY(int cpuTemp READ cpuTemp NOTIFY statsChanged)
    Q_PROPERTY(int gpuTemp READ gpuTemp NOTIFY statsChanged)
    Q_PROPERTY(QString uptimeText READ uptimeText NOTIFY statsChanged)
    Q_PROPERTY(QString machineName READ machineName CONSTANT)
    Q_PROPERTY(QString userName READ userName CONSTANT)

public:
    explicit WindowTracker(QObject* parent = nullptr);

    QVariantList runningApps() const { return m_runningApps; }
    bool dockOverlap() const { return m_dockOverlap; }
    bool bottomEdgeHovered() const { return m_bottomEdgeHovered; }
    bool topOverlap() const { return m_topOverlap; }
    bool topEdgeHovered() const { return m_topEdgeHovered; }
    QString activeAppName() const { return m_activeAppName; }
    QString activeWindowTitle() const { return m_activeWindowTitle; }
    int cpuUsage() const { return m_cpuUsage; }
    int ramUsage() const { return m_ramUsage; }
    int cpuTemp() const { return m_cpuTemp; }
    int gpuTemp() const { return m_gpuTemp; }
    QString uptimeText() const { return m_uptimeText; }
    QString machineName() const { return m_machineName; }
    QString userName() const { return m_userName; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap stateForTarget(const QString& target) const;
    Q_INVOKABLE bool activateOrToggle(const QString& target);
    Q_INVOKABLE QVariantList windowsForTarget(const QString& target) const;
    Q_INVOKABLE bool activateHwnd(qulonglong hwnd);
    Q_INVOKABLE bool minimizeHwnd(qulonglong hwnd);
    Q_INVOKABLE bool closeHwnd(qulonglong hwnd);
    Q_INVOKABLE bool openSpecialFolder(const QString& kind);
    Q_INVOKABLE void lockWorkstation();
    Q_INVOKABLE void sleepComputer();
    Q_INVOKABLE void takeScreenshot();

signals:
    void runningAppsChanged();
    void dockOverlapChanged();
    void bottomEdgeHoveredChanged();
    void topOverlapChanged();
    void topEdgeHoveredChanged();
    void activeWindowChanged();
    void statsChanged();

private:
    void pollEdgeAndOverlap();
    void updateSystemStats();
    struct AppGroup {
        QString exePath;
        QString exeKey;
        QString name;
        QList<quintptr> hwnds;
        quintptr primaryHwnd = 0;
        bool active = false;
        bool allMinimized = true;
    };

    QTimer m_pollTimer;
    QTimer m_edgeTimer;
    bool m_dockOverlap = false;
    bool m_bottomEdgeHovered = false;
    bool m_topOverlap = false;
    bool m_topEdgeHovered = false;
    QString m_activeAppName = QStringLiteral("Desktop");
    QString m_activeWindowTitle;
    int m_cpuUsage = 0;
    int m_ramUsage = 0;
    int m_cpuTemp = -1;
    int m_gpuTemp = -1;
    QString m_uptimeText = QStringLiteral("0m");
    QString m_machineName;
    QString m_userName;
    quint64 m_prevIdleTime = 0;
    quint64 m_prevKernelTime = 0;
    quint64 m_prevUserTime = 0;
    QVariantList m_runningApps;
    QHash<QString, AppGroup> m_groups;
};
