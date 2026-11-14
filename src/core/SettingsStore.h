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
    Q_INVOKABLE void flush();

    // Dotted-path helper for nested keys, e.g. get("dock.iconSize").
    static QVariant lookupPath(const QJsonObject& root, const QString& dottedPath);
    static void writePath(QJsonObject& root, const QString& dottedPath,
                          const QJsonValue& value);

    // Typed accessors callable from both C++ and QML (`ConfigStore.boolValue(...)`).
    Q_INVOKABLE bool boolValue(const QString& dottedPath, bool fallback = false) const;
    Q_INVOKABLE int intValue(const QString& dottedPath, int fallback = 0) const;
    Q_INVOKABLE QString stringValue(const QString& dottedPath, const QString& fallback = {}) const;

    // Look Presets persistence (%APPDATA%/SekaiDesk/presets/*.json).
    Q_INVOKABLE QVariantList listPresets() const;
    Q_INVOKABLE bool savePreset(const QString& name, const QVariantMap& data, bool favorite = false);
    Q_INVOKABLE QVariantMap loadPreset(const QString& name) const;
    Q_INVOKABLE bool deletePreset(const QString& name);
    Q_INVOKABLE bool renamePreset(const QString& oldName, const QString& newName);
    Q_INVOKABLE bool togglePresetFavorite(const QString& name);

signals:
    void settingChanged(const QString& key, const QVariant& value);
    void presetsChanged();

private:
    QString resolveFilePath() const;
    QString presetsDirPath() const;
    QString presetFilePath(const QString& name) const;
    bool saveToDisk();

    QString m_filePath;
    QJsonObject m_root;
};
