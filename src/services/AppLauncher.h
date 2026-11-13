#pragma once
// AppLauncher — manages pinned dock apps from config/sekaidesk.json and
// launches targets natively on Windows via ShellExecuteW.

#include <QObject>
#include <QVariantList>

class SettingsStore;

class AppLauncher : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList pinnedApps READ pinnedApps NOTIFY pinnedAppsChanged)

public:
    explicit AppLauncher(SettingsStore* settings, QObject* parent = nullptr);

    QVariantList pinnedApps() const { return m_pinnedApps; }

    Q_INVOKABLE bool launch(const QString& target, const QString& args = {});
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

private:
    void seedDefaultsIfEmpty();
    void savePinnedApps();

    SettingsStore* m_settings = nullptr;
    QVariantList m_pinnedApps;
};
