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
#include <QQmlEngine>
#include <QUrl>

#include "compat/QsCore.h"
#include "compat/QsIo.h"
#include "compat/QsWindow.h"
#include "core/SettingsStore.h"

int main(int argc, char* argv[])
{
    // SekaiDesk is a decorative shell: enable software fallback-friendly
    // defaults, keep the default RHI (D3D11 on Windows).
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("SekaiDesk"));
    app.setApplicationName(QStringLiteral("SekaiDesk"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));

    static SettingsStore settings;
    settings.ensureLoaded();

    // --- Quickshell compat registrations -----------------------------------
    // Unversioned imports (`import Quickshell`) resolve to the highest
    // registered version; everything is registered as 1.0.
    qmlRegisterSingletonInstance(QStringLiteral("Quickshell"), 1, 0,
                                 QStringLiteral("Quickshell"), QsGlobal::instance());
    qmlRegisterSingletonInstance(QStringLiteral("Quickshell"), 1, 0,
                                 QStringLiteral("SystemClock"), SystemClock::instance());
    qmlRegisterType<Variants>(QStringLiteral("Quickshell"), 1, 0,
                              QStringLiteral("Variants"));
    qmlRegisterType<PanelWindow>(QStringLiteral("Quickshell"), 1, 0,
                                 QStringLiteral("PanelWindow"));
    qmlRegisterType<QsRegion>(QStringLiteral("Quickshell"), 1, 0,
                              QStringLiteral("Region"));

    qmlRegisterType<QsProcess>(QStringLiteral("Quickshell.Io"), 1, 0,
                               QStringLiteral("Process"));
    qmlRegisterType<QsStdioCollector>(QStringLiteral("Quickshell.Io"), 1, 0,
                                      QStringLiteral("StdioCollector"));
    qmlRegisterType<QsFileView>(QStringLiteral("Quickshell.Io"), 1, 0,
                                QStringLiteral("FileView"));

    qmlRegisterSingletonInstance(QStringLiteral("SekaiDesk"), 1, 0,
                                 QStringLiteral("ConfigStore"), &settings);

    // --- Engine + import paths ----------------------------------------------
    QQmlApplicationEngine engine;

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
        return 1;
    }

    return app.exec();
}
