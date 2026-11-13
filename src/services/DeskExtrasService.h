#pragma once
// DeskExtrasService — LyricsService (LRCLIB synced/plain lyrics via native WinHTTP),
// WeatherService (Open-Meteo + IP city via native WinHTTP), and DropShelfService (temp file tray).

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

class MediaService;
class SettingsStore;

class LyricsService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY lyricsChanged)
    Q_PROPERTY(bool hasLyrics READ hasLyrics NOTIFY lyricsChanged)
    Q_PROPERTY(bool synced READ synced NOTIFY lyricsChanged)
    Q_PROPERTY(QVariantList lines READ lines NOTIFY lyricsChanged)
    Q_PROPERTY(QString plainText READ plainText NOTIFY lyricsChanged)
    Q_PROPERTY(int activeIndex READ activeIndex NOTIFY activeIndexChanged)
    Q_PROPERTY(QString trackKey READ trackKey NOTIFY lyricsChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY lyricsChanged)

public:
    explicit LyricsService(MediaService* media, QObject* parent = nullptr);

    bool loading() const { return m_loading; }
    bool hasLyrics() const { return !m_lines.isEmpty() || !m_plainText.isEmpty(); }
    bool synced() const { return m_synced; }
    QVariantList lines() const { return m_lines; }
    QString plainText() const { return m_plainText; }
    int activeIndex() const { return m_activeIndex; }
    QString trackKey() const { return m_trackKey; }
    QString statusText() const { return m_statusText; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void searchManual(const QString& query);

signals:
    void lyricsChanged();
    void activeIndexChanged();

private:
    void onMediaUpdated();
    void onTimelineUpdated();
    void updateActiveLine();
    void fetchLyrics(const QString& title, const QString& artist, double durationSec, bool force = false);
    void fetchSearchFallback(const QString& query, double targetDuration, uint64_t gen);
    bool applyTrackJson(const QByteArray& body, bool allowArray);
    void parseLrc(const QString& lrcText);

    MediaService* m_media = nullptr;
    QTimer m_tickTimer;
    bool m_loading = false;
    bool m_synced = false;
    QVariantList m_lines;
    QString m_plainText;
    int m_activeIndex = -1;
    QString m_trackKey;
    QString m_pendingKey;
    QString m_statusText;
    double m_anchorPosSec = 0.0;
    qint64 m_anchorMs = 0;
    uint64_t m_requestGen = 0;
};

class WeatherService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY weatherChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY weatherChanged)
    Q_PROPERTY(QString city READ city NOTIFY weatherChanged)
    Q_PROPERTY(int temperature READ temperature NOTIFY weatherChanged)
    Q_PROPERTY(int feelsLike READ feelsLike NOTIFY weatherChanged)
    Q_PROPERTY(int humidity READ humidity NOTIFY weatherChanged)
    Q_PROPERTY(int windSpeed READ windSpeed NOTIFY weatherChanged)
    Q_PROPERTY(int uvIndex READ uvIndex NOTIFY weatherChanged)
    Q_PROPERTY(int tempMin READ tempMin NOTIFY weatherChanged)
    Q_PROPERTY(int tempMax READ tempMax NOTIFY weatherChanged)
    Q_PROPERTY(int weatherCode READ weatherCode NOTIFY weatherChanged)
    Q_PROPERTY(QString conditionText READ conditionText NOTIFY weatherChanged)
    Q_PROPERTY(bool isDay READ isDay NOTIFY weatherChanged)
    Q_PROPERTY(QVariantList hourlyForecast READ hourlyForecast NOTIFY weatherChanged)

public:
    explicit WeatherService(SettingsStore* settings, QObject* parent = nullptr);

    bool loading() const { return m_loading; }
    bool ready() const { return m_ready; }
    QString city() const { return m_city; }
    int temperature() const { return m_temperature; }
    int feelsLike() const { return m_feelsLike; }
    int humidity() const { return m_humidity; }
    int windSpeed() const { return m_windSpeed; }
    int uvIndex() const { return m_uvIndex; }
    int tempMin() const { return m_tempMin; }
    int tempMax() const { return m_tempMax; }
    int weatherCode() const { return m_weatherCode; }
    QString conditionText() const { return m_conditionText; }
    bool isDay() const { return m_isDay; }
    QVariantList hourlyForecast() const { return m_hourlyForecast; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setCity(const QString& cityName);

signals:
    void weatherChanged();

private:
    void locateAndFetch();
    void fetchForecast(double lat, double lon, const QString& cityLabel);
    static QString describeWmo(int code);

    SettingsStore* m_settings = nullptr;
    QTimer m_refreshTimer;
    bool m_loading = false;
    bool m_ready = false;
    QString m_city = QStringLiteral("Ho Chi Minh");
    double m_lat = 10.8231;
    double m_lon = 106.6297;
    int m_temperature = 28;
    int m_feelsLike = 30;
    int m_humidity = 75;
    int m_windSpeed = 8;
    int m_uvIndex = 4;
    int m_tempMin = 24;
    int m_tempMax = 33;
    int m_weatherCode = 2;
    QString m_conditionText = QStringLiteral("Partly Cloudy");
    bool m_isDay = true;
    QVariantList m_hourlyForecast;
    uint64_t m_requestGen = 0;
};

class DropShelfService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(int count READ count NOTIFY itemsChanged)

public:
    explicit DropShelfService(QObject* parent = nullptr);

    QVariantList items() const { return m_items; }
    int count() const { return m_items.size(); }

    Q_INVOKABLE void addUrls(const QVariantList& urls);
    Q_INVOKABLE void addPaths(const QStringList& paths);
    Q_INVOKABLE void openItem(int index);
    Q_INVOKABLE void revealItem(int index);
    Q_INVOKABLE void copyAllPaths();
    Q_INVOKABLE void removeIndex(int index);
    Q_INVOKABLE void clear();

signals:
    void itemsChanged();

private:
    void appendSinglePath(const QString& rawPath);
    QVariantList m_items;
};
