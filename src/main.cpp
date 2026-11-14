// SekaiDesk main entry — Phase 0 smoke test shell.
//
// Boot sequence:
//   1. QGuiApplication (Qt Quick scene graph, Win32 platform integration)
//   2. Register Quickshell compat types (URI "Quickshell" / "Quickshell.Io")
//   3. Add import paths: <exe>/qml (compat modules + qs junction) and the
//      vendored SekaiPop shell root for plain `qs.`-free imports later.
//   4. Load qrc:/qml/Shell.qml (smoke test; replaced by the full shell in
//      later phases).

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QUrl>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <cstring>
#include <cwctype>
#include <string>
#endif

#include "compat/QsCore.h"
#include "compat/QsIo.h"
#include "compat/QsWindow.h"
#include "core/SettingsStore.h"
#include "services/AppLauncher.h"
#include "services/DwmThumbnailItem.h"
#include "services/MediaService.h"
#include "services/AudioService.h"
#include "services/SystemControlService.h"
#include "services/TrayService.h"
#include "services/TrashService.h"
#include "services/WinIconProvider.h"
#include "services/WindowTracker.h"
#include "services/ClipboardService.h"
#include "services/DeskExtrasService.h"
#include "services/NotificationService.h"
#include "services/VisualizerService.h"
#include "services/WallpaperService.h"

