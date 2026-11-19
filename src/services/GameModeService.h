#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

// ===========================================================================
// GameModeService — True Zero-Overhead Game Mode + RTSS Guard
//
// Two modes when a game or genuine fullscreen app is active:
//  1) "hibernate": hides all SekaiDesk panels, tears down Acrylic blur &
//     hidden GPU resources, pauses all Win32/PS/WASAPI timers, enables
//     Windows EcoQoS + IDLE_PRIORITY_CLASS, and trims working set.
//  2) "zero": restores Windows taskbar (optional), spawns a pure-Win32
//     lightweight watchdog (`SekaiDesk.exe --wait-game=<PID> --wait-exe=<NAME>`)
//     with ~2 MB RAM / 0 MB VRAM / 0% CPU, and exits the main GUI process
//     until the game terminates.
// ===========================================================================

class GameModeService : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool manualActive READ manualActive NOTIFY activeChanged)
    Q_PROPERTY(bool autoActive READ autoActive NOTIFY activeChanged)

    Q_PROPERTY(bool autoDetect READ autoDetect WRITE setAutoDetect NOTIFY autoDetectChanged)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(bool restoreTaskbarInZero READ restoreTaskbarInZero WRITE setRestoreTaskbarInZero NOTIFY restoreTaskbarInZeroChanged)

    Q_PROPERTY(QStringList gameList READ gameList NOTIFY gameListChanged)
    Q_PROPERTY(QStringList excludeList READ excludeList NOTIFY excludeListChanged)

    Q_PROPERTY(QString activeGameExe READ activeGameExe NOTIFY activeChanged)
    Q_PROPERTY(QString activeGameTitle READ activeGameTitle NOTIFY activeChanged)
    Q_PROPERTY(QString activeReason READ activeReason NOTIFY activeChanged)

    Q_PROPERTY(bool rtssDetected READ rtssDetected NOTIFY rtssStatusChanged)
    Q_PROPERTY(bool rtssExcluded READ rtssExcluded NOTIFY rtssStatusChanged)
    Q_PROPERTY(QString rtssInstallDir READ rtssInstallDir NOTIFY rtssStatusChanged)
    Q_PROPERTY(QString lastStatus READ lastStatus NOTIFY lastStatusChanged)

public:
    explicit GameModeService(QObject* parent = nullptr);
    ~GameModeService() override = default;

    // Pure-Win32 watchdog run BEFORE QGuiApplication when `--wait-game` is passed.
    static int runWaitGameWatchdog(unsigned long targetPid,
                                   const QString& waitExe,
                                   const QString& instanceTag = {});

    void setInstanceTag(const QString& tag) { m_instanceTag = tag; }

    bool active() const { return m_manualActive || m_autoActive; }
    bool manualActive() const { return m_manualActive; }
    bool autoActive() const { return m_autoActive; }

    bool autoDetect() const { return m_autoDetect; }
    void setAutoDetect(bool on);

    QString mode() const { return m_mode; }
    void setMode(const QString& mode);

    bool restoreTaskbarInZero() const { return m_restoreTaskbarInZero; }
    void setRestoreTaskbarInZero(bool on);

    QStringList gameList() const { return m_gameList; }
    QStringList excludeList() const { return m_excludeList; }

    QString activeGameExe() const { return m_activeGameExe; }
    QString activeGameTitle() const { return m_activeGameTitle; }
    QString activeReason() const { return m_activeReason; }

    bool rtssDetected() const { return m_rtssDetected; }
    bool rtssExcluded() const { return m_rtssExcluded; }
    QString rtssInstallDir() const { return m_rtssInstallDir; }
    QString lastStatus() const { return m_lastStatus; }

    Q_INVOKABLE void toggleManual();
    Q_INVOKABLE void setManualActive(bool on);
    Q_INVOKABLE void addGameExe(const QString& exeOrPath);
    Q_INVOKABLE void removeGameExe(const QString& exe);
    Q_INVOKABLE void addExcludeExe(const QString& exeOrPath);
    Q_INVOKABLE void removeExcludeExe(const QString& exe);
    Q_INVOKABLE void resetDefaultLists();
    Q_INVOKABLE void refreshRtssStatus();
    Q_INVOKABLE bool applyRtssExclusion();
    Q_INVOKABLE void setSpotlightOverride(bool open);

signals:
    void activeChanged();
    void autoDetectChanged();
    void modeChanged();
    void restoreTaskbarInZeroChanged();
    void gameListChanged();
    void excludeListChanged();
    void rtssStatusChanged();
    void lastStatusChanged();

    void hibernateChanged(bool hibernated, const QString& reason);
    void zeroFootprintRequested();
    void spotlightHiddenWhileHibernated();

private slots:
    void pollForeground();

private:
    void loadConfig();
    void saveConfig() const;
    void applyEffectiveState(const QString& reason);
    void applyProcessPowerState(bool eco);
    bool launchWaitGameAndExit(unsigned long targetPid, const QString& exeName);
    void setStatus(const QString& msg);

    static QString normalizeExeName(const QString& exeOrPath);
    static QStringList defaultGameList();
    static QStringList defaultExcludeList();
    static QString configFilePath();

    bool m_manualActive = false;
    bool m_autoActive = false;
    bool m_hibernatedState = false;
    bool m_spotlightOverride = false;
    bool m_zeroLaunching = false;

    bool m_autoDetect = true;
    QString m_mode = QStringLiteral("hibernate");
    bool m_restoreTaskbarInZero = true;

    QStringList m_gameList;
    QStringList m_excludeList;

    QString m_activeGameExe;
    QString m_activeGameTitle;
    QString m_activeReason;

    unsigned long m_pendingPid = 0;
    QString m_pendingExe;
    QString m_pendingTitle;
    QString m_pendingReason;
    int m_pendingHits = 0;
    int m_clearMisses = 0;

    bool m_rtssDetected = false;
    bool m_rtssExcluded = false;
    QString m_rtssInstallDir;
    QString m_lastStatus;
    QString m_instanceTag;

    QTimer m_pollTimer;
};
