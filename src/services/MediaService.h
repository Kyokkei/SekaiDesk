#pragma once
// MediaService — Windows GSMTC media session reader via persistent hidden
// PowerShell WinRT worker (metadata, album art thumbnail, timeline, multi-session).

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>

class MediaService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasSession READ hasSession NOTIFY mediaChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY mediaChanged)
    Q_PROPERTY(QString title READ title NOTIFY mediaChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY mediaChanged)
    Q_PROPERTY(QString album READ album NOTIFY mediaChanged)
    Q_PROPERTY(QString sourceApp READ sourceApp NOTIFY mediaChanged)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY mediaChanged)
    Q_PROPERTY(double positionSec READ positionSec NOTIFY timelineChanged)
    Q_PROPERTY(double durationSec READ durationSec NOTIFY mediaChanged)
    Q_PROPERTY(bool canNext READ canNext NOTIFY mediaChanged)
    Q_PROPERTY(bool canPrev READ canPrev NOTIFY mediaChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY mediaChanged)
    Q_PROPERTY(QVariantList players READ players NOTIFY mediaChanged)

public:
    explicit MediaService(QObject* parent = nullptr);
    ~MediaService() override;

    bool hasSession() const { return m_hasSession; }
    bool isPlaying() const { return m_isPlaying; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString album() const { return m_album; }
    QString sourceApp() const { return m_sourceApp; }
    QString artUrl() const { return m_artUrl; }
    double positionSec() const { return m_positionSec; }
    double durationSec() const { return m_durationSec; }
    bool canNext() const { return m_canNext; }
    bool canPrev() const { return m_canPrev; }
    bool canSeek() const { return m_canSeek; }
    QVariantList players() const { return m_players; }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void selectSession(const QString& appId);
    void setPaused(bool paused);

signals:
    void mediaChanged();
    void timelineChanged();

private:
    void startWorker();
    void sendCommand(const QString& cmd);
    void onStdoutReady();
    void applySnapshot(bool hasSession, bool isPlaying,
                       const QString& title, const QString& artist,
                       const QString& album, const QString& sourceApp,
                       const QString& artUrl, double posSec, double durSec,
                       bool canNext, bool canPrev, bool canSeek,
                       const QVariantList& players);

    bool m_hasSession = false;
    bool m_isPlaying = false;
    QString m_title;
    QString m_artist;
    QString m_album;
    QString m_sourceApp;
    QString m_artUrl;
    double m_positionSec = 0.0;
    double m_durationSec = 0.0;
    bool m_canNext = false;
    bool m_canPrev = false;
    bool m_canSeek = false;
    QVariantList m_players;
    QString m_cmdFile;
    QString m_artDir;

    QProcess* m_proc = nullptr;
    QByteArray m_buf;
};
