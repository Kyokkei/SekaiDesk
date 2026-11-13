#include "DeskExtrasService.h"
#include "MediaService.h"
#include "core/SettingsStore.h"

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>
#include <QVariantMap>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#endif

// ===========================================================================
// LyricsService
// ===========================================================================

LyricsService::LyricsService(MediaService* media, QObject* parent)
    : QObject(parent)
    , m_media(media)
{
    m_tickTimer.setInterval(250);
    connect(&m_tickTimer, &QTimer::timeout, this, &LyricsService::updateActiveLine);

    if (m_media) {
        connect(m_media, &MediaService::mediaChanged, this, &LyricsService::onMediaUpdated);
        connect(m_media, &MediaService::timelineChanged, this, &LyricsService::onTimelineUpdated);
        onMediaUpdated();
    }
}

void LyricsService::refresh()
{
    m_trackKey.clear();
    onMediaUpdated();
}

void LyricsService::onMediaUpdated()
{
    if (!m_media || !m_media->hasSession()) {
        m_tickTimer.stop();
        if (!m_lines.isEmpty() || !m_plainText.isEmpty() || !m_trackKey.isEmpty() || m_loading) {
            m_lines.clear();
            m_plainText.clear();
            m_trackKey.clear();
            m_synced = false;
            m_loading = false;
            m_activeIndex = -1;
            emit lyricsChanged();
            emit activeIndexChanged();
        }
        return;
    }

    if (m_media->isPlaying()) {
        m_anchorPosSec = m_media->positionSec();
        m_anchorMs = QDateTime::currentMSecsSinceEpoch();
        if (!m_tickTimer.isActive())
            m_tickTimer.start();
    } else {
        m_tickTimer.stop();
        m_anchorPosSec = m_media->positionSec();
        m_anchorMs = QDateTime::currentMSecsSinceEpoch();
        updateActiveLine();
    }

    const QString title = m_media->title().trimmed();
    const QString artist = m_media->artist().trimmed();
    const QString nextKey = artist + QStringLiteral(" — ") + title;
    if (title.isEmpty() || nextKey == m_trackKey)
        return;

    m_trackKey = nextKey;
    fetchLyrics(title, artist, m_media->durationSec());
}

void LyricsService::onTimelineUpdated()
{
    if (!m_media)
        return;
    m_anchorPosSec = m_media->positionSec();
    m_anchorMs = QDateTime::currentMSecsSinceEpoch();
    updateActiveLine();
}

void LyricsService::updateActiveLine()
{
    if (!m_synced || m_lines.isEmpty() || !m_media)
        return;

    double sec = m_anchorPosSec;
    if (m_media->isPlaying() && m_anchorMs > 0)
        sec += static_cast<double>(QDateTime::currentMSecsSinceEpoch() - m_anchorMs) / 1000.0;
    const qint64 posMs = static_cast<qint64>(sec * 1000.0) + 180; // slight visual lead

    int nextIdx = -1;
    for (int i = 0; i < m_lines.size(); ++i) {
        const qint64 t = m_lines.at(i).toMap().value(QStringLiteral("timeMs")).toLongLong();
        if (t <= posMs)
            nextIdx = i;
        else
            break;
    }
    if (nextIdx != m_activeIndex) {
        m_activeIndex = nextIdx;
        emit activeIndexChanged();
    }
}

