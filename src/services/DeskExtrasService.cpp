#include "DeskExtrasService.h"
#include "MediaService.h"
#include "core/SettingsStore.h"

#include <QClipboard>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>
#include <QVariantMap>

#include <algorithm>
#include <cmath>
#include <functional>
#include <thread>

#ifdef Q_OS_WIN
#include <windows.h>
#include <winhttp.h>
#endif

namespace {

struct HttpResult {
    int statusCode = 0;
    QByteArray body;
    QString error;
};

HttpResult winHttpGetSync(const QString& urlStr)
{
    HttpResult res;
#ifdef Q_OS_WIN
    const QUrl url(urlStr);
    if (!url.isValid() || url.host().isEmpty()) {
        res.error = QStringLiteral("Invalid URL");
        return res;
    }

    const bool isHttps = (url.scheme().compare(QStringLiteral("https"), Qt::CaseInsensitive) == 0);
    const std::wstring hostW = url.host().toStdWString();
    QString pathAndQuery = url.path(QUrl::FullyEncoded);
    if (pathAndQuery.isEmpty())
        pathAndQuery = QStringLiteral("/");
    if (url.hasQuery())
        pathAndQuery += QStringLiteral("?") + url.query(QUrl::FullyEncoded);
    const std::wstring pathW = pathAndQuery.toStdWString();
    const INTERNET_PORT port = url.port(isHttps ? INTERNET_DEFAULT_HTTPS_PORT : INTERNET_DEFAULT_HTTP_PORT);

    HINTERNET hSession = WinHttpOpen(
        L"SekaiDesk/0.2",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0);
    if (!hSession) {
        res.error = QStringLiteral("WinHttpOpen failed (%1)").arg(GetLastError());
        return res;
    }

    WinHttpSetTimeouts(hSession, 8000, 8000, 8000, 10000);
    DWORD redirPolicy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
    WinHttpSetOption(hSession, WINHTTP_OPTION_REDIRECT_POLICY, &redirPolicy, sizeof(redirPolicy));

    HINTERNET hConnect = WinHttpConnect(hSession, hostW.c_str(), port, 0);
    if (!hConnect) {
        res.error = QStringLiteral("WinHttpConnect failed (%1)").arg(GetLastError());
        WinHttpCloseHandle(hSession);
        return res;
    }

    HINTERNET hRequest = WinHttpOpenRequest(
        hConnect,
        L"GET",
        pathW.c_str(),
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        isHttps ? WINHTTP_FLAG_SECURE : 0);
    if (!hRequest) {
        res.error = QStringLiteral("WinHttpOpenRequest failed (%1)").arg(GetLastError());
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return res;
    }

    const wchar_t* headers = L"Accept: application/json\r\nUser-Agent: SekaiDesk/0.2 (Windows NT)\r\n";
    if (!WinHttpSendRequest(hRequest, headers, static_cast<DWORD>(-1L), WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(hRequest, nullptr)) {
        res.error = QStringLiteral("HTTP request failed (%1)").arg(GetLastError());
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return res;
    }

    DWORD statusCode = 0;
    DWORD statusSize = sizeof(statusCode);
    if (WinHttpQueryHeaders(hRequest,
                            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX,
                            &statusCode,
                            &statusSize,
                            WINHTTP_NO_HEADER_INDEX)) {
        res.statusCode = static_cast<int>(statusCode);
    }

    DWORD avail = 0;
    while (WinHttpQueryDataAvailable(hRequest, &avail) && avail > 0) {
        const DWORD toRead = qMin<DWORD>(avail, 65536);
        QByteArray chunk(static_cast<int>(toRead), Qt::Uninitialized);
        DWORD readBytes = 0;
        if (!WinHttpReadData(hRequest, chunk.data(), toRead, &readBytes) || readBytes == 0)
            break;
        chunk.truncate(static_cast<int>(readBytes));
        res.body.append(chunk);
        if (res.body.size() > 4 * 1024 * 1024)
            break;
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
#else
    res.error = QStringLiteral("Unsupported platform");
#endif
    return res;
}

void runHttpAsync(QObject* receiver, const QString& url, std::function<void(HttpResult)> onDone)
{
    QPointer<QObject> guard(receiver);
    std::thread([guard, url, cb = std::move(onDone)]() mutable {
        HttpResult result = winHttpGetSync(url);
        if (!guard)
            return;
        QMetaObject::invokeMethod(
            guard.data(),
            [guard, result = std::move(result), cb = std::move(cb)]() mutable {
                if (guard)
                    cb(result);
            },
            Qt::QueuedConnection);
    }).detach();
}

QString sanitizeTrackText(QString raw)
{
    static const QRegularExpression kParenRe(QStringLiteral("\\s*[\\[(](?:official|lyrics|audio|mv|music video|hd|4k|remix|feat\\.|ft\\.|explicit|ver\\.|version|visualizer)[^\\])]*[\\])]"), QRegularExpression::CaseInsensitiveOption);
    raw.remove(kParenRe);
    static const QRegularExpression kFeatRe(QStringLiteral("\\s+(?:feat\\.|ft\\.)\\s+.*$"), QRegularExpression::CaseInsensitiveOption);
    raw.remove(kFeatRe);
    return raw.simplified().trimmed();
}

} // namespace

// ---------------------------------------------------------------------------
// LyricsService
// ---------------------------------------------------------------------------

LyricsService::LyricsService(MediaService* media, QObject* parent)
    : QObject(parent)
    , m_media(media)
{
    m_tickTimer.setInterval(120);
    m_tickTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_tickTimer, &QTimer::timeout, this, &LyricsService::updateActiveLine);

    if (m_media) {
        connect(m_media, &MediaService::mediaChanged, this, &LyricsService::onMediaUpdated);
        connect(m_media, &MediaService::timelineChanged, this, &LyricsService::onTimelineUpdated);
    }
    onMediaUpdated();
}

void LyricsService::refresh()
{
    if (!m_media || m_media->title().trimmed().isEmpty()) {
        m_loading = false;
        m_synced = false;
        m_lines.clear();
        m_plainText.clear();
        m_activeIndex = -1;
        m_trackKey.clear();
        m_statusText = QStringLiteral("No track playing");
        m_tickTimer.stop();
        emit lyricsChanged();
        emit activeIndexChanged();
        return;
    }
    m_pendingKey.clear();
    fetchLyrics(m_media->title().trimmed(), m_media->artist().trimmed(), m_media->durationSec(), true);
}

void LyricsService::searchManual(const QString& query)
{
    const QString cleaned = query.trimmed();
    if (cleaned.isEmpty())
        return;

    ++m_requestGen;
    const uint64_t gen = m_requestGen;
    m_loading = true;
    m_synced = false;
    m_lines.clear();
    m_plainText.clear();
    m_activeIndex = -1;
    m_trackKey = cleaned;
    m_pendingKey = cleaned;
    m_statusText = QStringLiteral("Searching \"%1\"...").arg(cleaned);
    m_tickTimer.stop();
    emit lyricsChanged();
    emit activeIndexChanged();

    const double targetDuration = (m_media && m_media->hasSession()) ? m_media->durationSec() : 0.0;
    fetchSearchFallback(cleaned, targetDuration, gen);
}

void LyricsService::onMediaUpdated()
{
    if (!m_media || !m_media->hasSession() || m_media->title().trimmed().isEmpty()) {
        ++m_requestGen;
        const bool wasEmpty = m_lines.isEmpty() && m_plainText.isEmpty() && !m_loading;
        m_loading = false;
        m_synced = false;
        m_lines.clear();
        m_plainText.clear();
        m_activeIndex = -1;
        m_trackKey.clear();
        m_pendingKey.clear();
        m_statusText = QStringLiteral("Play music or search manually");
        m_tickTimer.stop();
        if (!wasEmpty) {
            emit lyricsChanged();
            emit activeIndexChanged();
        }
        return;
    }

    onTimelineUpdated();

    const QString key = m_media->title().trimmed() + QStringLiteral("|") + m_media->artist().trimmed();
    if (key != m_pendingKey)
        fetchLyrics(m_media->title().trimmed(), m_media->artist().trimmed(), m_media->durationSec());
}

void LyricsService::onTimelineUpdated()
{
    if (!m_media)
        return;
    m_anchorPosSec = m_media->positionSec();
    m_anchorMs = QDateTime::currentMSecsSinceEpoch();
    if (m_synced && !m_lines.isEmpty()) {
        if (m_media->isPlaying() && !m_tickTimer.isActive())
            m_tickTimer.start();
        else if (!m_media->isPlaying() && m_tickTimer.isActive())
            m_tickTimer.stop();
    }
    updateActiveLine();
}

void LyricsService::fetchLyrics(const QString& title, const QString& artist, double durationSec, bool force)
{
    const QString key = title + QStringLiteral("|") + artist;
    if (!force && key == m_pendingKey)
        return;

    ++m_requestGen;
    const uint64_t gen = m_requestGen;

    m_pendingKey = key;
    m_trackKey = key;
    m_loading = true;
    m_synced = false;
    m_lines.clear();
    m_plainText.clear();
    m_activeIndex = -1;
    m_statusText = QStringLiteral("Fetching lyrics...");
    m_tickTimer.stop();
    emit lyricsChanged();
    emit activeIndexChanged();

    QUrl url(QStringLiteral("https://lrclib.net/api/get"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("track_name"), title);
    if (!artist.isEmpty())
        q.addQueryItem(QStringLiteral("artist_name"), artist);
    if (durationSec > 10.0)
        q.addQueryItem(QStringLiteral("duration"), QString::number(qRound(durationSec)));
    url.setQuery(q);

    runHttpAsync(this, url.toString(QUrl::FullyEncoded), [this, gen, title, artist, durationSec](const HttpResult& res) {
        if (gen != m_requestGen)
            return;

        if (res.statusCode == 200 && applyTrackJson(res.body, false)) {
            m_loading = false;
            emit lyricsChanged();
            updateActiveLine();
            return;
        }

        // Clean up YouTube / Spotify suffixes for search fallback
        QString searchQ = sanitizeTrackText(title);
        const QString cleanArtist = sanitizeTrackText(artist);
        if (!cleanArtist.isEmpty() && !searchQ.contains(cleanArtist, Qt::CaseInsensitive))
            searchQ = searchQ + QStringLiteral(" ") + cleanArtist;
        if (searchQ.isEmpty())
            searchQ = title;

        fetchSearchFallback(searchQ, durationSec, gen);
    });
}

void LyricsService::fetchSearchFallback(const QString& query, double targetDuration, uint64_t gen)
{
    QUrl url(QStringLiteral("https://lrclib.net/api/search"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("q"), query);
    url.setQuery(q);

    runHttpAsync(this, url.toString(QUrl::FullyEncoded), [this, gen, targetDuration](const HttpResult& res) {
        if (gen != m_requestGen)
            return;

        m_loading = false;
        if (res.statusCode == 200 && !res.body.isEmpty()) {
            const QJsonDocument doc = QJsonDocument::fromJson(res.body);
            if (doc.isArray()) {
                const QJsonArray arr = doc.array();
                int bestIdx = -1;
                double bestScore = -1e9;
                for (int i = 0; i < arr.size(); ++i) {
                    const QJsonObject obj = arr.at(i).toObject();
                    const bool hasSync = !obj.value(QStringLiteral("syncedLyrics")).toString().trimmed().isEmpty();
                    const bool hasPlain = !obj.value(QStringLiteral("plainLyrics")).toString().trimmed().isEmpty();
                    if (!hasSync && !hasPlain)
                        continue;
                    double score = hasSync ? 100.0 : 20.0;
                    const double d = obj.value(QStringLiteral("duration")).toDouble();
                    if (targetDuration > 10.0 && d > 10.0)
                        score -= std::abs(d - targetDuration) * 0.5;
                    if (score > bestScore) {
                        bestScore = score;
                        bestIdx = i;
                    }
                }
                if (bestIdx >= 0) {
                    const QJsonObject chosen = arr.at(bestIdx).toObject();
                    const QString syncedLrc = chosen.value(QStringLiteral("syncedLyrics")).toString().trimmed();
                    const QString plainLrc = chosen.value(QStringLiteral("plainLyrics")).toString().trimmed();
                    if (!syncedLrc.isEmpty()) {
                        parseLrc(syncedLrc);
                        m_synced = !m_lines.isEmpty();
                        m_statusText = m_synced ? QStringLiteral("Synced") : QStringLiteral("Plain");
                    } else if (!plainLrc.isEmpty()) {
                        m_plainText = plainLrc;
                        const QStringList splitLines = plainLrc.split(QLatin1Char('\n'));
                        for (const QString& ln : splitLines) {
                            const QString t = ln.trimmed();
                            if (!t.isEmpty()) {
                                QVariantMap row;
                                row[QStringLiteral("time")] = -1.0;
                                row[QStringLiteral("text")] = t;
                                m_lines.append(row);
                            }
                        }
                        m_synced = false;
                        m_statusText = QStringLiteral("Plain lyrics");
                    }
                    emit lyricsChanged();
                    updateActiveLine();
                    return;
                }
            }
        }

        m_synced = false;
        m_lines.clear();
        m_plainText.clear();
        m_statusText = res.error.isEmpty()
            ? QStringLiteral("No lyrics found on LRCLIB")
            : QStringLiteral("Lyrics offline (%1)").arg(res.error);
        emit lyricsChanged();
        emit activeIndexChanged();
    });
}

bool LyricsService::applyTrackJson(const QByteArray& body, bool allowArray)
{
    const QJsonDocument doc = QJsonDocument::fromJson(body);
    QJsonObject obj;
    if (doc.isObject()) {
        obj = doc.object();
    } else if (allowArray && doc.isArray() && !doc.array().isEmpty()) {
        obj = doc.array().first().toObject();
    } else {
        return false;
    }

    const QString syncedLrc = obj.value(QStringLiteral("syncedLyrics")).toString().trimmed();
    const QString plainLrc = obj.value(QStringLiteral("plainLyrics")).toString().trimmed();

    if (!syncedLrc.isEmpty()) {
        parseLrc(syncedLrc);
        if (!m_lines.isEmpty()) {
            m_synced = true;
            m_statusText = QStringLiteral("Synced");
            return true;
        }
    }
    if (!plainLrc.isEmpty()) {
        m_plainText = plainLrc;
        const QStringList splitLines = plainLrc.split(QLatin1Char('\n'));
        for (const QString& ln : splitLines) {
            const QString t = ln.trimmed();
            if (!t.isEmpty()) {
                QVariantMap row;
                row[QStringLiteral("time")] = -1.0;
                row[QStringLiteral("text")] = t;
                m_lines.append(row);
            }
        }
        m_synced = false;
        m_statusText = QStringLiteral("Plain lyrics");
        return !m_lines.isEmpty();
    }
    return false;
}

void LyricsService::parseLrc(const QString& lrcText)
{
    m_lines.clear();
    static const QRegularExpression kTimeTag(QStringLiteral("\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"));

    const QStringList rawLines = lrcText.split(QLatin1Char('\n'));
    QList<QPair<double, QString>> entries;

    for (const QString& raw : rawLines) {
        QList<double> times;
        int lastEnd = 0;
        QRegularExpressionMatchIterator it = kTimeTag.globalMatch(raw);
        while (it.hasNext()) {
            const QRegularExpressionMatch m = it.next();
            const int mins = m.captured(1).toInt();
            const int secs = m.captured(2).toInt();
            const QString fracStr = m.captured(3);
            double frac = 0.0;
            if (fracStr.length() == 1)
                frac = fracStr.toInt() / 10.0;
            else if (fracStr.length() == 2)
                frac = fracStr.toInt() / 100.0;
            else if (fracStr.length() >= 3)
                frac = fracStr.left(3).toInt() / 1000.0;
            times.append(mins * 60.0 + secs + frac);
            lastEnd = m.capturedEnd();
        }
        if (times.isEmpty())
            continue;
        QString text = raw.mid(lastEnd).trimmed();
        if (text.isEmpty())
            text = QStringLiteral("♪");
        for (double t : times)
            entries.append(qMakePair(t, text));
    }

    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
        return a.first < b.first;
    });

    for (const auto& entry : entries) {
        QVariantMap row;
        row[QStringLiteral("time")] = entry.first;
        row[QStringLiteral("text")] = entry.second;
        m_lines.append(row);
    }

    if (m_media && m_media->isPlaying() && !m_lines.isEmpty())
        m_tickTimer.start();
}

void LyricsService::updateActiveLine()
{
    if (!m_synced || m_lines.isEmpty()) {
        if (m_activeIndex != -1) {
            m_activeIndex = -1;
            emit activeIndexChanged();
        }
        return;
    }

    double currentPos = m_anchorPosSec;
    if (m_media && m_media->isPlaying() && m_anchorMs > 0) {
        const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_anchorMs;
        if (elapsed > 0 && elapsed < 300000)
            currentPos += elapsed / 1000.0;
    }

    int idx = -1;
    for (int i = 0; i < m_lines.size(); ++i) {
        const double t = m_lines.at(i).toMap().value(QStringLiteral("time")).toDouble();
        if (t <= currentPos + 0.15)
            idx = i;
        else
            break;
    }

    if (idx != m_activeIndex) {
        m_activeIndex = idx;
        emit activeIndexChanged();
    }
}

// ---------------------------------------------------------------------------
// WeatherService
// ---------------------------------------------------------------------------

WeatherService::WeatherService(SettingsStore* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    if (m_settings) {
        const QString savedCity = m_settings->get(QStringLiteral("weather.city"), QStringLiteral("Ho Chi Minh")).toString().trimmed();
        if (!savedCity.isEmpty())
            m_city = savedCity;
        m_lat = m_settings->get(QStringLiteral("weather.lat"), 10.8231).toDouble();
        m_lon = m_settings->get(QStringLiteral("weather.lon"), 106.6297).toDouble();
    }

    m_refreshTimer.setInterval(20 * 60 * 1000);
    connect(&m_refreshTimer, &QTimer::timeout, this, &WeatherService::refresh);
    m_refreshTimer.start();

    QTimer::singleShot(900, this, &WeatherService::refresh);
}

void WeatherService::refresh()
{
    if (m_city.trimmed().isEmpty()) {
        locateAndFetch();
    } else {
        fetchForecast(m_lat, m_lon, m_city);
    }
}

void WeatherService::setCity(const QString& cityName)
{
    const QString cleaned = cityName.trimmed();
    if (cleaned.isEmpty()) {
        if (m_settings)
            m_settings->set(QStringLiteral("weather.city"), QString());
        locateAndFetch();
        return;
    }

    ++m_requestGen;
    const uint64_t gen = m_requestGen;
    m_loading = true;
    emit weatherChanged();

    QUrl url(QStringLiteral("https://geocoding-api.open-meteo.com/v1/search"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("name"), cleaned);
    q.addQueryItem(QStringLiteral("count"), QStringLiteral("1"));
    q.addQueryItem(QStringLiteral("language"), QStringLiteral("en"));
    url.setQuery(q);

    runHttpAsync(this, url.toString(QUrl::FullyEncoded), [this, gen, cleaned](const HttpResult& res) {
        if (gen != m_requestGen)
            return;

        if (res.statusCode == 200) {
            const QJsonDocument doc = QJsonDocument::fromJson(res.body);
            const QJsonArray results = doc.object().value(QStringLiteral("results")).toArray();
            if (!results.isEmpty()) {
                const QJsonObject first = results.first().toObject();
                const double lat = first.value(QStringLiteral("latitude")).toDouble(m_lat);
                const double lon = first.value(QStringLiteral("longitude")).toDouble(m_lon);
                const QString name = first.value(QStringLiteral("name")).toString(cleaned);
                m_city = name;
                m_lat = lat;
                m_lon = lon;
                if (m_settings) {
                    m_settings->set(QStringLiteral("weather.city"), name);
                    m_settings->set(QStringLiteral("weather.lat"), lat);
                    m_settings->set(QStringLiteral("weather.lon"), lon);
                }
                fetchForecast(lat, lon, name);
                return;
            }
        }
        m_loading = false;
        emit weatherChanged();
    });
}

void WeatherService::locateAndFetch()
{
    ++m_requestGen;
    const uint64_t gen = m_requestGen;
    m_loading = true;
    emit weatherChanged();

    runHttpAsync(this, QStringLiteral("https://ipwho.is/"), [this, gen](const HttpResult& res) {
        if (gen != m_requestGen)
            return;

        double lat = m_lat;
        double lon = m_lon;
        QString city = m_city;

        if (res.statusCode == 200) {
            const QJsonObject obj = QJsonDocument::fromJson(res.body).object();
            if (obj.value(QStringLiteral("success")).toBool(true)) {
                lat = obj.value(QStringLiteral("latitude")).toDouble(lat);
                lon = obj.value(QStringLiteral("longitude")).toDouble(lon);
                const QString detected = obj.value(QStringLiteral("city")).toString().trimmed();
                if (!detected.isEmpty())
                    city = detected;
            }
        }

        m_lat = lat;
        m_lon = lon;
        m_city = city;
        if (m_settings) {
            m_settings->set(QStringLiteral("weather.city"), city);
            m_settings->set(QStringLiteral("weather.lat"), lat);
            m_settings->set(QStringLiteral("weather.lon"), lon);
        }
        fetchForecast(lat, lon, city);
    });
}

void WeatherService::fetchForecast(double lat, double lon, const QString& cityLabel)
{
    ++m_requestGen;
    const uint64_t gen = m_requestGen;
    m_loading = true;
    emit weatherChanged();

    const QString urlStr = QStringLiteral(
        "https://api.open-meteo.com/v1/forecast?latitude=%1&longitude=%2"
        "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
        "&hourly=temperature_2m,weather_code,uv_index,is_day"
        "&daily=temperature_2m_max,temperature_2m_min,uv_index_max&timezone=auto&forecast_days=2")
        .arg(lat, 0, 'f', 4)
        .arg(lon, 0, 'f', 4);

    runHttpAsync(this, urlStr, [this, gen, cityLabel](const HttpResult& res) {
        if (gen != m_requestGen)
            return;

        m_loading = false;
        if (res.statusCode == 200) {
            const QJsonObject root = QJsonDocument::fromJson(res.body).object();
            const QJsonObject cur = root.value(QStringLiteral("current")).toObject();
            if (!cur.isEmpty()) {
                m_city = cityLabel;
                m_temperature = qRound(cur.value(QStringLiteral("temperature_2m")).toDouble(28.0));
                m_feelsLike = qRound(cur.value(QStringLiteral("apparent_temperature")).toDouble(m_temperature));
                m_humidity = qRound(cur.value(QStringLiteral("relative_humidity_2m")).toDouble(70.0));
                m_windSpeed = qRound(cur.value(QStringLiteral("wind_speed_10m")).toDouble(8.0));
                m_isDay = (cur.value(QStringLiteral("is_day")).toInt(1) != 0);
                m_weatherCode = cur.value(QStringLiteral("weather_code")).toInt(2);
                m_conditionText = describeWmo(m_weatherCode);

                const QJsonObject daily = root.value(QStringLiteral("daily")).toObject();
                const QJsonArray maxArr = daily.value(QStringLiteral("temperature_2m_max")).toArray();
                const QJsonArray minArr = daily.value(QStringLiteral("temperature_2m_min")).toArray();
                const QJsonArray uvDailyArr = daily.value(QStringLiteral("uv_index_max")).toArray();
                if (!maxArr.isEmpty())
                    m_tempMax = qRound(maxArr.first().toDouble(m_temperature + 3));
                if (!minArr.isEmpty())
                    m_tempMin = qRound(minArr.first().toDouble(m_temperature - 4));
                if (!uvDailyArr.isEmpty())
                    m_uvIndex = qRound(uvDailyArr.first().toDouble(4.0));

                // Build next 6 hourly slots starting from current local hour
                m_hourlyForecast.clear();
                const QJsonObject hourly = root.value(QStringLiteral("hourly")).toObject();
                const QJsonArray hTimes = hourly.value(QStringLiteral("time")).toArray();
                const QJsonArray hTemps = hourly.value(QStringLiteral("temperature_2m")).toArray();
                const QJsonArray hCodes = hourly.value(QStringLiteral("weather_code")).toArray();
                const QJsonArray hUvs = hourly.value(QStringLiteral("uv_index")).toArray();
                const QJsonArray hIsDay = hourly.value(QStringLiteral("is_day")).toArray();

                const QString curTimeIso = cur.value(QStringLiteral("time")).toString();
                const QString curHourPrefix = curTimeIso.left(13);
                int startIdx = 0;
                for (int i = 0; i < hTimes.size(); ++i) {
                    if (hTimes.at(i).toString().left(13) >= curHourPrefix) {
                        startIdx = i;
                        break;
                    }
                }
                if (startIdx < hUvs.size())
                    m_uvIndex = qRound(hUvs.at(startIdx).toDouble(m_uvIndex));

                for (int k = 0; k < 6 && (startIdx + k) < hTimes.size(); ++k) {
                    const int idx = startIdx + k;
                    const QString tStr = hTimes.at(idx).toString();
                    QString hh = tStr.mid(11, 5);
                    if (hh.isEmpty())
                        hh = QStringLiteral("--:--");
                    QVariantMap slot;
                    slot[QStringLiteral("time")] = (k == 0) ? QStringLiteral("Now") : hh.left(2) + QStringLiteral("h");
                    slot[QStringLiteral("temp")] = idx < hTemps.size() ? qRound(hTemps.at(idx).toDouble()) : m_temperature;
                    slot[QStringLiteral("code")] = idx < hCodes.size() ? hCodes.at(idx).toInt() : m_weatherCode;
                    slot[QStringLiteral("isDay")] = idx < hIsDay.size() ? (hIsDay.at(idx).toInt(1) != 0) : m_isDay;
                    m_hourlyForecast.append(slot);
                }

                m_ready = true;
            }
        }
        emit weatherChanged();
    });
}

QString WeatherService::describeWmo(int code)
{
    if (code == 0) return QStringLiteral("Clear Sky");
    if (code == 1) return QStringLiteral("Mainly Clear");
    if (code == 2) return QStringLiteral("Partly Cloudy");
    if (code == 3) return QStringLiteral("Overcast");
    if (code == 45 || code == 48) return QStringLiteral("Foggy");
    if (code >= 51 && code <= 57) return QStringLiteral("Drizzle");
    if (code >= 61 && code <= 67) return QStringLiteral("Rain");
    if (code >= 71 && code <= 77) return QStringLiteral("Snow");
    if (code >= 80 && code <= 82) return QStringLiteral("Rain Showers");
    if (code >= 85 && code <= 86) return QStringLiteral("Snow Showers");
    if (code >= 95) return QStringLiteral("Thunderstorm");
    return QStringLiteral("Cloudy");
}

// ---------------------------------------------------------------------------
// DropShelfService
// ---------------------------------------------------------------------------

DropShelfService::DropShelfService(QObject* parent)
    : QObject(parent)
{
}

void DropShelfService::appendSinglePath(const QString& rawPath)
{
    if (rawPath.trimmed().isEmpty())
        return;

    const QString path = QDir::toNativeSeparators(rawPath.trimmed());
    for (const QVariant& existing : m_items) {
        if (existing.toMap().value(QStringLiteral("path")).toString().compare(path, Qt::CaseInsensitive) == 0)
            return;
    }

    const QFileInfo fi(path);
    QVariantMap entry;
    entry[QStringLiteral("path")] = path;
    entry[QStringLiteral("name")] = fi.fileName().isEmpty() ? path : fi.fileName();
    entry[QStringLiteral("isDir")] = fi.isDir();

    if (fi.exists() && !fi.isDir()) {
        const qint64 sz = fi.size();
        if (sz < 1024)
            entry[QStringLiteral("sizeText")] = QStringLiteral("%1 B").arg(sz);
        else if (sz < 1024 * 1024)
            entry[QStringLiteral("sizeText")] = QStringLiteral("%1 KB").arg(sz / 1024);
        else
            entry[QStringLiteral("sizeText")] = QStringLiteral("%1 MB").arg(sz / (1024.0 * 1024.0), 0, 'f', 1);
    } else {
        entry[QStringLiteral("sizeText")] = fi.isDir() ? QStringLiteral("Folder") : QStringLiteral("File");
    }

    m_items.prepend(entry);
}

void DropShelfService::addUrls(const QVariantList& urls)
{
    bool changed = false;
    for (const QVariant& v : urls) {
        QString path;
        if (v.canConvert<QUrl>()) {
            const QUrl u = v.toUrl();
            path = u.isLocalFile() ? u.toLocalFile() : u.toString();
        } else {
            const QString s = v.toString();
            const QUrl u(s);
            path = u.isLocalFile() ? u.toLocalFile() : s;
        }
        const int before = m_items.size();
        appendSinglePath(path);
        if (m_items.size() != before)
            changed = true;
    }
    if (changed)
        emit itemsChanged();
}

void DropShelfService::addPaths(const QStringList& paths)
{
    const int before = m_items.size();
    for (const QString& p : paths)
        appendSinglePath(p);
    if (m_items.size() != before)
        emit itemsChanged();
}

void DropShelfService::openItem(int index)
{
    if (index < 0 || index >= m_items.size())
        return;
    const QString path = m_items.at(index).toMap().value(QStringLiteral("path")).toString();
    if (!path.isEmpty())
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void DropShelfService::revealItem(int index)
{
    if (index < 0 || index >= m_items.size())
        return;
    const QString path = m_items.at(index).toMap().value(QStringLiteral("path")).toString();
    if (path.isEmpty())
        return;
    QProcess::startDetached(QStringLiteral("explorer.exe"), { QStringLiteral("/select,"), QDir::toNativeSeparators(path) });
}

void DropShelfService::copyAllPaths()
{
    QStringList list;
    for (const QVariant& item : m_items)
        list.append(item.toMap().value(QStringLiteral("path")).toString());
    if (auto* cb = QGuiApplication::clipboard())
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
