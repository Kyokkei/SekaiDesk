#pragma once
// AudioService — Windows Core Audio master volume + per-app Volume Mixer
// (IMMDeviceEnumerator / IAudioEndpointVolume / IAudioSessionManager2)
// and external volume-change detection for OSD Volume Sticker.

#include <QObject>
#include <QTimer>
#include <QVariantList>

class AudioService : public QObject {
    Q_OBJECT
    Q_PROPERTY(int masterVolume READ masterVolume NOTIFY masterChanged)
    Q_PROPERTY(bool masterMuted READ masterMuted NOTIFY masterChanged)
    Q_PROPERTY(QVariantList sessions READ sessions NOTIFY sessionsChanged)
    Q_PROPERTY(QVariantList outputDevices READ outputDevices NOTIFY outputDevicesChanged)
    Q_PROPERTY(QString defaultOutputId READ defaultOutputId NOTIFY outputDevicesChanged)

public:
    explicit AudioService(QObject* parent = nullptr);
    ~AudioService() override;

    int masterVolume() const { return m_masterVolume; }
    bool masterMuted() const { return m_masterMuted; }
    QVariantList sessions() const { return m_sessions; }
    QVariantList outputDevices() const { return m_outputDevices; }
    QString defaultOutputId() const { return m_defaultOutputId; }

    Q_INVOKABLE void setMasterVolume(int volume);
    Q_INVOKABLE void toggleMasterMute();
    Q_INVOKABLE void setAppVolume(const QString& sessionId, int volume);
    Q_INVOKABLE void toggleAppMute(const QString& sessionId);
    Q_INVOKABLE void refreshSessions();
    Q_INVOKABLE void refreshOutputDevices();
    Q_INVOKABLE bool setDefaultOutputDevice(const QString& deviceId);

signals:
    void masterChanged();
    void sessionsChanged();
    void outputDevicesChanged();
    void volumeOsdRequested(int volume, bool muted);

private slots:
    void pollMaster();

private:
    void readMasterState(bool emitOsdIfExternal);

    int m_masterVolume = 50;
    bool m_masterMuted = false;
    bool m_initialized = false;
    qint64 m_lastSelfChangeMs = 0;
    QVariantList m_sessions;
    QVariantList m_outputDevices;
    QString m_defaultOutputId;
    QTimer m_pollTimer;
};
