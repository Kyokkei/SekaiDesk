#pragma once
// TrayService — Hybrid Windows 10 & Windows 11 System Tray monitor.
// On Windows 11 (22H2+ XAML Islands), injects passive SekaiTrayHook.dll into
// Explorer to subclass the real Shell_TrayWnd and stream live NIM_ADD /
// NIM_MODIFY / NIM_DELETE notifications over a named pipe without interfering
// with AppBar workarea reservation. Also scans legacy ToolbarWindow32 on
// Windows 10 and supports NOTIFYICON_VERSION_4 click activation.

#include <QImage>
#include <QObject>
#include <QString>
#include <QVariantList>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

class TrayService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)

public:
    struct CapturedIconUpdate {
        quintptr hwnd = 0;
        uint32_t uID = 0;
        uint32_t uFlags = 0;
        uint32_t uCallbackMessage = 0;
        uint32_t uVersion = 0;
        bool hasHiddenFlag = false;
        bool hidden = false;
        bool hasGuid = false;
        QString guid;
        bool hasTip = false;
        QString tip;
        QImage iconImage;
    };

    explicit TrayService(QObject* parent = nullptr);
    ~TrayService() override;

    QVariantList items() const { return m_items; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void activateItem(int index, bool rightClick);

    void setPaused(bool paused);
    void stop();

signals:
    void itemsChanged();

private:
    struct InternalItem {
        quintptr hwnd = 0;
        uint32_t uID = 0;
        uint32_t uCallbackMessage = 0;
        uint32_t uVersion = 0;
        bool hasGuid = false;
        QString guid;
        QString tip;
        QString exePath;
        QString iconUrl;
        QString iconFilePath;
        bool hidden = false;
        bool fromLegacyToolbar = false;
    };

#ifdef Q_OS_WIN
    void beginCapture();
    void pipeThreadMain();
    void handlePipePacket(const QByteArray& packet);
    void scanExplorerToolbars();
    void applyIconUpdate(const CapturedIconUpdate& update);
    void applyIconRemove(quintptr hwnd, uint32_t uID, bool hasGuid, const QString& guid);
    void pruneDeadItems();
    void rebuildVisibleItems();
    int findTrackedIndex(quintptr hwnd, uint32_t uID, bool hasGuid, const QString& guid) const;
    QString writeTempIconPng(const QImage& img);
    void removeTempIconFile(InternalItem& item);

    std::atomic<bool> m_stopping{false};
    std::atomic<bool> m_paused{false};
    std::atomic<bool> m_hookReady{false};
    std::atomic<UINT> m_taskbarCreatedMsg{0};
    std::thread m_pipeThread;
    std::mutex m_ioMutex;
    HANDLE m_hWatchdogMutex{nullptr};
    HANDLE m_hStopEvent{nullptr};
    HANDLE m_hPipe{INVALID_HANDLE_VALUE};
    HHOOK m_activeHook{nullptr};
    HMODULE m_activeHookDll{nullptr};
    QString m_hookDllPath;
    qint64 m_lastBroadcastMs = 0;
    quint64 m_iconSeq = 0;
    QVector<int> m_visibleIndices;
#endif

    QVector<InternalItem> m_tracked;
    QVariantList m_items;
    QString m_iconDir;
};
