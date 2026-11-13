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

public:
    explicit WindowTracker(QObject* parent = nullptr);

    QVariantList runningApps() const { return m_runningApps; }
    bool dockOverlap() const { return m_dockOverlap; }
    bool bottomEdgeHovered() const { return m_bottomEdgeHovered; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap stateForTarget(const QString& target) const;
    Q_INVOKABLE bool activateOrToggle(const QString& target);
    Q_INVOKABLE QVariantList windowsForTarget(const QString& target) const;
    Q_INVOKABLE bool activateHwnd(qulonglong hwnd);
    Q_INVOKABLE bool minimizeHwnd(qulonglong hwnd);
    Q_INVOKABLE bool closeHwnd(qulonglong hwnd);

signals:
    void runningAppsChanged();
    void dockOverlapChanged();
    void bottomEdgeHoveredChanged();

private:
    void pollEdgeAndOverlap();
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
    QVariantList m_runningApps;
    QHash<QString, AppGroup> m_groups;
};
