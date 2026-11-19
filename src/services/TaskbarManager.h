#pragma once

#include <QHash>
#include <QObject>
#include <QString>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

class QTimer;
class SettingsStore;

class TaskbarManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString hideMode READ hideMode WRITE setHideMode NOTIFY hideModeChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(bool temporarilyShown READ isTemporarilyShown NOTIFY temporarilyShownChanged)
    Q_PROPERTY(bool win11StrictHide READ win11StrictHide WRITE setWin11StrictHide NOTIFY win11StrictHideChanged)
    Q_PROPERTY(bool isWin11 READ isWin11 CONSTANT)
    Q_PROPERTY(int windowsBuild READ windowsBuild CONSTANT)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

public:
    explicit TaskbarManager(SettingsStore* settings, QObject* parent = nullptr);
    ~TaskbarManager() override;

    QString hideMode() const { return m_hideMode; }
    Q_INVOKABLE void setHideMode(const QString& mode);

    bool isActive() const;
    bool isTemporarilyShown() const { return m_temporarilyShown; }
    bool win11StrictHide() const { return m_win11StrictHide; }
    Q_INVOKABLE void setWin11StrictHide(bool on);

    bool isWin11() const { return m_isWin11; }
    int windowsBuild() const { return m_winBuild; }
    QString statusText() const;

    Q_INVOKABLE void toggleTemporary();
    Q_INVOKABLE void restoreNow();

    // Synchronous restoration used during orderly exit/shutdown without overwriting saved hideMode.
    void prepareForExit();

    // Standalone recovery helpers (for --restore CLI flag and SEH crash handler).
    static void emergencyRestoreAll(SettingsStore* settings);
    static void emergencyRestoreAllNoAlloc() noexcept;

    // Coordinates with SekaiDesk's own bottom-docked Bar AppBar so workarea reclaim doesn't erase it.
    static void setBottomAppBarReserved(bool reserved) noexcept;
    static bool isBottomAppBarReserved() noexcept;

signals:
    void hideModeChanged();
    void activeChanged();
    void temporarilyShownChanged();
    void win11StrictHideChanged();
    void statusTextChanged();

private:
    static QString sanitizeHideMode(const QString& raw);

#ifdef Q_OS_WIN
    void detectWindowsVersion();
    void createWatcherWindow();
    void destroyWatcherWindow();
    void installWinEventHooks(DWORD explorerPid);
    void removeWinEventHooks();
    void applySuppressionPass(bool allowWorkAreaTimer);
    void suppressSingleTray(HWND hwnd, bool isPrimary, bool strictHide);
    void restoreSingleTray(HWND hwnd, LONG_PTR origExStyle, bool isPrimary);
    void restoreAllSuppressed(bool updateConfigFlag);
    void syncAtomicCrashState();
    void checkAndReclaimWorkArea();
    void onWatchdogTick();

    static bool isStartMenuOrSearchForeground();
    static LRESULT CALLBACK watcherWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    static void CALLBACK winEventProc(HWINEVENTHOOK hook, DWORD event, HWND hwnd,
                                      LONG idObject, LONG idChild, DWORD dwEventThread,
                                      DWORD dwmsEventTime);
#endif

    SettingsStore* m_settings = nullptr;
    QString m_hideMode = QStringLiteral("primary");
    bool m_win11StrictHide = true;
    bool m_temporarilyShown = false;
    bool m_isWin11 = false;
    int m_winBuild = 0;

    QTimer* m_watchdogTimer = nullptr;
    QTimer* m_reclaimTimer = nullptr;
    QTimer* m_reapplyDebounceTimer = nullptr;

#ifdef Q_OS_WIN
    HWND m_watcherHwnd = nullptr;
    UINT m_taskbarCreatedMsg = 0;
    UINT m_shellHookMsg = 0;
    bool m_shellHookRegistered = false;
    HWINEVENTHOOK m_showHook = nullptr;
    HWINEVENTHOOK m_uncloakHook = nullptr;
    DWORD m_hookedExplorerPid = 0;
    LONG_PTR m_origPrimaryExStyle = 0;
    DWORD_PTR m_origAbsState = 0x00000002; // ABS_ALWAYSONTOP
    QHash<qulonglong, LONG_PTR> m_suppressedSecondaryStyles;
    qint64 m_lastWorkAreaReclaimMs = 0;
    bool m_applyingWorkArea = false;
#endif
};
