#pragma once
// WallpaperService — Scans a wallpaper folder, applies Windows desktop wallpaper
// via SystemParametersInfoW(SPI_SETDESKWALLPAPER), extracts SekaiPop accent palettes
// via QImage quantization, and supports folder picking + slideshow rotation.

#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class SettingsStore;

class WallpaperService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString directory READ directory NOTIFY directoryChanged)
    Q_PROPERTY(QString directoryShort READ directoryShort NOTIFY directoryChanged)
    Q_PROPERTY(bool customFolder READ customFolder NOTIFY directoryChanged)
    Q_PROPERTY(QString currentWallpaper READ currentWallpaper NOTIFY currentWallpaperChanged)
    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)
    Q_PROPERTY(QString sortBy READ sortBy WRITE setSortBy NOTIFY sortByChanged)
    Q_PROPERTY(bool slideshowEnabled READ slideshowEnabled WRITE setSlideshowEnabled NOTIFY slideshowChanged)
    Q_PROPERTY(int slideshowMinutes READ slideshowMinutes WRITE setSlideshowMinutes NOTIFY slideshowChanged)
    Q_PROPERTY(QString transitionStyle READ transitionStyle WRITE setTransitionStyle NOTIFY transitionStyleChanged)

public:
    explicit WallpaperService(SettingsStore* settings, QObject* parent = nullptr);
    ~WallpaperService() override;

    QString directory() const { return m_directory; }
    QString directoryShort() const { return m_directoryShort; }
    bool customFolder() const { return m_customFolder; }
    QString currentWallpaper() const { return m_currentWallpaper; }
    QVariantList wallpapers() const { return m_wallpapers; }
    QString sortBy() const { return m_sortBy; }
    bool slideshowEnabled() const { return m_slideshowEnabled; }
    int slideshowMinutes() const { return m_slideshowMinutes; }
    QString transitionStyle() const { return m_transitionStyle; }

    void setSortBy(const QString& sortBy);
    void setSlideshowEnabled(bool enabled);
    void setSlideshowMinutes(int minutes);
    void setTransitionStyle(const QString& style);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool applyWallpaper(const QString& filePath);
    Q_INVOKABLE void requestWallpaperChange(const QString& filePath);
    Q_INVOKABLE QString toFileUrl(const QString& filePath) const;
    Q_INVOKABLE QString syncSystemWallpaper();
    Q_INVOKABLE QVariantMap extractCurrentPalette();
    Q_INVOKABLE QVariantMap extractPalette(const QString& filePath) const;
    Q_INVOKABLE void pickFolder();
    Q_INVOKABLE void resetFolder();
    Q_INVOKABLE void nextRandomWallpaper();

signals:
    void directoryChanged();
    void currentWallpaperChanged();
    void wallpapersChanged();
    void sortByChanged();
    void slideshowChanged();
    void transitionStyleChanged();
    void transitionRequested(const QString& fromPath, const QString& toPath, const QString& style);

private:
    QString defaultPicturesFolder() const;
    void updateDirectory(const QString& dirPath, bool isCustom, bool persist);
    void updateDirectoryShort();
    void syncWatcher();
    void syncSlideshowTimer();
    void querySystemWallpaperState(QString& outPath, qint64& outMtime) const;

    SettingsStore* m_settings = nullptr;
    QString m_directory;
    QString m_directoryShort;
    bool m_customFolder = false;
    QString m_currentWallpaper;
    QString m_lastSysWallPath;
    qint64 m_lastSysWallMtime = 0;
    QVariantList m_wallpapers;
    QString m_sortBy = QStringLiteral("newest");
    bool m_slideshowEnabled = false;
    int m_slideshowMinutes = 15;
    QString m_transitionStyle = QStringLiteral("sekaiRing");
    QString m_lastRolledStyle;

    QFileSystemWatcher m_watcher;
    QTimer m_watchDebounce;
    QTimer m_slideshowTimer;
    QTimer m_sysWallTimer;
};