void LyricsService::fetchLyrics(const QString& title, const QString& artist, double durationSec)
{
    m_loading = true;
    m_lines.clear();
    m_plainText.clear();
    m_synced = false;
    m_activeIndex = -1;
    const QString reqKey = m_trackKey;
    m_pendingKey = reqKey;
    emit lyricsChanged();
    emit activeIndexChanged();

    // Clean common noise like " - YouTube", "(Official Video)", etc.
    auto cleanStr = [](QString s) {
        s.remove(QRegularExpression(QStringLiteral("\\s*[\\(\\[]\\s*(official|lyric|audio|mv|music video|hq|hd|remix).*?[\\)\\]]"),
                                    QRegularExpression::CaseInsensitiveOption));
        s.remove(QRegularExpression(QStringLiteral("\\s*-\\s*(YouTube|Topic).*$"),
                                    QRegularExpression::CaseInsensitiveOption));
        return s.trimmed();
    };

    const QString cleanTitle = cleanStr(title);
    const QString cleanArtist = cleanStr(artist);

    QUrl url(QStringLiteral("https://lrclib.net/api/search"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("track_name"), cleanTitle);
    if (!cleanArtist.isEmpty())
        q.addQueryItem(QStringLiteral("artist_name"), cleanArtist);
    Q_UNUSED(durationSec);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("SekaiDesk/0.1 (Windows Desktop Shell)"));
    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, reqKey, cleanTitle]() {
        reply->deleteLater();
        if (reqKey != m_pendingKey)
            return;

        m_loading = false;
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            if (doc.isArray()) {
                const QJsonArray arr = doc.array();
                QString bestSynced;
                QString bestPlain;
                for (const QJsonValue& v : arr) {
                    const QJsonObject obj = v.toObject();
                    const QString sy = obj.value(QStringLiteral("syncedLyrics")).toString();
                    const QString pl = obj.value(QStringLiteral("plainLyrics")).toString();
                    if (!sy.isEmpty() && bestSynced.isEmpty())
                        bestSynced = sy;
                    if (!pl.isEmpty() && bestPlain.isEmpty())
                        bestPlain = pl;
                    if (!bestSynced.isEmpty())
                        break;
                }
                if (!bestSynced.isEmpty()) {
                    parseLrc(bestSynced);
                } else if (!bestPlain.isEmpty()) {
                    m_plainText = bestPlain.trimmed();
                    const QStringList rawLines = m_plainText.split(QLatin1Char('\n'));
                    for (const QString& ln : rawLines) {
                        const QString t = ln.trimmed();
                        if (!t.isEmpty()) {
                            QVariantMap m;
                            m.insert(QStringLiteral("timeMs"), -1);
                            m.insert(QStringLiteral("text"), t);
                            m_lines.append(m);
                        }
                    }
                    m_synced = false;
                }
            }
        }
        Q_UNUSED(cleanTitle);
        emit lyricsChanged();
        updateActiveLine();
    });
}

void LyricsService::parseLrc(const QString& lrcText)
{
    static const QRegularExpression rx(QStringLiteral("^\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]\\s*(.*)$"));
    const QStringList rawLines = lrcText.split(QLatin1Char('\n'));
    QVariantList parsed;
    QStringList plainAcc;
    for (const QString& line : rawLines) {
        const QRegularExpressionMatch m = rx.match(line.trimmed());
        if (!m.hasMatch())
            continue;
        const qint64 mins = m.captured(1).toLongLong();
        const double secs = m.captured(2).toDouble();
        const QString text = m.captured(3).trimmed();
        if (text.isEmpty())
            continue;
        const qint64 ms = mins * 60000LL + static_cast<qint64>(secs * 1000.0);
        QVariantMap row;
        row.insert(QStringLiteral("timeMs"), ms);
        row.insert(QStringLiteral("text"), text);
        parsed.append(row);
        plainAcc << text;
    }
    m_lines = std::move(parsed);
    m_plainText = plainAcc.join(QLatin1Char('\n'));
    m_synced = !m_lines.isEmpty();
}

// ===========================================================================
// WeatherService
// ===========================================================================

WeatherService::WeatherService(SettingsStore* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    if (m_settings) {
        const QString savedCity = m_settings->stringValue(QStringLiteral("weather.city"));
        if (!savedCity.isEmpty())
            m_city = savedCity;
        const QVariant latV = m_settings->get(QStringLiteral("weather.lat"));
        const QVariant lonV = m_settings->get(QStringLiteral("weather.lon"));
        if (latV.isValid() && lonV.isValid()) {
            m_lat = latV.toDouble();
            m_lon = lonV.toDouble();
        }
    }

    m_refreshTimer.setInterval(30 * 60 * 1000);
    connect(&m_refreshTimer, &QTimer::timeout, this, &WeatherService::refresh);
    m_refreshTimer.start();

    QTimer::singleShot(1200, this, &WeatherService::refresh);
}

void WeatherService::refresh()
{
    if (m_settings && m_settings->has(QStringLiteral("weather.lat"))
        && m_settings->has(QStringLiteral("weather.lon"))) {
        fetchForecast(m_lat, m_lon, m_city);
    } else {
        locateAndFetch();
    }
}

