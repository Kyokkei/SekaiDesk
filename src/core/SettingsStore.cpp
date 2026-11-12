#include "SettingsStore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>

SettingsStore::SettingsStore(QObject* parent)
    : QObject(parent)
{
}

QString SettingsStore::resolveFilePath() const
{
    if (!m_filePath.isEmpty())
        return m_filePath;

    // Portable-first: <exe dir>/config/sekaidesk.json
    const QDir appDir(QCoreApplication::applicationDirPath());
    const QString portable = appDir.absoluteFilePath(
        QStringLiteral("config/sekaidesk.json"));
    if (QDir().mkpath(appDir.absoluteFilePath(QStringLiteral("config"))))
        return portable;

    // Fallback: platform app-data location.
    const QString dataDir = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    return QDir(dataDir).absoluteFilePath(QStringLiteral("sekaidesk.json"));
}

void SettingsStore::ensureLoaded()
{
    m_filePath = resolveFilePath();

    QFile file(m_filePath);
    if (file.exists() && file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        m_root = doc.object();
        file.close();
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

void SettingsStore::remove(const QString& key)
{
    QJsonObject node = m_root;
    const QStringList parts = key.split(QLatin1Char('.'));
    for (int i = 0; i < parts.size() - 1; ++i) {
        const QJsonValue v = node.value(parts.at(i));
        if (!v.isObject())
            return;
        node = v.toObject();
    }
    node.remove(parts.last());
    m_root = node;
    saveToDisk();
    emit settingChanged(key, {});
}

void SettingsStore::set(const QString& key, const QVariant& value)
{
    writePath(m_root, key, QJsonValue::fromVariant(value));
    if (saveToDisk())
        emit settingChanged(key, value);
}

bool SettingsStore::saveToDisk()
{
    if (m_filePath.isEmpty())
        m_filePath = resolveFilePath();

    QFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("SettingsStore: cannot write %s: %s",
                 qPrintable(m_filePath), qPrintable(file.errorString()));
        return false;
    }
    file.write(QJsonDocument(m_root).toJson(QJsonDocument::Indented));
    file.close();
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
