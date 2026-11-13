#pragma once
// AppLauncher — manages pinned dock apps from config/sekaidesk.json and
// launches targets natively on Windows via ShellExecuteW.

#include <QObject>
#include <QVariantList>

class SettingsStore;

class AppLauncher : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList pinnedApps READ pinnedApps NOTIFY pinnedAppsChanged)
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY installedAppsChanged)

public:
    explicit AppLauncher(SettingsStore* settings, QObject* parent = nullptr);

    QVariantList pinnedApps() const { return m_pinnedApps; }
    QVariantList installedApps() const { return m_installedApps; }

    Q_INVOKABLE bool launch(const QString& target, const QString& args = {});
    Q_INVOKABLE QVariantList searchApps(const QString& query) const;
    Q_INVOKABLE void refreshInstalledApps();
    Q_INVOKABLE void addPinnedApp(const QString& name, const QString& target,
                                  const QString& args = {});
    Q_INVOKABLE void removePinnedApp(int index);
    Q_INVOKABLE void removePinnedByTarget(const QString& target);
    Q_INVOKABLE void movePinnedApp(int fromIndex, int toIndex);
    Q_INVOKABLE void insertSeparatorAt(int index);
    Q_INVOKABLE void pinAppAt(const QString& name, const QString& target,
                              const QString& args, int index);
    Q_INVOKABLE void reorderDock(const QVariantList& currentAppItems,
                                 int fromIndex, int toIndex);
    Q_INVOKABLE void reload();

signals:
    void pinnedAppsChanged();
    void installedAppsChanged();

private:
    void seedDefaultsIfEmpty();
    void savePinnedApps();

    SettingsStore* m_settings = nullptr;
    QVariantList m_pinnedApps;
    QVariantList m_installedApps;
};
