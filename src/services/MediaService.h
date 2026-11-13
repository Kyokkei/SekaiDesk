#pragma once
// MediaService — Windows GSMTC media session reader via persistent hidden
// PowerShell WinRT worker + instant SendInput media-key transport controls.

#include <QObject>
#include <QProcess>
#include <QTimer>

class MediaService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasSession READ hasSession NOTIFY mediaChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY mediaChanged)
    Q_PROPERTY(QString title READ title NOTIFY mediaChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY mediaChanged)
    Q_PROPERTY(QString sourceApp READ sourceApp NOTIFY mediaChanged)

public:
    explicit MediaService(QObject* parent = nullptr);
    ~MediaService() override;

    bool hasSession() const { return m_hasSession; }
    bool isPlaying() const { return m_isPlaying; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString sourceApp() const { return m_sourceApp; }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

signals:
    void mediaChanged();

private:
    void startWorker();
    void onStdoutReady();
    void applySnapshot(bool hasSession, bool isPlaying,
                       const QString& title, const QString& artist,
                       const QString& sourceApp);

    bool m_hasSession = false;
    bool m_isPlaying = false;
    QString m_title;
    QString m_artist;
    QString m_sourceApp;

    QProcess* m_proc = nullptr;
    QByteArray m_buf;
};
