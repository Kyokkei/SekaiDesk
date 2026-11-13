#include "SettingsStore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>

SettingsStore::SettingsStore(QObject* parent)
    : QObject(parent)
{
}

QString SettingsStore::resolveFilePath() const
{
    if (!m_filePath.isEmpty())
        return m_filePath;

    // Single canonical user config path: %APPDATA%\SekaiDesk\sekaidesk.json
    // (using GenericDataLocation avoids Windows AppData\SekaiDesk\SekaiDesk nesting).
    QString baseData = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    if (baseData.isEmpty())
        baseData = QCoreApplication::applicationDirPath();
    const QString dataDir = QDir(baseData).absoluteFilePath(QStringLiteral("SekaiDesk"));
    QDir().mkpath(dataDir);
    const QString canonical = QDir(dataDir).absoluteFilePath(QStringLiteral("sekaidesk.json"));

    if (!QFileInfo::exists(canonical)) {
        // Migrate existing nested or portable config on first launch.
        const QDir appDir(QCoreApplication::applicationDirPath());
        const QString nested = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
            + QStringLiteral("/sekaidesk.json");
        const QStringList candidates = {
            nested,
            appDir.absoluteFilePath(QStringLiteral("config/sekaidesk.json")),
            QStringLiteral("D:/coding/SekaiDesk/dist/SekaiDesk/config/sekaidesk.json"),
            QStringLiteral("D:/coding/SekaiDesk/package/SekaiDesk/config/sekaidesk.json")
        };
        QJsonObject merged;
        for (const QString& cand : candidates) {
            QFile f(cand);
            if (!f.exists() || !f.open(QIODevice::ReadOnly))
                continue;
            const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
            f.close();
            for (auto it = obj.begin(); it != obj.end(); ++it) {
                if (!merged.contains(it.key()))
                    merged.insert(it.key(), it.value());
            }
        }
        if (!merged.isEmpty()) {
            QSaveFile sf(canonical);
            if (sf.open(QIODevice::WriteOnly)) {
                sf.write(QJsonDocument(merged).toJson(QJsonDocument::Indented));
                sf.commit();
            }
        }
    }

    return canonical;
}

void SettingsStore::ensureLoaded()
{
    m_filePath = resolveFilePath();

    QFile file(m_filePath);
    if (file.exists() && file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        m_root = doc.object();
        file.close();
    } else {
        saveToDisk();
    }
}

QVariant SettingsStore::lookupPath(const QJsonObject& root, const QString& dottedPath)
{
    QJsonObject node = root;
    const QStringList parts = dottedPath.split(QLatin1Char('.'));
    for (int i = 0; i < parts.size(); ++i) {
        if (!node.contains(parts.at(i)))
            return {};
        const QJsonValue v = node.value(parts.at(i));
        if (i == parts.size() - 1)
            return v.toVariant();
        if (!v.isObject())
            return {};
        node = v.toObject();
    }
    return {};
}

static QJsonObject writePathHelper(const QJsonObject& node, const QStringList& parts,
                                   int index, const QJsonValue& value)
{
    QJsonObject out = node;
    if (index == parts.size() - 1) {
        out.insert(parts.at(index), value);
        return out;
    }
    const QJsonValue existing = node.value(parts.at(index));
    const QJsonObject child = existing.isObject() ? existing.toObject() : QJsonObject();
    out.insert(parts.at(index), writePathHelper(child, parts, index + 1, value));
    return out;
}

void SettingsStore::writePath(QJsonObject& root, const QString& dottedPath,
                              const QJsonValue& value)
{
    const QStringList parts = dottedPath.split(QLatin1Char('.'));
    if (parts.isEmpty() || parts.first().isEmpty())
        return;
    root = writePathHelper(root, parts, 0, QJsonValue::fromVariant(value));
}

QVariant SettingsStore::get(const QString& key, const QVariant& fallback) const
{
    const QVariant v = lookupPath(m_root, key);
    return v.isValid() ? v : fallback;
}

bool SettingsStore::has(const QString& key) const
{
    return lookupPath(m_root, key).isValid();
}

static QJsonObject removePathHelper(const QJsonObject& node, const QStringList& parts, int index)
{
    QJsonObject out = node;
    if (index == parts.size() - 1) {
        out.remove(parts.at(index));
        return out;
    }
    const QJsonValue existing = node.value(parts.at(index));
    if (!existing.isObject())
        return out;
    out.insert(parts.at(index), removePathHelper(existing.toObject(), parts, index + 1));
    return out;
}

void SettingsStore::remove(const QString& key)
{
    const QStringList parts = key.split(QLatin1Char('.'));
    if (parts.isEmpty() || parts.first().isEmpty())
        return;
    m_root = removePathHelper(m_root, parts, 0);
    saveToDisk();
    emit settingChanged(key, {});
}

void SettingsStore::set(const QString& key, const QVariant& value)
{
    writePath(m_root, key, QJsonValue::fromVariant(value));
    if (saveToDisk())
        emit settingChanged(key, value);
}

void SettingsStore::flush()
{
    saveToDisk();
}

bool SettingsStore::saveToDisk()
{
    if (m_filePath.isEmpty())
        m_filePath = resolveFilePath();

    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("SettingsStore: cannot write %s: %s",
                 qPrintable(m_filePath), qPrintable(file.errorString()));
        return false;
    }
    file.write(QJsonDocument(m_root).toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        qWarning("SettingsStore: cannot commit %s: %s",
                 qPrintable(m_filePath), qPrintable(file.errorString()));
        return false;
    }
    return true;
}

bool SettingsStore::boolValue(const QString& dottedPath, bool fallback) const
{
    const QVariant v = lookupPath(m_root, dottedPath);
    return v.isValid() ? v.toBool() : fallback;
}

int SettingsStore::intValue(const QString& dottedPath, int fallback) const
{
    const QVariant v = lookupPath(m_root, dottedPath);
    return v.isValid() ? v.toInt() : fallback;
}

QString SettingsStore::stringValue(const QString& dottedPath, const QString& fallback) const
{
    const QVariant v = lookupPath(m_root, dottedPath);
    return v.isValid() ? v.toString() : fallback;
}
