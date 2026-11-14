#include "SettingsStore.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QVariantList>
#include <algorithm>

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
            appDir.absoluteFilePath(QStringLiteral("config/sekaidesk.json"))
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
        // Seed fresh-install UI/UX defaults when creating a new sekaidesk.json.
        writePath(m_root, QStringLiteral("notifications.style"), QStringLiteral("peek"));
        writePath(m_root, QStringLiteral("dock.style"), QStringLiteral("capsule"));
        writePath(m_root, QStringLiteral("bar.style"), QStringLiteral("transparent"));
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

namespace {
QString sanitizePresetFilename(const QString& rawName)
{
    QString trimmed = rawName.trimmed();
    if (trimmed.isEmpty() || trimmed == QStringLiteral(".") || trimmed == QStringLiteral(".."))
        return {};
    if (trimmed == QStringLiteral(".previous"))
        return QStringLiteral(".previous");
    QString out;
    out.reserve(trimmed.size());
    for (const QChar ch : trimmed) {
        if (ch == QLatin1Char('/') || ch == QLatin1Char('\\') || ch == QLatin1Char(':')
            || ch == QLatin1Char('*') || ch == QLatin1Char('?') || ch == QLatin1Char('"')
            || ch == QLatin1Char('<') || ch == QLatin1Char('>') || ch == QLatin1Char('|')
            || ch.unicode() < 32) {
            out.append(QLatin1Char('_'));
        } else {
            out.append(ch);
        }
    }
    while (out.startsWith(QLatin1Char('.')))
        out.remove(0, 1);
    while (out.endsWith(QLatin1Char('.')) || out.endsWith(QLatin1Char(' ')))
        out.chop(1);
    return out;
}
} // namespace

QString SettingsStore::presetsDirPath() const
{
    QString baseDir;
    if (!m_filePath.isEmpty()) {
        baseDir = QFileInfo(m_filePath).absolutePath();
    } else {
        baseDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
        if (baseDir.isEmpty())
            baseDir = QCoreApplication::applicationDirPath();
        baseDir = QDir(baseDir).absoluteFilePath(QStringLiteral("SekaiDesk"));
    }
    const QString presetsDir = QDir(baseDir).absoluteFilePath(QStringLiteral("presets"));
    QDir().mkpath(presetsDir);
    return presetsDir;
}

QString SettingsStore::presetFilePath(const QString& name) const
{
    const QString safe = sanitizePresetFilename(name);
    if (safe.isEmpty())
        return {};
    return QDir(presetsDirPath()).absoluteFilePath(safe + QStringLiteral(".json"));
}

QVariantList SettingsStore::listPresets() const
{
    QVariantList out;
    const QDir dir(presetsDirPath());
    const QFileInfoList files = dir.entryInfoList(
        { QStringLiteral("*.json") }, QDir::Files | QDir::Readable, QDir::Time);
    for (const QFileInfo& fi : files) {
        if (fi.fileName().startsWith(QLatin1Char('.')))
            continue;
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        f.close();
        if (!doc.isObject())
            continue;
        const QJsonObject obj = doc.object();
        const QJsonObject dataObj = obj.contains(QStringLiteral("data"))
            ? obj.value(QStringLiteral("data")).toObject()
            : obj;

        const QString name = obj.value(QStringLiteral("name")).toString(fi.completeBaseName());
        if (name.startsWith(QLatin1Char('.')))
            continue;

        QVariantMap item;
        item.insert(QStringLiteral("name"), name);
        item.insert(QStringLiteral("favorite"), obj.value(QStringLiteral("favorite")).toBool(false));
        item.insert(QStringLiteral("savedAtMs"),
                    static_cast<qint64>(obj.value(QStringLiteral("savedAtMs")).toDouble(
                        static_cast<double>(fi.lastModified().toMSecsSinceEpoch()))));
        item.insert(QStringLiteral("wallpaper"), dataObj.value(QStringLiteral("wallpaper")).toString());
        item.insert(QStringLiteral("bandId"), dataObj.value(QStringLiteral("bandId")).toString());
        QString accentA = dataObj.value(QStringLiteral("customAccentA")).toString();
        if (accentA.isEmpty())
            accentA = dataObj.value(QStringLiteral("accentA")).toString();
        QString accentB = dataObj.value(QStringLiteral("customAccentB")).toString();
        if (accentB.isEmpty())
            accentB = dataObj.value(QStringLiteral("accentB")).toString();
        item.insert(QStringLiteral("accentA"), accentA);
        item.insert(QStringLiteral("accentB"), accentB);
        out.append(item);
    }

    std::sort(out.begin(), out.end(), [](const QVariant& a, const QVariant& b) {
        const QVariantMap ma = a.toMap();
        const QVariantMap mb = b.toMap();
        const bool fa = ma.value(QStringLiteral("favorite")).toBool();
        const bool fb = mb.value(QStringLiteral("favorite")).toBool();
        if (fa != fb)
            return fa;
        const qint64 ta = ma.value(QStringLiteral("savedAtMs")).toLongLong();
        const qint64 tb = mb.value(QStringLiteral("savedAtMs")).toLongLong();
        if (ta != tb)
            return ta > tb;
        return ma.value(QStringLiteral("name")).toString().compare(
                   mb.value(QStringLiteral("name")).toString(), Qt::CaseInsensitive) < 0;
    });
    return out;
}

