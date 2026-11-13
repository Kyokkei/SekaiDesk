#pragma once
// DeskExtrasService — LyricsService (LRCLIB synced/plain lyrics),
// WeatherService (Open-Meteo + IP city), and DropShelfService (temp file tray).

#include <QNetworkAccessManager>
#include <QObject>
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

public:
    explicit LyricsService(MediaService* media, QObject* parent = nullptr);

    bool loading() const { return m_loading; }
    bool hasLyrics() const { return !m_lines.isEmpty() || !m_plainText.isEmpty(); }
    bool synced() const { return m_synced; }
    QVariantList lines() const { return m_lines; }
    QString plainText() const { return m_plainText; }
    int activeIndex() const { return m_activeIndex; }
    QString trackKey() const { return m_trackKey; }

    Q_INVOKABLE void refresh();

signals:
    void lyricsChanged();
    void activeIndexChanged();

private:
    void onMediaUpdated();
    void onTimelineUpdated();
    void updateActiveLine();
    void fetchLyrics(const QString& title, const QString& artist, double durationSec);
    void parseLrc(const QString& lrcText);

    MediaService* m_media = nullptr;
    QNetworkAccessManager m_nam;
    QTimer m_tickTimer;
    bool m_loading = false;
    bool m_synced = false;
    QVariantList m_lines;
    QString m_plainText;
    int m_activeIndex = -1;
    QString m_trackKey;
    QString m_pendingKey;
    double m_anchorPosSec = 0.0;
    qint64 m_anchorMs = 0;
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
    Q_PROPERTY(int tempMin READ tempMin NOTIFY weatherChanged)
    Q_PROPERTY(int tempMax READ tempMax NOTIFY weatherChanged)
    Q_PROPERTY(int weatherCode READ weatherCode NOTIFY weatherChanged)
    Q_PROPERTY(QString conditionText READ conditionText NOTIFY weatherChanged)
    Q_PROPERTY(bool isDay READ isDay NOTIFY weatherChanged)

public:
    explicit WeatherService(SettingsStore* settings, QObject* parent = nullptr);

    bool loading() const { return m_loading; }
    bool ready() const { return m_ready; }
    QString city() const { return m_city; }
    int temperature() const { return m_temperature; }
    int feelsLike() const { return m_feelsLike; }
    int humidity() const { return m_humidity; }
    int windSpeed() const { return m_windSpeed; }
    int tempMin() const { return m_tempMin; }
    int tempMax() const { return m_tempMax; }
    int weatherCode() const { return m_weatherCode; }
    QString conditionText() const { return m_conditionText; }
    bool isDay() const { return m_isDay; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setCity(const QString& cityName);

signals:
    void weatherChanged();

private:
    void locateAndFetch();
    void fetchForecast(double lat, double lon, const QString& cityLabel);
    static QString describeWmo(int code);

    SettingsStore* m_settings = nullptr;
    QNetworkAccessManager m_nam;
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
    int m_tempMin = 24;
    int m_tempMax = 33;
    int m_weatherCode = 2;
    QString m_conditionText = QStringLiteral("Partly Cloudy");
    bool m_isDay = true;
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
    Q_INVOKABLE void openItem(int index);
    Q_INVOKABLE void revealItem(int index);
    Q_INVOKABLE void copyAllPaths();
    Q_INVOKABLE void removeIndex(int index);
    Q_INVOKABLE void clear();

signals:
    void itemsChanged();

private:
    QVariantList m_items;
};
