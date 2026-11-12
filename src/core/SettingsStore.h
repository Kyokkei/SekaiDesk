#pragma once
// SettingsStore — the single source of truth for SekaiDesk configuration.
// Backing file: <app dir>/config/sekaidesk.json (portable, plain JSON).
// Exposed to QML as singleton `SekaiDesk.ConfigStore`.

#include <QJsonObject>
#include <QObject>
#include <QVariant>

class SettingsStore : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString filePath READ filePath CONSTANT)

public:
    explicit SettingsStore(QObject* parent = nullptr);

    QString filePath() const { return m_filePath; }

    // Loads (or creates) config/sekaidesk.json. Called once from main().
    void ensureLoaded();

    Q_INVOKABLE QVariant get(const QString& key, const QVariant& fallback = {}) const;
    Q_INVOKABLE void set(const QString& key, const QVariant& value);
    Q_INVOKABLE bool has(const QString& key) const;
    Q_INVOKABLE void remove(const QString& key);

    // Dotted-path helper for nested keys, e.g. get("dock.iconSize").
    static QVariant lookupPath(const QJsonObject& root, const QString& dottedPath);
    static void writePath(QJsonObject& root, const QString& dottedPath,
                          const QJsonValue& value);

    // C++-side typed accessors for core services.
    bool boolValue(const QString& dottedPath, bool fallback = false) const;
    int intValue(const QString& dottedPath, int fallback = 0) const;
    QString stringValue(const QString& dottedPath, const QString& fallback = {}) const;

signals:
    void settingChanged(const QString& key, const QVariant& value);

private:
    QString resolveFilePath() const;
    bool saveToDisk();

    QString m_filePath;
    QJsonObject m_root;
};