void WeatherService::locateAndFetch()
{
    m_loading = true;
    emit weatherChanged();

    QNetworkRequest req(QUrl(QStringLiteral("http://ip-api.com/json/?fields=status,city,lat,lon")));
    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
            if (obj.value(QStringLiteral("status")).toString() == QStringLiteral("success")) {
                m_city = obj.value(QStringLiteral("city")).toString(m_city);
                m_lat = obj.value(QStringLiteral("lat")).toDouble(m_lat);
                m_lon = obj.value(QStringLiteral("lon")).toDouble(m_lon);
                if (m_settings) {
                    m_settings->set(QStringLiteral("weather.city"), m_city);
                    m_settings->set(QStringLiteral("weather.lat"), m_lat);
                    m_settings->set(QStringLiteral("weather.lon"), m_lon);
                }
            }
        }
        fetchForecast(m_lat, m_lon, m_city);
    });
}

void WeatherService::setCity(const QString& cityName)
{
    const QString clean = cityName.trimmed();
    if (clean.isEmpty())
        return;

    m_loading = true;
    emit weatherChanged();

    QUrl url(QStringLiteral("https://geocoding-api.open-meteo.com/v1/search"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("name"), clean);
    q.addQueryItem(QStringLiteral("count"), QStringLiteral("1"));
    url.setQuery(q);

    QNetworkReply* reply = m_nam.get(QNetworkRequest(url));
    connect(reply, &QNetworkReply::finished, this, [this, reply, clean]() {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonArray arr = QJsonDocument::fromJson(reply->readAll()).object().value(QStringLiteral("results")).toArray();
            if (!arr.isEmpty()) {
                const QJsonObject first = arr.first().toObject();
                m_city = first.value(QStringLiteral("name")).toString(clean);
                m_lat = first.value(QStringLiteral("latitude")).toDouble(m_lat);
                m_lon = first.value(QStringLiteral("longitude")).toDouble(m_lon);
                if (m_settings) {
                    m_settings->set(QStringLiteral("weather.city"), m_city);
                    m_settings->set(QStringLiteral("weather.lat"), m_lat);
                    m_settings->set(QStringLiteral("weather.lon"), m_lon);
                }
            }
        }
        fetchForecast(m_lat, m_lon, m_city);
    });
}

void WeatherService::fetchForecast(double lat, double lon, const QString& cityLabel)
{
    m_loading = true;
    m_city = cityLabel;
    emit weatherChanged();

    const QString urlStr = QStringLiteral(
        "https://api.open-meteo.com/v1/forecast?latitude=%1&longitude=%2"
        "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
        "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1")
                               .arg(lat, 0, 'f', 4)
                               .arg(lon, 0, 'f', 4);

    QNetworkReply* reply = m_nam.get(QNetworkRequest(QUrl(urlStr)));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        m_loading = false;
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonObject root = QJsonDocument::fromJson(reply->readAll()).object();
            const QJsonObject cur = root.value(QStringLiteral("current")).toObject();
            const QJsonObject daily = root.value(QStringLiteral("daily")).toObject();
            m_temperature = qRound(cur.value(QStringLiteral("temperature_2m")).toDouble(28.0));
            m_feelsLike = qRound(cur.value(QStringLiteral("apparent_temperature")).toDouble(30.0));
            m_humidity = qRound(cur.value(QStringLiteral("relative_humidity_2m")).toDouble(75.0));
            m_windSpeed = qRound(cur.value(QStringLiteral("wind_speed_10m")).toDouble(8.0));
            m_weatherCode = cur.value(QStringLiteral("weather_code")).toInt(0);
            m_isDay = cur.value(QStringLiteral("is_day")).toInt(1) != 0;
            m_conditionText = describeWmo(m_weatherCode);

            const QJsonArray maxArr = daily.value(QStringLiteral("temperature_2m_max")).toArray();
            const QJsonArray minArr = daily.value(QStringLiteral("temperature_2m_min")).toArray();
            if (!maxArr.isEmpty())
                m_tempMax = qRound(maxArr.first().toDouble(m_temperature + 3));
            if (!minArr.isEmpty())
                m_tempMin = qRound(minArr.first().toDouble(m_temperature - 3));
            m_ready = true;
        }
        emit weatherChanged();
    });
}