int main(int argc, char* argv[])
{
#ifdef Q_OS_WIN
    std::wstring instanceTag;
    for (int i = 1; i < argc; ++i) {
        if (!argv[i])
            continue;
        const char* arg = argv[i];
        const char* rawVal = nullptr;
        if (std::strcmp(arg, "--instance") == 0 && (i + 1) < argc && argv[i + 1]) {
            rawVal = argv[++i];
        } else if (std::strncmp(arg, "--instance=", 11) == 0) {
            rawVal = arg + 11;
        }
        if (rawVal) {
            instanceTag.clear();
            for (const char* p = rawVal; *p != '\0' && instanceTag.size() < 48; ++p) {
                const wchar_t wc = static_cast<unsigned char>(*p);
                if (std::iswalnum(wc) || wc == L'_' || wc == L'-' || wc == L'.')
                    instanceTag.push_back(wc);
            }
        }
    }
    const std::wstring mutexName = instanceTag.empty()
        ? std::wstring(L"Local\\SekaiDesk_SingleInstance_v1")
        : (std::wstring(L"Local\\SekaiDesk_SingleInstance_") + instanceTag);

    HANDLE singleInstanceMutex = CreateMutexW(nullptr, FALSE, mutexName.c_str());
    const DWORD mutexErr = GetLastError();
    if (!singleInstanceMutex || mutexErr == ERROR_ALREADY_EXISTS || mutexErr == ERROR_ACCESS_DENIED) {
        if (singleInstanceMutex)
            CloseHandle(singleInstanceMutex);
        qInfo("SekaiDesk: another instance is already running; exiting.");
        return 0;
    }
#endif

    // SekaiDesk is a decorative shell: enable software fallback-friendly
    // defaults, keep the default RHI (D3D11 on Windows).
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("SekaiDesk"));
    app.setApplicationName(QStringLiteral("SekaiDesk"));
    app.setApplicationDisplayName(QStringLiteral("SekaiDesk"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setQuitOnLastWindowClosed(false);

    static SettingsStore settings;
    settings.ensureLoaded();

    static AppLauncher appLauncher(&settings);
    static WindowTracker windowTracker;
    static TrashService trashService;
    static MediaService mediaService;
    static AudioService audioService;
    static SystemControlService systemControl;
    systemControl.setSuppressStockOsd(
        settings.boolValue(QStringLiteral("ui.osdEnabled"), true));
    QObject::connect(&systemControl, &SystemControlService::volumeStepRequested,
                     &audioService, [&audioService](int delta) {
                         audioService.setMasterVolume(audioService.masterVolume() + delta);
                     });
    QObject::connect(&systemControl, &SystemControlService::volumeMuteToggleRequested,
                     &audioService, &AudioService::toggleMasterMute);
    QObject::connect(&audioService, &AudioService::osdRequested,
                     &systemControl, [&systemControl](const QString& kind, int, bool) {
                         if (kind == QLatin1String("volume"))
                             systemControl.hideStockOsdIfActive();
                     });
    static TrayService trayService;
    static ClipboardService clipboardService;
    static LyricsService lyricsService(&mediaService);
    static WeatherService weatherService(&settings);
    static DropShelfService dropShelfService;
    static NotificationService notificationService;
    static VisualizerService visualizerService(&settings, &mediaService);
    static WallpaperService wallpaperService(&settings);

    // --- Quickshell compat registrations -----------------------------------
    // Unversioned imports (`import Quickshell`) resolve to the highest
    // registered version; everything is registered as 1.0.
    qmlRegisterSingletonInstance("Quickshell", 1, 0,
                                 "Quickshell", QsGlobal::instance());
    qmlRegisterSingletonInstance("Quickshell", 1, 0,
                                 "SystemClock", SystemClock::instance());
    qmlRegisterType<Variants>("Quickshell", 1, 0,
                              "Variants");
    qmlRegisterType<PanelWindow>("Quickshell", 1, 0,
                                 "PanelWindow");
    qmlRegisterType<QsRegion>("Quickshell", 1, 0,
                              "Region");

    qmlRegisterType<QsProcess>("Quickshell.Io", 1, 0,
                               "Process");
    qmlRegisterType<QsStdioCollector>("Quickshell.Io", 1, 0,
                                      "StdioCollector");
    qmlRegisterType<QsFileView>("Quickshell.Io", 1, 0,
                                "FileView");

    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "ConfigStore", &settings);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "AppLauncher", &appLauncher);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "WindowTracker", &windowTracker);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "TrashService", &trashService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "MediaService", &mediaService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "AudioService", &audioService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "SystemControl", &systemControl);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "TrayService", &trayService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "ClipboardService", &clipboardService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "LyricsService", &lyricsService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "WeatherService", &weatherService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "DropShelfService", &dropShelfService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "NotificationService", &notificationService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "VisualizerService", &visualizerService);
    qmlRegisterSingletonInstance("SekaiDesk", 1, 0,
                                 "WallpaperService", &wallpaperService);
    qmlRegisterType<DwmThumbnailItem>("SekaiDesk", 1, 0,
                                      "DwmThumbnail");

    // --- Engine + import paths ----------------------------------------------
    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("winicon"), new WinIconProvider());

    // <exe>/qml: qml module dirs deployed by windeployqt + the `qs` junction
    // created by CMake (build/qml/qs -> SekaiPop/sekaipop).
    engine.addImportPath(QCoreApplication::applicationDirPath()
                         + QStringLiteral("/qml"));

    // The vendored shell root: lets later phases import SekaiPop modules
    // directly (module "services", "modules.*" style) if ever needed.
    const QString shellDir = QsGlobal::resolveShellDir();
    if (!shellDir.isEmpty()) {
        engine.addImportPath(shellDir);
        engine.rootContext()->setContextProperty(
            QStringLiteral("shellDir"), shellDir);
    } else {
        qWarning("SekaiDesk: vendored SekaiPop shell dir not found; "
                 "qs.* imports will fail");
    }

    // --restore: emergency work-area / taskbar rescue (implemented Phase 1).
    // --edit / other flags handled in later phases.

    engine.load(QUrl(QStringLiteral("qrc:/qml/Shell.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical("SekaiDesk: failed to load Shell.qml");
#ifdef Q_OS_WIN
        CloseHandle(singleInstanceMutex);
#endif
        return 1;
    }

    const int exitCode = app.exec();
#ifdef Q_OS_WIN
    CloseHandle(singleInstanceMutex);
#endif
    return exitCode;
}