bool SettingsStore::savePreset(const QString& name, const QVariantMap& data, bool favorite)
{
    const QString path = presetFilePath(name);
    if (path.isEmpty())
        return false;

    bool effectiveFav = favorite;
    if (!effectiveFav && QFileInfo::exists(path)) {
        QFile existing(path);
        if (existing.open(QIODevice::ReadOnly)) {
            const QJsonObject prev = QJsonDocument::fromJson(existing.readAll()).object();
            effectiveFav = prev.value(QStringLiteral("favorite")).toBool(false);
            existing.close();
        }
    }

    QJsonObject obj;
    obj.insert(QStringLiteral("name"), name.trimmed());
    obj.insert(QStringLiteral("favorite"), effectiveFav);
    obj.insert(QStringLiteral("savedAtMs"), QDateTime::currentMSecsSinceEpoch());
    obj.insert(QStringLiteral("data"), QJsonObject::fromVariantMap(data));

    QSaveFile sf(path);
    if (!sf.open(QIODevice::WriteOnly))
        return false;
    sf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    if (!sf.commit())
        return false;
    emit presetsChanged();
    return true;
}

QVariantMap SettingsStore::loadPreset(const QString& name) const
{
    const QString path = presetFilePath(name);
    if (path.isEmpty())
        return {};
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject())
        return {};
    const QJsonObject obj = doc.object();
    if (obj.contains(QStringLiteral("data")) && obj.value(QStringLiteral("data")).isObject())
        return obj.value(QStringLiteral("data")).toObject().toVariantMap();
    return obj.toVariantMap();
}

bool SettingsStore::deletePreset(const QString& name)
{
    const QString path = presetFilePath(name);
    if (path.isEmpty() || !QFileInfo::exists(path))
        return false;
    const bool ok = QFile::remove(path);
    if (ok)
        emit presetsChanged();
    return ok;
}

bool SettingsStore::renamePreset(const QString& oldName, const QString& newName)
{
    const QString oldPath = presetFilePath(oldName);
    const QString newPath = presetFilePath(newName);
    if (oldPath.isEmpty() || newPath.isEmpty() || !QFileInfo::exists(oldPath))
        return false;

    QFile f(oldPath);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject())
        return false;

    QJsonObject obj = doc.object();
    obj.insert(QStringLiteral("name"), newName.trimmed());

    QSaveFile sf(newPath);
    if (!sf.open(QIODevice::WriteOnly))
        return false;
    sf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    if (!sf.commit())
        return false;

    if (oldPath.compare(newPath, Qt::CaseInsensitive) != 0)
        QFile::remove(oldPath);
    emit presetsChanged();
    return true;
}

bool SettingsStore::togglePresetFavorite(const QString& name)
{
    const QString path = presetFilePath(name);
    if (path.isEmpty() || !QFileInfo::exists(path))
        return false;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject())
        return false;

    QJsonObject obj = doc.object();
    obj.insert(QStringLiteral("favorite"), !obj.value(QStringLiteral("favorite")).toBool(false));

    QSaveFile sf(path);
    if (!sf.open(QIODevice::WriteOnly))
        return false;
    sf.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    if (!sf.commit())
        return false;
    emit presetsChanged();
    return true;
}