QString WeatherService::describeWmo(int code)
{
    if (code == 0) return QStringLiteral("Clear Sky");
    if (code == 1 || code == 2) return QStringLiteral("Partly Cloudy");
    if (code == 3) return QStringLiteral("Overcast");
    if (code == 45 || code == 48) return QStringLiteral("Foggy");
    if (code >= 51 && code <= 57) return QStringLiteral("Drizzle");
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return QStringLiteral("Rain");
    if (code >= 71 && code <= 77) return QStringLiteral("Snow");
    if (code >= 95) return QStringLiteral("Thunderstorm");
    return QStringLiteral("Cloudy");
}

// ===========================================================================
// DropShelfService
// ===========================================================================

DropShelfService::DropShelfService(QObject* parent)
    : QObject(parent)
{
}

void DropShelfService::addUrls(const QVariantList& urls)
{
    bool changed = false;
    for (const QVariant& v : urls) {
        const QUrl u = v.toUrl().isValid() ? v.toUrl() : QUrl(v.toString());
        const QString local = u.isLocalFile() ? QDir::toNativeSeparators(u.toLocalFile()) : v.toString();
        if (local.trimmed().isEmpty())
            continue;

        bool dup = false;
        for (const QVariant& ex : m_items) {
            if (ex.toMap().value(QStringLiteral("path")).toString().compare(local, Qt::CaseInsensitive) == 0) {
                dup = true;
                break;
            }
        }
        if (dup)
            continue;

        const QFileInfo fi(local);
        QString sizeStr;
        if (fi.isDir()) {
            sizeStr = QStringLiteral("Folder");
        } else {
            const qint64 bytes = fi.size();
            if (bytes < 1024)
                sizeStr = QStringLiteral("%1 B").arg(bytes);
            else if (bytes < 1024 * 1024)
                sizeStr = QStringLiteral("%1 KB").arg(bytes / 1024);
            else
                sizeStr = QStringLiteral("%1 MB").arg(static_cast<double>(bytes) / (1024.0 * 1024.0), 0, 'f', 1);
        }

        QVariantMap m;
        m.insert(QStringLiteral("name"), fi.fileName().isEmpty() ? local : fi.fileName());
        m.insert(QStringLiteral("path"), local);
        m.insert(QStringLiteral("ext"), fi.suffix().toUpper());
        m.insert(QStringLiteral("isDir"), fi.isDir());
        m.insert(QStringLiteral("sizeText"), sizeStr);
        m_items.prepend(m);
        changed = true;
    }
    if (changed)
        emit itemsChanged();
}

void DropShelfService::openItem(int index)
{
    if (index < 0 || index >= m_items.size())
        return;
#ifdef Q_OS_WIN
    const QString path = m_items.at(index).toMap().value(QStringLiteral("path")).toString();
    ShellExecuteW(nullptr, L"open", reinterpret_cast<const wchar_t*>(path.utf16()), nullptr, nullptr, SW_SHOWNORMAL);
#endif
}

void DropShelfService::revealItem(int index)
{
    if (index < 0 || index >= m_items.size())
        return;
#ifdef Q_OS_WIN
    const QString path = m_items.at(index).toMap().value(QStringLiteral("path")).toString();
    const QString arg = QStringLiteral("/select,\"%1\"").arg(path);
    ShellExecuteW(nullptr, L"open", L"explorer.exe", reinterpret_cast<const wchar_t*>(arg.utf16()), nullptr, SW_SHOWNORMAL);
#endif
}

void DropShelfService::copyAllPaths()
{
    QStringList list;
    for (const QVariant& v : m_items)
        list << v.toMap().value(QStringLiteral("path")).toString();
    if (list.isEmpty())
        return;
    if (QClipboard* cb = QGuiApplication::clipboard())
        cb->setText(list.join(QLatin1Char('\n')));
}

void DropShelfService::removeIndex(int index)
{
    if (index < 0 || index >= m_items.size())
        return;
    m_items.removeAt(index);
    emit itemsChanged();
}

void DropShelfService::clear()
{
    if (m_items.isEmpty())
        return;
    m_items.clear();
    emit itemsChanged();
}
